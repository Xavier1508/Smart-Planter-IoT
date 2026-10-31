import 'dart:collection';

/// Short-lived smoothing of ADC observations, never a gas calibration or ppm.
/// Inputs are successive, already-averaged firmware frames. Rail and missing
/// readings clear the window so an older value cannot masquerade as live data.
class MqSignalAverage {
  static const maxSamples = 12;
  static const maxAgeMs = 60000;

  final Queue<({int uptimeMs, int raw})> _samples = Queue();
  int _sum = 0;
  int? _lastUptimeMs;

  int get count => _samples.length;
  int? get average => _samples.isEmpty
      ? null
      : (_sum + _samples.length ~/ 2) ~/ _samples.length;

  /// Direction of the smoothed signal: -1 falling, 0 steady, 1 rising.
  /// A three-ADC change is used as a small noise floor for five-conversion
  /// firmware means. This is a relative trend, never a gas concentration.
  int? get trend {
    if (_samples.length < 4) return null;
    final values = _samples.map((sample) => sample.raw).toList();
    final half = values.length ~/ 2;
    double mean(Iterable<int> items) =>
        items.reduce((left, right) => left + right) / items.length;
    final delta =
        mean(values.skip(values.length - half)) - mean(values.take(half));
    if (delta >= 3) return 1;
    if (delta <= -3) return -1;
    return 0;
  }

  void add(int? raw, int uptimeMs) {
    if (uptimeMs < 0 || uptimeMs > 0xffffffff) {
      clear();
      return;
    }
    final previous = _lastUptimeMs;
    if (previous != null) {
      final delta = (uptimeMs - previous) & 0xffffffff;
      if (delta == 0 || delta >= 0x80000000) return;
    }
    _lastUptimeMs = uptimeMs;
    if (raw == null || raw <= 0 || raw >= 4095) {
      _samples.clear();
      _sum = 0;
      return;
    }
    while (_samples.isNotEmpty &&
        ((uptimeMs - _samples.first.uptimeMs) & 0xffffffff) >= maxAgeMs) {
      _sum -= _samples.removeFirst().raw;
    }
    _samples.addLast((uptimeMs: uptimeMs, raw: raw));
    _sum += raw;
    while (_samples.length > maxSamples) {
      _sum -= _samples.removeFirst().raw;
    }
  }

  void clear() {
    _samples.clear();
    _sum = 0;
    _lastUptimeMs = null;
  }
}
