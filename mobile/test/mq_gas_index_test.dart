import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/mq_gas_index.dart';

void main() {
  test('first valid voltage becomes the baseline and index zero', () {
    final gas = MqGasIndex();
    gas.update(550);
    expect(gas.index, 0);
    expect(gas.status, 'baseline');
    expect(gas.baselineMv, 550);
  });

  test('higher voltage raises the relative gas index', () {
    final gas = MqGasIndex();
    gas.update(550);
    gas.update(800);
    expect(gas.index, 35);
    expect(gas.status, 'elevated');
    expect(gas.baselineMv, greaterThan(550));

    gas.update(1500);
    expect(gas.index, greaterThanOrEqualTo(60));
    expect(gas.status, 'high');
  });

  test('cleaner air lowers the baseline and returns to zero', () {
    final gas = MqGasIndex();
    gas.update(550);
    gas.update(800);
    expect(gas.index, greaterThan(0));
    gas.update(400);
    expect(gas.index, 0);
    expect(gas.status, 'baseline');
    expect(gas.baselineMv, 400);
  });

  test('invalid and rail voltages hide the index but keep the baseline', () {
    final gas = MqGasIndex();
    gas.update(550);
    for (final value in <int?>[null, 0, 99, 4900, 5000, -1]) {
      gas.update(value);
      expect(gas.index, isNull);
      expect(gas.status, 'unavailable');
      expect(gas.baselineMv, 550);
    }
    gas.update(560);
    expect(gas.index, lessThan(10));
    expect(gas.status, 'baseline');
  });

  test('reset clears the session baseline', () {
    final gas = MqGasIndex();
    gas.update(550);
    gas.update(800);
    gas.reset();
    expect(gas.index, isNull);
    expect(gas.status, 'unavailable');
    expect(gas.baselineMv, isNull);
  });
}
