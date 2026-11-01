import 'plant_telemetry.dart';

const _zonedPattern = r'(?:[zZ]|[+-]\d\d(?::?\d\d)?)$';

DateTime? _zonedTime(Object? value) {
  if (value is! String || !RegExp(_zonedPattern).hasMatch(value)) return null;
  return DateTime.tryParse(value);
}

/// Decode one server row without inferring sensor calibration or relay state.
PlantTelemetry decodeCloudReading(Map<String, dynamic> row) {
  final time = _zonedTime(row['recorded_at']);
  if (time == null) throw const FormatException('Missing server timestamp');

  int? integer(Object? value) =>
      value is num && value.isFinite && value == value.truncateToDouble()
      ? value.toInt()
      : null;
  double? decimal(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;
  bool? flag(Object? value) => value is bool ? value : null;
  String? text(Object? value, int max) =>
      value is String && value.trim().isNotEmpty && value.length <= max
      ? value.trim()
      : null;
  final sequence = integer(row['id']);
  if (sequence == null) throw const FormatException('Missing row ID');

  final captured = _zonedTime(row['captured_at']);
  final timeQuality =
      row['time_quality'] == 'ntp' || row['time_quality'] == 'uptime_only'
      ? row['time_quality'] as String
      : null;

  return PlantTelemetry(
    recordedAt: time,
    capturedAt: captured,
    timeQuality: timeQuality,
    sequence: sequence,
    soilPercent: integer(row['soil_percent']),
    temperatureC: decimal(row['temperature_c']),
    humidityPercent: integer(row['humidity_percent']),
    lightPercent: integer(row['light_percent']),
    uvIndex: decimal(row['uv_index']),
    soilAdc: integer(row['soil_adc']),
    waterAdc: integer(row['water_adc']),
    waterPercent: integer(row['water_percent']),
    waterObservationPercent: integer(row['water_observation_percent']),
    waterEmpty: flag(row['water_empty']),
    waterLow: flag(row['water_low']),
    lightAdc: integer(row['light_adc']),
    uvAdc: integer(row['uv_adc']),
    mqAdc: integer(row['mq_adc']),
    mqPinMv: integer(row['mq_pin_mv']),
    pumpCommand: flag(row['pump_on']),
    pumpReason: text(row['pump_reason'], 64),
    pumpCooldownSeconds: integer(row['pump_cooldown_s']),
    pumpRuntimeLockout: flag(row['pump_runtime_lockout']),
    lightCommand: flag(row['growlight_on']),
    lightReason: text(row['light_reason'], 64),
  );
}
