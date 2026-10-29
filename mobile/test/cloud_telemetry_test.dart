import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/cloud_telemetry.dart';
import 'package:smart_planter/src/plant_state.dart';

void main() {
  test('server reading decodes and feeds validated sensor state', () {
    final reading = CloudTelemetry.decodeReading({
      'id': 42,
      'recorded_at': '2026-10-27T16:30:00+00:00',
      'soil_percent': 24,
      'temperature_c': 26.5,
      'humidity_percent': 64,
      'light_percent': 70,
      'uv_index': 3.5,
    });
    final state = PlantState.fromTelemetry(reading);
    expect(reading.recordedAt, DateTime.utc(2026, 10, 27, 16, 30));
    expect(reading.sequence, 42);
    expect(state.mood, PlantMood.thirsty);
    expect(state.soilPercent, 24);
    expect(state.temperatureC, 26.5);
    expect(reading.uvIndex, 3.5);
    expect(state.uvIndex, 3.5);
    expect(state.waterPercent, isNull);
  });

  test('unknown or non-timezoned timestamps are rejected', () {
    expect(() => CloudTelemetry.decodeReading({}), throwsFormatException);
    expect(
      () =>
          CloudTelemetry.decodeReading({'recorded_at': '2026-10-27T16:30:00'}),
      throwsFormatException,
    );
    expect(
      () => CloudTelemetry.decodeReading({'recorded_at': 'not-a-dateZ'}),
      throwsFormatException,
    );
  });

  test('malformed sensor fields never turn into invented values', () {
    final reading = CloudTelemetry.decodeReading({
      'id': 43,
      'recorded_at': '2026-10-27T16:30:00Z',
      'soil_percent': '50',
      'temperature_c': double.infinity,
      'humidity_percent': 10.5,
      'light_percent': 101,
      'uv_index': 26,
    });
    final state = PlantState.fromTelemetry(reading);
    expect(state.hasSensorData, isFalse);
    expect(state.uvIndex, isNull);
    expect(state.mood, PlantMood.waiting);
  });

  test('missing and malformed UV fields remain unavailable', () {
    const timestamp = '2026-10-27T16:30:00Z';
    for (final value in <Object?>[null, '3.5', double.nan, double.infinity]) {
      final reading = CloudTelemetry.decodeReading({
        'id': 44,
        'recorded_at': timestamp,
        'uv_index': value,
      });
      expect(reading.uvIndex, isNull);
      expect(PlantState.fromTelemetry(reading).hasSensorData, isFalse);
    }
  });

  test('cloud readings require an integer row ID for ordering', () {
    const timestamp = '2026-10-27T16:30:00Z';
    expect(
      () => CloudTelemetry.decodeReading({'recorded_at': timestamp}),
      throwsFormatException,
    );
    expect(
      () => CloudTelemetry.decodeReading({'id': 1.5, 'recorded_at': timestamp}),
      throwsFormatException,
    );
  });
}
