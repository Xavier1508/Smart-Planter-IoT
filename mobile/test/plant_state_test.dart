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

  test(
    'ADC display percentages preserve missing and never claim calibration',
    () {
      expect(PlantState.adcDisplayPercent(null), isNull);
      expect(PlantState.adcDisplayPercent(-1), isNull);
      expect(PlantState.adcDisplayPercent(0), 0);
      expect(PlantState.adcDisplayPercent(2048), 50);
      expect(PlantState.adcDisplayPercent(4095), 100);
      expect(PlantState.adcDisplayPercent(4096), isNull);
    },
  );

  test('serial snapshot preserves raw zeros without pretending to be live', () {
    final snapshot = SerialSensorSnapshot.parse('''
      {"type":"sample","uptime_ms":12345,
       "dht":{"temperature_c":23.4,"humidity_percent":62.5,"status":"unverified"},
       "adc":{"soil_raw":800,"soil_status":"unverified","soil_relative_percent":32,
              "light_raw":2000,"light_relative_percent":51,"uv_raw":0,"status":"unverified"},
       "water_level":{"adc_raw":0,"status":"unverified"},
       "mq135":{"adc_raw":4095,"digital_raw":1,"adc_status":"unverified","status":"unverified"}}
    ''');
    final state = PlantState.fromSerial(snapshot);
    expect(snapshot.uptimeMs, 12345);
    expect(state.isSerialSnapshot, isTrue);
    expect(state.isLive, isFalse);
    expect(state.mood, PlantMood.waiting);
    expect(state.soilAdc, 800);
    expect(state.soilPercent, 32);
    expect(state.humidityPercent, 62.5);
    expect(state.uvAdc, 0);
    expect(state.uvIndex, isNull);
    expect(state.waterAdc, 0);
    expect(state.waterPercent, isNull);
    expect(state.mqAdc, 4095);
    expect(state.mqDigital, 1);
    expect(state.explanation, contains('waktu pembacaan tidak diketahui'));
  });

  test('observed water scale stays separate from control water percent', () {
    final snapshot = SerialSensorSnapshot.parse('''
      {"type":"sample","uptime_ms":5000,
       "water_level":{"adc_raw":1200,"relative_percent":null,"status":"unverified",
         "observation_scale":{"relative_percent":50,"basis":"operator_reported_window_means",
           "quality":"unverified","use_for_control":false}}}
    ''');
    expect(snapshot.waterRelativePercent, isNull);
    expect(snapshot.waterObservationPercent, 50);
    final state = PlantState.fromLocalWifi(snapshot);
    expect(state.isLive, isTrue);
    expect(state.isLocalLive, isTrue);
    expect(state.waterPercent, isNull);
    expect(state.waterObservationPercent, 50);
    expect(state.mood, PlantMood.waiting);
  });

  test('generic display references remain separate from water control', () {
    final sample = SerialSensorSnapshot.parse('''
      {"type":"sample",
       "water_level":{"adc_raw":1200,"relative_percent":null,"status":"unverified",
         "observation_scale":{"relative_percent":50,"basis":"generic_display_references",
           "quality":"unverified","use_for_control":false}}}
    ''');
    expect(sample.waterRelativePercent, isNull);
    expect(sample.waterObservationPercent, 50);
  });

  test(
    'serial import rejects bad samples and preserves unavailable readings',
    () {
      expect(
        () => SerialSensorSnapshot.parse('{"type":"startup"}'),
        throwsFormatException,
      );
      expect(
        () => SerialSensorSnapshot.parse('not json'),
        throwsFormatException,
      );
      expect(
        () => SerialSensorSnapshot.parse('x' * 4097),
        throwsFormatException,
      );
      final snapshot = SerialSensorSnapshot.parse('''
      {"type":"sample",
       "dht":{"temperature_c":999,"humidity_percent":-1,"status":"unverified"},
       "adc":{"soil_raw":200,"soil_status":"not_configured","uv_raw":0,"status":"unverified"},
       "water_level":{"adc_raw":9999,"status":"unverified"},
       "mq135":{"adc_raw":0,"digital_raw":1,"adc_status":"adc_read_failed","status":"unverified"}}
    ''');
      expect(snapshot.temperatureC, isNull);
      expect(snapshot.humidityPercent, isNull);
      expect(snapshot.soilAdc, isNull);
      expect(snapshot.uvAdc, 0);
      expect(snapshot.waterAdc, isNull);
      expect(snapshot.mqAdc, isNull);
      expect(snapshot.mqDigital, 1);
    },
  );

  test('diagnostic rule previews are not live relay states', () {
    final sample = SerialSensorSnapshot.parse('''
      {"type":"sample",
       "adc":{"soil_raw":800,"soil_status":"unverified","soil_relative_percent":32,
              "light_raw":2000,"light_relative_percent":51,"status":"unverified"},
       "water_level":{"adc_raw":0,"relative_percent":null,"status":"unverified"},
       "control_preview":{"mode":"diagnostic_only","basis":"relative_unverified",
                          "pump_on":true,"growlight_on":true,"water_low":null}}
    ''');
    final state = PlantState.fromSerial(sample);
    expect(state.isLive, isFalse);
    expect(state.pumpRulePreview, isTrue);
    expect(state.lightRulePreview, isTrue);
    expect(state.waterPercent, isNull);
    expect(state.waterLowPreview, isNull);
    expect(state.mood, PlantMood.waiting);
  });

  test('diagnostic previews validate thresholds and missing inputs', () {
    final sample = SerialSensorSnapshot.parse('''
      {"type":"sample",
       "adc":{"soil_raw":1225,"soil_status":"unverified","soil_relative_percent":50,
              "light_raw":1638,"light_relative_percent":60,"status":"unverified"},
       "water_level":{"adc_raw":400,"relative_percent":20,"status":"unverified"},
       "control_preview":{"mode":"diagnostic_only","basis":"relative_unverified",
                          "pump_on":false,"growlight_on":false,"water_low":false}}
    ''');
    expect(sample.pumpRulePreview, isFalse);
    expect(sample.lightRulePreview, isFalse);
    expect(sample.waterLowPreview, isFalse);

    final inconsistent = SerialSensorSnapshot.parse('''
      {"type":"sample",
       "adc":{"soil_raw":1225,"soil_status":"unverified","soil_relative_percent":50,
              "light_raw":1638,"light_relative_percent":60,"status":"unverified"},
       "water_level":{"adc_raw":null,"relative_percent":19,"status":"unverified"},
       "control_preview":{"mode":"diagnostic_only","basis":"relative_unverified",
                          "pump_on":true,"growlight_on":true,"water_low":true}}
    ''');
    expect(inconsistent.pumpRulePreview, isNull);
    expect(inconsistent.lightRulePreview, isNull);
    expect(inconsistent.waterRelativePercent, isNull);
    expect(inconsistent.waterLowPreview, isNull);

    final wrongMode = SerialSensorSnapshot.parse('''
      {"type":"sample",
       "adc":{"soil_raw":800,"soil_status":"unverified","soil_relative_percent":32,
              "status":"unverified"},
       "control_preview":{"mode":"active","basis":"relative_unverified","pump_on":true}}
    ''');
    expect(wrongMode.pumpRulePreview, isNull);
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
