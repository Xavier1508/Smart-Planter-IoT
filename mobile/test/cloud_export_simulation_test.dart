import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/cloud_telemetry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Explicit opt-in: these tests only connect to a Postman fixture on loopback.
// They exercise real HTTP client code, not real authentication or RLS.
void main() {
  const deviceId = '00000000-0000-4000-8000-000000000001';
  final base = Platform.environment['MOSS_READINGS_FIXTURE'];
  final failureBase = Platform.environment['MOSS_READINGS_ERROR_FIXTURE'];

  SupabaseClient clientFor(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        !uri.hasPort ||
        uri.path != '/supabase' ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError('Fixture must be the loopback simulation URL');
    }
    return SupabaseClient(
      value,
      'sb_publishable_fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }

  test(
    'exports ordered cloud rows and missing sensor fields over HTTP',
    () async {
      final client = clientFor(base!);
      addTearDown(client.dispose);
      final result = await CloudTelemetry(client).exportTrainingCsv(deviceId);
      expect(result.count, 3);
      expect(result.summary.manuallyLabeled, 0);
      final lines = result.csv.trimRight().split('\n');
      final headers = lines.first.split(',');
      Map<String, String> row(int index) =>
          Map.fromIterables(headers, lines[index].split(','));
      expect(row(1)['reading_id'], '1');
      expect(row(2)['reading_id'], '2');
      expect(row(3)['reading_id'], '3');
      expect(row(2)['light_mean_1h'], '15.0');
      expect(row(3)['light_mean_1h'], '90.0');
      expect(row(1)['soil_missing'], '1');
      expect(row(1)['water_missing'], '1');
      expect(row(1)['mq135_missing'], '1');
      expect(row(1)['label'], '');
    },
    skip: base == null ? 'No loopback simulation configured' : false,
  );

  test('a 503 never exports fabricated data', () async {
    final client = clientFor(failureBase!);
    addTearDown(client.dispose);
    await expectLater(
      CloudTelemetry(client).exportTrainingCsv(deviceId),
      throwsA(isA<PostgrestException>()),
    );
  }, skip: failureBase == null ? 'No error simulation configured' : false);
}
