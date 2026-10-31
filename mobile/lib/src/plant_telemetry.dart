import 'dart:convert';

/// A sensor sample supplied by the device data source.
///
/// [recordedAt] must be a trusted server timestamp, not the ESP32 clock. The
/// additional water-level and MQ135 sensors are deliberately not represented
/// here until their readings have been verified and calibrated.
class PlantTelemetry {
  const PlantTelemetry({
    required this.recordedAt,
    this.sequence,
    this.soilPercent,
    this.temperatureC,
    this.humidityPercent,
    this.lightPercent,
    this.uvIndex,
  });

  final DateTime recordedAt;

  /// Database row ID, used to break ties between equal server timestamps.
  final int? sequence;
  final int? soilPercent;
  final double? temperatureC;
  final int? humidityPercent;
  final int? lightPercent;

  /// Source-reported UV index estimate; calibration is not verified here.
  final double? uvIndex;

  /// Reject old readings and timestamps too far in the future. Allow a small
  /// amount of clock skew between the phone and the server.
  bool isFreshAt(DateTime now, {Duration maxAge = const Duration(minutes: 2)}) {
    final age = now.difference(recordedAt);
    return age <= maxAge && age >= -const Duration(seconds: 30);
  }
}

/// One device-protocol sample from a serial snapshot or local Wi-Fi stream.
/// Uptime is not a wall-clock timestamp; parsing alone does not establish
/// freshness, authentication, calibration, or a cloud record.
class SerialSensorSnapshot {
  const SerialSensorSnapshot._({
    this.uptimeMs,
    this.temperatureC,
    this.humidityPercent,
    this.soilAdc,
    this.soilRelativePercent,
    this.lightAdc,
    this.lightRelativePercent,
    this.uvAdc,
    this.waterAdc,
    this.waterRelativePercent,
    this.waterObservationPercent,
    this.mqAdc,
    this.mqDigital,
    this.mqAdcStatus,
    this.pumpRulePreview,
    this.lightRulePreview,
    this.waterLowPreview,
    this.pumpCommand,
    this.lightCommand,
    this.lightingCandidate,
  });

  final int? uptimeMs;
  final double? temperatureC;
  final double? humidityPercent;
  final int? soilAdc;
  final int? soilRelativePercent;
  final int? lightAdc;
  final int? lightRelativePercent;
  final int? uvAdc;
  final int? waterAdc;
  final int? waterRelativePercent;

  /// Display-only low-to-near-full scale, not the pump's water percentage.
  final int? waterObservationPercent;
  final int? mqAdc;
  final int? mqDigital;
  final String? mqAdcStatus;

  /// Offline diagnostic calculations, not commands or relay/contact states.
  final bool? pumpRulePreview;
  final bool? lightRulePreview;
  final bool? waterLowPreview;

  /// Requested GPIO commands, not measured relay/contact states.
  final bool? pumpCommand;
  final bool? lightCommand;

  /// Diagnostic decision only; never a command or a physical relay state.
  final String? lightingCandidate;

  bool get hasValues =>
      temperatureC != null ||
      humidityPercent != null ||
      soilAdc != null ||
      lightAdc != null ||
      uvAdc != null ||
      waterAdc != null ||
      mqAdc != null ||
      mqDigital != null;

  /// Accept only a single bounded sample from the serial JSON protocol.
  /// Invalid or explicitly unavailable fields remain null; a valid zero stays
  /// zero. Nothing is sent to cloud or stored persistently by this parser.
  static SerialSensorSnapshot parse(String input) {
    if (input.length > 4096) throw const FormatException('Sample too long');
    final decoded = jsonDecode(input);
    if (decoded is! Map<String, dynamic> || decoded['type'] != 'sample') {
      throw const FormatException('Not a serial sample');
    }
    Map<String, dynamic> map(Object? value) =>
        value is Map<String, dynamic> ? value : const {};
    double? decimal(Object? value, double min, double max) =>
        value is num && value.isFinite && value >= min && value <= max
        ? value.toDouble()
        : null;
    int? integer(Object? value, int min, int max) =>
        value is num &&
            value.isFinite &&
            value == value.truncateToDouble() &&
            value >= min &&
            value <= max
        ? value.toInt()
        : null;
    bool readable(Object? status) =>
        status == 'unverified' || status == 'valid' || status == 'partial';

    final dht = map(decoded['dht']);
    final adc = map(decoded['adc']);
    final water = map(decoded['water_level']);
    final waterObservation = map(water['observation_scale']);
    final mq = map(decoded['mq135']);
    final controlPreview = map(decoded['control_preview']);
    final lightingRule = map(decoded['lighting_rule']);
    final climatePresent = readable(dht['status']);
    final adcPresent = readable(adc['status']);
    final soil = readable(adc['soil_status'])
        ? integer(adc['soil_raw'], 0, 4095)
        : null;
    final light = adcPresent ? integer(adc['light_raw'], 0, 4095) : null;
    final waterRaw = readable(water['status'])
        ? integer(water['adc_raw'], 0, 4095)
        : null;
    final soilPercent = soil == null
        ? null
        : integer(adc['soil_relative_percent'], 0, 100);
    final lightPercent = light == null
        ? null
        : integer(adc['light_relative_percent'], 0, 100);
    final waterPercent = waterRaw == null
        ? null
        : integer(water['relative_percent'], 0, 100);
    bool? preview(String key, int? percent, int threshold) {
      if (controlPreview['mode'] != 'diagnostic_only' ||
          controlPreview['basis'] != 'relative_unverified' ||
          percent == null) {
        return null;
      }
      final value = controlPreview[key];
      return value is bool && value == (percent < threshold) ? value : null;
    }

    final snapshot = SerialSensorSnapshot._(
      uptimeMs: integer(decoded['uptime_ms'], 0, 0xffffffff),
      temperatureC: climatePresent
          ? decimal(dht['temperature_c'], -40, 80)
          : null,
      humidityPercent: climatePresent
          ? decimal(dht['humidity_percent'], 0, 100)
          : null,
      soilAdc: soil,
      soilRelativePercent: soilPercent,
      lightAdc: light,
      lightRelativePercent: lightPercent,
      uvAdc: adcPresent ? integer(adc['uv_raw'], 0, 4095) : null,
      waterAdc: waterRaw,
      waterRelativePercent: waterPercent,
      waterObservationPercent:
          waterRaw != null &&
              const {
                'operator_reported_window_means',
                'generic_display_references',
              }.contains(waterObservation['basis']) &&
              waterObservation['quality'] == 'unverified' &&
              waterObservation['use_for_control'] == false
          ? integer(waterObservation['relative_percent'], 0, 100)
          : null,
      mqAdc: readable(mq['status']) && readable(mq['adc_status'])
          ? integer(mq['adc_raw'], 0, 4095)
          : null,
      mqDigital: readable(mq['status'])
          ? integer(mq['digital_raw'], 0, 1)
          : null,
      mqAdcStatus: mq['adc_status'] == 'adc_read_failed'
          ? 'adc_read_failed'
          : null,
      pumpRulePreview: preview('pump_on', soilPercent, 50),
      lightRulePreview: preview('growlight_on', lightPercent, 60),
      waterLowPreview: preview('water_low', waterPercent, 20),
      pumpCommand: decoded['pump_cmd'] is bool
          ? decoded['pump_cmd'] as bool
          : null,
      lightCommand: decoded['growlight_cmd'] is bool
          ? decoded['growlight_cmd'] as bool
          : null,
      lightingCandidate:
          lightingRule['status'] == 'diagnostic_only_unverified' &&
              lightingRule['use_for_control'] == false &&
              const {
                'on',
                'off',
                'hold',
                'unavailable',
              }.contains(lightingRule['candidate'])
          ? lightingRule['candidate'] as String
          : null,
    );
    if (!snapshot.hasValues) throw const FormatException('No sensor values');
    return snapshot;
  }
}
