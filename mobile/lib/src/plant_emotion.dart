import 'plant_health.dart';
import 'plant_state.dart';

/// Three presentation emotions driven by the experimental synthetic model,
/// with threshold rules kept as a safety-oriented override. This is a demo
/// signal, not a plant-health diagnosis or an actuator command.
enum PlantEmotion { happy, neutral, alert }

extension PlantEmotionCopy on PlantEmotion {
  String get label => switch (this) {
    PlantEmotion.happy => 'Nyaman',
    PlantEmotion.neutral => 'Waspada',
    PlantEmotion.alert => 'Perlu perhatian',
  };

  String get shortLabel => switch (this) {
    PlantEmotion.happy => 'Tenang',
    PlantEmotion.neutral => 'Pantau',
    PlantEmotion.alert => 'Siaga',
  };

  String get message => switch (this) {
    PlantEmotion.happy =>
      'Tanah dan air terbaca dalam rentang yang nyaman. Karakter riang.',
    PlantEmotion.neutral =>
      'Ada sinyal yang perlu dipantau. Karakter tetap tenang, tetapi waspada.',
    PlantEmotion.alert =>
      'Kelembapan tanah atau air berada di bawah ambang. Karakter murung.',
  };
}

enum ConditionTrend { improving, stable, worsening, unknown }

extension ConditionTrendCopy on ConditionTrend {
  String get label => switch (this) {
    ConditionTrend.improving => 'Membaik',
    ConditionTrend.stable => 'Stabil',
    ConditionTrend.worsening => 'Memburuk',
    ConditionTrend.unknown => 'Menunggu tren',
  };

  String get explanation => switch (this) {
    ConditionTrend.improving =>
      'Pembacaan terakhir lebih baik dari awal jendela.',
    ConditionTrend.stable => 'Tidak ada perubahan besar dalam jendela pantau.',
    ConditionTrend.worsening =>
      'Pembacaan terakhir lebih rendah dari awal jendela.',
    ConditionTrend.unknown => 'Butuh beberapa sampel lagi untuk membaca arah.',
  };
}

/// One presentation result. [confidence] is the normalized winning score from
/// the mixed model and rules, not a calibrated probability.
class EmotionReading {
  const EmotionReading({
    required this.emotion,
    required this.trend,
    required this.confidence,
    required this.signal,
    required this.prediction,
    required this.modelLabel,
    required this.available,
  });

  final PlantEmotion emotion;
  final ConditionTrend trend;
  final double confidence;
  final String signal;
  final String prediction;
  final String modelLabel;
  final bool available;

  int get confidencePercent => (confidence * 100).round().clamp(0, 100);
}

/// Runs the existing pure-Dart gradient-boosted model and mixes its six
/// synthetic labels into three emotions. The rules are deliberately kept as a
/// guard: a low soil or water reading must never be hidden by a model score.
class PlantEmotionEngine {
  const PlantEmotionEngine(this.model);

  final PlantHealthModel? model;

  static const window = 6;

  EmotionReading evaluate(
    PlantState state, {
    List<PlantState> recent = const [],
  }) {
    if (!state.isLive && !state.isSerialSnapshot) {
      return const EmotionReading(
        emotion: PlantEmotion.neutral,
        trend: ConditionTrend.unknown,
        confidence: 0,
        signal: 'Belum ada perangkat terhubung',
        prediction: 'Hubungkan perangkat untuk mulai memantau.',
        modelLabel: 'menunggu',
        available: false,
      );
    }

    final soil = state.soilPercent;
    final water = state.waterObservationPercent ?? state.waterPercent;
    final light = state.lightPercent;
    final uv = state.uvIndex;

    // The tree expects soil/water/light percentages plus optional climate/gas
    // values. Missing optional sensors are imputed inside the model.
    PlantHealthPrediction? prediction;
    if (model != null) {
      prediction = model!.predict(
        soilPercent: soil,
        waterPercent: water,
        lightPercent: light,
        temperatureC: state.temperatureC,
        humidityPercent: state.humidityPercent?.toDouble(),
        uvIndex: uv,
        mqGasIndex: state.mqGasIndex,
      );
    }

    double happy = 0;
    double neutral = 0;
    double alert = 0;
    if (prediction != null) {
      double score(String name) {
        final index = PlantHealthModel.classes.indexOf(name);
        return index < 0 ? 0 : prediction!.scores[index];
      }

      happy += score('healthy');
      neutral += score('warning');
      alert += score('critical');
    }

    // Rule guard. The rules are not a second model; they keep the demo from
    // smiling when a measured value is clearly below the configured band.
    if (soil != null) {
      if (soil < 35) {
        alert += .75;
      } else if (soil < 55) {
        neutral += .35;
      } else {
        happy += .45;
      }
    }
    if (water != null) {
      if (water < 20) {
        alert += .75;
      } else if (water < 35) {
        neutral += .30;
      } else {
        happy += .30;
      }
    }
    if (state.waterLow == true) alert += .35;
    // Saturated soil is not healthy, even when the reservoir is full. A full
    // water sensor plus saturated soil is the classic flood/overwatering case.
    final waterlogged = soil != null && soil >= 85;
    final flooded = waterlogged && water != null && water >= 75;
    if (waterlogged) alert += flooded ? 1.2 : .7;
    final gas = state.mqGasIndex;
    if (gas != null && gas >= 70) alert += .15;
    final temperature = state.temperatureC;
    if (temperature != null && (temperature < 10 || temperature > 38)) {
      alert += .15;
    }
    if (soil == null && water == null) {
      neutral += .40;
    }

    final total = happy + neutral + alert;
    if (!total.isFinite || total <= 0) {
      return EmotionReading(
        emotion: PlantEmotion.neutral,
        trend: _trend(recent),
        confidence: 0,
        signal: 'Menunggu sinyal yang bisa dinilai',
        prediction: 'Beberapa sensor belum memberikan nilai yang valid.',
        modelLabel: prediction?.label ?? 'tidak tersedia',
        available: true,
      );
    }
    happy /= total;
    neutral /= total;
    alert /= total;

    // A measured alert is authoritative for presentation: never show a happy
    // character when soil or water is below the configured threshold.
    final measuredAlert =
        (soil != null && soil < 35) ||
        (water != null && water < 20) ||
        state.waterLow == true ||
        waterlogged;
    final measuredNeutral =
        (soil != null && soil >= 35 && soil < 55) ||
        (water != null && water >= 20 && water < 35);
    final emotion = measuredAlert
        ? PlantEmotion.alert
        : measuredNeutral
        ? PlantEmotion.neutral
        : (alert >= .48
              ? PlantEmotion.alert
              : (happy >= .46 && happy >= neutral
                    ? PlantEmotion.happy
                    : PlantEmotion.neutral));
    final confidence = switch (emotion) {
      PlantEmotion.happy => happy,
      PlantEmotion.alert => alert,
      PlantEmotion.neutral => neutral,
    };
    final trend = _trend(recent);
    return EmotionReading(
      emotion: emotion,
      trend: trend,
      confidence: confidence,
      signal: _signal(state, soil, water, gas, emotion),
      prediction: _prediction(emotion, trend, flooded: flooded),
      modelLabel: prediction?.label ?? 'aturan lokal',
      available: true,
    );
  }

  ConditionTrend _trend(List<PlantState> recent) {
    if (recent.length < 3) return ConditionTrend.unknown;
    final window = recent.length > PlantEmotionEngine.window
        ? recent.sublist(recent.length - PlantEmotionEngine.window)
        : recent;
    final soilValues = window
        .map((state) => state.soilPercent)
        .whereType<int>()
        .toList();
    if (soilValues.length >= 3) {
      final delta = soilValues.last - soilValues.first;
      if (delta <= -3) return ConditionTrend.worsening;
      if (delta >= 3) return ConditionTrend.improving;
      return ConditionTrend.stable;
    }
    final waterValues = window
        .map((state) => state.waterObservationPercent ?? state.waterPercent)
        .whereType<int>()
        .toList();
    if (waterValues.length >= 3) {
      final delta = waterValues.last - waterValues.first;
      if (delta <= -5) return ConditionTrend.worsening;
      if (delta >= 5) return ConditionTrend.improving;
      return ConditionTrend.stable;
    }
    return ConditionTrend.unknown;
  }

  String _signal(
    PlantState state,
    int? soil,
    int? water,
    int? gas,
    PlantEmotion emotion,
  ) {
    if (state.waterEmpty == true) {
      return 'Air penampung kosong (empty).';
    }
    if (soil != null && soil >= 85) {
      return water != null && water >= 75
          ? 'Tanah dan air terlalu tinggi — risiko banjir.'
          : 'Tanah terlalu basah — risiko kelebihan air.';
    }
    if (soil != null && soil < 35) return 'Kelembapan tanah rendah ($soil%).';
    if (water != null && water < 20) {
      return 'Air di bawah batas relatif ($water%).';
    }
    if (state.waterLow == true) return 'Sensor air menandai level rendah.';
    if (gas != null && gas >= 70) {
      return 'Indeks gas relatif tinggi ($gas/100).';
    }
    if (emotion == PlantEmotion.neutral && soil != null && soil < 55) {
      return 'Tanah mulai mengering ($soil%).';
    }
    if (emotion == PlantEmotion.neutral && water != null && water < 35) {
      return 'Air di zona waspada ($water%).';
    }
    return 'Tanah dan air dalam rentang pantau.';
  }

  String _prediction(
    PlantEmotion emotion,
    ConditionTrend trend, {
    bool flooded = false,
  }) {
    if (emotion == PlantEmotion.alert) {
      if (flooded) {
        return 'Kurangi air dan pastikan drainase; jangan siram lagi.';
      }
      return 'Perlu perhatian sekarang; cek pompa, air, dan probe tanah.';
    }
    if (trend == ConditionTrend.worsening) {
      return 'Berpotensi memburuk dalam beberapa menit jika dibiarkan.';
    }
    if (trend == ConditionTrend.improving) {
      return 'Kondisi sedang membaik dibanding awal jendela pantau.';
    }
    if (trend == ConditionTrend.stable) {
      return 'Tidak ada perubahan besar; lanjutkan pemantauan.';
    }
    return 'Butuh beberapa sampel lagi untuk memperkirakan arah.';
  }
}
