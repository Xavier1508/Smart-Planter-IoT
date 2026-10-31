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

class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    required this.render3d,
    required this.gaze,
    required this.atmosphere,
    this.telemetry,
    this.initialSerialJson = '',
    this.cloudSettings,
    this.localWifi,
    this.autoConnectLocal = true,
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
  final LocalWifiController? localWifi;
  final bool autoConnectLocal;
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
  var _liveState = const PlantState.waiting();
  PlantState? _serialSnapshot;
  String? _serialMessage;
  var _sourceNotice = 'Menunggu data sensor.';
  DateTime? _lastRecordedAt;
  int? _lastSequence;
  StreamSubscription<PlantTelemetry>? _subscription;
  Timer? _expiry;
  late LocalWifiController _localWifi;
  late bool _ownsLocalWifi;
  StreamSubscription<void>? _localWifiChanges;
  bool _useLocalWifi = false;

  @override
  void initState() {
    super.initState();
    _attachLocalWifi(widget.localWifi);
    _listenToTelemetry();
    if (widget.initialSerialJson.isNotEmpty) {
      try {
        _serialSnapshot = PlantState.fromSerial(
          SerialSensorSnapshot.parse(widget.initialSerialJson),
        );
      } catch (_) {
        _sourceNotice = 'Snapshot serial tidak valid; menunggu sumber data.';
      }
    } else if (widget.autoConnectLocal) {
      _useLocalWifi = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _useLocalWifi) unawaited(_localWifi.connect());
      });
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

  void _connectLocalWifi() {
    setState(() {
      _useLocalWifi = true;
      _serialSnapshot = null;
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
        ? 'Menunggu data sensor.'
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
    final state = _useLocalWifi
        ? (localSample == null
              ? const PlantState.waiting()
              : PlantState.fromLocalWifi(
                  localSample,
                  mqAverageAdc: _localWifi.mqAverageAdc,
                  mqAverageSamples: _localWifi.mqAverageSamples,
                  mqTrend: _localWifi.mqTrend,
                ))
        : (_serialSnapshot ?? _liveState);
    return Scaffold(
      body: SafeArea(
        child: switch (_page) {
          0 => _Home(
            state: state,
            render3d: widget.render3d,
            gaze: widget.gaze,
            atmosphere: widget.atmosphere,
            sourceNotice: state.isSerialSnapshot
                ? 'Data serial tersimpan; waktu ukur tidak diketahui. Bukan live.'
                : _useLocalWifi
                ? _localWifi.message
                : _sourceNotice,
            localSelected: _useLocalWifi,
            localStatus: _localWifi.status,
            sky: widget.sky,
            automaticSky: widget.appearance.sky == SkyChoice.automatic,
            selectedSky: widget.appearance.sky,
            onSkyChanged: widget.onSkyChanged,
          ),
          1 => const JournalPage(),
          2 => DevicesPage(state: state),
          _ => _SettingsPage(
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
    required this.render3d,
    required this.gaze,
    required this.atmosphere,
    required this.sourceNotice,
    required this.localSelected,
    required this.localStatus,
    required this.sky,
    required this.automaticSky,
    required this.selectedSky,
    required this.onSkyChanged,
  });

  final PlantState state;
  final bool render3d;
  final MossGaze gaze;
  final MossAtmosphere atmosphere;
  final String sourceNotice;
  final bool localSelected;
  final LocalWifiStatus localStatus;
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
                    live: state.isLive,
                    snapshot: state.isSerialSnapshot,
                    connecting:
                        localSelected &&
                        (localStatus == LocalWifiStatus.connecting ||
                            localStatus == LocalWifiStatus.waiting),
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
              _Notice(live: state.isLive, sourceNotice: sourceNotice),
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
                    state.isLive
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
                              : 'Belum terbaca',
                          detail: state.soilPercent != null
                              ? state.soilAdc != null
                                    ? 'ADC ${state.soilAdc} · perkiraan'
                                    : 'Skala belum diverifikasi'
                              : state.soilAdc != null
                              ? 'ADC ${state.soilAdc} · penyebab belum diketahui'
                              : 'Menunggu sensor',
                          color: const Color(0xFF51859A),
                        ),
                      ),
                      SizedBox(
                        width: columnWidth,
                        child: _Metric(
                          icon: Icons.waves_rounded,
                          title: 'Level air',
                          value: switch (state.waterLevel) {
                            WaterLevel.low => 'Low',
                            WaterLevel.medium => 'Medium',
                            WaterLevel.full => 'Full',
                            null => 'Belum terbaca',
                          },
                          detail: state.waterLevel == WaterLevel.full
                              ? 'Perkiraan · bisa hampir penuh'
                              : state.waterLevel != null
                              ? 'Perkiraan · belum terkalibrasi'
                              : state.waterAdc != null
                              ? 'ADC ${state.waterAdc} · belum dapat diklasifikasi'
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
                          detail: state.lightAdc != null
                              ? state.lightPercent != null
                                    ? 'ADC ${state.lightAdc} · perkiraan'
                                    : 'ADC ${state.lightAdc} · belum dapat diestimasi'
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
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.live,
    required this.snapshot,
    required this.connecting,
  });
  final bool live;
  final bool snapshot;
  final bool connecting;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: live ? const Color(0xFFDDE9DA) : const Color(0xFFE9EAE4),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          live ? Icons.sensors_rounded : Icons.cloud_off_outlined,
          size: 14,
          color: live ? forest : muted,
        ),
        const SizedBox(width: 5),
        Text(
          live
              ? 'SENSOR'
              : (snapshot ? 'SERIAL' : (connecting ? 'MENYAMBUNG' : 'OFFLINE')),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w800,
            color: live ? forest : muted,
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.live, required this.sourceNotice});
  final bool live;
  final String sourceNotice;

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
          live ? Icons.sensors_rounded : Icons.wifi_off_rounded,
          size: 19,
          color: context.mossColors.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            sourceNotice,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
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
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.7,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          detail,
          maxLines: 2,
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
  Widget build(BuildContext context) {
    final raw = state.mqAdc;
    final rail = raw == 0 || raw == 4095;
    final detail = state.mqAdcStatus == 'adc_read_failed'
        ? state.mqAdcUnit == 'ADC1'
              ? 'Analog gagal dibaca pada ADC1.'
              : 'Analog gagal dibaca; ADC2 bisa berbenturan dengan Wi-Fi.'
        : rail
        ? 'ADC mencapai batas; penyebab belum diketahui.'
        : raw != null
        ? 'Sinyal analog · belum dikalibrasi'
        : state.mqDigital != null
        ? 'Analog belum tersedia.'
        : 'Belum tersedia dan belum dikalibrasi';
    final detailStyle = TextStyle(
      fontSize: 11,
      height: 1.4,
      color: context.mossColors.onSurfaceVariant,
    );
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.air_rounded, color: context.mossColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sensor udara MQ135',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(detail, style: detailStyle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    raw?.toString() ?? '—',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: context.mossColors.primary,
                    ),
                  ),
                  Text(
                    state.isSerialSnapshot ? 'ADC snapshot' : 'ADC terbaru',
                    style: detailStyle,
                  ),
                ],
              ),
            ],
          ),
          if (state.mqAverageAdc != null && state.mqAverageSamples > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Rata-rata ${state.mqAverageSamples}/12 sampel: ${state.mqAverageAdc} ADC',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            if (state.mqTrend != null) ...[
              const SizedBox(height: 2),
              Text(switch (state.mqTrend) {
                1 => 'Arah sinyal: naik terhadap awal jendela.',
                -1 => 'Arah sinyal: turun terhadap awal jendela.',
                _ => 'Arah sinyal: stabil dalam batas derau.',
              }, style: detailStyle),
            ],
          ] else if (state.isLocalLive) ...[
            const SizedBox(height: 12),
            Text(
              'Rata-rata menunggu sinyal analog non-rel.',
              style: detailStyle,
            ),
          ],
          if (state.mqPinMillivolts != null) ...[
            const SizedBox(height: 4),
            Text(
              'Perkiraan pin ESP32: ~${state.mqPinMillivolts} mV',
              style: detailStyle,
            ),
          ],
          if (state.mqDigital != null) ...[
            const SizedBox(height: 4),
            Text(
              'D0 = ${state.mqDigital}: level pin, bukan ppm atau kualitas udara.',
              style: detailStyle,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'CO₂ belum tersedia · MQ135 merespons beberapa gas, bukan CO₂ saja.',
            style: detailStyle,
          ),
        ],
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
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
      AppearancePanel(
        settings: appearance,
        storageUnavailable: storageUnavailable,
        onThemeChanged: onThemeChanged,
        onSkyChanged: onSkyChanged,
        onManualTimeChanged: onManualTimeChanged,
      ),
      const Divider(height: 32),
      ?cloudSettings,
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
    ],
  );
}
