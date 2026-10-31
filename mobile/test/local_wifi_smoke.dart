// Standalone socket smoke test: no Flutter packages, device or real sensor data.
// Run with: dart mobile/test/local_wifi_smoke.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Standalone execution deliberately avoids needing a package configuration.
// ignore: avoid_relative_lib_imports
import '../lib/src/local_wifi.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

String fixture(int uptime) => jsonEncode({
  'type': 'sample',
  'schema': 'serial_observation_2',
  'firmware_version': 12,
  'uptime_ms': uptime,
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

Future<void> waitFor(LocalWifiController client, bool Function() ready) async {
  if (ready()) return;
  final done = Completer<void>();
  final subscription = client.changes.listen((_) {
    if (ready() && !done.isCompleted) done.complete();
  });
  try {
    if (ready() && !done.isCompleted) done.complete();
    await done.future.timeout(const Duration(seconds: 4));
  } finally {
    await subscription.cancel();
  }
}

Future<void> smoke({required bool oversized}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final incoming = server.first;
  final client = LocalWifiController(
    address: '127.0.0.1',
    port: server.port,
    sampleTimeout: const Duration(milliseconds: 600),
  );
  final connecting = client.connect();
  final peer = await incoming;
  try {
    await connecting;
    check(client.status == LocalWifiStatus.waiting, 'Expected waiting');
    if (oversized) {
      peer.add(List<int>.filled(4097, 65));
      await waitFor(
        client,
        () => client.status == LocalWifiStatus.disconnected,
      );
      check(client.snapshot == null, 'Oversized sample must be discarded');
      check(
        client.message.contains('tidak valid'),
        'Expected invalid-frame notice',
      );
    } else {
      final data = fixture(5000);
      peer.add(utf8.encode(data.substring(0, 15)));
      peer.add(utf8.encode('${data.substring(15)}\n'));
      await waitFor(client, () => client.status == LocalWifiStatus.live);
      check(client.snapshot?.soilRelativePercent == 44, 'Soil mismatch');
      check(client.snapshot?.uvAdc == 0, 'Raw UV zero must be preserved');
      check(
        client.snapshot?.waterRelativePercent == null,
        'Control water must stay null',
      );
      check(
        client.snapshot?.waterObservationPercent == 50,
        'Water scale mismatch',
      );
      check(
        client.snapshot?.mqAdc == null,
        'Failed MQ read must stay unavailable',
      );
      check(
        client.snapshot?.mqAdcStatus == 'adc_read_failed',
        'MQ failure status missing',
      );
      check(
        client.snapshot?.mqDigital == 1,
        'MQ digital should remain visible',
      );
      check(client.snapshot?.pumpCommand == false, 'Command mismatch');
      check(
        client.snapshot?.lightingCandidate == 'unavailable',
        'Rule mismatch',
      );
      peer.write('${fixture(5000)}\n');
      await waitFor(
        client,
        () => client.status == LocalWifiStatus.disconnected,
      );
      check(client.snapshot == null, 'Stale sample must be removed');
      check(client.message.contains('terlambat'), 'Expected stale-data notice');
    }
  } finally {
    peer.destroy();
    client.dispose();
    await server.close();
  }
}

Future<void> main() async {
  await smoke(oversized: false);
  await smoke(oversized: true);
  stdout.writeln(
    'Local Wi-Fi client: loopback stream, stale and invalid-frame checks passed; no ESP32 contacted.',
  );
}
