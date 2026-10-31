import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/plant_state.dart';
import 'package:smart_planter/src/plant_telemetry.dart';
import 'package:smart_planter/src/synthetic_xgboost.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyntheticXgboostModel model;

  setUpAll(() async {
    final asset = await File('assets/ml/pattern-models.json').readAsString();
    model = SyntheticXgboostModel.parse(asset);
  });

  test('portable inference matches 100 XGBoost synthetic golden vectors', () {
    final json = jsonDecode(
      File('test/fixtures/pattern-model-golden.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(json['schema'], SyntheticXgboostModel.schema);
    final vectors = json['vectors'] as List<dynamic>;
    expect(vectors, hasLength(100));
    for (final item in vectors) {
      final vector = item as Map<String, dynamic>;
      final features = vector['features'] as List<dynamic>;
      final expected = vector['scores'] as List<dynamic>;
      final result = model.predict(
        soilPercent: (features[0] as num).toInt(),
        waterObservationPercent: (features[1] as num).toInt(),
        lightPercent: (features[2] as num).toInt(),
        uvIndex: (features[3] as num?)?.toDouble(),
      );
      expect(result, isNotNull);
      expect(result!.scores, hasLength(expected.length));
      for (var index = 0; index < expected.length; index++) {
        expect(
          result.scores[index],
          closeTo((expected[index] as num).toDouble(), 0.00001),
        );
      }
    }
  });

  test('missing and invalid inputs do not become fabricated readings', () {
    expect(
      model.predict(
        soilPercent: null,
        waterObservationPercent: 50,
        lightPercent: 80,
        uvIndex: null,
      ),
      isNull,
    );
    expect(
      model.predict(
        soilPercent: 80,
        waterObservationPercent: 101,
        lightPercent: 80,
        uvIndex: null,
      ),
      isNull,
    );
    expect(
      model.predict(
        soilPercent: 80,
        waterObservationPercent: 50,
        lightPercent: 80,
        uvIndex: 15,
      ),
      isNull,
    );
    expect(() => SyntheticXgboostModel.parse('{}'), throwsFormatException);
  });

  test(
    'synthetic classes follow fixture examples without controlling relays',
    () {
      SyntheticPrediction predict(int soil, int water, int light, double? uv) =>
          model.predict(
            soilPercent: soil,
            waterObservationPercent: water,
            lightPercent: light,
            uvIndex: uv,
          )!;
      expect(predict(20, 80, 90, null).label, 'soil_relative_low');
      expect(predict(90, 10, 90, null).label, 'water_near_low_reference');
      expect(predict(90, 80, 90, null).label, 'no_synthetic_alert');
      expect(predict(90, 80, 10, null).label, 'uv_unavailable');
      expect(predict(90, 80, 66, 3).label, 'light_hold_band');
      expect(predict(90, 80, 20, 3).label, 'light_relative_low');
      expect(predict(90, 80, 20, 8).label, 'no_synthetic_alert');

      final sample = SerialSensorSnapshot.parse('''
      {"type":"sample","adc":{"soil_raw":1000,"soil_status":"unverified",
       "soil_relative_percent":44,"light_raw":2000,"light_relative_percent":51,
       "uv_raw":0,"status":"unverified"},"pump_cmd":false,"growlight_cmd":false}
    ''');
      // The experimental model remains testable but is not shown as live data.
      final state = PlantState.fromLocalWifi(sample);
      expect(state.moodLabel, 'Tanah terpantau');
      expect(state.explanation, contains('belum diverifikasi'));
      expect(state.pumpCommand, isFalse);
      expect(state.lightCommand, isFalse);
      expect(state.uvIndex, isNull);
      expect(state.uvAdc, 0);
    },
  );
}
