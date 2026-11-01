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
    String availability({required bool available, required bool usable}) =>
        !available
        ? 'Tidak tersedia'
        : usable
        ? 'Tersedia'
        : 'Tidak dapat menampilkan data';
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
          _ManualControls(
            state: state,
            onCommand: onCommand!,
            controlId: controlId!,
          ),
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
          status: availability(
            available: state.soilAdc != null,
            usable: state.soilPercent != null,
          ),
        ),
        _SensorRow(
          icon: Icons.thermostat_rounded,
          name: 'Suhu & kelembapan udara',
          status: availability(
            available:
                state.temperatureC != null || state.humidityPercent != null,
            usable: state.temperatureC != null || state.humidityPercent != null,
          ),
        ),
        _SensorRow(
          icon: Icons.wb_sunny_outlined,
          name: 'Cahaya',
          status: availability(
            available: state.lightAdc != null,
            usable: state.lightPercent != null,
          ),
        ),
        _SensorRow(
          icon: Icons.wb_twilight_rounded,
          name: 'UV',
          status: availability(
            available: state.uvAdc != null,
            usable: state.uvAdc != null,
          ),
        ),
        _SensorRow(
          icon: Icons.water_drop_outlined,
          name: 'Level air',
          status: state.waterAdc == null
              ? 'Tidak tersedia'
              : state.waterEmpty == true
              ? 'Empty'
              : (state.waterObservationPercent != null ||
                    state.waterPercent != null)
              ? 'Tersedia'
              : 'Tidak dapat menampilkan data',
        ),
        _SensorRow(
          icon: Icons.air_rounded,
          name: 'Sensor udara MQ135',
          status: availability(
            available: state.mqAdc != null || state.mqDigital != null,
            usable: state.mqGasIndex != null,
          ),
        ),
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
      ],
    );
  }

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
  int _lampMinutes = 5;
  int _lampSeconds = 0;
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
    final lampTotal = _lampMinutes * 60 + _lampSeconds;
    final durationSeconds = _target == 'pump'
        ? _duration.round()
        : (lampTotal < 1 ? 1 : (lampTotal > 1800 ? 1800 : lampTotal));
    Navigator.pop(
      context,
      ScheduleEntry(
        id: DateTime.now().microsecondsSinceEpoch,
        target: _target,
        on: _on,
        at: at,
        durationSeconds: durationSeconds,
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
          if (_target == 'light' && _on) ...[
            const SizedBox(height: 8),
            Text(
              'Durasi lampu: '
              '${_lampMinutes.toString().padLeft(2, '0')}:'
              '${_lampSeconds.toString().padLeft(2, '0')} (menit + detik)',
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Menit: $_lampMinutes'),
                      Slider(
                        value: _lampMinutes.toDouble(),
                        min: 0,
                        max: 30,
                        divisions: 30,
                        label: '$_lampMinutes m',
                        onChanged: (value) =>
                            setState(() => _lampMinutes = value.round()),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Detik: $_lampSeconds'),
                      Slider(
                        value: _lampSeconds.toDouble(),
                        min: 0,
                        max: 59,
                        divisions: 59,
                        label: '$_lampSeconds s',
                        onChanged: (value) =>
                            setState(() => _lampSeconds = value.round()),
                      ),
                    ],
                  ),
                ),
              ],
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

enum _ManualMode { on, off, auto }

extension on _ManualMode {
  String get label => switch (this) {
    _ManualMode.on => 'ON',
    _ManualMode.off => 'OFF',
    _ManualMode.auto => 'AUTO',
  };
}

class _ManualControls extends StatefulWidget {
  const _ManualControls({
    required this.state,
    required this.onCommand,
    required this.controlId,
  });

  final PlantState state;
  final Future<bool> Function(String line) onCommand;
  final int Function() controlId;

  @override
  State<_ManualControls> createState() => _ManualControlsState();
}

class _ManualControlsState extends State<_ManualControls> {
  double _pumpSeconds = 5;
  int _lampMinutes = 5;
  int _lampSeconds = 0;
  _ManualMode _pumpMode = _ManualMode.auto;
  _ManualMode _lightMode = _ManualMode.auto;
  bool _busy = false;
  String _message = 'Pilih mode. Tombol yang aktif ditandai.';
  Timer? _pumpTimer;
  Timer? _lightTimer;

  int get _lampTotalSeconds {
    final total = _lampMinutes * 60 + _lampSeconds;
    return total < 1 ? 1 : (total > 1800 ? 1800 : total);
  }

  @override
  void initState() {
    super.initState();
    _pumpMode = _pumpModeFromReason(widget.state.pumpReason);
    _lightMode = _lightModeFromReason(widget.state.lightReason);
  }

  @override
  void didUpdateWidget(covariant _ManualControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pump = _manualPumpMode(widget.state.pumpReason);
    final light = _manualLightMode(widget.state.lightReason);
    if (pump != null) _pumpMode = pump;
    if (light != null) _lightMode = light;
  }

  @override
  void dispose() {
    _pumpTimer?.cancel();
    _lightTimer?.cancel();
    super.dispose();
  }

  _ManualMode _pumpModeFromReason(String? reason) =>
      _manualPumpMode(reason) ?? _ManualMode.auto;

  _ManualMode _lightModeFromReason(String? reason) =>
      _manualLightMode(reason) ?? _ManualMode.auto;

  _ManualMode? _manualPumpMode(String? reason) => switch (reason) {
    'manual_on' => _ManualMode.on,
    'manual_off' => _ManualMode.off,
    'manual_expired' || 'manual_released' => _ManualMode.auto,
    _ => null,
  };

  _ManualMode? _manualLightMode(String? reason) => switch (reason) {
    'manual_on' => _ManualMode.on,
    'manual_off' || 'manual_expired' => _ManualMode.off,
    'manual_released' => _ManualMode.auto,
    _ => null,
  };

  Future<void> _send(
    String line, {
    required _ManualMode mode,
    required bool pump,
  }) async {
    if (_busy) return;
    final previousPump = _pumpMode;
    final previousLight = _lightMode;
    setState(() {
      _busy = true;
      _message = 'Mengirim…';
      if (pump) {
        _pumpMode = mode;
      } else {
        _lightMode = mode;
      }
    });
    final ok = await widget.onCommand(line);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        if (pump) {
          _pumpMode = previousPump;
        } else {
          _lightMode = previousLight;
        }
        _message = 'Perintah gagal; sambungkan Wi-Fi perangkat.';
      } else {
        _message = pump
            ? 'Pompa ${mode.label}${mode == _ManualMode.on ? ' · ${_pumpSeconds.round()} detik' : ''}.'
            : 'Lampu ${mode.label}${mode == _ManualMode.on ? ' · ${_durationText(_lampTotalSeconds)}' : ''}.';
      }
    });
    if (!ok) return;
    if (pump) {
      _pumpTimer?.cancel();
      if (mode == _ManualMode.on) {
        _pumpTimer = Timer(Duration(seconds: _pumpSeconds.round()), () {
          if (mounted && _pumpMode == _ManualMode.on) {
            setState(() => _pumpMode = _ManualMode.auto);
          }
        });
      }
    } else {
      _lightTimer?.cancel();
      if (mode == _ManualMode.on) {
        _lightTimer = Timer(Duration(seconds: _lampTotalSeconds), () {
          if (mounted && _lightMode == _ManualMode.on) {
            setState(() => _lightMode = _ManualMode.off);
          }
        });
      }
    }
  }

  void _setPump(_ManualMode mode) {
    final id = widget.controlId();
    final line = switch (mode) {
      _ManualMode.on => 'CTRL pump=on dur=${_pumpSeconds.round()} id=$id',
      _ManualMode.off => 'CTRL pump=off id=$id',
      _ManualMode.auto => 'CTRL pump=auto id=$id',
    };
    unawaited(_send(line, mode: mode, pump: true));
  }

  void _setLight(_ManualMode mode) {
    final id = widget.controlId();
    final line = switch (mode) {
      _ManualMode.on => 'CTRL light=on dur=$_lampTotalSeconds id=$id',
      _ManualMode.off => 'CTRL light=off id=$id',
      _ManualMode.auto => 'CTRL light=auto id=$id',
    };
    unawaited(_send(line, mode: mode, pump: false));
  }

  static String _durationText(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${rest.toString().padLeft(2, '0')}';
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
          'Kendali manual',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Pilih ON, OFF, atau AUTO. Tombol yang aktif diberi warna dan label AKTIF. '
          'Perintah dikirim langsung ke ESP32.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: context.mossColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _ControlBlock(
          title: 'Pompa',
          icon: Icons.water_drop_rounded,
          accent: const Color(0xFF3F7FA8),
          mode: _pumpMode,
          busy: _busy,
          onMode: _setPump,
          children: [
            Text('Durasi pompa: ${_pumpSeconds.round()} detik'),
            Slider(
              value: _pumpSeconds,
              min: 1,
              max: 30,
              divisions: 29,
              label: '${_pumpSeconds.round()} s',
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _pumpSeconds = value),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _ControlBlock(
          title: 'Lampu',
          icon: Icons.lightbulb_outline_rounded,
          accent: const Color(0xFFB8862E),
          mode: _lightMode,
          busy: _busy,
          onMode: _setLight,
          children: [
            Text(
              'Durasi lampu: ${_durationText(_lampTotalSeconds)} '
              '(menit + detik)',
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Menit: $_lampMinutes'),
                      Slider(
                        value: _lampMinutes.toDouble(),
                        min: 0,
                        max: 30,
                        divisions: 30,
                        label: '$_lampMinutes m',
                        onChanged: _busy
                            ? null
                            : (value) =>
                                  setState(() => _lampMinutes = value.round()),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Detik: $_lampSeconds'),
                      Slider(
                        value: _lampSeconds.toDouble(),
                        min: 0,
                        max: 59,
                        divisions: 59,
                        label: '$_lampSeconds s',
                        onChanged: _busy
                            ? null
                            : (value) =>
                                  setState(() => _lampSeconds = value.round()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
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

class _ControlBlock extends StatelessWidget {
  const _ControlBlock({
    required this.title,
    required this.icon,
    required this.accent,
    required this.mode,
    required this.busy,
    required this.onMode,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final _ManualMode mode;
  final bool busy;
  final ValueChanged<_ManualMode> onMode;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'AKTIF: ${mode.label}',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<_ManualMode>(
          segments: const [
            ButtonSegment(
              value: _ManualMode.on,
              label: Text('ON'),
              icon: Icon(Icons.power_settings_new_rounded),
            ),
            ButtonSegment(
              value: _ManualMode.off,
              label: Text('OFF'),
              icon: Icon(Icons.power_off_rounded),
            ),
            ButtonSegment(
              value: _ManualMode.auto,
              label: Text('AUTO'),
              icon: Icon(Icons.autorenew_rounded),
            ),
          ],
          selected: {mode},
          onSelectionChanged: busy ? null : (values) => onMode(values.first),
          showSelectedIcon: true,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? accent.withValues(alpha: .18)
                  : null;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected) ? accent : null;
            }),
          ),
        ),
      ),
      const SizedBox(height: 8),
      ...children,
    ],
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
