import 'plant_telemetry.dart';

/// Decode one server row without inferring sensor calibration or relay state.
PlantTelemetry decodeCloudReading(Map<String, dynamic> row) {
  final rawTime = row['recorded_at'];
  if (rawTime is! String ||
      !RegExp(r'(?:[zZ]|[+-]\d\d(?::?\d\d)?)$').hasMatch(rawTime)) {
    throw const FormatException('Missing server timestamp');
  }
  final time = DateTime.tryParse(rawTime);
  if (time == null) throw const FormatException('Invalid server timestamp');

  int? integer(Object? value) =>
      value is num && value.isFinite && value == value.truncateToDouble()
      ? value.toInt()
      : null;
  double? decimal(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;
  final sequence = integer(row['id']);
  if (sequence == null) throw const FormatException('Missing row ID');

  return PlantTelemetry(
    recordedAt: time,
    sequence: sequence,
    soilPercent: integer(row['soil_percent']),
    temperatureC: decimal(row['temperature_c']),
    humidityPercent: integer(row['humidity_percent']),
    lightPercent: integer(row['light_percent']),
    uvIndex: decimal(row['uv_index']),
  );
}
