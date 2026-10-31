import 'package:flutter/material.dart';

import 'moss_app.dart';
import 'plant_state.dart';

/// Preview controls are local UI state and never send device commands.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.state});
  final PlantState state;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  bool _pumpPreview = false;
  bool _lightPreview = false;

  @override
  void didUpdateWidget(covariant DevicesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.isDemo && !widget.state.isDemo) {
      _pumpPreview = false;
      _lightPreview = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    String status(bool available) => state.isDemo
        ? 'Simulasi'
        : available
        ? 'Belum diverifikasi'
        : 'Belum ada data';

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text(
          'SMART PLANTER',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w800,
            color: context.mossColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Perangkat',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.mossColors.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.sensors_rounded,
                color: context.mossColors.onPrimaryContainer,
                size: 28,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isDemo
                          ? 'Pratinjau perangkat'
                          : state.isLive
                          ? 'Data sensor tersedia'
                          : state.isSerialSnapshot
                          ? 'Data serial tersimpan'
                          : 'Menunggu data perangkat',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.mossColors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      state.isDemo
                          ? 'SIMULASI — bukan status ESP32 sebenarnya.'
                          : 'Status pompa dan lampu belum dapat diverifikasi dari aplikasi.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.mossColors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Sensor',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        _SensorRow(
          icon: Icons.grass_rounded,
          name: 'Kelembapan tanah',
          status: status(state.soilPercent != null || state.soilAdc != null),
        ),
        _SensorRow(
          icon: Icons.thermostat_rounded,
          name: 'Suhu & kelembapan udara',
          status: status(
            state.temperatureC != null || state.humidityPercent != null,
          ),
        ),
        _SensorRow(
          icon: Icons.wb_sunny_outlined,
          name: 'Cahaya',
          status: status(state.lightPercent != null),
        ),
        _SensorRow(
          icon: Icons.wb_twilight_rounded,
          name: 'UV',
          status: state.uvIndex == null && state.uvAdc == null
              ? 'Belum ada data'
              : state.isDemo
              ? 'Simulasi'
              : 'Belum diverifikasi',
        ),
        _SensorRow(
          icon: Icons.water_drop_outlined,
          name: 'Level air',
          status: state.waterPercent != null && !state.isDemo
              ? 'Skala relatif belum diverifikasi'
              : state.waterAdc == null
              ? 'Belum tersedia'
              : 'ADC belum diverifikasi',
        ),
        _SensorRow(
          icon: Icons.air_rounded,
          name: 'Sensor udara MQ135',
          status: state.mqAdc == null && state.mqDigital == null
              ? 'Belum tersedia'
              : 'ADC/digital belum diverifikasi',
        ),
        if (state.isSerialSnapshot &&
            (state.pumpRulePreview != null ||
                state.lightRulePreview != null ||
                state.waterLowPreview != null)) ...[
          const SizedBox(height: 22),
          const Text(
            'Pratinjau aturan serial',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Perhitungan dari snapshot dan skala relatif belum diverifikasi; '
            'bukan perintah, status relay, atau notifikasi live.',
          ),
          const SizedBox(height: 8),
          Text('Pompa <50%: ${_previewText(state.pumpRulePreview)}'),
          Text('Lampu <60%: ${_previewText(state.lightRulePreview)}'),
          Text('Air <20%: ${_waterPreviewText(state.waterLowPreview)}'),
        ],
        if (state.isLocalLive &&
            (state.pumpCommand != null || state.lightCommand != null)) ...[
          const SizedBox(height: 22),
          const Text(
            'Perintah firmware',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('Pompa: ${_commandText(state.pumpCommand)}'),
          Text('Lampu: ${_commandText(state.lightCommand)}'),
          const Text(
            'Perintah bukan pengukuran kontak relay atau keadaan beban.',
          ),
          if (state.lightingCandidate != null)
            Text(
              'Aturan lampu (pratinjau): ${_lightingCandidateText(state.lightingCandidate)}',
            ),
        ],
        const SizedBox(height: 22),
        Text(
          state.isDemo ? 'Kendali simulasi' : 'Kendali perangkat',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (state.isDemo)
          Material(
            color: context.mossColors.surfaceContainerLowest,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: context.mossColors.outlineVariant),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'SIMULASI — saklar ini tidak mengendalikan pompa atau lampu nyata.',
                    style: TextStyle(
                      color: context.mossColors.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Simulasi pompa'),
                  subtitle: Text(
                    _pumpPreview ? 'Contoh: menyala' : 'Contoh: mati',
                  ),
                  value: _pumpPreview,
                  onChanged: (value) => setState(() => _pumpPreview = value),
                ),
                SwitchListTile(
                  title: const Text('Simulasi lampu'),
                  subtitle: Text(
                    _lightPreview ? 'Contoh: menyala' : 'Contoh: mati',
                  ),
                  value: _lightPreview,
                  onChanged: (value) => setState(() => _lightPreview = value),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.mossColors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  color: context.mossColors.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Kendali nyata belum tersedia. Aplikasi tidak menyalakan atau mematikan aktuator.',
                    style: TextStyle(
                      color: context.mossColors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _previewText(bool? value) => value == null
      ? 'Belum tersedia'
      : value
      ? 'Menyala (pratinjau)'
      : 'Mati (pratinjau)';

  String _waterPreviewText(bool? value) => value == null
      ? 'Belum tersedia'
      : value
      ? 'Di bawah ambang (snapshot)'
      : 'Tidak di bawah ambang (snapshot)';

  String _commandText(bool? value) => value == null
      ? 'Tidak diketahui'
      : value
      ? 'ON diminta'
      : 'OFF diminta';

  String _lightingCandidateText(String? value) => switch (value) {
    'on' => 'ingin ON',
    'off' => 'ingin OFF',
    'hold' => 'pertahankan',
    _ => 'belum tersedia',
  };
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({
    required this.icon,
    required this.name,
    required this.status,
  });
  final IconData icon;
  final String name;
  final String status;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: context.mossColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.mossColors.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(icon, color: context.mossColors.primary, size: 20),
        const SizedBox(width: 11),
        Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
        const SizedBox(width: 8),
        Text(
          status,
          style: TextStyle(
            color: context.mossColors.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}
