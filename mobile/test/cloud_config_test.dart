import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/cloud_config.dart';

void main() {
  test(
    'only the intended HTTPS project and a publishable key are accepted',
    () {
      const url = 'https://sxrxhslnunlvjsiwfzjm.supabase.co';
      const key = 'sb_publishable_test_fixture';
      expect(
        const CloudConfig(url: url, publishableKey: key).isConfigured,
        isTrue,
      );
      expect(
        const CloudConfig(url: url, publishableKey: '').isConfigured,
        isFalse,
      );
      expect(
        const CloudConfig(
          url: url,
          publishableKey: 'sb_secret_fixture',
        ).isConfigured,
        isFalse,
      );
      expect(
        const CloudConfig(
          url: 'http://sxrxhslnunlvjsiwfzjm.supabase.co',
          publishableKey: key,
        ).isConfigured,
        isFalse,
      );
      expect(
        const CloudConfig(
          url: 'https://other.supabase.co',
          publishableKey: key,
        ).isConfigured,
        isFalse,
      );
      expect(
        const CloudConfig(url: '$url/other', publishableKey: key).isConfigured,
        isFalse,
      );
    },
  );
}
