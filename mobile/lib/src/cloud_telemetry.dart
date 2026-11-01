import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_reading_decoder.dart';
import 'ml_dataset.dart';
import 'plant_telemetry.dart';

class PlanterDevice {
  const PlanterDevice({
    required this.id,
    required this.name,
    required this.hardwareId,
  });
  final String id;
  final String name;
  final String hardwareId;
}

class MlCsvExport {
  const MlCsvExport({required this.csv, required this.summary});
  final String csv;
  final MlDatasetSummary summary;
  int get count => summary.rows;
}

class CloudDatasetExport {
  const CloudDatasetExport({
    required this.csv,
    required this.rows,
    required this.hardwareId,
  });
  final String csv;
  final int rows;
  final String hardwareId;
}

const _readingSelect =
    'id,device_id,recorded_at,captured_at,time_quality,boot_id,uptime_ms,'
    'firmware_version,soil_adc,soil_percent,water_adc,water_percent,'
    'water_observation_percent,water_empty,water_low,light_adc,light_percent,'
    'temperature_c,humidity_percent,uv_adc,uv_index,mq_adc,mq_pin_mv,'
    'pump_on,pump_reason,pump_cooldown_s,pump_runtime_lockout,growlight_on,'
    'light_reason,ingest_source';

/// Reads only rows permitted by the current user's database policy.
class CloudTelemetry {
  const CloudTelemetry(this.client);
  final SupabaseClient client;

  Future<PlanterDevice?> firstDevice() async {
    final rows = await client
        .from('planter_devices')
        .select('id, display_name, hardware_id')
        .order('created_at')
        .limit(1)
        .timeout(const Duration(seconds: 15));
    if (rows.isEmpty) return null;
    final row = rows.first;
    final id = row['id'];
    final name = row['display_name'];
    final hardware = row['hardware_id'];
    if (id is! String || name is! String) throw const FormatException();
    return PlanterDevice(
      id: id,
      name: name,
      hardwareId: hardware is String ? hardware : id,
    );
  }

  Future<PlanterDevice> claimDevice({
    required String hardwareId,
    required String claimCode,
  }) async {
    final data = await client
        .rpc(
          'claim_device',
          params: {
            'p_hardware_id': hardwareId.trim().toLowerCase(),
            'p_claim_code': claimCode.trim().toUpperCase(),
          },
        )
        .timeout(const Duration(seconds: 20));
    if (data is! Map) throw const FormatException();
    final id = data['device_id'];
    final name = data['display_name'];
    final hardware = data['hardware_id'];
    if (id is! String || name is! String) throw const FormatException();
    return PlanterDevice(
      id: id,
      name: name,
      hardwareId: hardware is String ? hardware : id,
    );
  }

  /// Recent rows for the chart. The full dataset is exported separately and is
  /// never truncated to this UI window.
  Future<List<PlantTelemetry>> readRecent(
    String deviceId, {
    int limit = 240,
  }) async {
    final rows = await client
        .from('planter_readings')
        .select(_readingSelect)
        .eq('device_id', deviceId)
        .order('recorded_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit.clamp(1, 1000))
        .timeout(const Duration(seconds: 15));
    final readings = <PlantTelemetry>[];
    for (final row in rows.reversed) {
      try {
        readings.add(decodeReading(row));
      } on FormatException {
        // A malformed row must not prevent the remaining history from loading.
      }
    }
    return readings;
  }

  /// An explicitly requested, bounded export for the ML helper. RLS still
  /// controls every row; unlabelled rows stay unlabelled.
  Future<MlCsvExport> exportTrainingCsv(String deviceId) async {
    final rows = await client
        .from('planter_readings')
        .select(
          'id, device_id, recorded_at, soil_percent, temperature_c, '
          'humidity_percent, light_percent, uv_index',
        )
        .eq('device_id', deviceId)
        .order('recorded_at', ascending: false)
        .order('id', ascending: false)
        .limit(1000)
        .timeout(const Duration(seconds: 15));
    final samples = <MlDatasetRow>[];
    for (final row in rows.reversed) {
      if (row['device_id'] != deviceId) throw const FormatException();
      samples.add(
        MlDatasetRow(reading: decodeReading(row), deviceRef: deviceId),
      );
    }
    return MlCsvExport(
      csv: MlDatasetCsv.encode(samples),
      summary: MlDatasetSummary.fromRows(samples),
    );
  }

  /// Fetches every readable row in stable order. Page size stays at the
  /// PostgREST default so the export also works on a free project.
  Future<CloudDatasetExport> exportDatasetCsv({
    required String deviceId,
    required String hardwareId,
  }) async {
    const pageSize = 1000;
    var from = 0;
    final rows = <Map<String, dynamic>>[];
    while (true) {
      final page = await client
          .from('planter_readings')
          .select(_readingSelect)
          .eq('device_id', deviceId)
          .order('recorded_at', ascending: true)
          .order('id', ascending: true)
          .range(from, from + pageSize - 1)
          .timeout(const Duration(seconds: 25));
      rows.addAll(page.map((row) => Map<String, dynamic>.from(row)));
      if (page.length < pageSize) break;
      from += pageSize;
      if (from > 500000) throw const CloudReadException();
    }
    return CloudDatasetExport(
      csv: CloudDatasetCsv.encode(rows, hardwareId: hardwareId),
      rows: rows.length,
      hardwareId: hardwareId,
    );
  }

  /// Subscribe before the first snapshot; reload it on every reconnect. The
  /// dashboard ignores older snapshots if an event arrives during the fetch.
  Stream<PlantTelemetry> watchDevice(String deviceId) {
    late final StreamController<PlantTelemetry> output;
    RealtimeChannel? channel;
    Timer? fallback;
    var cancelled = false;
    var connected = false;
    // A snapshot started before a disconnect must not restore stale live data.
    var generation = 0;

    void sendRow(Map<String, dynamic> row) {
      if (cancelled ||
          !connected ||
          output.isClosed ||
          row['device_id'] != deviceId) {
        return;
      }
      try {
        output.add(decodeReading(row));
      } on FormatException {
        output.addError(const CloudReadException());
      }
    }

    bool isCurrentConnection(int requestedGeneration) =>
        !cancelled &&
        connected &&
        !output.isClosed &&
        generation == requestedGeneration;

    Future<void> fetchLatest(
      int requestedGeneration, {
      bool silent = false,
    }) async {
      try {
        final rows = await client
            .from('planter_readings')
            .select(_readingSelect)
            .eq('device_id', deviceId)
            .order('recorded_at', ascending: false)
            .order('id', ascending: false)
            .limit(1)
            .timeout(const Duration(seconds: 15));
        if (isCurrentConnection(requestedGeneration) && rows.isNotEmpty) {
          sendRow(rows.first);
        }
      } catch (_) {
        if (!silent && isCurrentConnection(requestedGeneration)) {
          output.addError(const CloudReadException());
        }
      }
    }

    output = StreamController<PlantTelemetry>(
      onListen: () {
        channel = client
            .channel(
              'planter-readings:$deviceId',
              opts: const RealtimeChannelConfig(replicationReady: true),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'planter_readings',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'device_id',
                value: deviceId,
              ),
              callback: (payload) => sendRow(payload.newRecord),
            )
            .onSystemEvents((payload) {
              if (!cancelled &&
                  connected &&
                  payload is Map &&
                  payload['extension'] == 'system' &&
                  payload['status'] == 'ok') {
                // The channel join can precede actual replication readiness.
                unawaited(fetchLatest(generation));
              }
            })
            .subscribe((status, _) {
              if (cancelled || output.isClosed) return;
              if (status == RealtimeSubscribeStatus.subscribed) {
                connected = true;
                ++generation;
                unawaited(fetchLatest(generation));
              } else if (status == RealtimeSubscribeStatus.channelError ||
                  status == RealtimeSubscribeStatus.timedOut ||
                  status == RealtimeSubscribeStatus.closed) {
                connected = false;
                ++generation;
                output.addError(const CloudReadException());
              }
            });
        // Realtime should recover by itself, but a periodic REST reconciliation
        // also closes the gap if a socket stays half-open without an error.
        fallback = Timer.periodic(const Duration(seconds: 20), (_) {
          if (!cancelled && connected && !output.isClosed) {
            unawaited(fetchLatest(generation, silent: true));
          }
        });
      },
      onCancel: () async {
        cancelled = true;
        connected = false;
        ++generation;
        fallback?.cancel();
        final active = channel;
        if (active != null) await client.removeChannel(active);
      },
    );
    return output.stream;
  }

  /// Only server timestamps with an explicit timezone are accepted.
  static PlantTelemetry decodeReading(Map<String, dynamic> row) =>
      decodeCloudReading(row);
}

/// Canonical full-fidelity dataset. One header, UTC ISO timestamps, every raw
/// and derived sensor value, requested actuator state, reasons, and provenance.
class CloudDatasetCsv {
  const CloudDatasetCsv._();

  static const header =
      'recorded_at_utc,captured_at_utc,time_quality,row_id,device_id,'
      'hardware_id,boot_id,uptime_ms,firmware_version,soil_adc,soil_percent,'
      'water_adc,water_percent,water_observation_percent,water_empty,water_low,'
      'light_adc,light_percent,temperature_c,humidity_percent,uv_adc,uv_index,'
      'mq_adc,mq_pin_mv,pump_cmd,pump_reason,pump_cooldown_s,'
      'pump_runtime_lockout,light_cmd,light_reason,ingest_source';

  static String encode(
    List<Map<String, dynamic>> rows, {
    required String hardwareId,
  }) {
    final output = StringBuffer(header)..writeln();
    for (final row in rows) {
      output.writeln(
        [
          row['recorded_at'],
          row['captured_at'],
          row['time_quality'],
          row['id'],
          row['device_id'],
          hardwareId,
          row['boot_id'],
          row['uptime_ms'],
          row['firmware_version'],
          row['soil_adc'],
          row['soil_percent'],
          row['water_adc'],
          row['water_percent'],
          row['water_observation_percent'],
          _bool(row['water_empty']),
          _bool(row['water_low']),
          row['light_adc'],
          row['light_percent'],
          row['temperature_c'],
          row['humidity_percent'],
          row['uv_adc'],
          row['uv_index'],
          row['mq_adc'],
          row['mq_pin_mv'],
          _bool(row['pump_on']),
          row['pump_reason'],
          row['pump_cooldown_s'],
          _bool(row['pump_runtime_lockout']),
          _bool(row['growlight_on']),
          row['light_reason'],
          row['ingest_source'],
        ].map(_field).join(','),
      );
    }
    return output.toString();
  }

  static String _bool(Object? value) {
    if (value is! bool) return '';
    return value ? '1' : '0';
  }

  static String _field(Object? value) {
    if (value == null) return '';
    final text = value is bool ? (value ? '1' : '0') : value.toString();
    if (text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }
}

/// Never includes URLs, tokens, or response bodies in UI errors.
class CloudReadException implements Exception {
  const CloudReadException();
}
