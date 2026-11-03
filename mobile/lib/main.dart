import 'package:flutter/material.dart';

import 'src/appearance.dart';
import 'src/moss_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const appearanceStore = AppearanceStore();
  final appearance = await appearanceStore.read();
  runApp(
    MossApp(
      localOnly: true,
      initialAppearance: appearance,
      appearanceStore: appearanceStore,
    ),
  );
}
