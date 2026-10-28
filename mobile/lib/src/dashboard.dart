import 'dart:async';

import 'package:flutter/material.dart';

import 'appearance.dart';
import 'appearance_panel.dart';
import 'app_version_panel.dart';
import 'devices_page.dart';
import 'journal_page.dart';
import 'moss_app.dart';
import 'moss_avatar.dart';
import 'moss_sky.dart';
import 'plant_state.dart';
import 'plant_telemetry.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    required this.render3d,
    this.telemetry,
    this.cloudSettings,
    this.cloudSetupNotice,
    required this.appearance,
    required this.sky,
    required this.storageUnavailable,
    required this.onThemeChanged,
    required this.onSkyChanged,
    required this.onManualTimeChanged,
  });

  final bool render3d;
  final Stream<PlantTelemetry>? telemetry;
  final Widget? cloudSettings;
  final String? cloudSetupNotice;
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
  var _sourceNotice = 'Perangkat dan cloud belum terhubung.';
  DateTime? _lastRecordedAt;
  int? _lastSequence;
  StreamSubscription<PlantTelemetry>? _subscription;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    _listenToTelemetry();
  }

  @override
  void didUpdateWidget(covariant Dashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.telemetry != widget.telemetry) _listenToTelemetry();
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

  @override
  void dispose() {
    _expiry?.cancel();
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _demo ? PlantState.demo(_scenario) : _liveState;
    return Scaffold(
      body: SafeArea(
        child: switch (_page) {
          0 => _Home(
            state: state,
            scenario: _scenario,
            render3d: widget.render3d,
            sourceNotice: _sourceNotice,
            sky: widget.sky,
            automaticSky: widget.appearance.sky == SkyChoice.automatic,
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
    required this.sourceNotice,
    required this.onScenario,
    required this.onDemoChanged,
    required this.sky,
    required this.automaticSky,
  });

  final PlantState state;
  final DemoScenario scenario;
  final bool render3d;
  final String sourceNotice;
  final ValueChanged<DemoScenario> onScenario;
  final VoidCallback onDemoChanged;
  final SkyAppearance sky;
  final bool automaticSky;

  String _percent(int? value) => value == null ? '—' : '$value%';

  @override
  Widget build(BuildContext context) {
    final mood = state.mood;
    final skyInk = MossSky.foregroundFor(sky.bottom);
    final skyHeaderInk = MossSky.foregroundFor(sky.top);
    final mutedColor = context.mossColors.onSurfaceVariant;
    final tint = Color.lerp(
      const Color(0x44233665),
      const Color(0x12FFD38C),
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
                  _StatusPill(demo: state.isDemo, live: state.isLive),
                ],
              ),
              const SizedBox(height: 22),
              MossSky(
                sky: sky,
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
                              mood.label.toUpperCase(),
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
                            ? MossAvatar(mood: mood)
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
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                      child: Column(
                        children: [
                          Text(
                            mood.message,
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
                          value: _percent(state.soilPercent),
                          detail: state.soilPercent != null
                              ? 'Kondisi tanah'
                              : 'Menunggu sensor',
                          color: const Color(0xFF51859A),
                        ),
                      ),
                      SizedBox(
                        width: columnWidth,
                        child: _Metric(
                          icon: Icons.waves_rounded,
                          title: 'Air dalam wadah',
                          value: _percent(state.waterPercent),
                          detail: state.isDemo
                              ? 'Level simulasi'
                              : 'Belum dipasang',
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
                          value: _percent(state.lightPercent),
                          detail: state.isDemo
                              ? 'Intensitas contoh'
                              : state.lightPercent != null
                              ? 'Pembacaan sensor'
                              : 'Menunggu sensor',
                          color: const Color(0xFFAB843A),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              _AirRow(state: state),
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
                'Ekspresi Moss menggunakan aturan sederhana, bukan hasil model machine learning.',
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
  const _StatusPill({required this.demo, required this.live});
  final bool demo;
  final bool live;

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
          demo ? 'SIMULASI' : (live ? 'SENSOR' : 'OFFLINE'),
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
                    : 'Belum dipasang dan belum dikalibrasi',
                style: TextStyle(
                  fontSize: 11,
                  color: context.mossColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(
          state.isDemo ? (state.airChanged ? 'BERUBAH' : 'STABIL') : '—',
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
      const AppVersionPanel(),
      const _SettingLine(
        icon: Icons.sensors_outlined,
        title: 'Sensor tambahan',
        body: 'Sensor air dan MQ135 menunggu pemasangan dan konfigurasi pin.',
      ),
      const _SettingLine(
        icon: Icons.notifications_none_rounded,
        title: 'Notifikasi',
        body: 'Notifikasi nyata belum dikonfigurasi.',
      ),
      const _SettingLine(
        icon: Icons.psychology_outlined,
        title: 'Ekspresi Moss',
        body: 'Saat ini menggunakan aturan simulasi, bukan prediksi ML.',
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
