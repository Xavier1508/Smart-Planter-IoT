import 'dart:math' as math;

import 'plant_health.dart';
import 'plant_state.dart';

/// Three presentation emotions. The score and factors come from the holistic
/// model plus a small safety layer; they are not a medical diagnosis.
enum PlantEmotion { happy, neutral, alert }

extension PlantEmotionCopy on PlantEmotion {
  String get label => switch (this) {
    PlantEmotion.happy => 'Optimal',
    PlantEmotion.neutral => 'Pantau',
    PlantEmotion.alert => 'Perlu perhatian',
  };

  String get shortLabel => switch (this) {
    PlantEmotion.happy => 'Optimal',
    PlantEmotion.neutral => 'Pantau',
    PlantEmotion.alert => 'Siaga',
  };

  String get message => switch (this) {
    PlantEmotion.happy =>
      'Tanah, air, suhu, dan udara terbaca dalam rentang yang nyaman.',
    PlantEmotion.neutral => 'Ada aspek yang perlu dipantau, tetapi tidak semua berada di zona bahaya.',
    PlantEmotion.alert =>
      'Ada kondisi yang perlu ditangani; cek faktor dan tindakan di bawah.',
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

enum ConditionSeverity { good, watch, alert }

class ConditionFactor {
  const ConditionFactor({
    required this.label,
    required this.detail,
    required this.severity,
  });

  final String label;
  final String detail;
  final ConditionSeverity severity;
}

/// One presentation result. [score] is a 0-100 summary driven by the model;
/// [confidence] is the winning leaf probability, not a calibrated diagnosis.
class EmotionReading {
  const EmotionReading({
    required this.emotion,
    required this.trend,
    required this.confidence,
    required this.signal,
    required this.prediction,
    required this.modelLabel,
    required this.available,
    this.score = 0,
    this.factors = const [],
    this.actions = const [],
  });

  final PlantEmotion emotion;
  final ConditionTrend trend;
  final double confidence;
  final String signal;
  final String prediction;
  final String modelLabel;
  final bool available;
  final int score;
  final List<ConditionFactor> factors;
  final List<String> actions;

  int get confidencePercent => (confidence * 100).round().clamp(0, 100);
}

/// Runs the holistic tree and turns its class probabilities into a score.
/// Only extreme measurements override the model; ordinary "85% soil" or a low
/// reservoir becomes a watch factor instead of an automatic red alert.
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
        factors: [
          ConditionFactor(
            label: 'Koneksi',
            detail: 'Belum ada sampel sensor.',
            severity: ConditionSeverity.watch,
          ),
        ],
        actions: ['Hubungkan Wi-Fi planter untuk mulai memantau.'],
      );
    }

    final soil = state.soilPercent;
    final waterAdc = state.waterAdc;
    final waterUsable = waterAdc != null && waterAdc > 0 && waterAdc < 4095;
    final water =
        state.waterObservationPercent ??
        state.waterPercent ??
        (waterUsable ? 0 : null);
    final light = state.lightPercent;
    final gas = state.mqGasIndex;
    final temperature = state.temperatureC;
    final humidity = state.humidityPercent?.toDouble();
    final soilTrend = _delta(recent, (item) => item.soilPercent);
    final waterTrend = _delta(
      recent,
      (item) => item.waterObservationPercent ?? item.waterPercent,
    );
    final sensorCount = [
      soil != null,
      waterUsable,
      light != null,
    ].where((value) => value).length;

    PlantHealthPrediction? prediction;
    if (model != null) {
      prediction = model!.predict(
        soilPercent: soil,
        waterPercent: water,
        lightPercent: light,
        temperatureC: temperature,
        humidityPercent: humidity,
        uvIndex: state.uvIndex,
        mqGasIndex: gas,
        soilTrend: soilTrend,
        waterTrend: waterTrend,
        pumpLockout: state.pumpRuntimeLockout == true,
        sensorCount: sensorCount,
      );
    }

    final score = _score(
      prediction: prediction,
      soil: soil,
      water: water,
      light: light,
      temperature: temperature,
      humidity: humidity,
      gas: gas,
      state: state,
      sensorCount: sensorCount,
    );
    final hardAlert =
        state.waterEmpty == true ||
        (soil != null && soil < 25) ||
        (water != null && water < 10 && (soil == null || soil < 35)) ||
        (temperature != null && temperature >= 42) ||
        (gas != null && gas >= 90);
    final adjustedScore = hardAlert ? math.min(score, 24) : score;
    final emotion = hardAlert
        ? PlantEmotion.alert
        : adjustedScore >= 72
        ? PlantEmotion.happy
        : adjustedScore >= 45
        ? PlantEmotion.neutral
        : PlantEmotion.alert;
    final factors = _factors(
      state: state,
      soil: soil,
      water: water,
      light: light,
      temperature: temperature,
      humidity: humidity,
      gas: gas,
      soilTrend: soilTrend,
      waterTrend: waterTrend,
      sensorCount: sensorCount,
      prediction: prediction,
    );
    final actions = _actions(
      state: state,
      soil: soil,
      water: water,
      temperature: temperature,
      humidity: humidity,
      gas: gas,
      prediction: prediction,
      hardAlert: hardAlert,
    );
    final trend = _trend(recent);
    final signal = _signal(state, factors, soil, water);
    return EmotionReading(
      emotion: emotion,
      trend: trend,
      confidence: prediction?.confidence ?? adjustedScore / 100,
      signal: signal,
      prediction: _prediction(
        emotion: emotion,
        trend: trend,
        prediction: prediction,
        factors: factors,
        actions: actions,
      ),
      modelLabel: prediction?.displayLabel ?? 'aturan lokal',
      available: true,
      score: adjustedScore,
      factors: List.unmodifiable(factors),
      actions: List.unmodifiable(actions),
    );
  }

  int _score({
    required PlantHealthPrediction? prediction,
    required int? soil,
    required int? water,
    required int? light,
    required double? temperature,
    required double? humidity,
    required int? gas,
    required PlantState state,
    required int sensorCount,
  }) {
    double score;
    if (prediction != null) {
      double probability(String name) {
        final index = PlantHealthModel.classes.indexOf(name);
        return index < 0 ? 0 : prediction.scores[index];
      }

      score =
          probability('healthy') * 100 +
          probability('watch') * 68 +
          probability('dry') * 24 +
          probability('heat') * 28 +
          probability('air') * 22;
    } else {
      score = 100;
      if (soil != null) {
        if (soil < 22) {
          score = math.min(score, 22);
        } else if (soil < 35) {
          score -= 35;
        } else if (soil < 45) {
          score -= 15;
        }
      }
      if (water != null) {
        if (water < 10) {
          score = math.min(score, 25);
        } else if (water < 22) {
          score -= 18;
        } else if (water > 92) {
          score -= 8;
        }
      }
      if (temperature != null) {
        if (temperature >= 42) {
          score = math.min(score, 20);
        } else if (temperature >= 38) {
          score -= 35;
        } else if (temperature >= 33) {
          score -= 15;
        } else if (temperature <= 8) {
          score -= 20;
        }
      }
      if (humidity != null && humidity < 30) score -= 12;
      if (gas != null) {
        if (gas >= 80) {
          score = math.min(score, 25);
        } else if (gas >= 65) {
          score -= 15;
        }
      }
      if (light != null && light < 10) score -= 8;
    }

    // Small presentation nudges; they cannot turn a dry pot green or a flood
    // into a healthy result.
    if (state.waterLow == true || (water != null && water < 22)) {
      // A low reservoir is a watch condition even when the other features are
      // healthy. It must not be presented as an optimal result.
      score = math.min(score, 68);
    }
    if (state.pumpRuntimeLockout == true && state.pumpCommand != true) {
      score -= 5;
    }
    if (sensorCount < 3) {
      score -= 6 * (3 - sensorCount);
      // A partial readout must not be presented as a confident "optimal".
      score = math.min(score, 62);
    }
    return score.round().clamp(0, 100);
  }

  List<ConditionFactor> _factors({
    required PlantState state,
    required int? soil,
    required int? water,
    required int? light,
    required double? temperature,
    required double? humidity,
    required int? gas,
    required int soilTrend,
    required int waterTrend,
    required int sensorCount,
    required PlantHealthPrediction? prediction,
  }) {
    final factors = <ConditionFactor>[];
    if (soil == null) {
      factors.add(
        const ConditionFactor(
          label: 'Tanah',
          detail: 'Sensor tanah belum memberikan nilai.',
          severity: ConditionSeverity.watch,
        ),
      );
    } else if (soil < 22) {
      factors.add(
        ConditionFactor(
          label: 'Tanah',
          detail: 'Tanah sangat kering ($soil%).',
          severity: ConditionSeverity.alert,
        ),
      );
    } else if (soil < 35) {
      factors.add(
        ConditionFactor(
          label: 'Tanah',
          detail: 'Tanah kering ($soil%).',
          severity: ConditionSeverity.alert,
        ),
      );
    } else if (soil < 45) {
      factors.add(
        ConditionFactor(
          label: 'Tanah',
          detail: 'Tanah agak kering ($soil%).',
          severity: ConditionSeverity.watch,
        ),
      );
    } else {
      // The probe is a relative ADC scale, not a volumetric water sensor.
      // Wet soil (including the user's ~1900 ADC) is normal; do not turn a
      // high reading into an overwatering warning.
      factors.add(
        ConditionFactor(
          label: 'Tanah',
          detail: 'Tanah lembap ($soil%).',
          severity: ConditionSeverity.good,
        ),
      );
    }

    if (water == null) {
      factors.add(
        const ConditionFactor(
          label: 'Air',
          detail: 'Level penampung belum terbaca.',
          severity: ConditionSeverity.watch,
        ),
      );
    } else if (water < 10) {
      factors.add(
        ConditionFactor(
          label: 'Air',
          detail: 'Air penampung kosong ($water%).',
          severity: ConditionSeverity.alert,
        ),
      );
    } else if (water < 22) {
      factors.add(
        ConditionFactor(
          label: 'Air',
          detail: 'Air penampung rendah ($water%).',
          severity: ConditionSeverity.watch,
        ),
      );
    } else {
      factors.add(
        ConditionFactor(
          label: 'Air',
          detail: water > 92 ? 'Air penuh ($water%).' : 'Air cukup ($water%).',
          severity: ConditionSeverity.good,
        ),
      );
    }

    if (temperature == null && humidity == null) {
      factors.add(
        const ConditionFactor(
          label: 'Iklim',
          detail: 'Suhu dan kelembapan udara belum terbaca.',
          severity: ConditionSeverity.watch,
        ),
      );
    } else if (temperature != null && temperature >= 38) {
      factors.add(
        ConditionFactor(
          label: 'Suhu',
          detail: 'Suhu panas (${temperature.toStringAsFixed(1)}°C).',
          severity: ConditionSeverity.alert,
        ),
      );
    } else if (temperature != null && temperature >= 33) {
      factors.add(
        ConditionFactor(
          label: 'Suhu',
          detail: 'Suhu hangat (${temperature.toStringAsFixed(1)}°C).',
          severity: ConditionSeverity.watch,
        ),
      );
    } else if (humidity != null && humidity < 30) {
      factors.add(
        ConditionFactor(
          label: 'Udara',
          detail: 'Udara kering (${humidity.toStringAsFixed(0)}%).',
          severity: ConditionSeverity.watch,
        ),
      );
    } else if (humidity != null && humidity > 85) {
      factors.add(
        ConditionFactor(
          label: 'Udara',
          detail: 'Udara sangat lembap (${humidity.toStringAsFixed(0)}%).',
          severity: ConditionSeverity.watch,
        ),
      );
    } else {
      factors.add(
        const ConditionFactor(
          label: 'Iklim',
          detail: 'Suhu dan kelembapan udara dalam rentang pantau.',
          severity: ConditionSeverity.good,
        ),
      );
    }

    if (light == null) {
      factors.add(
        const ConditionFactor(
          label: 'Cahaya',
          detail: 'Cahaya belum terbaca.',
          severity: ConditionSeverity.watch,
        ),
      );
    } else if (light < 10) {
      factors.add(
        ConditionFactor(
          label: 'Cahaya',
          detail: 'Cahaya minim ($light%).',
          severity: ConditionSeverity.watch,
        ),
      );
    } else {
      factors.add(
        ConditionFactor(
          label: 'Cahaya',
          detail: 'Cahaya $light%.',
          severity: ConditionSeverity.good,
        ),
      );
    }

    if (gas != null && gas >= 80) {
      factors.add(
        ConditionFactor(
          label: 'Udara MQ135',
          detail: 'Indeks gas tinggi ($gas/100).',
          severity: ConditionSeverity.alert,
        ),
      );
    } else if (gas != null && gas >= 65) {
      factors.add(
        ConditionFactor(
          label: 'Udara MQ135',
          detail: 'Indeks gas meningkat ($gas/100).',
          severity: ConditionSeverity.watch,
        ),
      );
    }

    if (state.pumpRuntimeLockout == true && state.pumpCommand != true) {
      final seconds = state.pumpCooldownSeconds ?? 0;
      final minutes = (seconds / 60).ceil();
      factors.add(
        ConditionFactor(
          label: 'Pompa',
          detail: soil != null && soil < 5
              ? 'Pompa terkunci $minutes menit; probe tanah tetap $soil%.'
              : minutes > 0
              ? 'Pompa otomatis terkunci $minutes menit.'
              : 'Pompa otomatis sedang jeda.',
          severity: ConditionSeverity.watch,
        ),
      );
    } else if (state.pumpCommand == true) {
      factors.add(
        const ConditionFactor(
          label: 'Pompa',
          detail: 'Pompa sedang diminta menyala.',
          severity: ConditionSeverity.good,
        ),
      );
    }

    if (soilTrend <= -4 || waterTrend <= -6) {
      factors.add(
        const ConditionFactor(
          label: 'Tren',
          detail: 'Tanah atau air menurun dalam beberapa sampel.',
          severity: ConditionSeverity.watch,
        ),
      );
    } else if (soilTrend >= 4 || waterTrend >= 6) {
      factors.add(
        const ConditionFactor(
          label: 'Tren',
          detail: 'Kondisi membaik dibanding awal jendela.',
          severity: ConditionSeverity.good,
        ),
      );
    }

    if (sensorCount < 3) {
      factors.add(
        ConditionFactor(
          label: 'Sensor',
          detail: '${3 - sensorCount} sensor inti belum lengkap.',
          severity: ConditionSeverity.watch,
        ),
      );
    }
    if (prediction != null && prediction.label != 'healthy') {
      factors.add(
        ConditionFactor(
          label: 'Model',
          detail: 'Pola terbaca: ${prediction.displayLabel}.',
          severity: prediction.label == 'watch'
              ? ConditionSeverity.watch
              : ConditionSeverity.alert,
        ),
      );
    }

    final order = {
      ConditionSeverity.alert: 0,
      ConditionSeverity.watch: 1,
      ConditionSeverity.good: 2,
    };
    factors.sort((a, b) => order[a.severity]!.compareTo(order[b.severity]!));
    return factors;
  }

  List<String> _actions({
    required PlantState state,
    required int? soil,
    required int? water,
    required double? temperature,
    required double? humidity,
    required int? gas,
    required PlantHealthPrediction? prediction,
    required bool hardAlert,
  }) {
    final actions = <String>[];
    if (state.waterEmpty == true || (water != null && water < 10)) {
      actions.add('Isi penampung air.');
    } else if (state.waterLow == true || (water != null && water < 22)) {
      actions.add('Siapkan air cadangan; level penampung rendah.');
    }
    if (soil != null && soil < 35) {
      actions.add('Nyalakan pompa atau siram tanah.');
    }
    if (temperature != null && temperature >= 35) {
      actions.add('Naikkan naungan atau ventilasi.');
    } else if (humidity != null && humidity < 30) {
      actions.add('Tingkatkan kelembapan udara sekitar tanaman.');
    }
    if (gas != null && gas >= 70) {
      actions.add('Ventilasi udara di sekitar sensor MQ135.');
    }
    if (state.pumpRuntimeLockout == true && state.pumpCommand != true) {
      actions.add('Tunggu lockout pompa, atau pakai manual ON 1-30 detik.');
    }
    if (actions.isEmpty) {
      actions.add('Tidak ada tindakan mendesak; lanjutkan pemantauan.');
    }
    if (!hardAlert && prediction?.label == 'watch') {
      actions.add(
        'Cek kembali dalam beberapa sampel sebelum mengubah pengaturan.',
      );
    }
    return actions;
  }

  String _signal(
    PlantState state,
    List<ConditionFactor> factors,
    int? soil,
    int? water,
  ) {
    if (state.waterEmpty == true) return 'Air penampung kosong (empty).';
    if (factors.isNotEmpty) return factors.first.detail;
    if (soil != null) return 'Tanah $soil%.';
    if (water != null) return 'Air $water%.';
    return 'Menunggu sinyal yang bisa dinilai.';
  }

  String _prediction({
    required PlantEmotion emotion,
    required ConditionTrend trend,
    required PlantHealthPrediction? prediction,
    required List<ConditionFactor> factors,
    required List<String> actions,
  }) {
    final label = prediction?.label;
    if (label == 'dry' ||
        (emotion == PlantEmotion.alert &&
            factors.any((factor) => factor.detail.contains('kering')))) {
      return 'Tanah perlu air. ${actions.first}';
    }
    if (label == 'heat') {
      return 'Tekanan panas terdeteksi. ${actions.first}';
    }
    if (label == 'air') {
      return 'Kualitas udara perlu diperiksa. ${actions.first}';
    }
    if (emotion == PlantEmotion.alert) {
      return 'Perlu perhatian sekarang: ${actions.first}';
    }
    if (trend == ConditionTrend.worsening) {
      return 'Berpotensi memburuk dalam beberapa menit jika dibiarkan.';
    }
    if (trend == ConditionTrend.improving) {
      return 'Kondisi sedang membaik dibanding awal jendela pantau.';
    }
    if (emotion == PlantEmotion.neutral) {
      return 'Ada aspek yang perlu dipantau; belum perlu tindakan besar.';
    }
    return 'Semua aspek utama dalam rentang nyaman; lanjutkan pemantauan.';
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
    final waterValues = window
        .map((state) => state.waterObservationPercent ?? state.waterPercent)
        .whereType<int>()
        .toList();
    bool? worsening;
    bool? improving;
    if (soilValues.length >= 3) {
      final delta = soilValues.last - soilValues.first;
      if (delta <= -3) worsening = true;
      if (delta >= 3) improving = true;
    }
    if (waterValues.length >= 3) {
      final delta = waterValues.last - waterValues.first;
      if (delta <= -5) worsening = true;
      if (delta >= 5) improving = true;
    }
    if (worsening == true && improving != true) return ConditionTrend.worsening;
    if (improving == true && worsening != true) return ConditionTrend.improving;
    if (worsening == null && improving == null) return ConditionTrend.stable;
    return ConditionTrend.unknown;
  }

  int _delta(List<PlantState> recent, int? Function(PlantState) read) {
    if (recent.length < 2) return 0;
    final window = recent.length > PlantEmotionEngine.window
        ? recent.sublist(recent.length - PlantEmotionEngine.window)
        : recent;
    final values = window.map(read).whereType<int>().toList();
    if (values.length < 2) return 0;
    return (values.last - values.first).clamp(-100, 100);
  }
}
