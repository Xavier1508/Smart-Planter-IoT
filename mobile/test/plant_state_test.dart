import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/plant_state.dart';
import 'package:smart_planter/src/plant_telemetry.dart';

void main() {
  test('unconnected state never presents demonstration values', () {
    const state = PlantState.waiting();
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

  test('ADC rails stay raw; LDR rails remain bright/dark extremes', () {
    final snapshot = SerialSensorSnapshot.parse('''
      {"type":"sample",
       "adc":{"soil_raw":4095,"soil_status":"unverified","soil_relative_percent":100,
              "light_raw":0,"light_relative_percent":100,"uv_raw":0,"status":"unverified"},
       "water_level":{"adc_raw":0,"relative_percent":50,"status":"unverified",
         "observation_scale":{"relative_percent":50,"basis":"operator_reported_window_means",
           "quality":"unverified","use_for_control":false}}}
    ''');
    expect(snapshot.soilAdc, 4095);
    expect(snapshot.lightAdc, 0);
    expect(snapshot.waterAdc, 0);
    expect(snapshot.uvAdc, 0);
    expect(snapshot.soilRelativePercent, isNull);
    expect(snapshot.lightRelativePercent, 100);
    expect(snapshot.waterRelativePercent, isNull);
    expect(snapshot.waterObservationPercent, isNull);
  });

  test('zero soil is dry only when firmware confirms it', () {
    SerialSensorSnapshot parseZero({required bool confirmed}) =>
        SerialSensorSnapshot.parse(
          jsonEncode({
            'type': 'sample',
            'adc': {
              'soil_raw': 0,
              'soil_status': 'unverified',
              'soil_relative_percent': 0,
              if (confirmed) 'soil_zero_is_dry': true,
              'status': 'unverified',
            },
          }),
        );
    final confirmed = parseZero(confirmed: true);
    expect(confirmed.soilAdc, 0);
    expect(confirmed.soilRelativePercent, 0);
    expect(parseZero(confirmed: false).soilRelativePercent, isNull);
  });

  test('new LDR-only firmware reasons are exposed to the app', () {
    for (final reason in [
      'ldr_low',
      'ldr_sufficient',
      'ldr_input_unavailable',
    ]) {
      final sample = SerialSensorSnapshot.parse(
        jsonEncode({
          'type': 'sample',
          'uptime_ms': 1,
          'dht': {'temperature_c': 25, 'status': 'unverified'},
          'growlight_cmd': false,
          'growlight_reason': reason,
        }),
      );
      expect(sample.lightReason, reason);
    }
  });

  test('MQ ADC1 estimates and failures remain bounded and honest', () {
    SerialSensorSnapshot parseMq(Map<String, Object?> values) =>
        SerialSensorSnapshot.parse(
          jsonEncode({
            'type': 'sample',
            'adc': {'uv_raw': 0, 'status': 'unverified'},
            'mq135': {
              'adc_raw': 500,
              'digital_raw': 1,
              'adc_status': 'unverified',
              'status': 'unverified',
              'adc_unit': 'ADC1',
              'signal_quality': 'in_range_unverified',
              'adc_pin_mv_estimate': 550,
              'adc_calibration_source': 'efuse_vref',
              ...values,
            },
          }),
        );
    final valid = parseMq({});
    expect(valid.mqAdc, 500);
    expect(valid.mqAdcUnit, 'ADC1');
    expect(valid.mqPinMillivolts, 550);
    final state = PlantState.fromLocalWifi(
      valid,
      mqAverageAdc: 505,
      mqAverageSamples: 3,
      mqTrend: 1,
      mqGasIndex: 35,
      mqGasStatus: 'elevated',
      mqGasBaselineMv: 554,
    );
    expect(state.mqAverageAdc, 505);
    expect(state.mqAverageSamples, 3);
    expect(state.mqTrend, 1);
    expect(state.mqGasIndex, 35);
    expect(state.mqGasStatus, 'elevated');
    expect(state.mqGasBaselineMv, 554);
    expect(state.mqPinMillivolts, 550);
    expect(PlantState.fromSerial(valid).mqAverageAdc, isNull);

    final failure = parseMq({
      'adc_status': 'unavailable',
      'signal_quality': 'adc_read_failed',
    });
    expect(failure.mqAdc, isNull);
    expect(failure.mqAdcStatus, 'adc_read_failed');
    expect(failure.mqAdcUnit, 'ADC1');
    expect(failure.mqPinMillivolts, isNull);
    expect(parseMq({'adc_raw': 4095}).mqPinMillivolts, isNull);
    expect(parseMq({'adc_raw': 0}).mqPinMillivolts, isNull);
    expect(parseMq({'adc_pin_mv_estimate': 3301}).mqPinMillivolts, isNull);
    expect(
      parseMq({'adc_calibration_source': 'unknown'}).mqPinMillivolts,
      isNull,
    );
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

  test('water categories use raw ADC bands', () {
    PlantState stateFor(int? raw, {bool? low = false, bool? empty = false}) =>
        PlantState.fromLocalWifi(
          SerialSensorSnapshot.parse(
            jsonEncode({
              'type': 'sample',
              'water_level': {
                'adc_raw': raw,
                'status': raw == null ? 'unavailable' : 'unverified',
                'relative_percent': null,
                'low': low,
                'empty': empty,
              },
            }),
          ),
        );

    for (final (raw, expected) in [
      (451, WaterLevel.low),
      (800, WaterLevel.low),
      (890, WaterLevel.low),
      (950, WaterLevel.low),
      (951, WaterLevel.medium),
      (1040, WaterLevel.medium),
      (1499, WaterLevel.medium),
      (1500, WaterLevel.full),
      (1555, WaterLevel.full),
      (2000, WaterLevel.full),
    ]) {
      expect(stateFor(raw).waterLevel, expected, reason: 'raw ADC $raw');
    }

    // The firmware's warning flag is authoritative even when the raw value is
    // borderline, so a flagged low tank can never be shown as full.
    expect(stateFor(2000, low: true).waterLevel, WaterLevel.low);
    expect(stateFor(450, empty: true).waterLevel, WaterLevel.empty);
    expect(stateFor(450).waterLevel, WaterLevel.empty);
    expect(stateFor(950, low: true).mood, PlantMood.thirsty);
  });

  test('water rails and malformed inputs stay unavailable', () {
    PlantState stateFor(Map<String, Object?> water) => PlantState.fromLocalWifi(
      SerialSensorSnapshot.parse(
        jsonEncode({
          'type': 'sample',
          'dht': {'temperature_c': 25, 'status': 'unverified'},
          'water_level': {'adc_raw': 2000, 'status': 'unverified', ...water},
        }),
      ),
    );

    for (final raw in [null, -1, 0, 4095, 4096]) {
      expect(
        stateFor({'adc_raw': raw, 'relative_percent': 50, 'low': true})
            .waterLevel,
        isNull,
        reason: 'unusable raw $raw',
      );
    }
    expect(
      stateFor({'status': 'unavailable', 'relative_percent': 50, 'low': true})
          .waterLevel,
      isNull,
    );
    expect(stateFor({'relative_percent': 101, 'low': true}).waterLevel, isNull);
    expect(
      stateFor({'relative_percent': 50, 'low': true}).waterLevel,
      WaterLevel.low,
    );
    expect(
      stateFor({'relative_percent': 19, 'low': false}).waterLevel,
      WaterLevel.full,
    );
    expect(const PlantState.waiting().waterLevel, isNull);
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

  test('diagnostic soil preview follows the known firmware version', () {
    SerialSensorSnapshot sample(int version) => SerialSensorSnapshot.parse('''
      {"type":"sample","firmware_version":$version,
       "adc":{"soil_raw":1000,"soil_status":"unverified","soil_relative_percent":45,
              "status":"unverified"},
       "control_preview":{"mode":"diagnostic_only","basis":"relative_unverified",
                          "pump_on":false}}
    ''');
    final v15 = sample(15);
    expect(v15.pumpRuleThreshold, 40);
    expect(v15.pumpRulePreview, isFalse);
    expect(PlantState.fromSerial(v15).pumpRuleThreshold, 40);
    expect(sample(16).pumpRuleThreshold, 40);
    expect(sample(16).pumpRulePreview, isFalse);
    // The same preview contradicts the old 50% rule and must be discarded.
    expect(sample(14).pumpRulePreview, isNull);
    expect(sample(17).pumpRuleThreshold, isNull);
    expect(sample(17).pumpRulePreview, isNull);
  });

  test('low water and dry soil take priority over air changes', () {
    const state = PlantState(
      isLive: true,
      soilPercent: 29,
      waterPercent: 50,
      airChanged: true,
    );
    expect(state.mood, PlantMood.thirsty);
    expect(
      const PlantState(
        isLive: true,
        soilPercent: 30,
        waterAdc: 1000,
        waterPercent: 20,
      ).mood,
      PlantMood.content,
    );
    expect(
      const PlantState(
        isLive: true,
        soilPercent: 50,
        waterAdc: 950,
        waterPercent: 19,
      ).mood,
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

  test('pump runtime lockout is parsed for the UI countdown', () {
    final state = PlantState.fromLocalWifi(
      SerialSensorSnapshot.parse(
        jsonEncode({
          'type': 'sample',
          'dht': {'temperature_c': 25, 'status': 'unverified'},
          'water_level': {'adc_raw': 900, 'status': 'unverified'},
          'pump_cmd': false,
          'pump_reason': 'runtime_limit',
          'pump_cooldown_s': 1200,
          'pump_runtime_lockout': true,
        }),
      ),
    );
    expect(state.pumpReason, 'runtime_limit');
    expect(state.pumpCooldownSeconds, 1200);
    expect(state.pumpRuntimeLockout, isTrue);
  });
}
