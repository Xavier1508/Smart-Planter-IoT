import 'dart:convert';

/// A compact holistic decision tree trained offline by
/// `tools/ml/train-plant-health.py`. It combines agronomic scenarios with
/// observed sensor patterns. It is a presentation model, not a validated
/// plant-health diagnosis or an actuator command.
class PlantHealthModel {
  PlantHealthModel._(this._tree);

  static const schema = 'tunas-plant-health-tree-v2';
  static const features = <String>[
    'soil_percent',
    'water_percent',
    'light_percent',
    'temperature_c',
    'humidity_percent',
    'uv_index',
    'mq_gas_index',
    'soil_water_interaction',
    'soil_trend',
    'water_trend',
    'pump_lockout',
    'sensor_count',
  ];
  static const classes = <String>[
    'healthy',
    'watch',
    'dry',
    'wet',
    'heat',
    'air',
  ];
  static const displayLabels = <String, String>{
    'healthy': 'Optimal',
    'watch': 'Pantau',
    'dry': 'Kekeringan',
    'wet': 'Kelebihan air',
    'heat': 'Tekanan panas',
    'air': 'Udara buruk',
  };

  final _HealthNode _tree;

  factory PlantHealthModel.parse(String input) {
    if (input.length > 200000) throw const FormatException('Model too large');
    final decoded = jsonDecode(input);
    if (decoded is! Map<String, dynamic> ||
        decoded['schema'] != schema ||
        decoded['training_data'] != 'synthetic_plus_observed_patterns_v2' ||
        decoded['not_for_plant_health_or_relay_control'] != true ||
        !_sameStrings(decoded['features'], features) ||
        !_sameStrings(decoded['classes'], classes)) {
      throw const FormatException('Unexpected plant health model');
    }
    return PlantHealthModel._(_parseNode(decoded['tree'], 0));
  }

  PlantHealthPrediction? predict({
    required int? soilPercent,
    required int? waterPercent,
    required int? lightPercent,
    double? temperatureC,
    double? humidityPercent,
    double? uvIndex,
    int? mqGasIndex,
    int soilTrend = 0,
    int waterTrend = 0,
    bool pumpLockout = false,
    int sensorCount = 3,
  }) {
    bool validPercent(int? value) =>
        value != null && value >= 0 && value <= 100;
    if (!validPercent(soilPercent) ||
        !validPercent(waterPercent) ||
        !validPercent(lightPercent)) {
      return null;
    }
    final temperature =
        temperatureC != null &&
            temperatureC.isFinite &&
            temperatureC >= -40 &&
            temperatureC <= 80
        ? temperatureC
        : 25.0;
    final humidity =
        humidityPercent != null &&
            humidityPercent.isFinite &&
            humidityPercent >= 0 &&
            humidityPercent <= 100
        ? humidityPercent.toDouble()
        : 60.0;
    final uv =
        uvIndex != null && uvIndex.isFinite && uvIndex >= 0 && uvIndex <= 14
        ? uvIndex
        : 5.0;
    final gas = mqGasIndex != null && mqGasIndex >= 0 && mqGasIndex <= 100
        ? mqGasIndex.toDouble()
        : 30.0;
    final values = <double>[
      soilPercent!.toDouble(),
      waterPercent!.toDouble(),
      lightPercent!.toDouble(),
      temperature,
      humidity,
      uv,
      gas,
      soilPercent * waterPercent / 100.0,
      soilTrend.clamp(-100, 100).toDouble(),
      waterTrend.clamp(-100, 100).toDouble(),
      pumpLockout ? 1 : 0,
      sensorCount.clamp(0, 3).toDouble(),
    ];
    var node = _tree;
    for (var depth = 0; depth < 32 && node.feature != null; depth++) {
      node = values[node.feature!] <= node.threshold! ? node.yes! : node.no!;
    }
    final scores = node.probabilities;
    if (scores == null || scores.length != classes.length) return null;
    var selected = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[selected]) selected = i;
    }
    return PlantHealthPrediction._(classes[selected], scores[selected], scores);
  }

  static _HealthNode _parseNode(Object? value, int depth) {
    if (depth > 24 || value is! Map<String, dynamic>) {
      throw const FormatException('Invalid tree node');
    }
    final rawProbabilities = value['p'];
    if (rawProbabilities is List) {
      if (rawProbabilities.length != classes.length) {
        throw const FormatException('Invalid leaf');
      }
      final probabilities = <double>[];
      for (final raw in rawProbabilities) {
        if (raw is! num || !raw.isFinite || raw < 0 || raw > 1) {
          throw const FormatException('Invalid leaf probability');
        }
        probabilities.add(raw.toDouble());
      }
      return _HealthNode.leaf(List<double>.unmodifiable(probabilities));
    }
    final feature = value['f'];
    final threshold = value['t'];
    if (feature is! int ||
        feature < 0 ||
        feature >= features.length ||
        threshold is! num ||
        !threshold.isFinite) {
      throw const FormatException('Invalid split');
    }
    return _HealthNode.split(
      feature,
      threshold.toDouble(),
      _parseNode(value['y'], depth + 1),
      _parseNode(value['n'], depth + 1),
    );
  }

  static bool _sameStrings(Object? candidate, List<String> expected) {
    if (candidate is! List || candidate.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (candidate[i] != expected[i]) return false;
    }
    return true;
  }
}

class PlantHealthPrediction {
  const PlantHealthPrediction._(this.label, this.confidence, this.scores);

  final String label;
  final double confidence;
  final List<double> scores;

  String get displayLabel => PlantHealthModel.displayLabels[label] ?? label;
}

class _HealthNode {
  const _HealthNode.leaf(this.probabilities)
    : feature = null,
      threshold = null,
      yes = null,
      no = null;

  const _HealthNode.split(this.feature, this.threshold, this.yes, this.no)
    : probabilities = null;

  final List<double>? probabilities;
  final int? feature;
  final double? threshold;
  final _HealthNode? yes;
  final _HealthNode? no;
}
