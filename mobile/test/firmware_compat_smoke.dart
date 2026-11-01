// Pipe the host firmware test's TEST_FIXTURE lines into this standalone test.
// The input consists of synthetic fixtures, not uploaded device data.
import 'dart:convert';
import 'dart:io';

// Standalone execution deliberately avoids needing a package configuration.
// ignore: avoid_relative_lib_imports
import '../lib/src/plant_state.dart';
// ignore: avoid_relative_lib_imports
import '../lib/src/plant_telemetry.dart';
// ignore: avoid_relative_lib_imports
import '../lib/src/local_wifi.dart';

Future<void> main() async {
  if (PlantState.adcDisplayPercent(null) != null ||
      PlantState.adcDisplayPercent(-1) != null ||
      PlantState.adcDisplayPercent(0) != 0 ||
      PlantState.adcDisplayPercent(2048) != 50 ||
      PlantState.adcDisplayPercent(4095) != 100 ||
      PlantState.adcDisplayPercent(4096) != null) {
    throw StateError(
      'ADC display scale must preserve missing/out-of-range input',
    );
  }
  var count = 0;
  var waterMidpoints = 0;
  var nearEmptySamples = 0;
  var mqReadFailures = 0;
  final ldrOnlyReasons = <String>{};
  var maxFrameBytes = 0;
  String? frameForTransport;
  String? framePumpOn;
  String? framePumpOff;
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (!line.startsWith('TEST_FIXTURE ')) continue;
    final jsonLine = line.substring('TEST_FIXTURE '.length);
    if (jsonLine.length > maxFrameBytes) maxFrameBytes = jsonLine.length;
    if (jsonLine.length + 1 >= 3072 || jsonLine.length > 4096) {
      throw StateError('Firmware frame too long');
    }
    final json = jsonDecode(jsonLine) as Map<String, dynamic>;
    if (json['schema'] != 'serial_observation_2' ||
        json['firmware_version'] != 31) {
      throw StateError('Unexpected firmware fixture');
    }
    final snapshot = SerialSensorSnapshot.parse(jsonLine);
    final preview = json['control_preview'];
    if (preview is Map<String, dynamic> && preview['pump_on'] is bool) {
      // The app does not guess a diagnostic threshold for v31; this
      // does not prevent it from accepting live values or firmware commands.
      if (snapshot.pumpRuleThreshold != null ||
          snapshot.pumpRulePreview != null) {
        throw StateError('Unknown-version preview must remain unavailable');
      }
    }
    final debug = json['pump_soil_debug'];
    final soil = snapshot.soilAdc;
    final zeroIsDry =
        json['adc'] is Map<String, dynamic> &&
        (json['adc'] as Map<String, dynamic>)['soil_zero_is_dry'] == true;
    final usableSoil =
        soil != null && ((soil > 0 && soil < 4095) || (zeroIsDry && soil == 0));
    final expectedBand = !usableSoil
        ? 'unavailable'
        : soil < 1000
        ? 'dry'
        : soil < 1200
        ? 'hold'
        : 'wet';
    if (debug is! Map<String, dynamic> ||
        debug['band'] != expectedBand ||
        debug['dry_below_on'] != (usableSoil ? soil < 1000 : null) ||
        debug['wet_at_or_above_off'] != (usableSoil ? soil >= 1200 : null) ||
        debug['on_below_adc'] != 1000 ||
        debug['off_at_or_above_adc'] != 1200 ||
        debug['basis'] != 'averaged_adc_unverified') {
      throw StateError('Pump soil diagnostic mismatch');
    }
    final sampling = json['adc_sampling'];
    if (sampling is! Map<String, dynamic> ||
        sampling['method'] != 'median_5' ||
        sampling['samples_per_cycle'] != 5 ||
        sampling['mixed_rail'] != 'unavailable' ||
        sampling['failed_read'] != 'unavailable') {
      throw StateError('ADC sampling metadata mismatch');
    }
    if (snapshot.pumpCommand != json['pump_cmd']) {
      throw StateError('Pump command mismatch');
    }
    if (snapshot.pumpCommand != null &&
        snapshot.pumpReason != json['pump_reason']) {
      throw StateError('Pump command reason mismatch');
    }
    if (soil == 999 && snapshot.pumpCommand == true) {
      framePumpOn = jsonLine;
    }
    if (soil == 1200 && snapshot.pumpCommand == false) {
      framePumpOff = jsonLine;
    }
    if (snapshot.lightCommand != json['growlight_cmd']) {
      throw StateError('Light command mismatch');
    }
    if (const {
      'ldr_low',
      'ldr_sufficient',
      'ldr_input_unavailable',
    }.contains(json['growlight_reason'])) {
      ldrOnlyReasons.add(json['growlight_reason'] as String);
      if (snapshot.lightReason != json['growlight_reason']) {
        throw StateError('App must expose the real LDR-only reason');
      }
    }
    if (snapshot.uptimeMs != json['uptime_ms']) {
      throw StateError('Uptime mismatch');
    }
    final water = json['water_level'];
    if (water is Map<String, dynamic>) {
      final scale = water['observation_scale'];
      if (water['adc_raw'] == 550) {
        nearEmptySamples++;
        if (water['relative_percent'] != 11 ||
            water['low'] != true ||
            water['control_band'] != 'below_threshold' ||
            scale is! Map<String, dynamic> ||
            scale['relative_percent'] != 11 ||
            snapshot.waterRelativePercent != 11 ||
            snapshot.waterObservationPercent != 11 ||
            snapshot.pumpReason != 'water_low') {
          throw StateError('Low-water reference must stay LOW, not empty');
        }
        if (snapshot.pumpCommand != null &&
            snapshot.soilRelativePercent != null) {
          frameForTransport = jsonLine;
        }
      }
      if (scale is Map<String, dynamic> && scale['relative_percent'] == 50) {
        waterMidpoints++;
        if (snapshot.waterRelativePercent != 50 ||
            snapshot.waterObservationPercent != 50) {
          throw StateError('Provisional water scales do not match the fixture');
        }
      }
    }
    final lighting = json['lighting_rule'];
    if (lighting is! Map<String, dynamic> ||
        lighting['uv_index'] != null ||
        lighting['uv_role'] != 'monitoring_only' ||
        lighting['use_for_control'] != false) {
      throw StateError('UV index or diagnostic candidate was misrepresented');
    }
    if (snapshot.lightingCandidate != lighting['candidate']) {
      throw StateError('Lighting diagnostic mismatch');
    }
    final mq = json['mq135'];
    if (mq is Map<String, dynamic>) {
      if (mq['adc_unit'] != 'ADC1' ||
          mq['co2_ppm'] != null ||
          mq['air_quality'] != null) {
        throw StateError('MQ reading was misrepresented');
      }
      if (mq['adc_raw'] is int) {
        final expectedPercent = ((mq['adc_raw'] as int) * 100 + 2047) ~/ 4095;
        if (mq['adc_percent'] != expectedPercent) {
          throw StateError('MQ ADC percentage mismatch');
        }
      } else if (mq['adc_percent'] != null) {
        throw StateError('Missing MQ ADC must not have a percentage');
      }
      if (mq['signal_quality'] == 'adc_read_failed') {
        mqReadFailures++;
        if (mq['adc_status'] != 'unavailable' ||
            snapshot.mqAdc != null ||
            snapshot.mqAdcStatus != 'adc_read_failed' ||
            snapshot.mqAdcUnit != 'ADC1') {
          throw StateError(
            'ADC1 failure must not be described as ADC2 conflict',
          );
        }
      }
    }
    count++;
  }
  if (count != 16 ||
      waterMidpoints < 1 ||
      nearEmptySamples != 1 ||
      mqReadFailures < 1 ||
      ldrOnlyReasons.length != 3 ||
      framePumpOn == null ||
      framePumpOff == null ||
      frameForTransport == null) {
    throw StateError(
      'Fixture coverage incomplete: count=$count waterMid=$waterMidpoints '
      'nearEmpty=$nearEmptySamples mqFail=$mqReadFailures '
      'ldr=${ldrOnlyReasons.toList()} on=${framePumpOn != null} '
      'off=${framePumpOff != null} transport=${frameForTransport != null}',
    );
  }

  // Exercise the local client with generated v31 frames and a real loopback
  // socket. Never connects to an ESP32.
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final incoming = server.first;
  final wifi = LocalWifiController(address: '127.0.0.1', port: server.port);
  Socket? peer;
  try {
    final connecting = wifi.connect();
    peer = await incoming.timeout(const Duration(seconds: 3));
    await connecting;
    Future<void> sendAndWait(String frame) async {
      final expectedUptime =
          (jsonDecode(frame) as Map<String, dynamic>)['uptime_ms'] as int;
      final live = wifi.changes
          .firstWhere(
            (_) =>
                wifi.status == LocalWifiStatus.live &&
                wifi.snapshot?.uptimeMs == expectedUptime,
          )
          .timeout(const Duration(seconds: 3));
      peer!.write('$frame\n');
      await peer.flush();
      await live;
    }

    await sendAndWait(framePumpOn);
    if (wifi.snapshot?.soilAdc != 999 || wifi.snapshot?.pumpCommand != true) {
      throw StateError('Local client did not receive pump ON');
    }
    await sendAndWait(framePumpOff);
    if (wifi.snapshot?.soilAdc != 1200 || wifi.snapshot?.pumpCommand != false) {
      throw StateError('Local client did not receive pump OFF');
    }
    // Give the final transport fixture a later uptime so it is not treated as a
    // duplicate of the 1200-ADC boundary frame.
    final transport = jsonDecode(frameForTransport) as Map<String, dynamic>;
    transport['uptime_ms'] = 60000;
    await sendAndWait(jsonEncode(transport));
    if (wifi.snapshot?.soilRelativePercent == null ||
        wifi.snapshot?.pumpCommand == null ||
        wifi.snapshot?.pumpReason != 'water_low' ||
        wifi.snapshot?.waterAdc != 550 ||
        wifi.snapshot?.waterRelativePercent != 11 ||
        wifi.snapshot?.waterObservationPercent != 11) {
      throw StateError('Local client did not receive v31 data');
    }
  } finally {
    // The controller broadcasts synchronously. Let the current notification
    // finish before closing its stream during teardown.
    await Future<void>.delayed(Duration.zero);
    peer?.destroy();
    wifi.dispose();
    await server.close();
  }
  stdout.writeln(
    'Firmware-to-mobile compatibility: $count synthetic v31 fixtures, '
    'max frame $maxFrameBytes bytes, and three-frame loopback passed; '
    'no ESP32 contacted.',
  );
}
