import 'package:flutter/services.dart';

/// Android Wi-Fi provisioning for the local `Moss` AP; Android shows a consent
/// dialog and the app cannot force a connection.
class WifiProvisioning {
  const WifiProvisioning();

  static const _channel = MethodChannel('moss/wifi_provisioning');
  static const mossSsid = 'Moss';
  static const apPassword = '15082005';

  Future<bool> connect({
    String ssid = mossSsid,
    String password = apPassword,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('connect', {
        'ssid': ssid,
        'password': password,
        'timeoutMs': timeout.inMilliseconds,
      });
      return result ?? false;
    } on PlatformException catch (error) {
      throw WifiProvisioningException(error.code, error.message);
    } on MissingPluginException {
      throw const WifiProvisioningException(
        'unsupported',
        'Fitur Wi-Fi hanya tersedia di aplikasi Android.',
      );
    }
  }

  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } on PlatformException {
      // The system may already have released the request.
    } on MissingPluginException {
      // Desktop/test target.
    }
  }

  Future<String?> currentSsid() async {
    try {
      return await _channel.invokeMethod<String>('currentSsid');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

class WifiProvisioningException implements Exception {
  const WifiProvisioningException(this.code, this.message);
  final String code;
  final String? message;

  bool get permissionDenied => code == 'permission_denied';
  bool get unavailable => code == 'ap_unavailable' || code == 'not_connected';
  bool get unsupported =>
      code == 'unsupported' || code == 'unsupported_android';

  @override
  String toString() => 'WifiProvisioningException($code, $message)';
}
