import 'package:flutter/material.dart';

import 'cloud_account_panel.dart';
import 'cloud_controller.dart';
import 'dashboard.dart';
import 'plant_telemetry.dart';

const ink = Color(0xFF213027);
const forest = Color(0xFF315E48);
const paper = Color(0xFFF7F5EF);
const muted = Color(0xFF6A756B);
const terracotta = Color(0xFFAE674F);

class MossApp extends StatelessWidget {
  const MossApp({
    super.key,
    this.render3d = true,
    this.telemetry,
    this.cloud,
    this.cloudSetupNotice,
  }) : assert(telemetry == null || cloud == null);

  /// Widget tests can exercise the interface without requiring a GPU renderer.
  final bool render3d;

  /// A real device source can be supplied when the cloud integration is ready.
  /// Null means no source is configured; no simulated values are substituted.
  final Stream<PlantTelemetry>? telemetry;
  final CloudController? cloud;
  final String? cloudSetupNotice;

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: forest,
      surface: paper,
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Moss · Smart Planter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: paper,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: paper,
          indicatorColor: const Color(0xFFDDE9DA),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: cloud == null
          ? Dashboard(
              render3d: render3d,
              telemetry: telemetry,
              cloudSetupNotice: cloudSetupNotice,
            )
          : ListenableBuilder(
              listenable: cloud!,
              builder: (context, _) => Dashboard(
                render3d: render3d,
                telemetry: cloud!.telemetry,
                cloudSettings: CloudAccountPanel(controller: cloud!),
              ),
            ),
    );
  }
}
