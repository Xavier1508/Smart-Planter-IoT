import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/local_wifi.dart';

String sample(
  int uptime, {
  int version = 12,
  int soil = 44,
  int? mqAdc,
  bool adc1Failure = false,
  int? mqMv = 550,
}) => jsonEncode({
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
    'soil_relative_percent': soil,
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
    'adc_raw': mqAdc,
    'digital_raw': 1,
    'adc_status': mqAdc == null
        ? (adc1Failure ? 'unavailable' : 'adc_read_failed')
        : 'unverified',
    'status': 'unverified',
    if (mqAdc != null || adc1Failure) 'adc_unit': 'ADC1',
    if (adc1Failure) 'signal_quality': 'adc_read_failed',
    if (mqAdc != null && mqMv != null) 'adc_pin_mv_estimate': mqMv,
    if (mqAdc != null) 'adc_calibration_source': 'efuse_vref',
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

      // Old and new frames both update the actual displayed measurement.
      peer.write('${sample(10000, version: 13, soil: 25)}\n');
      await waitFor(controller, () => controller.snapshot?.uptimeMs == 10000);
      expect(controller.snapshot?.soilRelativePercent, 25);
      peer.write('${sample(15000, version: 16, soil: 80)}\n');
      await waitFor(controller, () => controller.snapshot?.uptimeMs == 15000);
      expect(controller.snapshot?.soilRelativePercent, 80);

      peer.destroy();
      await waitFor(
        controller,
        () => controller.status == LocalWifiStatus.disconnected,
      );
      expect(controller.snapshot, isNull);
    },
  );

  test(
    'MQ average follows live frames and clears on rail, failure and disconnect',
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
      Future<void> send(int uptime, {int? raw, bool failure = false}) async {
        peer.write(
          '${sample(uptime, version: 19, mqAdc: raw, adc1Failure: failure)}\n',
        );
        await waitFor(
          controller,
          () => controller.snapshot?.uptimeMs == uptime,
        );
      }

      await send(5000, raw: 500);
      await send(10000, raw: 510);
      await send(15000, raw: 520);
      expect(controller.mqAverageSamples, 3);
      expect(controller.mqAverageAdc, 510);
      expect(controller.mqTrend, isNull);
      expect(controller.snapshot?.mqPinMillivolts, 550);
      expect(controller.mqGasIndex, 0);
      expect(controller.mqGasStatus, 'baseline');
      expect(controller.mqGasBaselineMv, 550);
      await send(20000, raw: 4095);
      expect(controller.snapshot?.mqAdc, 4095);
      expect(controller.snapshot?.mqPinMillivolts, isNull);
      expect(controller.mqAverageSamples, 0);
      expect(controller.mqAverageAdc, isNull);
      expect(controller.mqGasIndex, isNull);
      expect(controller.mqGasStatus, 'unavailable');
      expect(controller.mqGasBaselineMv, 550);
      await send(25000, raw: 530);
      expect(controller.mqAverageAdc, 530);
      expect(controller.mqAverageSamples, 1);
      expect(controller.mqTrend, isNull);
      await send(30000, failure: true);
      expect(controller.snapshot?.mqAdcStatus, 'adc_read_failed');
      expect(controller.snapshot?.mqAdcUnit, 'ADC1');
      expect(controller.mqAverageAdc, isNull);
      await send(35000, raw: 540);
      expect(controller.mqAverageAdc, 540);
      controller.disconnect();
      expect(controller.snapshot, isNull);
      expect(controller.mqAverageAdc, isNull);
      expect(controller.mqAverageSamples, 0);
      expect(controller.mqGasIndex, isNull);
    },
  );

  test('gas index is relative to the session baseline', () async {
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
    Future<void> send(int uptime, {required int raw, required int mv}) async {
      peer.write('${sample(uptime, version: 20, mqAdc: raw, mqMv: mv)}\n');
      await waitFor(controller, () => controller.snapshot?.uptimeMs == uptime);
    }

    await send(5000, raw: 500, mv: 550);
    expect(controller.mqGasIndex, 0);
    expect(controller.mqGasStatus, 'baseline');
    await send(10000, raw: 760, mv: 800);
    expect(controller.mqGasIndex, 35);
    expect(controller.mqGasStatus, 'elevated');
    expect(controller.mqGasBaselineMv, greaterThan(550));
    await send(15000, raw: 500, mv: 500);
    expect(controller.mqGasIndex, 0);
    expect(controller.mqGasStatus, 'baseline');
    expect(controller.mqGasBaselineMv, 500);
    controller.disconnect();
    expect(controller.mqGasIndex, isNull);
    expect(controller.mqGasStatus, 'unavailable');
  });

  test('control commands are sent and acknowledgements are parsed', () async {
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
    peer.write(
      '{"type":"ack","id":7,"ok":true,"pump_manual":true,'
      '"pump_remaining_s":5,"light_manual":false}\n',
    );
    await waitFor(controller, () => controller.lastCommandOk == true);
    expect(controller.lastCommandId, 7);
    expect(controller.lastPumpRemainingSeconds, 5);
    expect(await controller.sendControlCommand('CTRL pump=auto id=8'), isTrue);
  });

  test('a couple of malformed frames do not drop the live stream', () async {
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
    peer.write('not json\n');
    peer.write('{"type":"sample"}\n');
    peer.write('${sample(5000, version: 21, mqAdc: 500)}\n');
    await waitFor(controller, () => controller.status == LocalWifiStatus.live);
    expect(controller.snapshot?.uptimeMs, 5000);

    peer.write('broken 1\nbroken 2\nbroken 3\n');
    await waitFor(
      controller,
      () => controller.status == LocalWifiStatus.disconnected,
    );
    expect(controller.snapshot, isNull);
  });

  test(
    'reconnect clears stale data and manual disconnect stops retries',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = StreamController<Socket>();
      var accepted = 0;
      final serverSubscription = server.listen((peer) {
        accepted++;
        peers.add(peer);
      });
      final incoming = StreamIterator(peers.stream);
      final controller = LocalWifiController(
        address: '127.0.0.1',
        port: server.port,
        reconnectDelay: const Duration(milliseconds: 100),
      );
      Socket? first;
      Socket? second;
      addTearDown(() async {
        first?.destroy();
        second?.destroy();
        controller.dispose();
        await incoming.cancel();
        await serverSubscription.cancel();
        await peers.close();
        await server.close();
      });

      final connecting = controller.connect();
      expect(await incoming.moveNext(), isTrue);
      first = incoming.current;
      await connecting;
      first.write('${sample(5000, version: 16, soil: 25)}\n');
      await waitFor(
        controller,
        () => controller.snapshot?.soilRelativePercent == 25,
      );
      first.destroy();
      await waitFor(
        controller,
        () => controller.status == LocalWifiStatus.disconnected,
      );
      expect(controller.snapshot, isNull);

      expect(
        await incoming.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      second = incoming.current;
      second.write('${sample(5000, version: 16, soil: 80)}\n');
      await waitFor(
        controller,
        () => controller.snapshot?.soilRelativePercent == 80,
      );
      controller.disconnect();
      expect(controller.snapshot, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(accepted, 2);
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
