/// Relative MQ135 gas index from pin voltage, not ppm or CO2.
/// 0 = at/below the session baseline; 100 = strongest relative change.
class MqGasIndex {
  static const int supplyMillivolts = 5000;
  static const int minimumMillivolts = 100;
  static const int maximumMillivolts = 4900;

  int? _baselineMv;
  int? _index;
  String _status = 'unavailable';

  int? get index => _index;
  String get status => _status;
  int? get baselineMv => _baselineMv;

  void reset() {
    _baselineMv = null;
    _index = null;
    _status = 'unavailable';
  }

  /// Missing, rail or implausible voltages keep the last baseline but make the
  /// current index unavailable, so a disconnected sensor cannot look clean.
  void update(int? pinMillivolts) {
    if (pinMillivolts == null ||
        pinMillivolts < minimumMillivolts ||
        pinMillivolts >= maximumMillivolts) {
      _index = null;
      _status = 'unavailable';
      return;
    }
    final previous = _baselineMv;
    if (previous == null || pinMillivolts < previous) {
      _baselineMv = pinMillivolts;
    } else {
      final delta = pinMillivolts - previous;
      if (delta > 2) {
        // Follow a cleaner baseline quickly, but let a dirty baseline recover
        // only slowly so ordinary noise does not erase a real gas change.
        _baselineMv = previous + (delta / 64).ceil();
      }
    }
    final baseline = _baselineMv!;
    final resistance = (supplyMillivolts - pinMillivolts) / pinMillivolts;
    final baselineResistance = (supplyMillivolts - baseline) / baseline;
    final ratio = resistance / baselineResistance;
    final value = ((1 - ratio) * 100).round().clamp(0, 100);
    _index = value;
    _status = value < 10
        ? 'baseline'
        : value < 30
        ? 'slight'
        : value < 60
        ? 'elevated'
        : 'high';
  }
}
