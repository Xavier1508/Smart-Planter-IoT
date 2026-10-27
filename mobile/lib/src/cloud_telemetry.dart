import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'plant_telemetry.dart';

class PlanterDevice {
  const PlanterDevice({required this.id, required this.name});
  final String id;
  final String name;
}

/// Reads only rows permitted by the current user's database policy.
class CloudTelemetry {
  const CloudTelemetry(this.client);
  final SupabaseClient client;

  Future<PlanterDevice?> firstDevice() async {
    final rows = await client
        .from('planter_devices')
        .select('id, display_name')
        .order('created_at')
        .limit(1)
        .timeout(const Duration(seconds: 15));
    if (rows.isEmpty) return null;
    final row = rows.first;
    final id = row['id'];
    final name = row['display_name'];
    if (id is! String || name is! String) throw const FormatException();
    return PlanterDevice(id: id, name: name);
  }

  /// Subscribe before the first snapshot; reload it on every reconnect. The
  /// dashboard ignores older snapshots if an event arrives during the fetch.
  Stream<PlantTelemetry> watchDevice(String deviceId) {
    late final StreamController<PlantTelemetry> output;
    RealtimeChannel? channel;
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

    Future<void> fetchLatest(int requestedGeneration) async {
      try {
        final rows = await client
            .from('planter_readings')
            .select(
              'id, device_id, recorded_at, soil_percent, temperature_c, '
              'humidity_percent, light_percent',
            )
            .eq('device_id', deviceId)
            .order('recorded_at', ascending: false)
            .order('id', ascending: false)
            .limit(1)
            .timeout(const Duration(seconds: 15));
        if (isCurrentConnection(requestedGeneration) && rows.isNotEmpty) {
          sendRow(rows.first);
        }
      } catch (_) {
        if (isCurrentConnection(requestedGeneration)) {
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
      },
      onCancel: () async {
        cancelled = true;
        connected = false;
        ++generation;
        final active = channel;
        if (active != null) await client.removeChannel(active);
      },
    );
    return output.stream;
  }

  /// Only server timestamps with an explicit timezone are accepted.
  static PlantTelemetry decodeReading(Map<String, dynamic> row) {
    final rawTime = row['recorded_at'];
    if (rawTime is! String ||
        !RegExp(r'(?:[zZ]|[+-]\d\d(?::?\d\d)?)$').hasMatch(rawTime)) {
      throw const FormatException('Missing server timestamp');
    }
    final time = DateTime.tryParse(rawTime);
    if (time == null) throw const FormatException('Invalid server timestamp');

    int? integer(Object? value) =>
        value is num && value.isFinite && value == value.truncateToDouble()
        ? value.toInt()
        : null;
    double? decimal(Object? value) =>
        value is num && value.isFinite ? value.toDouble() : null;
    final sequence = integer(row['id']);
    if (sequence == null) throw const FormatException('Missing row ID');

    return PlantTelemetry(
      recordedAt: time,
      sequence: sequence,
      soilPercent: integer(row['soil_percent']),
      temperatureC: decimal(row['temperature_c']),
      humidityPercent: integer(row['humidity_percent']),
      lightPercent: integer(row['light_percent']),
    );
  }
}

/// Never includes URLs, tokens, or response bodies in UI errors.
class CloudReadException implements Exception {
  const CloudReadException();
}
