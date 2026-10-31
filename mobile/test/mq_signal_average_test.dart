import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/mq_signal_average.dart';

void main() {
  test('averages only the newest twelve distinct samples', () {
    final window = MqSignalAverage();
    expect(window.average, isNull);
    for (var i = 0; i < 13; i++) {
      window.add(100 + i, i * 1000);
    }
    expect(window.count, 12);
    expect(window.average, 107); // Mean of 101..112, rounded to nearest ADC.
    window.add(1000, 12000); // Duplicate timestamps are ignored.
    window.add(1000, 11000); // Older timestamps are ignored too.
    expect(window.count, 12);
    expect(window.average, 107);
    window.clear();
    expect(window.count, 0);
    expect(window.average, isNull);
  });

  test('expires samples at sixty seconds of device uptime', () {
    final window = MqSignalAverage();
    window.add(100, 0);
    window.add(200, 59999);
    expect(window.count, 2);
    expect(window.average, 150);
    window.add(300, 60000);
    expect(window.count, 2);
    expect(window.average, 250);
    window.add(400, 120000);
    expect(window.count, 1);
    expect(window.average, 400);
  });

  test('missing, rail and out-of-range readings clear old values', () {
    final window = MqSignalAverage();
    var uptime = 0;
    for (final raw in <int?>[null, -1, 0, 4095, 4096]) {
      window.add(500, uptime += 5000);
      expect(window.average, 500);
      window.add(raw, uptime += 5000);
      expect(window.count, 0);
      expect(window.average, isNull);
    }
    window.add(600, uptime += 5000);
    expect(window.average, 600);
    window.add(600, -1);
    expect(window.average, isNull);
  });

  test('device uptime wrap is handled without accepting old readings', () {
    final window = MqSignalAverage();
    window.add(100, 0xfffffff0);
    window.add(200, 0x20);
    expect(window.count, 2);
    expect(window.average, 150);
    window.add(400, 0xffffffe0);
    expect(window.average, 150);
  });

  test('trend needs four samples and ignores small noise', () {
    final window = MqSignalAverage();
    for (final raw in [500, 510, 520]) {
      window.add(raw, window.count * 5000);
    }
    expect(window.trend, isNull);
    window.add(530, 15000);
    expect(window.trend, 1);

    final noisy = MqSignalAverage();
    for (final raw in [500, 501, 500, 502]) {
      noisy.add(raw, noisy.count * 5000);
    }
    expect(noisy.trend, 0);

    final falling = MqSignalAverage();
    for (final raw in [600, 590, 580, 570]) {
      falling.add(raw, falling.count * 5000);
    }
    expect(falling.trend, -1);
  });
}
