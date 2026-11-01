import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/schedule.dart';

void main() {
  test('schedule entries build bounded pump and light commands', () {
    final at = DateTime(2026, 11, 1, 12, 30, 15);
    final pump = ScheduleEntry(
      id: 7,
      target: 'pump',
      on: true,
      at: at,
      durationSeconds: 9,
    );
    expect(pump.command, 'CTRL pump=on dur=9 id=7');
    expect(pump.label, contains('12:30:15'));
    final pumpOff = ScheduleEntry(id: 8, target: 'pump', on: false, at: at);
    expect(pumpOff.command, 'CTRL pump=off id=8');
    final light = ScheduleEntry(id: 9, target: 'light', on: true, at: at);
    expect(light.command, 'CTRL light=on id=9');
  });

  test('schedule serialization keeps local time and duration', () {
    final at = DateTime(2026, 11, 1, 7, 5, 3);
    final entry = ScheduleEntry(
      id: 11,
      target: 'pump',
      on: true,
      at: at,
      durationSeconds: 30,
    );
    final restored = ScheduleEntry.fromMap(entry.toMap());
    expect(restored, isNotNull);
    expect(restored!.id, 11);
    expect(restored.target, 'pump');
    expect(restored.on, isTrue);
    expect(restored.at, at);
    expect(restored.durationSeconds, 30);
  });

  test('invalid schedule records are rejected', () {
    expect(ScheduleEntry.fromMap(null), isNull);
    expect(ScheduleEntry.fromMap({'id': 1}), isNull);
    expect(
      ScheduleEntry.fromMap({
        'id': 1,
        'target': 'pump',
        'on': true,
        'at': 'not-a-date',
        'durationSeconds': 5,
      }),
      isNull,
    );
    expect(
      ScheduleEntry.fromMap({
        'id': 1,
        'target': 'pump',
        'on': true,
        'at': DateTime.now().toUtc().toIso8601String(),
        'durationSeconds': 31,
      }),
      isNull,
    );
  });
}
