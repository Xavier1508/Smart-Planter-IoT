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
    this.waterLow,
    this.waterClassificationInputsValid = false,
    this.mqAdc,
    this.mqDigital,
    this.mqAdcStatus,
    this.mqAdcUnit,
    this.mqPinMillivolts,
    this.pumpRulePreview,
    this.pumpRuleThreshold,
    this.lightRulePreview,
    this.waterLowPreview,
    this.pumpCommand,
    this.pumpReason,
    this.lightCommand,
    this.lightReason,
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

  /// Unverified low-to-near-full display field; firmware versions may use the
  /// same references for control. It is not a measured tank volume.
  final int? waterObservationPercent;

  /// Firmware's provisional low-water result, not a physical level switch.
  final bool? waterLow;

  /// Malformed classification inputs must not be mistaken for missing fields.
  final bool waterClassificationInputsValid;
  final int? mqAdc;
  final int? mqDigital;
  final String? mqAdcStatus;
  final String? mqAdcUnit;

  /// ADC-characterized estimate at the ESP32 pin, not necessarily module A0.
  final int? mqPinMillivolts;

  /// Offline diagnostic calculations, not commands or relay/contact states.
  final bool? pumpRulePreview;
  final int? pumpRuleThreshold;
  final bool? lightRulePreview;
  final bool? waterLowPreview;

  /// Requested GPIO commands, not measured relay/contact states.
  final bool? pumpCommand;
  final String? pumpReason;
  final bool? lightCommand;
  final String? lightReason;

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
    final mqReadFailed =
        mq['adc_status'] == 'adc_read_failed' ||
        (mq['adc_unit'] == 'ADC1' && mq['signal_quality'] == 'adc_read_failed');
    final mqRaw =
        !mqReadFailed && readable(mq['status']) && readable(mq['adc_status'])
        ? integer(mq['adc_raw'], 0, 4095)
        : null;
    // Keep rail values as raw diagnostics, but do not present an ambiguous
    // disconnected/saturated input as a calibrated-looking percentage.
    bool usableAdc(int? raw) => raw != null && raw > 0 && raw < 4095;
    final soilPercent = !usableAdc(soil)
        ? null
        : integer(adc['soil_relative_percent'], 0, 100);
    final lightPercent = !usableAdc(light)
        ? null
        : integer(adc['light_relative_percent'], 0, 100);
    final waterPercent = !usableAdc(waterRaw)
        ? null
        : integer(water['relative_percent'], 0, 100);
    final observationScaleRecognized =
        const {
          'operator_reported_window_means',
          'generic_display_references',
        }.contains(waterObservation['basis']) &&
        waterObservation['quality'] == 'unverified' &&
        waterObservation['use_for_control'] == false;
    final observationPercent = usableAdc(waterRaw) && observationScaleRecognized
        ? integer(waterObservation['relative_percent'], 0, 100)
        : null;
    final waterInputsValid =
        usableAdc(waterRaw) &&
        (water['low'] == null || water['low'] is bool) &&
        (water['relative_percent'] == null || waterPercent != null) &&
        (!observationScaleRecognized ||
            waterObservation['relative_percent'] == null ||
            observationPercent != null);
    // Historical snapshots used 50%; v15/v16 use 40%. Unknown future versions
    // must not be interpreted using a guessed threshold.
    final version = integer(decoded['firmware_version'], 0, 0xffffffff);
    final int? pumpThreshold = version == null || version <= 14
        ? 50
        : version == 15 || version == 16
        ? 40
        : null;
    bool? preview(String key, int? percent, int? threshold) {
      if (controlPreview['mode'] != 'diagnostic_only' ||
          controlPreview['basis'] != 'relative_unverified' ||
          percent == null ||
          threshold == null) {
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
      waterObservationPercent: observationPercent,
      waterLow: usableAdc(waterRaw) && water['low'] is bool
          ? water['low'] as bool
          : null,
      waterClassificationInputsValid: waterInputsValid,
      mqAdc: mqRaw,
      mqDigital: readable(mq['status'])
          ? integer(mq['digital_raw'], 0, 1)
          : null,
      mqAdcStatus: mqReadFailed ? 'adc_read_failed' : null,
      mqAdcUnit: const {'ADC1', 'ADC2'}.contains(mq['adc_unit'])
          ? mq['adc_unit'] as String
          : null,
      mqPinMillivolts:
          usableAdc(mqRaw) &&
              const {
                'efuse_two_point',
                'efuse_vref',
                'default_vref_estimate',
              }.contains(mq['adc_calibration_source'])
          ? integer(mq['adc_pin_mv_estimate'], 0, 3300)
          : null,
      pumpRulePreview: preview('pump_on', soilPercent, pumpThreshold),
      pumpRuleThreshold: pumpThreshold,
      lightRulePreview: preview('growlight_on', lightPercent, 60),
      waterLowPreview: preview('water_low', waterPercent, 20),
      pumpCommand: decoded['pump_cmd'] is bool
          ? decoded['pump_cmd'] as bool
          : null,
      pumpReason:
          decoded['pump_cmd'] is bool &&
              const {
                'boot_grace',
                'soil_not_dry',
                'soil_moist',
                'soil_dry',
                'watering',
                'cooldown',
                'water_low',
                'water_unavailable',
                'soil_unverified',
                'soil_unavailable',
                'watchdog_unavailable',
                'sample_stale',
                'runtime_limit',
              }.contains(decoded['pump_reason'])
          ? decoded['pump_reason'] as String
          : null,
      lightCommand: decoded['growlight_cmd'] is bool
          ? decoded['growlight_cmd'] as bool
          : null,
      lightReason:
          decoded['growlight_cmd'] is bool &&
              const {
                'boot_grace',
                'light_low',
                'light_sufficient',
                'light_input_unavailable',
                'ldr_low',
                'ldr_sufficient',
                'ldr_input_unavailable',
                'light_inhibited',
                'minimum_hold',
                'hysteresis',
                'watchdog_unavailable',
                'sample_stale',
              }.contains(decoded['growlight_reason'])
          ? decoded['growlight_reason'] as String
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
