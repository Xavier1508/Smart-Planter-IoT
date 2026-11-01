import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/appearance.dart';
import 'src/cloud_config.dart';
import 'src/cloud_controller.dart';
import 'src/moss_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const appearanceStore = AppearanceStore();
  final appearance = await appearanceStore.read();
  final config = CloudConfig.environment;
  CloudController? cloud;
  String? notice;
  if (config.isConfigured) {
    try {
      await Supabase.initialize(
        url: config.url.endsWith('/')
            ? config.url.substring(0, config.url.length - 1)
            : config.url,
        publishableKey: config.publishableKey,
        debug: false,
        authOptions: const FlutterAuthClientOptions(
          persistSession: true,
          detectSessionInUri: false,
        ),
      );
      cloud = CloudController(Supabase.instance.client);
    } catch (_) {
      // Keep the explicitly labelled offline/demo interface available.
      notice = 'Cloud sementara tidak tersedia.';
    }
  } else {
    notice = 'Aplikasi belum dikonfigurasi untuk cloud.';
  }
  runApp(
    MossApp(
      cloud: cloud,
      cloudSetupNotice: notice,
      initialAppearance: appearance,
      appearanceStore: appearanceStore,
    ),
  );
}
