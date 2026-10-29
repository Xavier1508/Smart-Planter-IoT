import 'dart:collection';

import 'plant_state.dart';
import 'plant_telemetry.dart';

/// Labels must come from an independent human observation or review, not from
/// the same soil threshold that will be used as a model feature.
enum MlLabelSource { manualObservation, manualReview }

/// One real, server-timestamped reading for an explicitly requested export.
/// The caller must not pass demonstration data as a device observation.
class MlDatasetRow {
  const MlDatasetRow({
    required this.reading,
    this.deviceRef,
    this.firmwareVersion,
    this.calibrationVersion,
    this.waterRelativePercent,
    this.mq135Adc,
    this.label,
    this.labelSource,
  });

  final PlantTelemetry reading;
  final String? deviceRef;
  final String? firmwareVersion;
  final String? calibrationVersion;
  final int? waterRelativePercent;
  final int? mq135Adc;
  final String? label;
  final MlLabelSource? labelSource;
}

/// Describes available observations, not model quality or training readiness.
/// A manually sourced label is not proof that the observation was independent.
class MlDatasetSummary {
  const MlDatasetSummary({required this.rows, required this.manuallyLabeled});

  final int rows;
  final int manuallyLabeled;

  static MlDatasetSummary fromRows(Iterable<MlDatasetRow> rows) {
    var count = 0;
    var labeled = 0;
    for (final row in rows) {
      count++;
      if (row.label != null && row.labelSource != null) labeled++;
    }
    return MlDatasetSummary(rows: count, manuallyLabeled: labeled);
  }
}

/// Stable CSV schema. Empty numeric cells mean missing, never zero. All
/// supplied sensor values remain unverified until provenance exists upstream.
class MlDatasetCsv {
  const MlDatasetCsv._();

  static const columns = <String>[
    'schema_version',
    'recorded_at_utc',
    'reading_id',
    'source_type',
    'source_file',
    'source_line',
    'time_quality',
    'device_ref',
    'firmware_version',
    'calibration_version',
    'soil_relative_percent',
    'soil_missing',
    'soil_quality',
    'temperature_c',
    'temperature_missing',
    'temperature_quality',
    'humidity_percent',
    'humidity_missing',
    'humidity_quality',
    'light_relative_percent',
    'light_missing',
    'light_quality',
    'uv_index_estimate',
    'uv_missing',
    'uv_quality',
    'uv_legacy_proxy',
    'uv_legacy_proxy_missing',
    'uv_legacy_proxy_quality',
    'water_relative_percent',
    'water_missing',
    'water_quality',
    'mq135_adc_raw',
    'mq135_missing',
    'mq135_quality',
    'soil_mean_1h',
    'soil_mean_1h_missing',
    'soil_mean_1h_quality',
    'soil_delta_1h',
    'soil_delta_1h_missing',
    'soil_delta_1h_quality',
    'soil_samples_1h',
    'light_mean_1h',
    'light_mean_1h_missing',
    'light_mean_1h_quality',
    'light_samples_1h',
    'label',
    'label_source',
  ];

  /// Encode already-collected records in chronological order. Does not fetch,
  /// store, label, or synthesize readings and never starts model training.
  static String encode(Iterable<MlDatasetRow> rows) {
    final output = StringBuffer()..writeln(columns.join(','));
    DateTime? previousTime;
    int? previousId;
    String? source;
    var sourceSet = false;
    final soilWindow = Queue<_TimedValue>();
    final lightWindow = Queue<_TimedValue>();
    for (final row in rows) {
      final reading = row.reading;
      final id = reading.sequence;
      if (!reading.recordedAt.isUtc || id == null || id <= 0) {
        throw const FormatException(
          'A UTC timestamp and reading ID are required',
        );
      }
      if (previousTime != null &&
          (reading.recordedAt.isBefore(previousTime) ||
              (reading.recordedAt == previousTime && id <= previousId!))) {
        throw const FormatException('Readings must be unique and time ordered');
      }
      previousTime = reading.recordedAt;
      previousId = id;

      final deviceRef = _identifier(row.deviceRef);
      if (sourceSet && source != deviceRef) {
        throw const FormatException('Export one device at a time');
      }
      source = deviceRef;
      sourceSet = true;
      final firmware = _identifier(row.firmwareVersion);
      final calibration = _identifier(row.calibrationVersion);
      final label = _label(row.label);
      if ((label == null) != (row.labelSource == null)) {
        throw const FormatException(
          'A label and its manual source must appear together',
        );
      }
      final labelSource = switch (row.labelSource) {
        MlLabelSource.manualObservation => 'manual_observation',
        MlLabelSource.manualReview => 'manual_review',
        null => '',
      };

      final state = PlantState.fromTelemetry(reading);
      final cutoff = reading.recordedAt.subtract(const Duration(hours: 1));
      _updateWindow(soilWindow, cutoff, reading.recordedAt, state.soilPercent);
      _updateWindow(
        lightWindow,
        cutoff,
        reading.recordedAt,
        state.lightPercent,
      );
      final soilMean = _mean(soilWindow);
      final soilDelta = soilWindow.length < 2
          ? null
          : soilWindow.last.value - soilWindow.first.value;
      final lightMean = _mean(lightWindow);
      final water = _percent(row.waterRelativePercent);
      final mq = row.mq135Adc;
      final validMq = mq != null && mq >= 0 && mq <= 4095 ? mq : null;
      final fields = <String>[
        '1',
        reading.recordedAt.toIso8601String(),
        id.toString(),
        'cloud_reading',
        '',
        '',
        'server_reported',
        deviceRef ?? '',
        firmware ?? '',
        calibration ?? '',
        ..._feature(state.soilPercent),
        ..._feature(state.temperatureC),
        ..._feature(state.humidityPercent),
        ..._feature(state.lightPercent),
        ..._feature(state.uvIndex),
        ..._feature(null),
        ..._feature(water),
        ..._feature(validMq),
        ..._feature(soilMean),
        ..._feature(soilDelta),
        soilWindow.length.toString(),
        ..._feature(lightMean),
        lightWindow.length.toString(),
        label ?? '',
        labelSource,
      ];
      output.writeln(fields.join(','));
    }
    return output.toString();
  }

  static List<String> _feature(num? value) => value == null
      ? const ['', '1', 'not_available']
      : [value.toString(), '0', 'unverified'];

  static int? _percent(int? value) =>
      value != null && value >= 0 && value <= 100 ? value : null;

  static void _updateWindow(
    Queue<_TimedValue> window,
    DateTime cutoff,
    DateTime time,
    int? value,
  ) {
    while (window.isNotEmpty && window.first.time.isBefore(cutoff)) {
      window.removeFirst();
    }
    if (value != null) window.addLast(_TimedValue(time, value));
  }

  static double? _mean(Queue<_TimedValue> window) {
    if (window.isEmpty) return null;
    final sum = window.fold<int>(0, (total, point) => total + point.value);
    return sum / window.length;
  }

  // Restricted tokens are safe in spreadsheets and cannot inject CSV cells.
  static String? _identifier(String? value) {
    if (value == null) return null;
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,79}$').hasMatch(value)) {
      throw const FormatException('Invalid dataset identifier');
    }
    return value;
  }

  static String? _label(String? value) {
    if (value == null) return null;
    if (!RegExp(r'^[a-z][a-z0-9_]{0,39}$').hasMatch(value)) {
      throw const FormatException('Invalid label code');
    }
    return value;
  }
}

class _TimedValue {
  const _TimedValue(this.time, this.value);
  final DateTime time;
  final int value;
}
