// Pipe the host firmware test's TEST_FIXTURE lines into this standalone test.
// The input consists of synthetic fixtures, not uploaded device data.
import 'dart:convert';
import 'dart:io';

// Standalone execution deliberately avoids needing a package configuration.
// ignore: avoid_relative_lib_imports
import '../lib/src/plant_state.dart';
// ignore: avoid_relative_lib_imports
import '../lib/src/plant_telemetry.dart';

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
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (!line.startsWith('TEST_FIXTURE ')) continue;
    final jsonLine = line.substring('TEST_FIXTURE '.length);
    if (jsonLine.length > 4096) throw StateError('Firmware frame too long');
    final json = jsonDecode(jsonLine) as Map<String, dynamic>;
    if (json['schema'] != 'serial_observation_2' ||
        json['firmware_version'] != 13) {
      throw StateError('Unexpected firmware fixture');
    }
    final snapshot = SerialSensorSnapshot.parse(jsonLine);
    if (snapshot.uptimeMs != json['uptime_ms']) {
      throw StateError('Uptime mismatch');
    }
    final water = json['water_level'];
    if (water is Map<String, dynamic>) {
      final scale = water['observation_scale'];
      if (scale is Map<String, dynamic> && scale['relative_percent'] == 50) {
        waterMidpoints++;
        if (snapshot.waterRelativePercent != null ||
            snapshot.waterObservationPercent != 50) {
          throw StateError('Water display and control scales mixed');
        }
      }
    }
    final lighting = json['lighting_rule'];
    if (lighting is! Map<String, dynamic> ||
        lighting['uv_index'] != null ||
        lighting['use_for_control'] != false) {
      throw StateError('Unverified UV must not authorize control');
    }
    if (snapshot.lightingCandidate != lighting['candidate']) {
      throw StateError('Lighting diagnostic mismatch');
    }
    count++;
  }
  if (count != 7 || waterMidpoints < 1) {
    throw StateError('Fixture coverage incomplete');
  }
  stdout.writeln(
    'Firmware-to-mobile compatibility: $count synthetic v13 fixtures passed; water scale remains display-only.',
  );
}
