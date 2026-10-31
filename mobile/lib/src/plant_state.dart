import 'plant_telemetry.dart';
import 'synthetic_xgboost.dart';

/// Plant expressions are simple UI rules, not medical or ML diagnoses.
enum PlantMood { waiting, content, thirsty, airConcern }

enum DemoScenario { content, thirsty, airConcern }

class PlantState {
  const PlantState({
    required this.isDemo,
    this.isLive = false,
    this.isSerialSnapshot = false,
    this.isLocalLive = false,
    this.soilPercent,
    this.waterPercent,
    this.waterObservationPercent,
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
    this.pumpRulePreview,
    this.lightRulePreview,
    this.waterLowPreview,
    this.pumpCommand,
    this.lightCommand,
    this.lightingCandidate,
    this.syntheticPrediction,
    this.airChanged = false,
  }) : assert(!isDemo || (!isLive && !isSerialSnapshot)),
       assert(!isLive || !isSerialSnapshot),
       assert(!isLocalLive || isLive);

  const PlantState.waiting() : this(isDemo: false);

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
      isDemo: false,
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
    isDemo: false,
    isSerialSnapshot: true,
    soilPercent: reading.soilRelativePercent,
    waterPercent: reading.waterRelativePercent,
    waterObservationPercent: reading.waterObservationPercent,
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
    pumpRulePreview: reading.pumpRulePreview,
    lightRulePreview: reading.lightRulePreview,
    waterLowPreview: reading.waterLowPreview,
    pumpCommand: reading.pumpCommand,
    lightCommand: reading.lightCommand,
    lightingCandidate: reading.lightingCandidate,
  );

  /// A new sample received directly over the local Wi-Fi stream. The phone's
  /// reception time is not substituted for a device measurement timestamp.
  factory PlantState.fromLocalWifi(
    SerialSensorSnapshot reading, {
    SyntheticPrediction? syntheticPrediction,
  }) => PlantState(
    isDemo: false,
    isLive: true,
    isLocalLive: true,
    soilPercent: reading.soilRelativePercent,
    waterPercent: reading.waterRelativePercent,
    waterObservationPercent: reading.waterObservationPercent,
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
    pumpCommand: reading.pumpCommand,
    lightCommand: reading.lightCommand,
    lightingCandidate: reading.lightingCandidate,
    syntheticPrediction: syntheticPrediction,
  );

  factory PlantState.demo(DemoScenario scenario) => switch (scenario) {
    DemoScenario.content => const PlantState(
      isDemo: true,
      soilPercent: 64,
      waterPercent: 78,
      temperatureC: 25.4,
      humidityPercent: 62,
      lightPercent: 68,
    ),
    DemoScenario.thirsty => const PlantState(
      isDemo: true,
      soilPercent: 22,
      waterPercent: 18,
      temperatureC: 27.1,
      humidityPercent: 58,
      lightPercent: 71,
    ),
    DemoScenario.airConcern => const PlantState(
      isDemo: true,
      soilPercent: 58,
      waterPercent: 63,
      temperatureC: 26.2,
      humidityPercent: 64,
      lightPercent: 56,
      airChanged: true,
    ),
  };

  final bool isDemo;
  final bool isLive;
  final bool isSerialSnapshot;
  final bool isLocalLive;
  final int? soilPercent;
  final int? waterPercent;
  final int? waterObservationPercent;
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
  final bool? pumpRulePreview;
  final bool? lightRulePreview;
  final bool? waterLowPreview;
  final bool? pumpCommand;
  final bool? lightCommand;
  final String? lightingCandidate;
  final SyntheticPrediction? syntheticPrediction;
  final bool airChanged;

  /// Fraction of the 12-bit ADC range for display only. It is not a UV index,
  /// gas concentration or physical air-quality measurement.
  static int? adcDisplayPercent(int? raw) =>
      raw == null || raw < 0 || raw > 4095 ? null : (raw * 100) ~/ 4095;

  int? get uvAdcPercent => adcDisplayPercent(uvAdc);
  int? get mqAdcPercent => adcDisplayPercent(mqAdc);

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
    if (!isDemo && !isLive) return PlantMood.waiting;
    if (isLocalLive && syntheticPrediction != null) {
      return switch (syntheticPrediction!.label) {
        'soil_relative_low' || 'water_near_low_reference' => PlantMood.thirsty,
        'no_synthetic_alert' => PlantMood.content,
        _ => PlantMood.waiting,
      };
    }
    if ((soilPercent != null && soilPercent! < 30) ||
        (waterPercent != null && waterPercent! < 20)) {
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
    if (isLocalLive && syntheticPrediction != null) {
      return 'Model mengikuti aturan sintetis; bukan diagnosis atau perintah relay.';
    }
    return switch (mood) {
      PlantMood.waiting => 'Menunggu pembacaan kelembapan tanah.',
      PlantMood.content =>
        'Estimasi tanah tidak berada di bawah ambang; belum diverifikasi.',
      PlantMood.thirsty => 'Estimasi tanah di bawah ambang; belum diverifikasi dan bukan diagnosis.',
      PlantMood.airConcern => 'Ada perubahan pada pembacaan udara.',
    };
  }

  /// Local ML affects only the character's presentation, never the relay.
  String get moodLabel =>
      isLocalLive && syntheticPrediction != null ? 'Pola sintetis' : mood.label;

  String get moodMessage {
    if (isLocalLive && syntheticPrediction != null) {
      return switch (syntheticPrediction!.label) {
        'soil_relative_low' => 'Pola tanah relatif rendah.',
        'water_near_low_reference' => 'Air mendekati acuan rendah.',
        'no_synthetic_alert' => 'Tidak ada penanda aturan sintetis.',
        'uv_unavailable' => 'Data UV belum tersedia.',
        'light_hold_band' => 'Aturan cahaya berada di zona tunggu.',
        'light_relative_low' => 'Cahaya relatif di bawah acuan.',
        _ => 'Menunggu data sensor.',
      };
    }
    return mood.message;
  }
}

extension PlantMoodCopy on PlantMood {
  String get label => switch (this) {
    PlantMood.waiting => 'Menunggu data',
    PlantMood.content => 'Sedang baik',
    PlantMood.thirsty => 'Butuh air',
    PlantMood.airConcern => 'Udara berubah',
  };

  String get message => switch (this) {
    PlantMood.waiting => 'Halo, aku Moss.',
    PlantMood.content => 'Aku merasa nyaman hari ini.',
    PlantMood.thirsty => 'Sepertinya aku butuh air.',
    PlantMood.airConcern => 'Ada perubahan di udara.',
  };

  String get explanation => switch (this) {
    PlantMood.waiting => 'Hubungkan perangkat untuk melihat kondisi tanaman.',
    PlantMood.content => 'Contoh: tanah dan air berada dalam rentang nyaman.',
    PlantMood.thirsty => 'Contoh: tanah kering atau air wadah mulai rendah.',
    PlantMood.airConcern =>
      'Contoh: pembacaan udara berubah dari kondisi awal.',
  };
}
