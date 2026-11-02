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
    this.runningSchedules = const [],
    this.onAddSchedule,
    this.onDeleteSchedule,
    this.onStopRunningSchedule,
  });
  final PlantState state;
  final bool localSelected;
  final LocalWifiStatus localStatus;
  final Future<bool> Function(String line)? onCommand;
  final int Function()? controlId;
  final List<ScheduleEntry> schedules;
  final List<RunningSchedule> runningSchedules;
  final Future<void> Function(ScheduleEntry entry)? onAddSchedule;
  final Future<void> Function(int id)? onDeleteSchedule;
  final Future<void> Function(RunningSchedule running)? onStopRunningSchedule;

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
        : localSelected &&
              localStatus == LocalWifiStatus.live &&
              state.hasSensorData
        ? 'Sudah terhubung'
        : localSelected && localStatus == LocalWifiStatus.live
        ? 'Sudah terhubung, belum ada data'
        : localSelected && state.hasSensorData
        ? 'Koneksi terputus · menampilkan data terakhir'
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
            runningSchedules: runningSchedules,
            connected: localSelected && localStatus == LocalWifiStatus.live,
            onAdd: onAddSchedule!,
            onDelete: onDeleteSchedule!,
            onStopRunning: onStopRunningSchedule,
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
              : switch (state.waterLevel) {
                  WaterLevel.empty => 'Empty',
                  WaterLevel.low => 'Low',
                  WaterLevel.medium => 'Medium',
                  WaterLevel.full => 'Full',
                  null => 'Tidak dapat menampilkan data',
                },
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
          if ((state.pumpCooldownSeconds ?? 0) > 0)
            Text(
              state.pumpRuntimeLockout == true
                  ? 'Jeda otomatis: ${_cooldownText(state.pumpCooldownSeconds!)} '
                        '(setelah batas 5 menit)'
                  : 'Jeda pompa: ${_cooldownText(state.pumpCooldownSeconds!)}',
            ),
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

  String _cooldownText(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (minutes <= 0) return '$rest dtk';
    return rest == 0 ? '$minutes mnt' : '$minutes mnt $rest dtk';
  }

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
    'soil_no_response' => 'tanah tidak merespons penyiraman',
    'brownout_hold' => 'pompa ditahan setelah brownout',
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

class _SchedulePanel extends StatefulWidget {
  const _SchedulePanel({
    required this.schedules,
    required this.runningSchedules,
    required this.connected,
    required this.onAdd,
    required this.onDelete,
    required this.onStopRunning,
  });

  final List<ScheduleEntry> schedules;
  final List<RunningSchedule> runningSchedules;
  final bool connected;
  final Future<void> Function(ScheduleEntry entry) onAdd;
  final Future<void> Function(int id) onDelete;
  final Future<void> Function(RunningSchedule running)? onStopRunning;

  @override
  State<_SchedulePanel> createState() => _SchedulePanelState();
}

class _SchedulePanelState extends State<_SchedulePanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The countdown is presentation-only; the ESP32 owns the actual relay
    // duration. A one-second tick keeps the remaining time readable.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _add() async {
    final entry = await showDialog<ScheduleEntry>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ScheduleDialog(connected: widget.connected),
    );
    if (entry != null) await widget.onAdd(entry);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final running = widget.runningSchedules
        .where((item) => !item.expired(now))
        .toList(growable: false);
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
            children: [
              Icon(
                Icons.event_note_rounded,
                size: 20,
                color: context.mossColors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Jadwal & aksi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Tambah aksi',
                onPressed: _add,
                icon: const Icon(Icons.add_alarm_rounded),
              ),
            ],
          ),
          Text(
            'Aksi "Sekarang" langsung dijalankan. Aksi terjadwal memakai '
            'kalender dan jam ponsel; keduanya disimpan di perangkat ini.',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: context.mossColors.onSurfaceVariant,
            ),
          ),
          if (running.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _SectionLabel(text: 'SEDANG BERJALAN'),
            const SizedBox(height: 6),
            for (final item in running)
              _RunningScheduleTile(
                running: item,
                now: now,
                onStop: widget.onStopRunning == null
                    ? null
                    : () => widget.onStopRunning!(item),
              ),
          ],
          if (widget.schedules.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _SectionLabel(text: 'BERIKUTNYA'),
            const SizedBox(height: 6),
            for (final entry in widget.schedules)
              _PendingScheduleTile(
                entry: entry,
                now: now,
                connected: widget.connected,
                onDelete: () => widget.onDelete(entry.id),
              ),
          ],
          if (running.isEmpty && widget.schedules.isEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.mossColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Belum ada aksi. Tambahkan jadwal atau nyalakan relay '
                'langsung untuk melihat hitungan mundur di sini.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: context.mossColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tambah aksi'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 9,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w800,
      color: context.mossColors.onSurfaceVariant,
    ),
  );
}

class _RunningScheduleTile extends StatelessWidget {
  const _RunningScheduleTile({
    required this.running,
    required this.now,
    required this.onStop,
  });

  final RunningSchedule running;
  final DateTime now;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final entry = running.entry;
    final remaining = running.remainingSeconds(now);
    final timer =
        '${(remaining ~/ 60).toString().padLeft(2, '0')}:'
        '${(remaining % 60).toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            entry.target == 'pump'
                ? Icons.water_drop_rounded
                : Icons.lightbulb_outline_rounded,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.targetLabel} ON · sisa $timer',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: running.progress(now),
                  ),
                ),
              ],
            ),
          ),
          if (onStop != null)
            IconButton(
              tooltip: 'Hentikan aksi',
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 20),
            ),
        ],
      ),
    );
  }
}

class _PendingScheduleTile extends StatelessWidget {
  const _PendingScheduleTile({
    required this.entry,
    required this.now,
    required this.connected,
    required this.onDelete,
  });

  final ScheduleEntry entry;
  final DateTime now;
  final bool connected;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final late = !entry.immediate && entry.at.isBefore(now);
    final when = entry.immediate ? 'Sekarang' : entry.atLabel;
    final subtitle = !connected
        ? 'Menunggu koneksi · ${entry.durationLabel}'
        : late
        ? '$when · menunggu koneksi'
        : '$when · ${entry.durationLabel}';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        entry.target == 'pump'
            ? Icons.water_drop_outlined
            : Icons.lightbulb_outline_rounded,
        size: 20,
      ),
      title: Text(
        '${entry.targetLabel} ${entry.on ? 'ON' : 'OFF'}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 10)),
      trailing: IconButton(
        tooltip: 'Batalkan aksi',
        icon: const Icon(Icons.close_rounded, size: 19),
        onPressed: onDelete,
      ),
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.connected});

  final bool connected;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  int _step = 0;
  String _target = 'pump';
  bool _on = true;
  bool _now = true;
  late DateTime _at;
  int _second = 0;
  int _pumpSeconds = 10;
  int _lampMinutes = 5;
  int _lampSeconds = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final base = DateTime.now().add(const Duration(minutes: 5));
    _at = DateTime(base.year, base.month, base.day, base.hour, base.minute);
    _second = 0;
  }

  int get _lampTotalSeconds {
    final total = _lampMinutes * 60 + _lampSeconds;
    return total < 1 ? 1 : (total > 1800 ? 1800 : total);
  }

  int get _durationSeconds =>
      _on ? (_target == 'pump' ? _pumpSeconds : _lampTotalSeconds) : 1;

  String get _durationText {
    if (!_on) return 'Tanpa durasi';
    if (_target == 'pump') return '$_pumpSeconds detik';
    final total = _lampTotalSeconds;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')} menit';
  }

  DateTime get _scheduledAt =>
      DateTime(_at.year, _at.month, _at.day, _at.hour, _at.minute, _second);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _at = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _at.hour,
          _at.minute,
        );
        _error = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (picked != null) {
      setState(() {
        _at = DateTime(
          _at.year,
          _at.month,
          _at.day,
          picked.hour,
          picked.minute,
        );
        _error = null;
      });
    }
  }

  void _next() {
    if (_step == 0 && !_now && !_scheduledAt.isAfter(DateTime.now())) {
      setState(() => _error = 'Pilih waktu setelah sekarang.');
      return;
    }
    setState(() {
      _error = null;
      _step = (_step + 1).clamp(0, 2);
    });
  }

  void _back() => setState(() {
    _error = null;
    _step = (_step - 1).clamp(0, 2);
  });

  void _submit() {
    final at = _now ? DateTime.now() : _scheduledAt;
    if (!_now && !at.isAfter(DateTime.now())) {
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
        durationSeconds: _durationSeconds,
        immediate: _now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
    title: Row(
      children: [
        const Icon(Icons.schedule_send_rounded),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _step == 0
                ? 'Aksi & waktu'
                : _step == 1
                ? 'Atur durasi'
                : 'Konfirmasi',
          ),
        ),
      ],
    ),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StepBar(step: _step),
            const SizedBox(height: 16),
            if (_step == 0) _buildScheduleStep(context),
            if (_step == 1) _buildDurationStep(context),
            if (_step == 2) _buildConfirmStep(context),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      if (_step > 0)
        TextButton(onPressed: _back, child: const Text('Kembali'))
      else
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
      FilledButton(
        onPressed: _step == 2 ? _submit : _next,
        child: Text(
          _step == 2
              ? (_now ? 'Jalankan sekarang' : 'Simpan jadwal')
              : 'Lanjut',
        ),
      ),
    ],
  );

  Widget _buildScheduleStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _FieldLabel('Perangkat'),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'pump', label: Text('Pompa')),
          ButtonSegment(value: 'light', label: Text('Lampu')),
        ],
        selected: {_target},
        showSelectedIcon: false,
        onSelectionChanged: (values) => setState(() => _target = values.first),
      ),
      const SizedBox(height: 14),
      const _FieldLabel('Aksi'),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('ON')),
          ButtonSegment(value: false, label: Text('OFF')),
        ],
        selected: {_on},
        showSelectedIcon: false,
        onSelectionChanged: (values) => setState(() {
          _on = values.first;
          _error = null;
        }),
      ),
      const SizedBox(height: 14),
      const _FieldLabel('Waktu'),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Sekarang')),
          ButtonSegment(value: false, label: Text('Jadwalkan')),
        ],
        selected: {_now},
        showSelectedIcon: false,
        onSelectionChanged: (values) => setState(() {
          _now = values.first;
          _error = null;
        }),
      ),
      const SizedBox(height: 10),
      if (_now)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.mossColors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.connected
                ? 'Aksi langsung dikirim setelah konfirmasi. Tidak perlu '
                      'mengisi tanggal.'
                : 'Aksi disimpan dulu dan dikirim begitu koneksi ke '
                      'planter tersedia.',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: context.mossColors.onSurfaceVariant,
            ),
          ),
        )
      else ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_month_rounded),
          title: const Text('Tanggal'),
          subtitle: Text(
            '${_at.day.toString().padLeft(2, '0')}/'
            '${_at.month.toString().padLeft(2, '0')}/${_at.year}',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _pickDate,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.access_time_rounded),
          title: const Text('Jam & menit'),
          subtitle: Text(
            '${_at.hour.toString().padLeft(2, '0')}:'
            '${_at.minute.toString().padLeft(2, '0')}',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _pickTime,
        ),
        DropdownButtonFormField<int>(
          initialValue: _second,
          decoration: const InputDecoration(
            labelText: 'Detik',
            prefixIcon: Icon(Icons.timer_outlined),
          ),
          items: [
            for (var second = 0; second < 60; second++)
              DropdownMenuItem(value: second, child: Text('$second')),
          ],
          onChanged: (value) => setState(() {
            _second = value ?? 0;
            _error = null;
          }),
        ),
      ],
    ],
  );

  Widget _buildDurationStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!_on)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.mossColors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Aksi OFF tidak memerlukan durasi. Perintah OFF dikirim sekali '
            'dan langsung selesai.',
          ),
        )
      else if (_target == 'pump') ...[
        Center(
          child: Text(
            '$_pumpSeconds detik',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
        ),
        Slider(
          value: _pumpSeconds.toDouble(),
          min: 1,
          max: 30,
          divisions: 29,
          label: '$_pumpSeconds s',
          onChanged: (value) => setState(() => _pumpSeconds = value.round()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: _pumpSeconds > 1
                  ? () => setState(() => _pumpSeconds--)
                  : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            const SizedBox(width: 18),
            IconButton.filledTonal(
              onPressed: _pumpSeconds < 30
                  ? () => setState(() => _pumpSeconds++)
                  : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final preset in [5, 10, 15, 30])
              ChoiceChip(
                label: Text('$preset dtk'),
                selected: _pumpSeconds == preset,
                onSelected: (_) => setState(() => _pumpSeconds = preset),
              ),
          ],
        ),
      ] else ...[
        Center(
          child: Text(
            _durationText,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _NumberStepper(
                label: 'Menit',
                value: _lampMinutes,
                min: 0,
                max: 30,
                onChanged: (value) => setState(() {
                  _lampMinutes = value;
                  if (_lampMinutes == 30) _lampSeconds = 0;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberStepper(
                label: 'Detik',
                value: _lampSeconds,
                min: 0,
                max: _lampMinutes == 30 ? 0 : 59,
                onChanged: (value) => setState(() => _lampSeconds = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final preset in [1, 5, 10, 30])
              ChoiceChip(
                label: Text('$preset mnt'),
                selected: _lampMinutes == preset && _lampSeconds == 0,
                onSelected: (_) => setState(() {
                  _lampMinutes = preset;
                  _lampSeconds = 0;
                }),
              ),
          ],
        ),
      ],
    ],
  );

  Widget _buildConfirmStep(BuildContext context) {
    final time = _now
        ? 'Sekarang'
        : '${_at.day.toString().padLeft(2, '0')}/'
              '${_at.month.toString().padLeft(2, '0')}/${_at.year} '
              '${_at.hour.toString().padLeft(2, '0')}:'
              '${_at.minute.toString().padLeft(2, '0')}:'
              '${_second.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ConfirmRow(
          label: 'Perangkat',
          value: _target == 'pump' ? 'Pompa' : 'Lampu',
        ),
        _ConfirmRow(label: 'Aksi', value: _on ? 'ON' : 'OFF'),
        _ConfirmRow(label: 'Waktu', value: time),
        _ConfirmRow(label: 'Durasi', value: _durationText),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.mossColors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.connected
                ? 'Perintah akan dikirim ke ESP32 sekarang.'
                : 'Jadwal tersimpan. Perintah dikirim saat aplikasi '
                      'terhubung ke Wi-Fi planter.',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: context.mossColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < 3; index++) ...[
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: index <= step
                  ? context.mossColors.primary
                  : context.mossColors.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        if (index < 2) const SizedBox(width: 6),
      ],
    ],
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: context.mossColors.onSurfaceVariant,
      ),
    ),
  );
}

class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: BoxDecoration(
      border: Border.all(color: context.mossColors.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: context.mossColors.onSurfaceVariant,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_rounded, size: 18),
            ),
            Text(
              value.toString().padLeft(2, '0'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_rounded, size: 18),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: context.mossColors.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
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
  int _pumpSeconds = 10;
  int _lampMinutes = 5;
  int _lampSeconds = 0;
  _ManualMode _pumpMode = _ManualMode.auto;
  _ManualMode _lightMode = _ManualMode.auto;
  bool _busy = false;
  String _message = 'Pilih mode. Tombol ON akan menanyakan durasi dulu.';
  Timer? _pumpTimer;
  Timer? _lightTimer;
  DateTime? _ignoreRemoteModeUntil;

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
    // Telemetry from before the local command may still arrive while the
    // command is in flight. Do not let a stale reason snap the button back.
    final holdUntil = _ignoreRemoteModeUntil;
    if (holdUntil != null && DateTime.now().isBefore(holdUntil)) return;
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
    int? durationSeconds,
  }) async {
    if (_busy) return;
    final previousPump = _pumpMode;
    final previousLight = _lightMode;
    setState(() {
      _busy = true;
      _message = 'Mengirim…';
      _ignoreRemoteModeUntil = DateTime.now().add(const Duration(seconds: 15));
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
        _ignoreRemoteModeUntil = null;
        if (pump) {
          _pumpMode = previousPump;
        } else {
          _lightMode = previousLight;
        }
        _message = 'Perintah gagal; periksa koneksi cloud.';
      } else if (pump) {
        _message = mode == _ManualMode.on
            ? 'Pompa ON · ${durationSeconds ?? _pumpSeconds} detik.'
            : 'Pompa ${mode.label}.';
      } else {
        _message = mode == _ManualMode.on
            ? 'Lampu ON · ${_durationText(durationSeconds ?? _lampTotalSeconds)}.'
            : 'Lampu ${mode.label}.';
      }
    });
    if (!ok) return;
    if (pump) {
      _pumpTimer?.cancel();
      _pumpTimer = null;
      if (mode == _ManualMode.on) {
        final seconds = durationSeconds ?? _pumpSeconds;
        _pumpTimer = Timer(Duration(seconds: seconds), () {
          if (mounted && _pumpMode == _ManualMode.on) {
            setState(() => _pumpMode = _ManualMode.auto);
          }
        });
      }
    } else {
      _lightTimer?.cancel();
      _lightTimer = null;
      if (mode == _ManualMode.on) {
        final seconds = durationSeconds ?? _lampTotalSeconds;
        _lightTimer = Timer(Duration(seconds: seconds), () {
          if (mounted && _lightMode == _ManualMode.on) {
            setState(() => _lightMode = _ManualMode.off);
          }
        });
      }
    }
  }

  Future<void> _setPump(_ManualMode mode) async {
    if (_busy) return;
    final id = widget.controlId();
    if (mode == _ManualMode.on) {
      final seconds = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PumpDurationDialog(initialSeconds: _pumpSeconds),
      );
      if (seconds == null || !mounted) return;
      setState(() => _pumpSeconds = seconds);
      await _send(
        'CTRL pump=on dur=$seconds id=$id',
        mode: mode,
        pump: true,
        durationSeconds: seconds,
      );
      return;
    }
    final line = switch (mode) {
      _ManualMode.off => 'CTRL pump=off id=$id',
      _ManualMode.auto => 'CTRL pump=auto id=$id',
      _ManualMode.on => '',
    };
    await _send(line, mode: mode, pump: true);
  }

  Future<void> _setLight(_ManualMode mode) async {
    if (_busy) return;
    final id = widget.controlId();
    if (mode == _ManualMode.on) {
      final total = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _LampDurationDialog(
          initialMinutes: _lampMinutes,
          initialSeconds: _lampSeconds,
        ),
      );
      if (total == null || !mounted) return;
      setState(() {
        _lampMinutes = total ~/ 60;
        _lampSeconds = total % 60;
      });
      await _send(
        'CTRL light=on dur=$total id=$id',
        mode: mode,
        pump: false,
        durationSeconds: total,
      );
      return;
    }
    final line = switch (mode) {
      _ManualMode.off => 'CTRL light=off id=$id',
      _ManualMode.auto => 'CTRL light=auto id=$id',
      _ManualMode.on => '',
    };
    await _send(line, mode: mode, pump: false);
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
          'Pilih ON, OFF, atau AUTO. Tombol yang aktif diberi warna dan label '
          'AKTIF. ON selalu membuka dialog durasi sebelum perintah dikirim.',
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
          onMode: (mode) => unawaited(_setPump(mode)),
          hint: 'ON meminta durasi 1–30 detik. Terakhir: $_pumpSeconds detik.',
        ),
        const SizedBox(height: 18),
        _ControlBlock(
          title: 'Lampu',
          icon: Icons.lightbulb_outline_rounded,
          accent: const Color(0xFFB8862E),
          mode: _lightMode,
          busy: _busy,
          onMode: (mode) => unawaited(_setLight(mode)),
          hint:
              'ON meminta menit + detik (1 detik–30 menit). Terakhir: '
              '${_durationText(_lampTotalSeconds)}.',
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
    required this.hint,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final _ManualMode mode;
  final bool busy;
  final ValueChanged<_ManualMode> onMode;
  final String hint;

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
              maxLines: 1,
              softWrap: false,
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
              label: FittedBox(fit: BoxFit.scaleDown, child: Text('ON')),
            ),
            ButtonSegment(
              value: _ManualMode.off,
              label: FittedBox(fit: BoxFit.scaleDown, child: Text('OFF')),
            ),
            ButtonSegment(
              value: _ManualMode.auto,
              label: FittedBox(fit: BoxFit.scaleDown, child: Text('AUTO')),
            ),
          ],
          selected: {mode},
          onSelectionChanged: busy ? null : (values) => onMode(values.first),
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
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
      const SizedBox(height: 6),
      Text(
        hint,
        style: TextStyle(
          fontSize: 10,
          height: 1.35,
          color: context.mossColors.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _PumpDurationDialog extends StatefulWidget {
  const _PumpDurationDialog({required this.initialSeconds});
  final int initialSeconds;

  @override
  State<_PumpDurationDialog> createState() => _PumpDurationDialogState();
}

class _PumpDurationDialogState extends State<_PumpDurationDialog> {
  late int _seconds = widget.initialSeconds.clamp(1, 30);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Durasi pompa'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$_seconds detik',
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        Slider(
          value: _seconds.toDouble(),
          min: 1,
          max: 30,
          divisions: 29,
          label: '$_seconds s',
          onChanged: (value) => setState(() => _seconds = value.round()),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final preset in [5, 10, 15, 30])
              ChoiceChip(
                label: Text('$preset dtk'),
                selected: _seconds == preset,
                onSelected: (_) => setState(() => _seconds = preset),
              ),
          ],
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _seconds),
        child: const Text('Mulai'),
      ),
    ],
  );
}

class _LampDurationDialog extends StatefulWidget {
  const _LampDurationDialog({
    required this.initialMinutes,
    required this.initialSeconds,
  });

  final int initialMinutes;
  final int initialSeconds;

  @override
  State<_LampDurationDialog> createState() => _LampDurationDialogState();
}

class _LampDurationDialogState extends State<_LampDurationDialog> {
  late int _minutes = widget.initialMinutes.clamp(0, 30);
  late int _seconds = widget.initialSeconds.clamp(0, 59);

  int get _total {
    final total = _minutes * 60 + _seconds;
    return total.clamp(1, 1800);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Durasi lampu'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${(_total ~/ 60).toString().padLeft(2, '0')}:'
          '${(_total % 60).toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _NumberStepper(
                label: 'Menit',
                value: _minutes,
                min: 0,
                max: 30,
                onChanged: (value) => setState(() {
                  _minutes = value;
                  if (_minutes == 30) _seconds = 0;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberStepper(
                label: 'Detik',
                value: _seconds,
                min: 0,
                max: _minutes == 30 ? 0 : 59,
                onChanged: (value) => setState(() => _seconds = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final preset in [1, 5, 10, 30])
              ChoiceChip(
                label: Text('$preset mnt'),
                selected: _minutes == preset && _seconds == 0,
                onSelected: (_) => setState(() {
                  _minutes = preset;
                  _seconds = 0;
                }),
              ),
          ],
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: _minutes == 0 && _seconds == 0
            ? null
            : () => Navigator.pop(context, _total),
        child: const Text('Nyalakan'),
      ),
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
