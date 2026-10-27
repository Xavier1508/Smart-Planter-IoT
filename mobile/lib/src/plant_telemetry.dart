/// A sensor sample from a future device data source.
///
/// [recordedAt] must be a trusted server timestamp, not the ESP32 clock. The
/// additional water-level and MQ135 sensors are deliberately not represented
/// here until they have been installed and calibrated.
class PlantTelemetry {
  const PlantTelemetry({
    required this.recordedAt,
    this.soilPercent,
    this.temperatureC,
    this.humidityPercent,
    this.lightPercent,
  });

  final DateTime recordedAt;
  final int? soilPercent;
  final double? temperatureC;
  final int? humidityPercent;
  final int? lightPercent;

  /// Reject old readings and timestamps too far in the future. Allow a small
  /// amount of clock skew between the phone and the server.
  bool isFreshAt(DateTime now, {Duration maxAge = const Duration(minutes: 2)}) {
    final age = now.difference(recordedAt);
    return age <= maxAge && age >= -const Duration(seconds: 30);
  }
}
