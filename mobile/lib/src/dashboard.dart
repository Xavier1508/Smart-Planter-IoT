import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance.dart';
import 'appearance_panel.dart';
import 'app_version_panel.dart';
import 'devices_page.dart';
import 'journal_page.dart';
import 'local_wifi.dart';
import 'moss_app.dart';
import 'moss_avatar.dart';
import 'moss_gaze.dart';
import 'moss_sky.dart';
import 'plant_state.dart';
import 'plant_telemetry.dart';
import 'synthetic_xgboost.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    required this.render3d,
    required this.gaze,
    required this.atmosphere,
    this.telemetry,
    this.initialSerialJson = '',
    this.cloudSettings,
    this.cloudSetupNotice,
    this.localWifi,
    this.modelAssetLoader,
    required this.appearance,
    required this.sky,
    required this.storageUnavailable,
    required this.onThemeChanged,
    required this.onSkyChanged,
    required this.onManualTimeChanged,
  });

  final bool render3d;
  final MossGaze gaze;
  final MossAtmosphere atmosphere;
  final Stream<PlantTelemetry>? telemetry;
  final String initialSerialJson;
  final Widget? cloudSettings;
  final String? cloudSetupNotice;
  final LocalWifiController? localWifi;
  final Future<String> Function()? modelAssetLoader;
  final AppearanceSettings appearance;
  final SkyAppearance sky;
  final bool storageUnavailable;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<SkyChoice> onSkyChanged;
  final ValueChanged<int> onManualTimeChanged;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  static const _readingMaxAge = Duration(minutes: 2);

  var _page = 0;
  var _demo = true;
  var _scenario = DemoScenario.content;
  var _liveState = const PlantState.waiting();
  PlantState? _serialSnapshot;
  String? _serialMessage;
  var _sourceNotice = 'Perangkat dan cloud belum terhubung.';
  DateTime? _lastRecordedAt;
  int? _lastSequence;
  StreamSubscription<PlantTelemetry>? _subscription;
  Timer? _expiry;
  late LocalWifiController _localWifi;
  late bool _ownsLocalWifi;
  StreamSubscription<void>? _localWifiChanges;
  bool _useLocalWifi = false;
  SyntheticXgboostModel? _syntheticModel;
  bool _modelLoadFinished = false;

  @override
  void initState() {
    super.initState();
    _attachLocalWifi(widget.localWifi);
    unawaited(_loadSyntheticModel());
    _listenToTelemetry();
    if (widget.initialSerialJson.isNotEmpty) {
      _demo = false;
      try {
        _serialSnapshot = PlantState.fromSerial(
          SerialSensorSnapshot.parse(widget.initialSerialJson),
        );
      } catch (_) {
        _sourceNotice = 'Snapshot serial tidak valid; menunggu sumber data.';
      }
    }
  }

  @override
  void didUpdateWidget(covariant Dashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.telemetry != widget.telemetry) _listenToTelemetry();
    if (oldWidget.localWifi != widget.localWifi) {
      final previous = _localWifiChanges;
      if (previous != null) unawaited(previous.cancel());
      if (_ownsLocalWifi) _localWifi.dispose();
      _useLocalWifi = false;
      _attachLocalWifi(widget.localWifi);
    }
  }

  void _attachLocalWifi(LocalWifiController? controller) {
    _ownsLocalWifi = controller == null;
    _localWifi = controller ?? LocalWifiController();
    _localWifiChanges = _localWifi.changes.listen((_) => _onLocalWifiChanged());
  }

  void _onLocalWifiChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSyntheticModel() async {
    SyntheticXgboostModel? model;
    try {
      final json =
          await (widget.modelAssetLoader?.call() ??
              rootBundle.loadString('assets/ml/pattern-models.json'));
      model = SyntheticXgboostModel.parse(json);
    } catch (_) {
      // Missing or malformed models are never replaced with a fabricated result.
    }
    if (!mounted) return;
    setState(() {
      _syntheticModel = model;
      _modelLoadFinished = true;
    });
  }

  SyntheticPrediction? _predictLocal(SerialSensorSnapshot? sample) {
    if (sample == null || _syntheticModel == null) return null;
    bool nonRail(int? raw) => raw != null && raw > 0 && raw < 4095;
    if (!nonRail(sample.soilAdc) ||
        !nonRail(sample.waterAdc) ||
        !nonRail(sample.lightAdc)) {
      return null;
    }
    return _syntheticModel!.predict(
      soilPercent: sample.soilRelativePercent,
      waterObservationPercent: sample.waterObservationPercent,
      lightPercent: sample.lightRelativePercent,
      // The real device currently emits raw UV ADC, not a calibrated index.
      uvIndex: null,
    );
  }

  void _connectLocalWifi() {
    setState(() {
      _useLocalWifi = true;
      _serialSnapshot = null;
      _demo = false;
    });
    unawaited(_localWifi.connect());
  }

  void _disconnectLocalWifi() {
    _localWifi.disconnect();
    setState(() => _useLocalWifi = false);
  }

  void _listenToTelemetry() {
    final previous = _subscription;
    if (previous != null) unawaited(previous.cancel());
    _subscription = null;
    _expiry?.cancel();
    _lastRecordedAt = null;
    _lastSequence = null;
    _liveState = const PlantState.waiting();
    final source = widget.telemetry;
    _sourceNotice = source == null
        ? 'Perangkat dan cloud belum terhubung.'
        : 'Menunggu pembacaan sensor.';
    if (source == null) return;
    _subscription = source.listen(
      _acceptReading,
      onError: (Object _, StackTrace _) => _disconnect(),
      onDone: _disconnect,
    );
  }

  void _acceptReading(PlantTelemetry reading) {
    if (!mounted) return;
    final now = DateTime.now();
    if (!reading.isFreshAt(now, maxAge: _readingMaxAge)) {
      if (!_liveState.isLive) {
        setState(() {
          _sourceNotice = 'Pembacaan terlalu lama atau waktu tidak sesuai.';
        });
      }
      return;
    }
    final previous = _lastRecordedAt;
    if (previous != null && reading.recordedAt.isBefore(previous)) return;
    if (previous != null &&
        reading.recordedAt.isAtSameMomentAs(previous) &&
        _lastSequence != null &&
        (reading.sequence == null ||
            reading.sequence! < _lastSequence! ||
            (reading.sequence == _lastSequence && _liveState.isLive))) {
      return;
    }
    final next = PlantState.fromTelemetry(reading);
    if (!next.hasSensorData) {
      _expiry?.cancel();
      _lastRecordedAt = reading.recordedAt;
      _lastSequence = reading.sequence;
      setState(() {
        _liveState = const PlantState.waiting();
        _sourceNotice = 'Menunggu pembacaan sensor yang valid.';
      });
      return;
    }

    _expiry?.cancel();
    _lastRecordedAt = reading.recordedAt;
    _lastSequence = reading.sequence;
    setState(() {
      _liveState = next;
      _sourceNotice = 'Pembacaan sensor terbaru.';
    });
    final remaining = reading.recordedAt.add(_readingMaxAge).difference(now);
    _expiry = Timer(remaining, () {
      if (!mounted) return;
      setState(() {
        _liveState = const PlantState.waiting();
        _sourceNotice = 'Data sensor sudah lama; menunggu pembaruan.';
      });
    });
  }

  void _disconnect() {
    if (!mounted) return;
    _expiry?.cancel();
    setState(() {
      _liveState = const PlantState.waiting();
      _sourceNotice = 'Koneksi data terputus.';
    });
  }

  Future<void> _importSerialSnapshot() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboard?.text;
      if (text == null) throw const FormatException();
      final snapshot = SerialSensorSnapshot.parse(text.trim());
      if (!mounted) return;
      _localWifi.disconnect();
      setState(() {
        _useLocalWifi = false;
        _serialSnapshot = PlantState.fromSerial(snapshot);
        _serialMessage = null;
        _demo = false;
        _page = 0;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _serialMessage = 'Salin satu baris JSON sample dari monitor serial.';
        });
      }
    }
  }

  void _clearSerialSnapshot() => setState(() {
    _serialSnapshot = null;
    _serialMessage = null;
  });

  @override
  void dispose() {
    _expiry?.cancel();
    final localChanges = _localWifiChanges;
    if (localChanges != null) unawaited(localChanges.cancel());
    if (_ownsLocalWifi) _localWifi.dispose();
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localSample = _localWifi.snapshot;
    final state = _demo
        ? PlantState.demo(_scenario)
        : _useLocalWifi
        ? (localSample == null
              ? const PlantState.waiting()
              : PlantState.fromLocalWifi(
                  localSample,
                  syntheticPrediction: _predictLocal(localSample),
                ))
        : (_serialSnapshot ?? _liveState);
    return Scaffold(
      body: SafeArea(
        child: switch (_page) {
          0 => _Home(
            state: state,
            scenario: _scenario,
            render3d: widget.render3d,
            gaze: widget.gaze,
            atmosphere: widget.atmosphere,
            sourceNotice: state.isSerialSnapshot
                ? 'Data serial tersimpan; waktu ukur tidak diketahui. Bukan live.'
                : _useLocalWifi
                ? _localWifi.message
                : _sourceNotice,
            modelAvailable: _syntheticModel != null,
            modelLoadFinished: _modelLoadFinished,
            sky: widget.sky,
            automaticSky: widget.appearance.sky == SkyChoice.automatic,
            selectedSky: widget.appearance.sky,
            onSkyChanged: widget.onSkyChanged,
            onScenario: (value) => setState(() => _scenario = value),
            onDemoChanged: () => setState(() => _demo = !_demo),
          ),
          1 => JournalPage(demo: _demo, scenario: _scenario),
          2 => DevicesPage(state: state),
          _ => _SettingsPage(
            demo: _demo,
            onDemoChanged: () => setState(() => _demo = !_demo),
            sourceNotice: widget.cloudSetupNotice ?? _sourceNotice,
            cloudSettings: widget.cloudSettings,
            serialMessage: _serialMessage,
            hasSerialSnapshot: _serialSnapshot != null,
            onImportSerial: _importSerialSnapshot,
            onClearSerial: _clearSerialSnapshot,
            localSelected: _useLocalWifi,
            localStatus: _localWifi.status,
            localMessage: _localWifi.message,
            onConnectLocal: _connectLocalWifi,
            onDisconnectLocal: _disconnectLocalWifi,
            appearance: widget.appearance,
            storageUnavailable: widget.storageUnavailable,
            onThemeChanged: widget.onThemeChanged,
            onSkyChanged: widget.onSkyChanged,
            onManualTimeChanged: widget.onManualTimeChanged,
          ),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (index) => setState(() => _page = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.spa_outlined),
            selectedIcon: Icon(Icons.spa),
            label: 'Hari ini',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Riwayat',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors),
            label: 'Perangkat',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({
    required this.state,
    required this.scenario,
    required this.render3d,
    required this.gaze,
    required this.atmosphere,
    required this.sourceNotice,
    required this.modelAvailable,
    required this.modelLoadFinished,
    required this.onScenario,
    required this.onDemoChanged,
    required this.sky,
    required this.automaticSky,
    required this.selectedSky,
    required this.onSkyChanged,
  });

  final PlantState state;
  final DemoScenario scenario;
  final bool render3d;
  final MossGaze gaze;
  final MossAtmosphere atmosphere;
  final String sourceNotice;
  final bool modelAvailable;
  final bool modelLoadFinished;
  final ValueChanged<DemoScenario> onScenario;
  final VoidCallback onDemoChanged;
  final SkyAppearance sky;
  final bool automaticSky;
  final SkyChoice selectedSky;
  final ValueChanged<SkyChoice> onSkyChanged;

  String _percent(int? value) => value == null ? '—' : '$value%';

  void _stepSky({required bool next}) =>
      onSkyChanged(SkyChoice.step(selectedSky, sky.hour, next: next));

  @override
  Widget build(BuildContext context) {
    final mood = state.mood;
    final skyInk = MossSky.foregroundFor(sky.bottom);
    final skyHeaderInk = MossSky.foregroundFor(sky.top);
    final mutedColor = context.mossColors.onSurfaceVariant;
    final tint = Color.lerp(
      const Color(0x19233665),
      const Color(0x09FFD38C),
      sky.sunOpacity,
    )!;
    final transition = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 1200);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SMART PLANTER',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                            color: mutedColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Ruang Moss',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(
                    demo: state.isDemo,
                    live: state.isLive,
                    snapshot: state.isSerialSnapshot,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              MossSky(
                sky: sky,
                gaze: gaze,
                atmosphere: atmosphere,
                onSwipe: (next) => _stepSky(next: next),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Row(
                        children: [
                          Icon(Icons.eco_outlined, color: skyInk, size: 17),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              state.moodLabel.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: skyHeaderInk,
                              ),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              '${sky.label.toUpperCase()} · ${automaticSky ? 'JAM HP' : 'PILIHAN'}',
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .6,
                                color: skyHeaderInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 235,
                      width: double.infinity,
                      child: TweenAnimationBuilder<Color?>(
                        tween: ColorTween(end: tint),
                        duration: transition,
                        builder: (context, color, child) => ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            color!,
                            BlendMode.srcATop,
                          ),
                          child: child,
                        ),
                        child: render3d
                            ? MossAvatar(
                                mood: mood,
                                sky: sky,
                                gaze: gaze,
                                atmosphere: atmosphere,
                              )
                            : Center(
                                child: Icon(
                                  Icons.spa_outlined,
                                  size: 88,
                                  color: skyHeaderInk,
                                ),
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Suasana sebelumnya',
                            onPressed: () => _stepSky(next: false),
                            icon: Icon(
                              Icons.chevron_left_rounded,
                              color: skyInk,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Geser untuk mengubah suasana',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: skyInk, fontSize: 11),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Suasana berikutnya',
                            onPressed: () => _stepSky(next: true),
                            icon: Icon(
                              Icons.chevron_right_rounded,
                              color: skyInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                      child: Column(
                        children: [
                          Text(
                            state.moodMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                              color: skyInk,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            state.explanation,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: skyInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Notice(
                demo: state.isDemo,
                live: state.isLive,
                sourceNotice: sourceNotice,
                onToggle: onDemoChanged,
              ),
              if (state.isDemo) ...[
                const SizedBox(height: 20),
                Text(
                  'COBA KONDISI MOSS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: mutedColor,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _ScenarioChip(
                      label: 'Nyaman',
                      selected: scenario == DemoScenario.content,
                      onTap: () => onScenario(DemoScenario.content),
                    ),
                    _ScenarioChip(
                      label: 'Butuh air',
                      selected: scenario == DemoScenario.thirsty,
                      onTap: () => onScenario(DemoScenario.thirsty),
                    ),
                    _ScenarioChip(
                      label: 'Udara berubah',
                      selected: scenario == DemoScenario.airConcern,
                      onTap: () => onScenario(DemoScenario.airConcern),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 25),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Kondisi tanaman',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  Text(
                    state.isDemo
                        ? 'CONTOH DATA'
                        : state.isLive
                        ? 'DATA SENSOR'
                        : state.isSerialSnapshot
                        ? 'DATA SERIAL'
                        : 'BELUM TERHUBUNG',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: mutedColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (state.isLive || state.isSerialSnapshot) ...[
                Text(
                  'Nilai sensor belum diverifikasi; tanah dan cahaya berupa skala relatif.',
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final columnWidth = (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: columnWidth,
                        child: _Metric(
                          icon: Icons.water_drop_outlined,
                          title: 'Kelembapan tanah',
                          value: state.soilPercent != null
                              ? _percent(state.soilPercent)
                              : '—',
                          detail: state.soilPercent != null
                              ? state.isDemo
                                    ? 'Kondisi tanah'
                                    : state.soilAdc != null
                                    ? 'ADC ${state.soilAdc} · perkiraan'
                                    : 'Skala belum diverifikasi'
                              : state.soilAdc != null
                              ? 'ADC ${state.soilAdc} · belum dapat diestimasi'
                              : 'Menunggu sensor',
                          color: const Color(0xFF51859A),
                        ),
                      ),
                      SizedBox(
                        width: columnWidth,
                        child: _Metric(
                          icon: Icons.waves_rounded,
                          title: 'Air (relatif)',
                          value: state.waterPercent != null
                              ? _percent(state.waterPercent)
                              : state.waterObservationPercent != null
                              ? '~${_percent(state.waterObservationPercent)}'
                              : '—',
                          detail: state.isDemo
                              ? 'Level simulasi'
                              : state.waterPercent != null
                              ? 'ADC ${state.waterAdc} · belum diverifikasi'
                              : state.waterObservationPercent != null
                              ? 'Rendah–hampir penuh · perkiraan'
                              : state.waterAdc != null
                              ? 'ADC ${state.waterAdc} · belum dapat diestimasi'
                              : 'Belum tersedia',
                          color: const Color(0xFF568896),
                        ),
                      ),
                      SizedBox(
                        width: columnWidth,
                        child: _Metric(
                          icon: Icons.thermostat_rounded,
                          title: 'Suhu udara',
                          value: state.temperatureC == null
                              ? '—'
                              : '${state.temperatureC!.toStringAsFixed(1)}°',
                          detail: state.humidityPercent == null
                              ? 'Menunggu sensor'
                              : 'Kelembapan ${state.humidityPercent}%',
                          color: terracotta,
                        ),
                      ),
                      SizedBox(
                        width: columnWidth,
                        child: _Metric(
                          icon: Icons.wb_sunny_outlined,
                          title: 'Cahaya',
                          value: state.lightPercent != null
                              ? _percent(state.lightPercent)
                              : '—',
                          detail: state.isDemo
                              ? 'Intensitas contoh'
                              : state.lightAdc != null
                              ? state.lightPercent != null
                                    ? 'ADC ${state.lightAdc} · perkiraan'
                                    : 'ADC mentah'
                              : state.lightPercent != null
                              ? 'Skala belum diverifikasi'
                              : 'Menunggu sensor',
                          color: const Color(0xFFAB843A),
                        ),
                      ),
                      SizedBox(
                        width: constraints.maxWidth,
                        child: _Metric(
                          icon: Icons.wb_twilight_rounded,
                          title: state.uvAdc == null
                              ? 'UV (perkiraan)'
                              : 'UV (skala ADC)',
                          value:
                              (state.uvAdcPercent == null
                                  ? null
                                  : '~${state.uvAdcPercent}%') ??
                              state.uvIndex?.toStringAsFixed(1) ??
                              '—',
                          detail: state.uvAdc != null
                              ? 'ADC ${state.uvAdc} · bukan indeks UV'
                              : state.uvIndex == null
                              ? 'Menunggu data sensor'
                              : state.isDemo
                              ? 'Contoh, bukan sensor'
                              : 'Belum diverifikasi',
                          color: const Color(0xFF967144),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              _AirRow(state: state),
              const SizedBox(height: 10),
              _SyntheticMlCard(
                state: state,
                modelAvailable: modelAvailable,
                modelLoadFinished: modelLoadFinished,
              ),
              const SizedBox(height: 23),
              const Text(
                'Perangkat',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 12),
              const _ControlNotice(),
              const SizedBox(height: 22),
              Text(
                state.syntheticPrediction == null
                    ? 'Ekspresi Moss menggunakan aturan sederhana, bukan hasil model machine learning.'
                    : 'Ekspresi Moss mengikuti model sintetis; bukan diagnosis tanaman.',
                style: TextStyle(color: mutedColor, fontSize: 11, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.demo,
    required this.live,
    required this.snapshot,
  });
  final bool demo;
  final bool live;
  final bool snapshot;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: demo
          ? const Color(0xFFF0E6CF)
          : live
          ? const Color(0xFFDDE9DA)
          : const Color(0xFFE9EAE4),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          demo
              ? Icons.science_outlined
              : live
              ? Icons.sensors_rounded
              : Icons.cloud_off_outlined,
          size: 14,
          color: demo ? const Color(0xFF8B6937) : (live ? forest : muted),
        ),
        const SizedBox(width: 5),
        Text(
          demo
              ? 'SIMULASI'
              : (live ? 'SENSOR' : (snapshot ? 'SERIAL' : 'OFFLINE')),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w800,
            color: demo ? const Color(0xFF8B6937) : (live ? forest : muted),
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.demo,
    required this.live,
    required this.sourceNotice,
    required this.onToggle,
  });
  final bool demo;
  final bool live;
  final String sourceNotice;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
    decoration: BoxDecoration(
      color: context.mossColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: context.mossColors.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(
          demo
              ? Icons.science_outlined
              : live
              ? Icons.sensors_rounded
              : Icons.wifi_off_rounded,
          size: 19,
          color: context.mossColors.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            demo ? 'Simulasi — bukan data sensor.' : sourceNotice,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(onPressed: onToggle, child: Text(demo ? 'Tutup' : 'Demo')),
      ],
    ),
  );
}

class _ScenarioChip extends StatelessWidget {
  const _ScenarioChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    selectedColor: context.mossColors.primaryContainer,
    backgroundColor: context.mossColors.surfaceContainerLowest,
    labelStyle: TextStyle(
      color: selected
          ? context.mossColors.onPrimaryContainer
          : context.mossColors.onSurface,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    side: BorderSide(color: context.mossColors.outlineVariant),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: context.mossColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: context.mossColors.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 12),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.mossColors.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.mossColors.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _AirRow extends StatelessWidget {
  const _AirRow({required this.state});
  final PlantState state;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.mossColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: context.mossColors.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(Icons.air_rounded, color: context.mossColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sensor udara MQ135',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                state.isDemo
                    ? 'Kondisi contoh, bukan pembacaan CO₂'
                    : state.mqAdcStatus == 'adc_read_failed'
                    ? 'Analog gagal · digital ${state.mqDigital ?? '—'}'
                    : state.mqAdc != null
                    ? 'ADC ${state.mqAdc} · bukan kualitas udara'
                    : state.mqDigital != null
                    ? 'Digital ${state.mqDigital} · analog belum tersedia'
                    : 'Belum tersedia dan belum dikalibrasi',
                style: TextStyle(
                  fontSize: 11,
                  color: context.mossColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(
          state.isDemo
              ? (state.airChanged ? 'BERUBAH' : 'STABIL')
              : state.mqAdcPercent != null
              ? '~${state.mqAdcPercent}% ADC'
              : state.mqDigital != null
              ? 'D ${state.mqDigital}'
              : '—',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: context.mossColors.primary,
          ),
        ),
      ],
    ),
  );
}

class _SyntheticMlCard extends StatelessWidget {
  const _SyntheticMlCard({
    required this.state,
    required this.modelAvailable,
    required this.modelLoadFinished,
  });

  final PlantState state;
  final bool modelAvailable;
  final bool modelLoadFinished;

  @override
  Widget build(BuildContext context) {
    final prediction = state.syntheticPrediction;
    final description = !modelLoadFinished
        ? 'Menyiapkan model.'
        : !modelAvailable
        ? 'Model tidak tersedia.'
        : !state.isLocalLive
        ? 'Hubungkan sensor melalui Wi-Fi lokal untuk menjalankan model.'
        : prediction == null
        ? 'Menunggu data tanah, air, dan cahaya yang dapat dibaca.'
        : 'Pola: ${state.moodMessage}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.mossColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: context.mossColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ML XGBoost · sintetis',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(description, style: const TextStyle(fontSize: 12)),
          if (prediction != null) ...[
            const SizedBox(height: 4),
            Text(
              'Skor model sintetis ${(prediction.score * 100).round()}% · bukan akurasi sensor',
              style: TextStyle(
                color: context.mossColors.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 5),
          Text(
            'Dilatih dengan data buatan dan aturan; bukan diagnosis tanaman atau kendali relay. UV nyata belum terkalibrasi.',
            style: TextStyle(
              color: context.mossColors.onSurfaceVariant,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlNotice extends StatelessWidget {
  const _ControlNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.mossColors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(17),
    ),
    child: Row(
      children: [
        Icon(
          Icons.power_settings_new_rounded,
          color: context.mossColors.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pompa & lampu',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Kendali nyata belum tersedia.',
                style: TextStyle(
                  color: context.mossColors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.lock_outline_rounded,
          size: 18,
          color: context.mossColors.onSurfaceVariant,
        ),
      ],
    ),
  );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.demo,
    required this.onDemoChanged,
    required this.sourceNotice,
    required this.cloudSettings,
    required this.serialMessage,
    required this.hasSerialSnapshot,
    required this.onImportSerial,
    required this.onClearSerial,
    required this.localSelected,
    required this.localStatus,
    required this.localMessage,
    required this.onConnectLocal,
    required this.onDisconnectLocal,
    required this.appearance,
    required this.storageUnavailable,
    required this.onThemeChanged,
    required this.onSkyChanged,
    required this.onManualTimeChanged,
  });
  final bool demo;
  final VoidCallback onDemoChanged;
  final String sourceNotice;
  final Widget? cloudSettings;
  final String? serialMessage;
  final bool hasSerialSnapshot;
  final VoidCallback onImportSerial;
  final VoidCallback onClearSerial;
  final bool localSelected;
  final LocalWifiStatus localStatus;
  final String localMessage;
  final VoidCallback onConnectLocal;
  final VoidCallback onDisconnectLocal;
  final AppearanceSettings appearance;
  final bool storageUnavailable;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<SkyChoice> onSkyChanged;
  final ValueChanged<int> onManualTimeChanged;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'PREFERENSI',
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
          color: context.mossColors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 7),
      const Text(
        'Pengaturan',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
      ),
      const SizedBox(height: 24),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Mode simulasi',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Coba ekspresi Moss tanpa perangkat.',
          style: TextStyle(color: context.mossColors.onSurfaceVariant),
        ),
        value: demo,
        onChanged: (_) => onDemoChanged(),
      ),
      const Divider(height: 32),
      AppearancePanel(
        settings: appearance,
        storageUnavailable: storageUnavailable,
        onThemeChanged: onThemeChanged,
        onSkyChanged: onSkyChanged,
        onManualTimeChanged: onManualTimeChanged,
      ),
      const Divider(height: 32),
      cloudSettings ??
          _SettingLine(
            icon: Icons.cloud_outlined,
            title: 'Koneksi cloud',
            body: sourceNotice,
          ),
      const Text(
        'Wi-Fi lokal ESP32',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 5),
      const Text(
        'Pilih Wi-Fi Moss pada ponsel menggunakan sandi di LCD ESP32, '
        'lalu hubungkan di sini. Data tetap di jaringan lokal; jaringan ini '
        'tidak menyediakan internet.',
        style: TextStyle(fontSize: 12, height: 1.4),
      ),
      Text(localMessage, style: const TextStyle(fontSize: 12)),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: localStatus == LocalWifiStatus.connecting
                ? null
                : onConnectLocal,
            child: const Text('Hubungkan Wi-Fi lokal'),
          ),
          if (localSelected)
            TextButton(
              onPressed: onDisconnectLocal,
              child: const Text('Putuskan Wi-Fi lokal'),
            ),
        ],
      ),
      const Divider(height: 32),
      const Text('Data serial', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      const Text(
        'Salin satu baris JSON sample dari ESP32, lalu tempel di sini. '
        'Snapshot bukan live. Data tempel hanya di memori; data bawaan APK dapat muncul kembali saat dibuka.',
        style: TextStyle(fontSize: 12, height: 1.4),
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: onImportSerial,
            child: const Text('Tempel data serial'),
          ),
          if (hasSerialSnapshot)
            TextButton(
              onPressed: onClearSerial,
              child: const Text('Hapus snapshot'),
            ),
        ],
      ),
      if (serialMessage != null)
        Text(serialMessage!, style: const TextStyle(fontSize: 12)),
      const Divider(height: 32),
      const AppVersionPanel(),
      const _SettingLine(
        icon: Icons.sensors_outlined,
        title: 'Sensor tambahan',
        body: 'Impor serial menampilkan ADC air dan MQ mentah, bukan hasil terkalibrasi.',
      ),
      const _SettingLine(
        icon: Icons.notifications_none_rounded,
        title: 'Notifikasi',
        body: 'Notifikasi nyata belum dikonfigurasi.',
      ),
      const _SettingLine(
        icon: Icons.psychology_outlined,
        title: 'Ekspresi Moss',
        body: 'Prediksi ML: N/A. Ekspresi menggunakan aturan sederhana, bukan model terlatih.',
      ),
    ],
  );
}

class _SettingLine extends StatelessWidget {
  const _SettingLine({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.mossColors.primary, size: 21),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  color: context.mossColors.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
