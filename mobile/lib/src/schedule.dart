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
  });

  final int id;
  final String target; // 'pump' or 'light'
  final bool on;
  final DateTime at;
  final int durationSeconds;

  Map<String, Object> toMap() => {
    'id': id,
    'target': target,
    'on': on,
    'at': at.toUtc().toIso8601String(),
    'durationSeconds': durationSeconds,
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
        duration > 30) {
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
    );
  }

  String get command {
    final idPart = ' id=$id';
    if (target == 'pump') {
      return on
          ? 'CTRL pump=on dur=$durationSeconds$idPart'
          : 'CTRL pump=off$idPart';
    }
    return on ? 'CTRL light=on$idPart' : 'CTRL light=off$idPart';
  }

  String get label {
    final time =
        '${at.day.toString().padLeft(2, '0')}/'
        '${at.month.toString().padLeft(2, '0')} '
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}:'
        '${at.second.toString().padLeft(2, '0')}';
    if (target == 'pump') {
      return on ? 'Pompa ON $time · $durationSeconds dtk' : 'Pompa OFF $time';
    }
    return on ? 'Lampu ON $time' : 'Lampu OFF $time';
  }
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
