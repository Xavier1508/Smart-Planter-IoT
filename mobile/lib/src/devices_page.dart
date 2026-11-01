import 'package:flutter/material.dart';

import 'local_wifi.dart';
import 'moss_app.dart';
import 'plant_state.dart';

/// Displays sensor availability and requested firmware commands; read-only.
class DevicesPage extends StatelessWidget {
  const DevicesPage({
    super.key,
    required this.state,
    this.localSelected = false,
    this.localStatus = LocalWifiStatus.disconnected,
  });
  final PlantState state;
  final bool localSelected;
  final LocalWifiStatus localStatus;

  @override
  Widget build(BuildContext context) {
    String status(bool available) => available ? 'Tersedia' : 'Belum ada data';
    final connected =
        localSelected &&
        (localStatus == LocalWifiStatus.live ||
            localStatus == LocalWifiStatus.waiting);
    final connectionTitle = state.isSerialSnapshot
        ? 'Data serial tersimpan'
        : state.isLive && state.hasSensorData
        ? 'Sudah terhubung'
        : localSelected && localStatus == LocalWifiStatus.connecting
        ? 'Menghubungkan…'
        : connected
        ? 'Sudah terhubung, belum ada data'
        : 'Belum terhubung';

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
                      connectionTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.mossColors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Perintah relay bukan pengukuran kontak atau beban fisik.',
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
          status: state.soilPercent != null && state.soilAdc != null
              ? 'ADC ${state.soilAdc} · ${state.soilPercent}%'
              : state.soilAdc != null
              ? 'Belum ada data · ADC ${state.soilAdc}'
              : 'Belum ada data',
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
          status: state.lightPercent != null && state.lightAdc != null
              ? 'ADC ${state.lightAdc} · ${state.lightPercent}%'
              : status(state.lightPercent != null),
        ),
        _SensorRow(
          icon: Icons.wb_twilight_rounded,
          name: 'UV',
          status: state.uvAdc != null
              ? 'ADC ${state.uvAdc}'
              : state.uvIndex != null
              ? 'Tersedia'
              : 'Belum ada data',
        ),
        _SensorRow(
          icon: Icons.water_drop_outlined,
          name: 'Level air',
          status: state.waterAdc != null
              ? 'ADC ${state.waterAdc}'
              : 'Belum dapat diklasifikasi',
        ),
        _SensorRow(
          icon: Icons.air_rounded,
          name: 'Sensor udara MQ135',
          status: state.mqGasIndex != null
              ? 'Indeks gas ${state.mqGasIndex}/100 · relatif'
              : state.mqAdc != null
              ? 'ADC ${state.mqAdc} · indeks belum tersedia'
              : state.mqDigital == null
              ? 'Belum tersedia'
              : 'Digital ${state.mqDigital}',
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
            'Perhitungan dari snapshot; bukan perintah, status relay, '
            'atau notifikasi live.',
          ),
          const SizedBox(height: 8),
          Text(
            'Pompa <${state.pumpRuleThreshold ?? '?'}%: ${_previewText(state.pumpRulePreview)}',
          ),
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
          if (state.pumpReason != null)
            Text('Alasan pompa: ${_pumpReasonText(state.pumpReason)}'),
          Text('Lampu: ${_commandText(state.lightCommand)}'),
          if (state.lightReason != null)
            Text('Alasan lampu: ${_lightReasonText(state.lightReason)}'),
          const Text(
            'Perintah bukan pengukuran kontak relay atau keadaan beban.',
          ),
        ],
        const SizedBox(height: 22),
        const Text(
          'Kendali perangkat',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
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
                  'Otomasi pompa dan lampu berjalan di ESP32; aplikasi ini hanya memantau.',
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

  String _pumpReasonText(String? value) => switch (value) {
    'boot_grace' => 'menunggu setelah dinyalakan',
    'soil_not_dry' => 'tanah belum di bawah batas nyala',
    'soil_moist' => 'tanah mencapai batas berhenti',
    'soil_dry' => 'tanah di bawah batas nyala',
    'watering' => 'siklus penyiraman berjalan',
    'cooldown' => 'jeda antarsiklus',
    'dry_confirm' => 'menunggu tanah kering terkonfirmasi',
    'water_low' => 'air di bawah batas relatif',
    'water_unavailable' => 'data air belum tersedia',
    'soil_unverified' => 'skala tanah belum diizinkan',
    'soil_unavailable' => 'data tanah belum tersedia',
    'watchdog_unavailable' => 'pengawas perangkat belum tersedia',
    'sample_stale' => 'data sensor terlambat',
    'runtime_limit' => 'batas waktu pompa tercapai',
    _ => 'belum diketahui',
  };

  String _lightReasonText(String? value) => switch (value) {
    'boot_grace' => 'menunggu setelah dinyalakan',
    'light_low' => 'LDR dan proksi UV memenuhi syarat',
    'light_sufficient' => 'LDR cukup terang atau proksi UV tinggi',
    'light_input_unavailable' => 'input LDR belum tersedia',
    'ldr_low' => 'cahaya LDR di bawah 65%',
    'ldr_sufficient' => 'cahaya LDR 65% atau lebih',
    'ldr_input_unavailable' => 'input LDR belum tersedia',
    'light_inhibited' => 'otomasi lampu belum diaktifkan',
    'minimum_hold' => 'menunggu jeda perpindahan',
    'hysteresis' => 'mempertahankan keadaan di zona jeda',
    'watchdog_unavailable' => 'pengawas perangkat belum tersedia',
    'sample_stale' => 'data sensor terlambat',
    _ => 'belum diketahui',
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
        Flexible(
          child: Text(
            status,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: context.mossColors.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ),
      ],
    ),
  );
}
