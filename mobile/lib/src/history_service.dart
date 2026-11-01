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
    int limit = 240,
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
