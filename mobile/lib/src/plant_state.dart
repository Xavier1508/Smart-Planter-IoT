/// This initial dashboard contains demonstration data only. Real telemetry,
/// calibration and machine learning will be integrated separately.
enum PlantMood { waiting, content, thirsty, airConcern }

enum DemoScenario { content, thirsty, airConcern }

class PlantState {
  const PlantState({
    required this.isDemo,
    this.soilPercent,
    this.waterPercent,
    this.temperatureC,
    this.humidityPercent,
    this.lightPercent,
    this.airChanged = false,
  });

  const PlantState.waiting() : this(isDemo: false);

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
  final int? soilPercent;
  final int? waterPercent;
  final double? temperatureC;
  final int? humidityPercent;
  final int? lightPercent;
  final bool airChanged;

  PlantMood get mood {
    if (!isDemo) return PlantMood.waiting;
    if ((soilPercent != null && soilPercent! < 30) ||
        (waterPercent != null && waterPercent! < 20)) {
      return PlantMood.thirsty;
    }
    if (airChanged) return PlantMood.airConcern;
    return PlantMood.content;
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
