import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/local_wifi.dart';

String sample(int uptime, {int version = 12}) => jsonEncode({
  'type': 'sample',
  'schema': 'serial_observation_2',
  'firmware_version': version,
  'uptime_ms': uptime,
  'dht': {
    'temperature_c': 28.7,
    'humidity_percent': 74.0,
    'status': 'unverified',
  },
  'adc': {
    'soil_raw': 1000,
    'soil_status': 'unverified',
    'soil_relative_percent': 44,
    'light_raw': 2000,
    'light_relative_percent': 51,
    'uv_raw': 0,
    'status': 'unverified',
  },
  'water_level': {
    'adc_raw': 1200,
    'relative_percent': null,
    'status': 'unverified',
    'observation_scale': {
      'relative_percent': 50,
      'basis': 'operator_reported_window_means',
      'quality': 'unverified',
      'use_for_control': false,
    },
  },
  'mq135': {
    'adc_raw': null,
    'digital_raw': 1,
    'adc_status': 'adc_read_failed',
    'status': 'unverified',
  },
  'pump_cmd': false,
  'growlight_cmd': false,
  'lighting_rule': {
    'candidate': 'unavailable',
    'status': 'diagnostic_only_unverified',
    'use_for_control': false,
  },
});

Future<void> waitFor(
  LocalWifiController controller,
  bool Function() ready,
) async {
  if (ready()) return;
  final done = Completer<void>();
  final subscription = controller.changes.listen((_) {
    if (ready() && !done.isCompleted) done.complete();
  });
  try {
    if (ready() && !done.isCompleted) done.complete();
    await done.future.timeout(const Duration(seconds: 3));
  } finally {
    await subscription.cancel();
  }
}

void main() {
  test('default endpoint is the dedicated local ESP32 AP', () {
    final controller = LocalWifiController();
    expect(controller.address, '192.168.4.1');
    expect(controller.port, 3333);
    controller.dispose();
  });

  test(
    'real loopback stream receives frames and clears data on disconnect',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final incoming = server.first;
      final controller = LocalWifiController(
        address: '127.0.0.1',
        port: server.port,
      );
      final connecting = controller.connect();
      final peer = await incoming;
      addTearDown(() async {
        peer.destroy();
        controller.dispose();
        await server.close();
      });
      await connecting;
      expect(controller.status, LocalWifiStatus.waiting);

      final data = sample(5000);
      peer.add(utf8.encode(data.substring(0, 15)));
      peer.add(utf8.encode('${data.substring(15)}\n'));
      await waitFor(
        controller,
        () => controller.status == LocalWifiStatus.live,
      );
      expect(controller.snapshot?.soilRelativePercent, 44);
      expect(controller.snapshot?.uvAdc, 0);
      expect(controller.snapshot?.waterRelativePercent, isNull);
      expect(controller.snapshot?.waterObservationPercent, 50);
      expect(controller.snapshot?.mqAdc, isNull);
      expect(controller.snapshot?.mqAdcStatus, 'adc_read_failed');
      expect(controller.snapshot?.mqDigital, 1);
      expect(controller.snapshot?.pumpCommand, isFalse);
      expect(controller.snapshot?.lightingCandidate, 'unavailable');

      // The updated app keeps v12 compatibility while accepting v13 frames.
      peer.write('${sample(10000, version: 13)}\n');
      await waitFor(controller, () => controller.snapshot?.uptimeMs == 10000);
      expect(controller.snapshot?.soilRelativePercent, 44);

      peer.destroy();
      await waitFor(
        controller,
        () => controller.status == LocalWifiStatus.disconnected,
      );
      expect(controller.snapshot, isNull);
    },
  );

  test('duplicate sample cannot keep stale data live', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final incoming = server.first;
    final controller = LocalWifiController(
      address: '127.0.0.1',
      port: server.port,
      sampleTimeout: const Duration(milliseconds: 400),
    );
    final connecting = controller.connect();
    final peer = await incoming;
    addTearDown(() async {
      peer.destroy();
      controller.dispose();
      await server.close();
    });
    await connecting;
    peer.write('${sample(5000)}\n');
    await waitFor(controller, () => controller.status == LocalWifiStatus.live);
    peer.write('${sample(5000)}\n');
    await waitFor(
      controller,
      () => controller.status == LocalWifiStatus.disconnected,
    );
    expect(controller.snapshot, isNull);
    expect(controller.message, contains('terlambat'));
  });

  test('oversized frame is rejected without a live reading', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final incoming = server.first;
    final controller = LocalWifiController(
      address: '127.0.0.1',
      port: server.port,
    );
    final connecting = controller.connect();
    final peer = await incoming;
    addTearDown(() async {
      peer.destroy();
      controller.dispose();
      await server.close();
    });
    await connecting;
    peer.add(List<int>.filled(4097, 65));
    await waitFor(
      controller,
      () => controller.status == LocalWifiStatus.disconnected,
    );
    expect(controller.snapshot, isNull);
    expect(controller.message, contains('tidak valid'));
  });
}
