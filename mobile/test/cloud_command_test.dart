import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/cloud_command.dart';
import 'package:smart_planter/src/cloud_telemetry.dart';
import 'package:smart_planter/src/mq_gas_index.dart';
import 'package:smart_planter/src/plant_state.dart';

void main() {
  test('CTRL cloud parser accepts bounded pump and light commands', () {
    final pump = CloudControlCommand.parse('CTRL pump=on dur=5 id=1');
    expect(pump?.actuator, 'pump');
    expect(pump?.action, 'on');
    expect(pump?.durationSeconds, 5);

    final light = CloudControlCommand.parse('CTRL light=on dur=1800 id=2');
    expect(light?.durationSeconds, 1800);

    final auto = CloudControlCommand.parse('CTRL pump=auto id=3');
    expect(auto?.action, 'auto');
    expect(auto?.durationSeconds, isNull);
  });

  test('CTRL cloud parser rejects unsafe or ambiguous input', () {
    expect(CloudControlCommand.parse('CTRL pump=on dur=31 id=1'), isNull);
    expect(CloudControlCommand.parse('CTRL light=on dur=1801 id=1'), isNull);
    expect(CloudControlCommand.parse('CTRL pump=on id=1'), isNull);
    expect(CloudControlCommand.parse('CTRL pump=maybe id=1'), isNull);
    expect(CloudControlCommand.parse('pump=on dur=5'), isNull);
    expect(CloudControlCommand.parse('CTRL pump=on dur=5 extra=1'), isNull);
  });

  test('request IDs are RFC-4122 version 4 UUIDs', () {
    final first = newCloudRequestId();
    final second = newCloudRequestId();
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(first),
      isTrue,
    );
    expect(first, isNot(second));
  });

  test('full cloud row feeds raw and actuator fields into PlantState', () {
    final reading = CloudTelemetry.decodeReading({
      'id': 99,
      'recorded_at': '2026-11-02T10:00:00Z',
      'captured_at': '2026-11-02T09:59:58Z',
      'time_quality': 'ntp',
      'soil_adc': 0,
      'soil_percent': 0,
      'water_adc': 364,
      'water_percent': 0,
      'water_observation_percent': 0,
      'water_empty': true,
      'water_low': true,
      'light_adc': 934,
      'light_percent': 60,
      'temperature_c': 25.0,
      'humidity_percent': 65,
      'uv_adc': 0,
      'uv_index': null,
      'mq_adc': 598,
      'mq_pin_mv': 480,
      'pump_on': false,
      'pump_reason': 'water_low',
      'pump_cooldown_s': 0,
      'pump_runtime_lockout': false,
      'growlight_on': true,
      'light_reason': 'ldr_low',
    });
    final state = PlantState.fromTelemetry(reading);
    expect(reading.capturedAt, DateTime.utc(2026, 11, 2, 9, 59, 58));
    expect(reading.timeQuality, 'ntp');
    expect(state.waterAdc, 364);
    expect(state.waterEmpty, isTrue);
    expect(state.waterLow, isTrue);
    expect(state.mqAdc, 598);
    expect(state.pumpCommand, isFalse);
    expect(state.pumpReason, 'water_low');
    expect(state.lightCommand, isTrue);
    expect(state.lightReason, 'ldr_low');
    expect(state.soilAdc, 0);
    expect(state.mqPinMillivolts, 480);
  });

  test('buffered replay uses capture time for freshness', () {
    final reading = CloudTelemetry.decodeReading({
      'id': 100,
      'recorded_at': '2026-11-02T10:00:00Z',
      'captured_at': '2026-11-02T08:00:00Z',
      'time_quality': 'ntp',
      'water_adc': 900,
    });
    expect(reading.isFreshAt(DateTime.utc(2026, 11, 2, 10, 0, 10)), isFalse);
  });

  test('cloud MQ pin voltage produces a relative gas index', () async {
    final reading = CloudTelemetry.decodeReading({
      'id': 101,
      'recorded_at': '2026-11-02T10:00:00Z',
      'captured_at': '2026-11-02T10:00:00Z',
      'time_quality': 'ntp',
      'mq_adc': 575,
      'mq_pin_mv': 602,
    });
    final index = MqGasIndex()..update(reading.mqPinMv);
    expect(index.index, isNotNull);
    expect(index.status, 'baseline');
    final state = PlantState.fromTelemetry(
      reading,
      mqGasIndex: index.index,
      mqGasStatus: index.status,
    );
    expect(state.mqGasIndex, index.index);
    expect(state.mqGasStatus, 'baseline');
    expect(state.mqAdc, 575);
  });

  test('dataset CSV has one header, nulls, booleans, and all columns', () {
    final csv = CloudDatasetCsv.encode([
      {
        'id': 7,
        'recorded_at': '2026-11-02T10:00:00Z',
        'captured_at': null,
        'time_quality': 'uptime_only',
        'device_id': '3e0cf2c4-8164-4dbf-9a8a-c174a6272980',
        'boot_id': 'a1b2c3d4',
        'uptime_ms': 5000,
        'firmware_version': 32,
        'soil_adc': 0,
        'soil_percent': 0,
        'water_adc': 364,
        'water_percent': 0,
        'water_observation_percent': 0,
        'water_empty': true,
        'water_low': true,
        'light_adc': 934,
        'light_percent': 60,
        'temperature_c': 25.0,
        'humidity_percent': 65,
        'uv_adc': 0,
        'uv_index': null,
        'mq_adc': 598,
        'mq_pin_mv': 480,
        'pump_on': false,
        'pump_reason': 'water_low',
        'pump_cooldown_s': 0,
        'pump_runtime_lockout': false,
        'growlight_on': true,
        'light_reason': 'ldr_low',
        'ingest_source': 'buffer_replay',
      },
    ], hardwareId: 'moss-c31c-9c9c01f0');
    final lines = csv.trimRight().split('\n');
    expect(lines, hasLength(2));
    expect(lines.first, startsWith('recorded_at_utc,'));
    expect(lines.first, CloudDatasetCsv.header);
    final fields = lines[1].split(',');
    final headers = lines.first.split(',');
    final row = Map.fromIterables(headers, fields);
    expect(row['hardware_id'], 'moss-c31c-9c9c01f0');
    expect(row['captured_at_utc'], '');
    expect(row['water_empty'], '1');
    expect(row['pump_cmd'], '0');
    expect(row['light_cmd'], '1');
    expect(row['ingest_source'], 'buffer_replay');
  });
}
