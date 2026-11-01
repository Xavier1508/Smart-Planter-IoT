import 'package:flutter/services.dart';

/// Native Android notifications. The platform side owns the channels, the
/// POST_NOTIFICATIONS permission, and the repeating alarm. When the channel is
/// unavailable (widget tests or a non-Android build), every method is a no-op.
class NotificationService {
  const NotificationService();

  static const _channel = MethodChannel('moss/notifications');
  static const waterAlertId = 4101;
  static const predictionId = 4102;

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
  }) async {
    try {
      await _channel.invokeMethod<void>('show', {
        'id': id,
        'title': title,
        'body': body,
        'channel': channel,
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
  }) async {
    try {
      await _channel.invokeMethod<void>('schedule', {
        'id': id,
        'title': title,
        'body': body,
        'intervalMinutes': intervalMinutes,
        'channel': channel,
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
  }) async {
    try {
      await _channel.invokeMethod<void>('update', {
        'id': id,
        'title': title,
        'body': body,
        'channel': channel,
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
