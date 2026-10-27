import 'package:flutter/material.dart';

import 'moss_app.dart';
import 'moss_avatar.dart';
import 'plant_state.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.render3d});

  final bool render3d;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  var _page = 0;
  var _demo = true;
  var _scenario = DemoScenario.content;

  @override
  Widget build(BuildContext context) {
    final state = _demo
        ? PlantState.demo(_scenario)
        : const PlantState.waiting();
    return Scaffold(
      body: SafeArea(
        child: switch (_page) {
          0 => _Home(
            state: state,
            scenario: _scenario,
            render3d: widget.render3d,
            onScenario: (value) => setState(() => _scenario = value),
            onDemoChanged: () => setState(() => _demo = !_demo),
          ),
          1 => const _InfoPage(
            eyebrow: 'JURNAL TANAMAN',
            title: 'Riwayat',
            icon: Icons.history_rounded,
            heading: 'Belum ada riwayat',
            body: 'Catatan sensor akan muncul di sini setelah perangkat dan cloud terhubung. Data demo tidak disimpan sebagai riwayat.',
          ),
          _ => _SettingsPage(
            demo: _demo,
            onDemoChanged: () => setState(() => _demo = !_demo),
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
    required this.onScenario,
    required this.onDemoChanged,
  });

  final PlantState state;
  final DemoScenario scenario;
  final bool render3d;
  final ValueChanged<DemoScenario> onScenario;
  final VoidCallback onDemoChanged;

  String _percent(int? value) => value == null ? '—' : '$value%';

  @override
  Widget build(BuildContext context) {
    final mood = state.mood;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SMART PLANTER',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                            color: muted,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
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
                  _StatusPill(demo: state.isDemo),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE5EDE1),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.eco_outlined,
                            color: forest,
                            size: 17,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              mood.label.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: forest,
                              ),
                            ),
                          ),
                          const Text(
                            '01  /  MOSS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 235,
                      width: double.infinity,
                      child: render3d
                          ? MossAvatar(mood: mood)
                          : const Center(
                              child: Icon(
                                Icons.spa_outlined,
                                size: 88,
                                color: forest,
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
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            mood.explanation,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Notice(demo: state.isDemo, onToggle: onDemoChanged),
              if (state.isDemo) ...[
                const SizedBox(height: 20),
                const Text(
                  'COBA KONDISI MOSS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: muted,
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
                    state.isDemo ? 'CONTOH DATA' : 'BELUM TERHUBUNG',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: muted,
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
                          detail: state.isDemo
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
              const Text(
                'Ekspresi Moss saat ini menggunakan aturan contoh, bukan hasil model machine learning.',
                style: TextStyle(color: muted, fontSize: 11, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.demo});
  final bool demo;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: demo ? const Color(0xFFF0E6CF) : const Color(0xFFE9EAE4),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          demo ? Icons.science_outlined : Icons.cloud_off_outlined,
          size: 14,
          color: demo ? const Color(0xFF8B6937) : muted,
        ),
        const SizedBox(width: 5),
        Text(
          demo ? 'SIMULASI' : 'OFFLINE',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w800,
            color: demo ? const Color(0xFF8B6937) : muted,
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.demo, required this.onToggle});
  final bool demo;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFE6E9DF)),
    ),
    child: Row(
      children: [
        Icon(
          demo ? Icons.science_outlined : Icons.wifi_off_rounded,
          size: 19,
          color: forest,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            demo
                ? 'Simulasi — bukan data sensor.'
                : 'Perangkat dan cloud belum terhubung.',
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
    selectedColor: forest,
    backgroundColor: Colors.white,
    labelStyle: TextStyle(
      color: selected ? Colors.white : ink,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    side: BorderSide(color: selected ? forest : const Color(0xFFE0E5DC)),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFFEBEDE6)),
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
          style: const TextStyle(
            color: muted,
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
          style: const TextStyle(color: muted, fontSize: 11),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFFEBEDE6)),
    ),
    child: Row(
      children: [
        const Icon(Icons.air_rounded, color: forest),
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
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
        ),
        Text(
          state.isDemo ? (state.airChanged ? 'BERUBAH' : 'STABIL') : '—',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: forest,
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
      color: const Color(0xFFF0EEE6),
      borderRadius: BorderRadius.circular(17),
    ),
    child: const Row(
      children: [
        Icon(Icons.power_settings_new_rounded, color: muted),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pompa & lampu',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              SizedBox(height: 4),
              Text(
                'Kontrol tersedia setelah ESP32 terhubung.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
        Icon(Icons.lock_outline_rounded, size: 18, color: muted),
      ],
    ),
  );
}

class _InfoPage extends StatelessWidget {
  const _InfoPage({
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.heading,
    required this.body,
  });
  final String eyebrow;
  final String title;
  final IconData icon;
  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: forest, size: 42),
                const SizedBox(height: 18),
                Text(
                  heading,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.demo, required this.onDemoChanged});
  final bool demo;
  final VoidCallback onDemoChanged;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'PREFERENSI',
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
          color: muted,
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
        subtitle: const Text(
          'Coba ekspresi Moss tanpa perangkat.',
          style: TextStyle(color: muted),
        ),
        value: demo,
        onChanged: (_) => onDemoChanged(),
      ),
      const Divider(height: 32),
      const _SettingLine(
        icon: Icons.cloud_outlined,
        title: 'Koneksi cloud',
        body: 'Project Supabase sudah disiapkan; aplikasi belum terhubung.',
      ),
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
        Icon(icon, color: forest, size: 21),
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
                style: const TextStyle(color: muted, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
