import 'package:flutter/material.dart';

import 'dart:async';

import 'local_wifi.dart';
import 'moss_app.dart';
import 'plant_state.dart';
import 'schedule.dart';

/// Displays sensor availability and requested firmware commands; read-only.
class DevicesPage extends StatelessWidget {
  const DevicesPage({
    super.key,
    required this.state,
    this.localSelected = false,
    this.localStatus = LocalWifiStatus.disconnected,
    this.onCommand,
    this.controlId,
    this.schedules = const [],
    this.onAddSchedule,
    this.onDeleteSchedule,
  });
  final PlantState state;
  final bool localSelected;
  final LocalWifiStatus localStatus;
  final Future<bool> Function(String line)? onCommand;
  final int Function()? controlId;
  final List<ScheduleEntry> schedules;
  final Future<void> Function(ScheduleEntry entry)? onAddSchedule;
  final Future<void> Function(int id)? onDeleteSchedule;

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
        if (onCommand != null && controlId != null) ...[
          const SizedBox(height: 20),
          _ManualControls(onCommand: onCommand!, controlId: controlId!),
        ],
        if (onAddSchedule != null && onDeleteSchedule != null) ...[
          const SizedBox(height: 20),
          _SchedulePanel(
            schedules: schedules,
            onAdd: onAddSchedule!,
            onDelete: onDeleteSchedule!,
          ),
        ],
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

class _SchedulePanel extends StatelessWidget {
  const _SchedulePanel({
    required this.schedules,
    required this.onAdd,
    required this.onDelete,
  });
  final List<ScheduleEntry> schedules;
  final Future<void> Function(ScheduleEntry entry) onAdd;
  final Future<void> Function(int id) onDelete;

  Future<void> _add(BuildContext context) async {
    final entry = await showDialog<ScheduleEntry>(
      context: context,
      builder: (_) => const _ScheduleDialog(),
    );
    if (entry != null) await onAdd(entry);
  }

  @override
  Widget build(BuildContext context) => Container(
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
          'Jadwal otomatis',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Berjalan saat aplikasi terbuka dan terhubung ke Wi-Fi Moss. '
          'Jadwal disimpan di ponsel.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: context.mossColors.onSurfaceVariant,
          ),
        ),
        if (schedules.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final entry in schedules)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded, size: 20),
              title: Text(entry.label, style: const TextStyle(fontSize: 12)),
              trailing: IconButton(
                tooltip: 'Hapus jadwal',
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: () => onDelete(entry.id),
              ),
            ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _add(context),
          icon: const Icon(Icons.add_alarm_rounded, size: 18),
          label: const Text('Tambah jadwal'),
        ),
      ],
    ),
  );
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog();

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  String _target = 'pump';
  bool _on = true;
  DateTime _at = DateTime.now().add(const Duration(minutes: 5));
  int _second = 0;
  double _duration = 5;
  String? _error;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(
        () => _at = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _at.hour,
          _at.minute,
          _second,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (picked != null) {
      setState(
        () => _at = DateTime(
          _at.year,
          _at.month,
          _at.day,
          picked.hour,
          picked.minute,
          _second,
        ),
      );
    }
  }

  void _save() {
    final at = DateTime(
      _at.year,
      _at.month,
      _at.day,
      _at.hour,
      _at.minute,
      _second,
    );
    if (!at.isAfter(DateTime.now())) {
      setState(() => _error = 'Waktu jadwal harus di masa depan.');
      return;
    }
    Navigator.pop(
      context,
      ScheduleEntry(
        id: DateTime.now().microsecondsSinceEpoch,
        target: _target,
        on: _on,
        at: at,
        durationSeconds: _duration.round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tambah jadwal'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _target,
            decoration: const InputDecoration(labelText: 'Perangkat'),
            items: const [
              DropdownMenuItem(value: 'pump', child: Text('Pompa')),
              DropdownMenuItem(value: 'light', child: Text('Lampu')),
            ],
            onChanged: (value) => setState(() => _target = value ?? 'pump'),
          ),
          DropdownButtonFormField<bool>(
            initialValue: _on,
            decoration: const InputDecoration(labelText: 'Aksi'),
            items: const [
              DropdownMenuItem(value: true, child: Text('ON')),
              DropdownMenuItem(value: false, child: Text('OFF')),
            ],
            onChanged: (value) => setState(() => _on = value ?? true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tanggal'),
            subtitle: Text('${_at.day}/${_at.month}/${_at.year}'),
            trailing: const Icon(Icons.calendar_today_rounded),
            onTap: _pickDate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Jam'),
            subtitle: Text(
              '${_at.hour.toString().padLeft(2, '0')}:'
              '${_at.minute.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.access_time_rounded),
            onTap: _pickTime,
          ),
          DropdownButtonFormField<int>(
            initialValue: _second,
            decoration: const InputDecoration(labelText: 'Detik'),
            items: [
              for (var second = 0; second < 60; second++)
                DropdownMenuItem(value: second, child: Text('$second')),
            ],
            onChanged: (value) => setState(() => _second = value ?? 0),
          ),
          if (_target == 'pump' && _on) ...[
            const SizedBox(height: 8),
            Text('Durasi pompa: ${_duration.round()} detik'),
            Slider(
              value: _duration,
              min: 1,
              max: 30,
              divisions: 29,
              onChanged: (value) => setState(() => _duration = value),
            ),
          ],
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _save, child: const Text('Simpan')),
    ],
  );
}

class _ManualControls extends StatefulWidget {
  const _ManualControls({required this.onCommand, required this.controlId});
  final Future<bool> Function(String line) onCommand;
  final int Function() controlId;

  @override
  State<_ManualControls> createState() => _ManualControlsState();
}

class _ManualControlsState extends State<_ManualControls> {
  double _duration = 5;
  bool _busy = false;
  String _message = 'Pilih perintah; status relay fisik tidak diukur.';

  Future<void> _send(String line) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Mengirim…';
    });
    final ok = await widget.onCommand(line);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = ok
          ? 'Perintah terkirim. Pompa ON maksimal ${_duration.round()} detik.'
          : 'Perintah gagal; sambungkan Wi-Fi Moss.';
    });
  }

  String _id() => widget.controlId().toString();

  @override
  Widget build(BuildContext context) => Container(
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
          'Kendali manual',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Override otomatis. Pompa ON dibatasi 30 detik, lalu kembali otomatis.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: context.mossColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Text('Durasi pompa: ${_duration.round()} detik'),
        Slider(
          value: _duration,
          min: 1,
          max: 30,
          divisions: 29,
          label: '${_duration.round()} s',
          onChanged: _busy
              ? null
              : (value) => setState(() => _duration = value),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _send(
                        'CTRL pump=on dur=${_duration.round()} id=${_id()}',
                      ),
                    ),
              child: const Text('Pompa ON'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => unawaited(_send('CTRL pump=off id=${_id()}')),
              child: const Text('Pompa OFF'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => unawaited(_send('CTRL pump=auto id=${_id()}')),
              child: const Text('Pompa AUTO'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => unawaited(_send('CTRL light=on id=${_id()}')),
              child: const Text('Lampu ON'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => unawaited(_send('CTRL light=off id=${_id()}')),
              child: const Text('Lampu OFF'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => unawaited(_send('CTRL light=auto id=${_id()}')),
              child: const Text('Lampu AUTO'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _message,
          style: TextStyle(
            fontSize: 11,
            color: context.mossColors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
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
