import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/plant_state.dart';
import 'package:smart_planter/src/plant_telemetry.dart';

void main() {
  test('unconnected state never presents demonstration values', () {
    const state = PlantState.waiting();
    expect(state.isDemo, isFalse);
    expect(state.soilPercent, isNull);
    expect(state.waterPercent, isNull);
    expect(state.uvIndex, isNull);
    expect(state.mood, PlantMood.waiting);
  });

  test('demonstration scenarios produce distinct expressions', () {
    expect(PlantState.demo(DemoScenario.content).mood, PlantMood.content);
    expect(PlantState.demo(DemoScenario.thirsty).mood, PlantMood.thirsty);
    expect(PlantState.demo(DemoScenario.airConcern).mood, PlantMood.airConcern);
  });

  test('low water and dry soil take priority over simulated air changes', () {
    const state = PlantState(
      isDemo: true,
      soilPercent: 29,
      waterPercent: 50,
      airChanged: true,
    );
    expect(state.mood, PlantMood.thirsty);
    expect(
      const PlantState(isDemo: true, soilPercent: 30, waterPercent: 20).mood,
      PlantMood.content,
    );
    expect(
      const PlantState(isDemo: true, soilPercent: 50, waterPercent: 19).mood,
      PlantMood.thirsty,
    );
  });

  test('live readings drive Moss without enabling uninstalled sensors', () {
    final state = PlantState.fromTelemetry(
      PlantTelemetry(
        recordedAt: DateTime.utc(2026),
        soilPercent: 24,
        temperatureC: 26.2,
        humidityPercent: 65,
        lightPercent: 40,
      ),
    );
    expect(state.isDemo, isFalse);
    expect(state.isLive, isTrue);
    expect(state.mood, PlantMood.thirsty);
    expect(state.explanation, isNot(contains('Contoh')));
    expect(state.explanation, contains('belum diverifikasi'));
    expect(state.explanation, contains('bukan diagnosis'));
    expect(state.waterPercent, isNull);
    expect(state.airChanged, isFalse);
  });

  test('invalid readings are not clamped into invented measurements', () {
    final state = PlantState.fromTelemetry(
      PlantTelemetry(
        recordedAt: DateTime.utc(2026),
        soilPercent: 101,
        temperatureC: double.nan,
        humidityPercent: -1,
        lightPercent: 200,
      ),
    );
    expect(state.hasSensorData, isFalse);
    expect(state.soilPercent, isNull);
    expect(state.temperatureC, isNull);
    expect(state.humidityPercent, isNull);
    expect(state.lightPercent, isNull);
    expect(state.mood, PlantMood.waiting);
  });

  test('without soil data Moss does not claim the plant is comfortable', () {
    final state = PlantState.fromTelemetry(
      PlantTelemetry(recordedAt: DateTime.utc(2026), temperatureC: 25),
    );
    expect(state.hasSensorData, isTrue);
    expect(state.mood, PlantMood.waiting);
  });

  test('UV values are range checked without inferring soil condition', () {
    PlantState fromUv(double value) => PlantState.fromTelemetry(
      PlantTelemetry(recordedAt: DateTime.utc(2026), uvIndex: value),
    );

    for (final value in [0.0, 3.5, 25.0]) {
      final state = fromUv(value);
      expect(state.uvIndex, value);
      expect(state.hasSensorData, isTrue);
      expect(state.mood, PlantMood.waiting);
    }
    for (final value in [-0.1, 25.1, double.nan, double.infinity]) {
      final state = fromUv(value);
      expect(state.uvIndex, isNull);
      expect(state.hasSensorData, isFalse);
    }
  });

  test('old readings and far-future timestamps are not fresh', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    PlantTelemetry sample(Duration age) =>
        PlantTelemetry(recordedAt: now.subtract(age), soilPercent: 50);

    expect(sample(const Duration(minutes: 2)).isFreshAt(now), isTrue);
    expect(
      sample(const Duration(minutes: 2, seconds: 1)).isFreshAt(now),
      isFalse,
    );
    expect(sample(const Duration(seconds: -30)).isFreshAt(now), isTrue);
    expect(sample(const Duration(seconds: -31)).isFreshAt(now), isFalse);
  });
}
