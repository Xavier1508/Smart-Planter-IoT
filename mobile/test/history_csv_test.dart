import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/journal_page.dart';
import 'package:smart_planter/src/plant_emotion.dart';
import 'package:smart_planter/src/plant_state.dart';

void main() {
  test('history CSV round-trips the sensor and command fields', () {
    const state = PlantState(
      isLive: true,
      soilAdc: 900,
      soilPercent: 50,
      waterAdc: 700,
      waterPercent: 0,
      waterObservationPercent: 0,
      waterEmpty: false,
      waterLow: true,
      lightAdc: 800,
      lightPercent: 60,
      temperatureC: 26.5,
      humidityPercent: 65,
      uvAdc: 500,
      uvIndex: 3.5,
      mqAdc: 700,
      mqGasIndex: 20,
      pumpCommand: true,
      pumpReason: 'watering',
      lightCommand: false,
      lightReason: 'ldr_sufficient',
    );
    const emotion = EmotionReading(
      emotion: PlantEmotion.neutral,
      trend: ConditionTrend.stable,
      confidence: .72,
      signal: 'Tanah mulai mengering (50%).',
      prediction: 'Tidak ada perubahan besar; lanjutkan pemantauan.',
      modelLabel: 'warning',
      available: true,
    );
    final now = DateTime.utc(2026, 11, 1, 12, 0, 0);
    final line = HistoryCsv.line(
      now: now,
      deviceId: 'planter-1',
      firmwareVersion: 28,
      uptimeMs: 5000,
      state: state,
      emotion: emotion,
    );
    final parsed = HistoryCsv.parse(line);
    expect(parsed, isNotNull);
    expect(parsed!.at.toUtc(), now);
    expect(parsed.state.soilAdc, 900);
    expect(parsed.state.soilPercent, 50);
    expect(parsed.state.waterAdc, 700);
    expect(parsed.state.waterEmpty, isFalse);
    expect(parsed.state.waterLow, isTrue);
    expect(parsed.state.lightPercent, 60);
    expect(parsed.state.temperatureC, 26.5);
    expect(parsed.state.mqGasIndex, 20);
    expect(parsed.state.pumpCommand, isTrue);
    expect(parsed.state.pumpReason, 'watering');
    expect(parsed.state.lightCommand, isFalse);
    expect(parsed.state.lightReason, 'ldr_sufficient');
  });

  test('history CSV rejects malformed rows', () {
    expect(HistoryCsv.parse('not,a,valid,row'), isNull);
    expect(HistoryCsv.parse(''), isNull);
  });
}
