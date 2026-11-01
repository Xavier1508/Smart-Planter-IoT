import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/plant_emotion.dart';
import 'package:smart_planter/src/plant_state.dart';
import 'package:smart_planter/src/plant_health.dart';

void main() {
  late PlantHealthModel model;

  setUpAll(() async {
    final asset = await File('assets/ml/plant-health.json').readAsString();
    model = PlantHealthModel.parse(asset);
  });

  PlantState live({
    int? soil,
    int? water,
    int? light = 70,
    double? uv = 5,
    bool? waterLow,
    double? temp,
    int? humidity,
    int? gas,
    bool? pumpLockout,
    int? lockoutSeconds,
  }) => PlantState(
    isLive: true,
    soilPercent: soil,
    waterObservationPercent: water,
    waterAdc: water == null ? null : 1000,
    lightPercent: light,
    uvIndex: uv,
    waterLow: waterLow,
    temperatureC: temp,
    humidityPercent: humidity,
    mqGasIndex: gas,
    pumpRuntimeLockout: pumpLockout,
    pumpCooldownSeconds: lockoutSeconds,
  );

  test('waiting state is neutral and not available', () {
    final reading = const PlantEmotionEngine(null)
        .evaluate(const PlantState.waiting());
    expect(reading.emotion, PlantEmotion.neutral);
    expect(reading.available, isFalse);
    expect(reading.confidencePercent, 0);
    expect(reading.signal, contains('Belum ada perangkat'));
  });

  test('healthy soil and water produce a happy presentation', () {
    final reading = PlantEmotionEngine(model)
        .evaluate(live(soil: 72, water: 60));
    expect(reading.emotion, PlantEmotion.happy);
    expect(reading.confidence, greaterThan(0));
    expect(reading.available, isTrue);
  });

  test('low soil is authoritative even if the model is uncertain', () {
    final reading = PlantEmotionEngine(model)
        .evaluate(live(soil: 22, water: 60));
    expect(reading.emotion, PlantEmotion.alert);
    expect(reading.signal.toLowerCase(), contains('tanah'));
    expect(reading.prediction.toLowerCase(), contains('air'));
  });

  test('low water is a watch factor, not an automatic red alert', () {
    final reading = PlantEmotionEngine(model)
        .evaluate(live(soil: 70, water: 12, waterLow: true));
    expect(reading.emotion, PlantEmotion.neutral);
    expect(reading.signal, contains('Air'));
    expect(
      reading.factors.any((factor) => factor.detail.contains('Air')),
      isTrue,
    );
  });

  test('saturated soil with a full reservoir is a flood, not healthy', () {
    final reading = PlantEmotionEngine(model)
        .evaluate(live(soil: 99, water: 99));
    expect(reading.emotion, PlantEmotion.alert);
    expect(reading.signal, contains('banjir'));
    expect(reading.prediction, contains('Kurangi air'));
  });

  test('saturated soil alone is overwatering', () {
    final reading = PlantEmotionEngine(model)
        .evaluate(live(soil: 95, water: 40));
    expect(reading.emotion, PlantEmotion.alert);
    expect(reading.signal, contains('terlalu basah'));
  });

  test('the middle band is never presented as happy', () {
    final reading = PlantEmotionEngine(model)
        .evaluate(live(soil: 46, water: 40));
    expect(reading.emotion, isNot(PlantEmotion.happy));
  });

  test('a falling soil window is reported as worsening', () {
    final recent = [
      live(soil: 70, water: 65),
      live(soil: 66, water: 65),
      live(soil: 63, water: 65),
      live(soil: 60, water: 65),
    ];
    final reading = PlantEmotionEngine(model)
        .evaluate(live(soil: 58, water: 65), recent: recent);
    expect(reading.trend, ConditionTrend.worsening);
    expect(reading.prediction, contains('Berpotensi memburuk'));
  });

  test('missing values never become invented measurements', () {
    final reading = PlantEmotionEngine(model)
        .evaluate(const PlantState(isLive: true));
    expect(reading.emotion, PlantEmotion.neutral);
    expect(reading.available, isTrue);
    expect(reading.prediction, isNotEmpty);
  });

  test('85% soil with normal water is moist, not an emergency', () {
    final reading = PlantEmotionEngine(model)
        .evaluate(live(soil: 85, water: 40, temp: 25, humidity: 60, gas: 20));
    expect(reading.emotion, isNot(PlantEmotion.alert));
    expect(reading.score, greaterThanOrEqualTo(45));
    expect(
      reading.factors.any((factor) => factor.detail.contains('lembap')),
      isTrue,
    );
  });

  test('the score covers climate and air, not only water', () {
    final hot = PlantEmotionEngine(model)
        .evaluate(live(soil: 60, water: 55, temp: 39, humidity: 25, gas: 20));
    expect(hot.emotion, PlantEmotion.alert);
    expect(hot.factors.any((factor) => factor.label == 'Suhu'), isTrue);

    final air = PlantEmotionEngine(model)
        .evaluate(live(soil: 60, water: 55, temp: 25, humidity: 60, gas: 90));
    expect(air.emotion, PlantEmotion.alert);
    expect(air.factors.any((factor) => factor.label.contains('MQ135')), isTrue);
  });

  test('pump lockout is surfaced as a factor without inventing dry soil', () {
    final reading = PlantEmotionEngine(model).evaluate(
      live(
        soil: 55,
        water: 40,
        temp: 25,
        humidity: 60,
        gas: 20,
        pumpLockout: true,
        lockoutSeconds: 1200,
      ),
    );
    expect(
      reading.factors.any((factor) => factor.detail.contains('terkunci')),
      isTrue,
    );
  });
}
