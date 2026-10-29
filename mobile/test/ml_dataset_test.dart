import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/ml_dataset.dart';
import 'package:smart_planter/src/plant_telemetry.dart';

Map<String, String> oneRow(String csv) {
  final lines = csv.trimRight().split('\n');
  expect(lines.length, 2);
  final headers = lines[0].split(',');
  final values = lines[1].split(',');
  expect(values.length, headers.length);
  return Map.fromIterables(headers, values);
}

void main() {
  final now = DateTime.utc(2026, 10, 29, 12);
  PlantTelemetry reading(int id, DateTime time) => PlantTelemetry(
    recordedAt: time,
    sequence: id,
    soilPercent: 0,
    temperatureC: -2.5,
    humidityPercent: 0,
    lightPercent: 100,
    uvIndex: 4.5,
  );

  test('missing sensor fields stay empty and zero stays a real value', () {
    final result = oneRow(
      MlDatasetCsv.encode([MlDatasetRow(reading: reading(1, now))]),
    );
    expect(result['schema_version'], '1');
    expect(result['source_type'], 'cloud_reading');
    expect(result['time_quality'], 'server_reported');
    expect(result['source_file'], '');
    expect(result['soil_relative_percent'], '0');
    expect(result['soil_missing'], '0');
    expect(result['soil_quality'], 'unverified');
    expect(result['temperature_c'], '-2.5');
    expect(result['humidity_percent'], '0');
    expect(result['water_relative_percent'], '');
    expect(result['water_missing'], '1');
    expect(result['mq135_adc_raw'], '');
    expect(result['mq135_missing'], '1');
    expect(result['uv_legacy_proxy'], '');
    expect(result['uv_legacy_proxy_missing'], '1');
    expect(result['label'], '');
    expect(result['label_source'], '');
  });

  test(
    'summary counts manually sourced labels without asserting model readiness',
    () {
      final summary = MlDatasetSummary.fromRows([
        MlDatasetRow(reading: reading(1, now)),
        MlDatasetRow(
          reading: reading(2, now.add(const Duration(seconds: 1))),
          label: 'needs_water',
          labelSource: MlLabelSource.manualObservation,
        ),
      ]);
      expect(summary.rows, 2);
      expect(summary.manuallyLabeled, 1);
    },
  );

  test('future sensors and manually sourced labels fit the same schema', () {
    final result = oneRow(
      MlDatasetCsv.encode([
        MlDatasetRow(
          reading: reading(1, now),
          deviceRef: 'planter-1',
          waterRelativePercent: 0,
          mq135Adc: 1024,
          label: 'needs_water',
          labelSource: MlLabelSource.manualObservation,
        ),
      ]),
    );
    expect(result['water_relative_percent'], '0');
    expect(result['water_missing'], '0');
    expect(result['mq135_adc_raw'], '1024');
    expect(result['mq135_quality'], 'unverified');
    expect(result['label'], 'needs_water');
    expect(result['label_source'], 'manual_observation');
  });

  test('out-of-range and nonfinite readings are missing, never clamped', () {
    final result = oneRow(
      MlDatasetCsv.encode([
        MlDatasetRow(
          reading: PlantTelemetry(
            recordedAt: now,
            sequence: 1,
            soilPercent: 101,
            temperatureC: double.nan,
            uvIndex: double.infinity,
          ),
          waterRelativePercent: 101,
          mq135Adc: 4096,
        ),
      ]),
    );
    for (final field in ['soil', 'temperature', 'uv', 'water', 'mq135']) {
      expect(result['${field}_missing'], '1');
    }
  });

  test('labels require a manual source and spreadsheet-safe identifiers', () {
    expect(
      () => MlDatasetCsv.encode([
        MlDatasetRow(reading: reading(1, now), label: 'dry'),
      ]),
      throwsFormatException,
    );
    expect(
      () => MlDatasetCsv.encode([
        MlDatasetRow(reading: reading(1, now), deviceRef: '=2+2'),
      ]),
      throwsFormatException,
    );
  });

  test('time ordering, unique IDs and UTC timestamps are required', () {
    final first = MlDatasetRow(reading: reading(1, now));
    final earlier = MlDatasetRow(
      reading: reading(2, now.subtract(const Duration(seconds: 1))),
    );
    expect(() => MlDatasetCsv.encode([first, earlier]), throwsFormatException);
    expect(() => MlDatasetCsv.encode([first, first]), throwsFormatException);
    expect(
      () => MlDatasetCsv.encode([
        MlDatasetRow(reading: reading(1, DateTime(2026, 10, 29))),
      ]),
      throwsFormatException,
    );
  });

  test('rolling features use only the same device and past hour', () {
    PlantTelemetry soil(int id, Duration offset, int value) => PlantTelemetry(
      recordedAt: now.add(offset),
      sequence: id,
      soilPercent: value,
    );
    final csv = MlDatasetCsv.encode([
      MlDatasetRow(reading: soil(1, Duration.zero, 10), deviceRef: 'a'),
      MlDatasetRow(
        reading: soil(2, const Duration(minutes: 30), 20),
        deviceRef: 'a',
      ),
      MlDatasetRow(
        reading: soil(3, const Duration(hours: 2), 90),
        deviceRef: 'a',
      ),
    ]);
    final lines = csv.trimRight().split('\n');
    final headers = lines.first.split(',');
    Map<String, String> values(int index) =>
        Map.fromIterables(headers, lines[index].split(','));
    expect(values(1)['soil_mean_1h'], '10.0');
    expect(values(1)['soil_delta_1h_missing'], '1');
    expect(values(2)['soil_mean_1h'], '15.0');
    expect(values(2)['soil_delta_1h'], '10');
    expect(values(2)['soil_samples_1h'], '2');
    expect(values(3)['soil_mean_1h'], '90.0');
    expect(values(3)['soil_delta_1h_missing'], '1');
    expect(
      () => MlDatasetCsv.encode([
        MlDatasetRow(reading: soil(1, Duration.zero, 10), deviceRef: 'a'),
        MlDatasetRow(
          reading: soil(2, const Duration(minutes: 1), 20),
          deviceRef: 'b',
        ),
      ]),
      throwsFormatException,
    );
  });
}
