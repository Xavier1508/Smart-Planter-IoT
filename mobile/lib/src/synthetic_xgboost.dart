import 'dart:convert';
import 'dart:math' as math;

/// An experimental classifier trained on synthetic threshold-based examples.
/// It estimates the synthetic label, not plant health or actuator state.
class SyntheticXgboostModel {
  SyntheticXgboostModel._(this._trees);

  static const schema = 'moss-synthetic-rule-xgboost-v1';
  static const features = <String>[
    'soil_relative_percent',
    'water_observation_percent',
    'light_relative_percent',
    'uv_index',
  ];
  static const classes = <String>[
    'soil_relative_low',
    'water_near_low_reference',
    'no_synthetic_alert',
    'uv_unavailable',
    'light_hold_band',
    'light_relative_low',
  ];

  final List<List<_TreeNode>> _trees;

  factory SyntheticXgboostModel.parse(String input) {
    if (input.length > 2000000) throw const FormatException('Model too large');
    final decoded = jsonDecode(input);
    if (decoded is! Map<String, dynamic> ||
        decoded['schema'] != schema ||
        decoded['training_data'] != 'synthetic_rule_labels_only' ||
        decoded['not_for_plant_health_or_relay_control'] != true ||
        !_sameStrings(decoded['features'], features) ||
        !_sameStrings(decoded['classes'], classes)) {
      throw const FormatException('Unexpected synthetic model');
    }
    final rawTrees = decoded['trees'];
    if (rawTrees is! List ||
        rawTrees.isEmpty ||
        rawTrees.length > 3000 ||
        rawTrees.length % classes.length != 0) {
      throw const FormatException('Invalid model trees');
    }
    final trees = <List<_TreeNode>>[];
    for (final rawTree in rawTrees) {
      if (rawTree is! List || rawTree.isEmpty || rawTree.length > 255) {
        throw const FormatException('Invalid model tree');
      }
      final nodes = <_TreeNode>[];
      for (final rawNode in rawTree) {
        if (rawNode is! Map<String, dynamic>) {
          throw const FormatException('Invalid model node');
        }
        final leaf = rawNode['leaf'];
        if (leaf is num && leaf.isFinite) {
          nodes.add(_TreeNode.leaf(leaf.toDouble()));
          continue;
        }
        final feature = rawNode['feature'];
        final threshold = rawNode['threshold'];
        final yes = rawNode['yes'];
        final no = rawNode['no'];
        final missing = rawNode['missing'];
        if (feature is! int ||
            feature < 0 ||
            feature >= features.length ||
            threshold is! num ||
            !threshold.isFinite ||
            yes is! int ||
            no is! int ||
            missing is! int ||
            yes < 0 ||
            no < 0 ||
            missing < 0 ||
            yes >= rawTree.length ||
            no >= rawTree.length ||
            missing >= rawTree.length) {
          throw const FormatException('Invalid split node');
        }
        nodes.add(
          _TreeNode.split(feature, threshold.toDouble(), yes, no, missing),
        );
      }
      trees.add(List.unmodifiable(nodes));
    }
    return SyntheticXgboostModel._(List.unmodifiable(trees));
  }

  /// Null indicates missing/out-of-range required input. UV may be null; raw UV
  /// ADC must never be substituted for an index. Scores are model outputs on
  /// synthetic labels, not validated probabilities of actual plant conditions.
  SyntheticPrediction? predict({
    required int? soilPercent,
    required int? waterObservationPercent,
    required int? lightPercent,
    required double? uvIndex,
  }) {
    bool validPercent(int? value) =>
        value != null && value >= 0 && value <= 100;
    if (!validPercent(soilPercent) ||
        !validPercent(waterObservationPercent) ||
        !validPercent(lightPercent) ||
        (uvIndex != null &&
            (!uvIndex.isFinite || uvIndex < 1 || uvIndex > 14))) {
      return null;
    }
    final values = <double?>[
      soilPercent!.toDouble(),
      waterObservationPercent!.toDouble(),
      lightPercent!.toDouble(),
      uvIndex,
    ];
    final margins = List<double>.filled(classes.length, 0);
    for (var treeIndex = 0; treeIndex < _trees.length; treeIndex++) {
      final tree = _trees[treeIndex];
      var index = 0;
      var foundLeaf = false;
      for (var steps = 0; steps < tree.length; steps++) {
        final node = tree[index];
        final leaf = node.leaf;
        if (leaf != null) {
          margins[treeIndex % classes.length] += leaf;
          foundLeaf = true;
          break;
        }
        final value = values[node.feature!];
        index = value == null
            ? node.missing!
            : value < node.threshold!
            ? node.yes!
            : node.no!;
      }
      if (!foundLeaf) return null;
    }
    final largest = margins.reduce(math.max);
    final weights = margins.map((value) => math.exp(value - largest)).toList();
    final sum = weights.fold<double>(0, (total, value) => total + value);
    if (!sum.isFinite || sum <= 0) return null;
    final scores = weights.map((value) => value / sum).toList(growable: false);
    var selected = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[selected]) selected = i;
    }
    return SyntheticPrediction._(classes[selected], scores[selected], scores);
  }

  static bool _sameStrings(Object? candidate, List<String> expected) {
    if (candidate is! List || candidate.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (candidate[i] != expected[i]) return false;
    }
    return true;
  }
}

class SyntheticPrediction {
  const SyntheticPrediction._(this.label, this.score, this.scores);

  final String label;
  final double score;
  final List<double> scores;
}

class _TreeNode {
  const _TreeNode.leaf(this.leaf)
    : feature = null,
      threshold = null,
      yes = null,
      no = null,
      missing = null;

  const _TreeNode.split(
    this.feature,
    this.threshold,
    this.yes,
    this.no,
    this.missing,
  ) : leaf = null;

  final double? leaf;
  final int? feature;
  final double? threshold;
  final int? yes;
  final int? no;
  final int? missing;
}
