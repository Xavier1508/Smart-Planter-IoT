import 'plant_state.dart';
import 'synthetic_xgboost.dart';

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

  final SyntheticXgboostModel? model;

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

    // The model expects a 0-100 soil value, a 0-100 water observation value,
    // a 0-100 light value and an optional 1-14 UV index.
    SyntheticPrediction? prediction;
    if (model != null) {
      prediction = model!.predict(
        soilPercent: soil,
        waterObservationPercent: water,
        lightPercent: light,
        uvIndex: uv != null && uv >= 1 && uv <= 14 ? uv : null,
      );
    }

    double happy = 0;
    double neutral = 0;
    double alert = 0;
    if (prediction != null) {
      double score(String name) {
        final index = SyntheticXgboostModel.classes.indexOf(name);
        return index < 0 ? 0 : prediction!.scores[index];
      }

      happy += score('no_synthetic_alert');
      alert += score('soil_relative_low') + score('water_near_low_reference');
      neutral +=
          score('uv_unavailable') +
          score('light_hold_band') +
          score('light_relative_low');
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
        state.waterLow == true;
    final emotion = measuredAlert
        ? PlantEmotion.alert
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
      prediction: _prediction(emotion, trend),
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

  String _prediction(PlantEmotion emotion, ConditionTrend trend) {
    if (emotion == PlantEmotion.alert) {
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
