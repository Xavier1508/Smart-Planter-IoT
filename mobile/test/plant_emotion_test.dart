import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/plant_emotion.dart';
import 'package:smart_planter/src/plant_state.dart';
import 'package:smart_planter/src/synthetic_xgboost.dart';

void main() {
  late SyntheticXgboostModel model;

  setUpAll(() async {
    final asset = await File('assets/ml/pattern-models.json').readAsString();
    model = SyntheticXgboostModel.parse(asset);
  });

  PlantState live({
    int? soil,
    int? water,
    int? light = 70,
    double? uv = 5,
    bool? waterLow,
  }) => PlantState(
    isLive: true,
    soilPercent: soil,
    waterObservationPercent: water,
    lightPercent: light,
    uvIndex: uv,
    waterLow: waterLow,
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
    expect(reading.signal, contains('tanah'));
    expect(reading.prediction, contains('Perlu perhatian'));
  });

  test('low water is authoritative and is reported as the signal', () {
    final reading = PlantEmotionEngine(model)
        .evaluate(live(soil: 70, water: 12, waterLow: true));
    expect(reading.emotion, PlantEmotion.alert);
    expect(reading.signal, contains('Air'));
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
}
