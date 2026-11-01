import 'dart:convert';

import 'package:flutter/services.dart';

/// One app-side schedule. It is executed only while the phone is connected to
/// the Moss access point; the ESP32 receives a normal manual-control command.
class ScheduleEntry {
  const ScheduleEntry({
    required this.id,
    required this.target,
    required this.on,
    required this.at,
    this.durationSeconds = 5,
    this.immediate = false,
  });

  final int id;
  final String target; // 'pump' or 'light'
  final bool on;
  final DateTime at;
  final int durationSeconds;

  /// Created with the "Sekarang" option. The command is sent as soon as the
  /// app can reach the device; it is not a future calendar entry.
  final bool immediate;

  Map<String, Object> toMap() => {
    'id': id,
    'target': target,
    'on': on,
    'at': at.toUtc().toIso8601String(),
    'durationSeconds': durationSeconds,
    'immediate': immediate,
  };

  static ScheduleEntry? fromMap(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final target = value['target'];
    final on = value['on'];
    final at = value['at'];
    final duration = value['durationSeconds'];
    if (id is! int ||
        (target != 'pump' && target != 'light') ||
        on is! bool ||
        at is! String ||
        duration is! int ||
        duration < 1 ||
        duration > (target == 'pump' ? 30 : 1800)) {
      return null;
    }
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;
    return ScheduleEntry(
      id: id,
      target: target as String,
      on: on,
      at: parsed.toLocal(),
      durationSeconds: duration,
      immediate: value['immediate'] == true,
    );
  }

  String get command {
    final idPart = ' id=$id';
    if (target == 'pump') {
      return on
          ? 'CTRL pump=on dur=$durationSeconds$idPart'
          : 'CTRL pump=off$idPart';
    }
    return on
        ? 'CTRL light=on dur=$durationSeconds$idPart'
        : 'CTRL light=off$idPart';
  }

  String get targetLabel => target == 'pump' ? 'Pompa' : 'Lampu';

  String get durationLabel {
    if (!on) return 'tanpa durasi';
    if (target == 'pump') return '$durationSeconds dtk';
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String get atLabel {
    final time =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}:'
        '${at.second.toString().padLeft(2, '0')}';
    final today = DateTime.now();
    if (at.year == today.year &&
        at.month == today.month &&
        at.day == today.day) {
      return 'Hari ini $time';
    }
    final date =
        '${at.day.toString().padLeft(2, '0')}/'
        '${at.month.toString().padLeft(2, '0')}/${at.year}';
    return '$date $time';
  }

  String get label {
    final action = '$targetLabel ${on ? 'ON' : 'OFF'}';
    if (immediate && !on) return 'Sekarang · $action';
    if (immediate) return 'Sekarang · $action · $durationLabel';
    if (!on) return '$action · $atLabel';
    return '$action · $atLabel · $durationLabel';
  }
}

class RunningSchedule {
  const RunningSchedule({
    required this.entry,
    required this.startedAt,
    required this.endsAt,
  });

  final ScheduleEntry entry;
  final DateTime startedAt;
  final DateTime endsAt;

  int remainingSeconds(DateTime now) {
    final remaining = endsAt.difference(now).inMilliseconds;
    return remaining <= 0 ? 0 : (remaining / 1000).ceil();
  }

  double progress(DateTime now) {
    final total = endsAt.difference(startedAt).inMilliseconds;
    if (total <= 0) return 1;
    final elapsed = now.difference(startedAt).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  bool expired(DateTime now) => !now.isBefore(endsAt);
}

class ScheduleStore {
  const ScheduleStore();

  static const _channel = MethodChannel('moss/schedule');

  Future<List<ScheduleEntry>> read() async {
    try {
      final raw = await _channel.invokeMethod<String>('read');
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(ScheduleEntry.fromMap)
          .whereType<ScheduleEntry>()
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  Future<bool> write(List<ScheduleEntry> entries) async {
    try {
      await _channel.invokeMethod<void>('write', {
        'json': jsonEncode(entries.map((entry) => entry.toMap()).toList()),
      });
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
