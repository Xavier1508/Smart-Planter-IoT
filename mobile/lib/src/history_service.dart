import 'package:flutter/services.dart';

/// Native append-only CSV history. The phone stores one file per device per
/// day; the UI only reads the latest rows, and the export button copies the
/// full device history to Downloads/Tunas as a CSV.
class HistoryService {
  const HistoryService();

  static const _channel = MethodChannel('moss/history');

  Future<void> append({
    required String deviceId,
    required String header,
    required String line,
  }) async {
    try {
      await _channel.invokeMethod<void>('append', {
        'deviceId': deviceId,
        'header': header,
        'line': line,
      });
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  Future<List<String>> readTail({
    required String deviceId,
    int limit = 1000,
  }) async {
    try {
      final rows = await _channel.invokeMethod<List<Object?>>('readTail', {
        'deviceId': deviceId,
        'limit': limit,
      });
      if (rows == null) return const [];
      return rows.whereType<String>().toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Total number of appended samples for this device across all daily files.
  Future<int> count({required String deviceId}) async {
    try {
      final value = await _channel.invokeMethod<int>('count', {
        'deviceId': deviceId,
      });
      return value ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  Future<String?> export({required String deviceId}) async {
    try {
      return await _channel.invokeMethod<String>('export', {
        'deviceId': deviceId,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Saves one complete dataset atomically: an internal canonical copy for the
  /// app and a user-visible copy under Downloads/Tunas. `kind` is `full` for
  /// the assignment schema or `ml` for the canonical schema plus ML features.
  Future<String?> saveDataset({
    required String deviceId,
    required String csv,
    String kind = 'full',
  }) async {
    try {
      return await _channel.invokeMethod<String>('saveDataset', {
        'deviceId': deviceId,
        'csv': csv,
        'kind': kind,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> clear({required String deviceId}) async {
    try {
      await _channel.invokeMethod<void>('clear', {'deviceId': deviceId});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
