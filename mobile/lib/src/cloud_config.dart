/// Client configuration is public by design. A service-role key or user token
/// must never be embedded in an APK.
class CloudConfig {
  const CloudConfig({required this.url, required this.publishableKey});

  static const projectHost = 'sxrxhslnunlvjsiwfzjm.supabase.co';
  static const environment = CloudConfig(
    url: String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://$projectHost',
    ),
    publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  final String url;
  final String publishableKey;

  /// Do not send an account password to a different or unencrypted endpoint.
  bool get isConfigured {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == projectHost &&
        !uri.hasPort &&
        uri.userInfo.isEmpty &&
        (uri.path.isEmpty || uri.path == '/') &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(publishableKey);
  }
}
