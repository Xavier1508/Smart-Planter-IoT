import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance.dart';
import 'dashboard.dart';
import 'local_moss_gate.dart';
import 'local_wifi.dart';
import 'moss_gaze.dart';
import 'plant_telemetry.dart';
import 'update_progress.dart';

const ink = Color(0xFF213027);
const forest = Color(0xFF315E48);
const paper = Color(0xFFF7F5EF);
const muted = Color(0xFF6A756B);
const terracotta = Color(0xFFAE674F);

extension MossThemeColors on BuildContext {
  ColorScheme get mossColors => Theme.of(this).colorScheme;
}

/// Local-only root. The phone talks directly to the ESP32 access point; there
/// is no account, Supabase client, pairing, or cloud mode.
class MossApp extends StatefulWidget {
  const MossApp({
    super.key,
    this.render3d = true,
    this.telemetry,
    this.localWifi,
    this.localOnly = false,
    this.autoConnectLocal = true,
    this.initialAppearance = const AppearanceSettings(),
    this.appearanceStore,
    this.clock,
    this.initialSerialJson = const String.fromEnvironment(
      'MOSS_SERIAL_SNAPSHOT',
    ),
  });

  /// Widget tests can exercise the interface without requiring a GPU renderer.
  final bool render3d;

  /// Optional injected telemetry stream for tests; the app itself uses the
  /// local Wi-Fi controller.
  final Stream<PlantTelemetry>? telemetry;

  /// Optional injected local transport for tests; the default is the ESP32 AP.
  final LocalWifiController? localWifi;

  /// Full local-only mode: the mandatory Moss gate is shown and the settings
  /// page uses the compact local layout.
  final bool localOnly;

  /// Tests may disable the initial connection and inject their own transport.
  final bool autoConnectLocal;

  final AppearanceSettings initialAppearance;
  final AppearanceStore? appearanceStore;

  /// Allows time-dependent appearance to be tested without changing the clock.
  final DateTime Function()? clock;

  /// Optional explicitly supplied snapshot, never a live connection.
  final String initialSerialJson;

  @override
  State<MossApp> createState() => _MossAppState();
}

class _MossAppState extends State<MossApp> with WidgetsBindingObserver {
  late AppearanceSettings _appearance;
  late DateTime _now;
  Timer? _clockTimer;
  bool _storageUnavailable = false;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _gaze = MossGaze();
  final _atmosphere = MossAtmosphere(SkyAppearance.atHour(12));
  final Stream<Object?> _updateEvents = const EventChannel(
    'moss/update_progress',
  ).receiveBroadcastStream();

  DateTime _readClock() => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _appearance = widget.initialAppearance;
    _now = _readClock();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshClock(),
    );
  }

  void _refreshClock() {
    if (mounted) setState(() => _now = _readClock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshClock();
  }

  void _updateAppearance(AppearanceSettings next) {
    setState(() => _appearance = next);
    final store = widget.appearanceStore;
    if (store != null) unawaited(_saveAppearance(store, next));
  }

  Future<void> _saveAppearance(
    AppearanceStore store,
    AppearanceSettings next,
  ) async {
    final saved = await store.write(next);
    if (mounted && _storageUnavailable == saved) {
      setState(() => _storageUnavailable = !saved);
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _gaze.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors =
        ColorScheme.fromSeed(
          seedColor: forest,
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xFFA8D7B2) : forest,
          surface: dark ? const Color(0xFF111A16) : paper,
          onSurface: dark ? const Color(0xFFE5EFE6) : ink,
          onSurfaceVariant: dark
              ? const Color(0xFFB4C5B7)
              : const Color(0xFF59675E),
          surfaceContainerLowest: dark ? const Color(0xFF1B2A21) : Colors.white,
          outlineVariant: dark
              ? const Color(0xFF3A5041)
              : const Color(0xFFE3E9DF),
          primaryContainer: dark
              ? const Color(0xFF2B4938)
              : const Color(0xFFDDE9DA),
          onPrimaryContainer: dark ? const Color(0xFFDAF2DD) : ink,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      textTheme: (dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
        bodyColor: colors.onSurface,
        displayColor: colors.onSurface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sky = SkyAppearance.resolve(
      _appearance.sky,
      _now,
      manualMinute: _appearance.manualMinute,
    );
    Widget dashboard({required bool autoConnectLocal}) => Dashboard(
      render3d: widget.render3d,
      gaze: _gaze,
      atmosphere: _atmosphere,
      telemetry: widget.telemetry,
      initialSerialJson: widget.initialSerialJson,
      localWifi: widget.localWifi,
      localOnly: widget.localOnly,
      autoConnectLocal: autoConnectLocal,
      appearance: _appearance,
      sky: sky,
      storageUnavailable: _storageUnavailable,
      onThemeChanged: (value) =>
          _updateAppearance(_appearance.copyWith(themeMode: value)),
      onSkyChanged: (value) =>
          _updateAppearance(_appearance.copyWith(sky: value)),
      onManualTimeChanged: (value) => _updateAppearance(
        _appearance.copyWith(sky: SkyChoice.custom, manualMinute: value),
      ),
    );

    Widget home() {
      if (widget.localOnly) {
        return LocalMossGate(child: dashboard(autoConnectLocal: true));
      }
      return dashboard(autoConnectLocal: widget.autoConnectLocal);
    }

    return MaterialApp(
      title: 'Tunas · Smart Planter',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _appearance.themeMode,
      builder: (context, child) => MossScreenTracker(
        gaze: _gaze,
        child: UpdateProgressHost(
          events: _updateEvents,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: home(),
    );
  }
}
