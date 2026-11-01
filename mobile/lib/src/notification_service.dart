import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class NotificationPayload {
  const NotificationPayload({
    required this.route,
    required this.title,
    required this.body,
  });

  final String route;
  final String title;
  final String body;

  static NotificationPayload? fromMap(Object? value) {
    if (value is! Map) return null;
    final route = value['route'];
    final title = value['title'];
    final body = value['body'];
    if (route is! String || title is! String || body is! String) return null;
    return NotificationPayload(route: route, title: title, body: body);
  }
}

/// Native Android notifications. The platform side owns the channels, the
/// POST_NOTIFICATIONS permission, and the repeating alarm. When the channel is
/// unavailable (widget tests or a non-Android build), every method is a no-op.
class NotificationService {
  const NotificationService();

  static const _channel = MethodChannel('moss/notifications');
  static const _tapChannel = EventChannel('moss/notification_taps');
  static const waterAlertId = 4101;
  static const predictionId = 4102;
  static const insightId = 4103;

  Stream<NotificationPayload> get taps => Platform.isAndroid
      ? _tapChannel
            .receiveBroadcastStream()
            .handleError((Object _) {})
            .map(NotificationPayload.fromMap)
            .where((payload) => payload != null)
            .cast<NotificationPayload>()
      : const Stream.empty();

  Future<NotificationPayload?> takeLaunch() async {
    try {
      final raw = await _channel.invokeMethod<String>('takeLaunch');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return NotificationPayload.fromMap(decoded);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String channel = 'tunas_alerts',
    String? route,
    String? payload,
  }) async {
    try {
      await _channel.invokeMethod<void>('show', {
        'id': id,
        'title': title,
        'body': body,
        'channel': channel,
        'route': ?route,
        'payload': ?payload,
      });
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required int intervalMinutes,
    String channel = 'tunas_predictions',
    String? route,
    String? payload,
  }) async {
    try {
      await _channel.invokeMethod<void>('schedule', {
        'id': id,
        'title': title,
        'body': body,
        'intervalMinutes': intervalMinutes,
        'channel': channel,
        'route': ?route,
        'payload': ?payload,
      });
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  Future<void> update({
    required int id,
    required String title,
    required String body,
    String channel = 'tunas_predictions',
    String? route,
    String? payload,
  }) async {
    try {
      await _channel.invokeMethod<void>('update', {
        'id': id,
        'title': title,
        'body': body,
        'channel': channel,
        'route': ?route,
        'payload': ?payload,
      });
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  Future<void> cancel(int id) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}
