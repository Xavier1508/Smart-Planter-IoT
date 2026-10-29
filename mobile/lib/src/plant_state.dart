import 'plant_telemetry.dart';

/// Plant expressions are simple UI rules, not medical or ML diagnoses.
enum PlantMood { waiting, content, thirsty, airConcern }

enum DemoScenario { content, thirsty, airConcern }

class PlantState {
  const PlantState({
    required this.isDemo,
    this.isLive = false,
    this.soilPercent,
    this.waterPercent,
    this.temperatureC,
    this.humidityPercent,
    this.lightPercent,
    this.uvIndex,
    this.airChanged = false,
  }) : assert(!isDemo || !isLive);

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
  final int? soilPercent;
  final int? waterPercent;
  final double? temperatureC;
  final int? humidityPercent;
  final int? lightPercent;
  final double? uvIndex;
  final bool airChanged;

  bool get hasSensorData =>
      soilPercent != null ||
      temperatureC != null ||
      humidityPercent != null ||
      lightPercent != null ||
      uvIndex != null;

  PlantMood get mood {
    if (!isDemo && !isLive) return PlantMood.waiting;
    if ((soilPercent != null && soilPercent! < 30) ||
        (waterPercent != null && waterPercent! < 20)) {
      return PlantMood.thirsty;
    }
    if (airChanged) return PlantMood.airConcern;
    if (soilPercent == null) return PlantMood.waiting;
    return PlantMood.content;
  }

  String get explanation {
    if (!isLive) return mood.explanation;
    return switch (mood) {
      PlantMood.waiting => 'Menunggu pembacaan kelembapan tanah.',
      PlantMood.content =>
        'Estimasi tanah tidak berada di bawah ambang; belum diverifikasi.',
      PlantMood.thirsty => 'Estimasi tanah di bawah ambang; belum diverifikasi dan bukan diagnosis.',
      PlantMood.airConcern => 'Ada perubahan pada pembacaan udara.',
    };
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
