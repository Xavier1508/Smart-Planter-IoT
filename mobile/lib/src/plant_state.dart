import 'plant_telemetry.dart';

/// Plant expressions are simple UI rules, not medical or ML diagnoses.
enum PlantMood { waiting, content, thirsty, airConcern }

/// Coarse display categories, not a calibrated volume or actuator control.
enum WaterLevel { low, medium, full }

class PlantState {
  const PlantState({
    this.isLive = false,
    this.isSerialSnapshot = false,
    this.isLocalLive = false,
    this.soilPercent,
    this.waterPercent,
    this.waterObservationPercent,
    this.waterLow,
    this.waterClassificationInputsValid = true,
    this.temperatureC,
    this.humidityPercent,
    this.lightPercent,
    this.uvIndex,
    this.soilAdc,
    this.lightAdc,
    this.uvAdc,
    this.waterAdc,
    this.mqAdc,
    this.mqDigital,
    this.mqAdcStatus,
    this.mqAdcUnit,
    this.mqPinMillivolts,
    this.mqAverageAdc,
    this.mqAverageSamples = 0,
    this.mqTrend,
    this.pumpRulePreview,
    this.pumpRuleThreshold,
    this.lightRulePreview,
    this.waterLowPreview,
    this.pumpCommand,
    this.pumpReason,
    this.lightCommand,
    this.lightReason,
    this.lightingCandidate,
    this.airChanged = false,
  }) : assert(!isLive || !isSerialSnapshot),
       assert(!isLocalLive || isLive);

  const PlantState.waiting() : this();

  /// Invalid sensor values are omitted instead of being clamped or presented
  /// as real measurements. Uninstalled sensors stay unavailable.
  factory PlantState.fromTelemetry(PlantTelemetry reading) {
    int? percent(int? value) =>
        value != null && value >= 0 && value <= 100 ? value : null;
    final temperature = reading.temperatureC;
    final validTemperature =
        temperature != null &&
        temperature.isFinite &&
        temperature >= -40 &&
        temperature <= 80;
    final uv = reading.uvIndex;
    // This bounds the stored value; it does not verify sensor calibration.
    final validUv = uv != null && uv.isFinite && uv >= 0 && uv <= 25;
    return PlantState(
      isLive: true,
      soilPercent: percent(reading.soilPercent),
      temperatureC: validTemperature ? temperature : null,
      humidityPercent: percent(reading.humidityPercent),
      lightPercent: percent(reading.lightPercent),
      uvIndex: validUv ? uv : null,
    );
  }

  /// A manually imported snapshot has no trusted measurement time and must
  /// never be presented as a live stream or an ML/health prediction.
  factory PlantState.fromSerial(SerialSensorSnapshot reading) => PlantState(
    isSerialSnapshot: true,
    soilPercent: reading.soilRelativePercent,
    waterPercent: reading.waterRelativePercent,
    waterObservationPercent: reading.waterObservationPercent,
    waterLow: reading.waterLow,
    waterClassificationInputsValid: reading.waterClassificationInputsValid,
    temperatureC: reading.temperatureC,
    humidityPercent: reading.humidityPercent,
    lightPercent: reading.lightRelativePercent,
    soilAdc: reading.soilAdc,
    lightAdc: reading.lightAdc,
    uvAdc: reading.uvAdc,
    waterAdc: reading.waterAdc,
    mqAdc: reading.mqAdc,
    mqDigital: reading.mqDigital,
    mqAdcStatus: reading.mqAdcStatus,
    mqAdcUnit: reading.mqAdcUnit,
    mqPinMillivolts: reading.mqPinMillivolts,
    pumpRulePreview: reading.pumpRulePreview,
    pumpRuleThreshold: reading.pumpRuleThreshold,
    lightRulePreview: reading.lightRulePreview,
    waterLowPreview: reading.waterLowPreview,
    pumpCommand: reading.pumpCommand,
    pumpReason: reading.pumpReason,
    lightCommand: reading.lightCommand,
    lightReason: reading.lightReason,
    lightingCandidate: reading.lightingCandidate,
  );

  /// A new sample received directly over the local Wi-Fi stream. The phone's
  /// reception time is not substituted for a device measurement timestamp.
  factory PlantState.fromLocalWifi(
    SerialSensorSnapshot reading, {
    int? mqAverageAdc,
    int mqAverageSamples = 0,
    int? mqTrend,
  }) => PlantState(
    isLive: true,
    isLocalLive: true,
    soilPercent: reading.soilRelativePercent,
    waterPercent: reading.waterRelativePercent,
    waterObservationPercent: reading.waterObservationPercent,
    waterLow: reading.waterLow,
    waterClassificationInputsValid: reading.waterClassificationInputsValid,
    temperatureC: reading.temperatureC,
    humidityPercent: reading.humidityPercent,
    lightPercent: reading.lightRelativePercent,
    soilAdc: reading.soilAdc,
    lightAdc: reading.lightAdc,
    uvAdc: reading.uvAdc,
    waterAdc: reading.waterAdc,
    mqAdc: reading.mqAdc,
    mqDigital: reading.mqDigital,
    mqAdcStatus: reading.mqAdcStatus,
    mqAdcUnit: reading.mqAdcUnit,
    mqPinMillivolts: reading.mqPinMillivolts,
    mqAverageAdc: mqAverageAdc,
    mqAverageSamples: mqAverageSamples,
    mqTrend: mqTrend,
    pumpCommand: reading.pumpCommand,
    pumpReason: reading.pumpReason,
    lightCommand: reading.lightCommand,
    lightReason: reading.lightReason,
    lightingCandidate: reading.lightingCandidate,
  );

  final bool isLive;
  final bool isSerialSnapshot;
  final bool isLocalLive;
  final int? soilPercent;
  final int? waterPercent;
  final int? waterObservationPercent;
  final bool? waterLow;
  final bool waterClassificationInputsValid;
  final double? temperatureC;
  final num? humidityPercent;
  final int? lightPercent;
  final double? uvIndex;
  final int? soilAdc;
  final int? lightAdc;
  final int? uvAdc;
  final int? waterAdc;
  final int? mqAdc;
  final int? mqDigital;
  final String? mqAdcStatus;
  final String? mqAdcUnit;
  final int? mqPinMillivolts;
  final int? mqAverageAdc;
  final int mqAverageSamples;
  final int? mqTrend;
  final bool? pumpRulePreview;
  final int? pumpRuleThreshold;
  final bool? lightRulePreview;
  final bool? waterLowPreview;
  final bool? pumpCommand;
  final String? pumpReason;
  final bool? lightCommand;
  final String? lightReason;
  final String? lightingCandidate;
  final bool airChanged;

  /// Fraction of the 12-bit ADC range for display only. It is not a UV index,
  /// gas concentration or physical air-quality measurement.
  static int? adcDisplayPercent(int? raw) =>
      raw == null || raw < 0 || raw > 4095 ? null : (raw * 100) ~/ 4095;

  int? get uvAdcPercent => adcDisplayPercent(uvAdc);
  int? get mqAdcPercent => adcDisplayPercent(mqAdc);

  /// The firmware's 100% reference is near-full, not a verified full tank.
  /// These thresholds are provisional display buckets, never pump decisions.
  WaterLevel? get waterLevel {
    if (!waterClassificationInputsValid ||
        waterAdc == null ||
        waterAdc! <= 0 ||
        waterAdc! >= 4095) {
      return null;
    }

    WaterLevel? band(int? percent) {
      if (percent == null || percent < 0 || percent > 100) return null;
      if (percent < 20) return WaterLevel.low;
      if (percent < 90) return WaterLevel.medium;
      return WaterLevel.full;
    }

    if ((waterPercent != null && band(waterPercent) == null) ||
        (waterObservationPercent != null &&
            band(waterObservationPercent) == null)) {
      return null;
    }
    final controlBand = band(waterPercent);
    final observationBand = band(waterObservationPercent);
    if (controlBand != null &&
        observationBand != null &&
        controlBand != observationBand) {
      return null;
    }
    final relativeBand = controlBand ?? observationBand;
    if (waterLow != null &&
        relativeBand != null &&
        waterLow != (relativeBand == WaterLevel.low)) {
      return null;
    }
    if (waterLow == true) return WaterLevel.low;
    return relativeBand;
  }

  bool get hasSensorData =>
      soilPercent != null ||
      temperatureC != null ||
      humidityPercent != null ||
      lightPercent != null ||
      uvIndex != null ||
      soilAdc != null ||
      lightAdc != null ||
      uvAdc != null ||
      waterAdc != null ||
      waterObservationPercent != null ||
      mqAdc != null ||
      mqDigital != null;

  PlantMood get mood {
    if (!isLive) return PlantMood.waiting;
    if ((soilPercent != null && soilPercent! < 30) ||
        waterLevel == WaterLevel.low) {
      return PlantMood.thirsty;
    }
    if (airChanged) return PlantMood.airConcern;
    if (soilPercent == null) return PlantMood.waiting;
    return PlantMood.content;
  }

  String get explanation {
    if (isSerialSnapshot) {
      return 'Data serial tersimpan; waktu pembacaan tidak diketahui.';
    }
    if (!isLive) return mood.explanation;
    return switch (mood) {
      PlantMood.waiting => 'Menunggu pembacaan kelembapan tanah.',
      PlantMood.content =>
        'Estimasi tanah tidak berada di bawah ambang; belum diverifikasi.',
      PlantMood.thirsty => 'Estimasi tanah atau air di bawah ambang; belum diverifikasi dan bukan diagnosis.',
      PlantMood.airConcern => 'Ada perubahan pada pembacaan udara.',
    };
  }

  String get moodLabel => mood.label;

  String get moodMessage => mood.message;
}

extension PlantMoodCopy on PlantMood {
  String get label => switch (this) {
    PlantMood.waiting => 'Menunggu data',
    PlantMood.content => 'Tanah terpantau',
    PlantMood.thirsty => 'Kelembapan rendah',
    PlantMood.airConcern => 'Udara berubah',
  };

  String get message => switch (this) {
    PlantMood.waiting => 'Halo, aku Moss.',
    PlantMood.content => 'Kelembapan tanah terbaca.',
    PlantMood.thirsty => 'Tanah atau air relatif rendah.',
    PlantMood.airConcern => 'Ada perubahan di udara.',
  };

  String get explanation => switch (this) {
    PlantMood.waiting => 'Hubungkan perangkat untuk melihat kondisi tanaman.',
    PlantMood.content => 'Kelembapan tanah relatif belum diverifikasi.',
    PlantMood.thirsty => 'Kelembapan atau air relatif berada di bawah ambang.',
    PlantMood.airConcern => 'Ada perubahan pada pembacaan udara.',
  };
}
