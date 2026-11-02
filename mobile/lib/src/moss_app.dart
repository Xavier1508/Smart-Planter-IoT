import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_mode.dart';
import 'appearance.dart';
import 'cloud_account_panel.dart';
import 'cloud_controller.dart';
import 'dashboard.dart';
import 'local_wifi.dart';
import 'moss_gaze.dart';
import 'onboarding.dart';
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

class MossApp extends StatefulWidget {
  const MossApp({
    super.key,
    this.render3d = true,
    this.telemetry,
    this.cloud,
    this.cloudSetupNotice,
    this.localWifi,
    this.autoConnectLocal = true,
    this.initialMode,
    this.modeStore = const AppModeStore(),
    this.initialAppearance = const AppearanceSettings(),
    this.appearanceStore,
    this.clock,
    this.initialSerialJson = const String.fromEnvironment(
      'MOSS_SERIAL_SNAPSHOT',
    ),
  }) : assert(telemetry == null || cloud == null);

  /// Widget tests can exercise the interface without requiring a GPU renderer.
  final bool render3d;

  /// A real device source can be supplied when the cloud integration is ready.
  /// Null means no source is configured; no simulated values are substituted.
  final Stream<PlantTelemetry>? telemetry;
  final CloudController? cloud;
  final String? cloudSetupNotice;

  /// Optional injected local transport for tests; the default is the ESP32 AP.
  final LocalWifiController? localWifi;

  /// Tests may disable the initial connection and inject their own transport.
  final bool autoConnectLocal;

  /// Optional override for widget tests and deterministic starts.
  final AppMode? initialMode;
  final AppModeStore modeStore;
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
  AppMode? _mode;
  Timer? _clockTimer;
  bool _storageUnavailable = false;
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
    if (widget.cloud == null) {
      _mode = AppMode.offline;
    } else if (widget.initialMode != null) {
      _mode = widget.initialMode;
    } else {
      unawaited(_loadMode());
    }
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshClock(),
    );
  }

  Future<void> _loadMode() async {
    final stored = await widget.modeStore.read();
    if (!mounted) return;
    setState(() => _mode = stored ?? AppMode.online);
  }

  Future<void> _setMode(AppMode mode) async {
    if (!mounted) return;
    setState(() => _mode = mode);
    await widget.modeStore.write(mode);
  }

  Future<void> _goOnline() => _setMode(AppMode.online);

  Future<void> _goOffline() => _setMode(AppMode.offline);

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
    Widget dashboard({
      required CloudController? cloud,
      required Widget? settings,
      required bool autoConnectLocal,
    }) => Dashboard(
      render3d: widget.render3d,
      gaze: _gaze,
      atmosphere: _atmosphere,
      telemetry: cloud?.telemetry ?? widget.telemetry,
      initialSerialJson: widget.initialSerialJson,
      cloud: cloud,
      cloudSettings: settings,
      localWifi: widget.localWifi,
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
      final cloud = widget.cloud;
      if (cloud == null) {
        return dashboard(
          cloud: null,
          settings: null,
          autoConnectLocal: widget.autoConnectLocal,
        );
      }
      if (_mode == null) {
        return const MossLoadingPage(label: 'Menyiapkan Tunas...');
      }
      if (_mode == AppMode.offline) {
        return ListenableBuilder(
          listenable: cloud,
          builder: (context, _) => dashboard(
            cloud: null,
            settings: OfflineModePanel(
              onGoOnline: _goOnline,
              onSignOut: cloud.signOut,
              signedIn: cloud.signedIn,
            ),
            autoConnectLocal: widget.autoConnectLocal,
          ),
        );
      }
      return ListenableBuilder(
        listenable: cloud,
        builder: (context, _) {
          if (!cloud.authReady) {
            return const MossLoadingPage(label: 'Memeriksa sesi...');
          }
          if (!cloud.signedIn) {
            return AuthPage(controller: cloud, onOffline: _goOffline);
          }
          if (cloud.loadingDevice && !cloud.hasDevice) {
            return const MossLoadingPage(label: 'Mencari perangkat Anda...');
          }
          if (!cloud.hasDevice) {
            return PairingPage(
              controller: cloud,
              onOffline: _goOffline,
              onSignOut: cloud.signOut,
            );
          }
          return dashboard(
            cloud: cloud,
            settings: CloudAccountPanel(
              controller: cloud,
              onOffline: _goOffline,
            ),
            autoConnectLocal: false,
          );
        },
      );
    }

    return MaterialApp(
      title: 'Tunas · Smart Planter',
      debugShowCheckedModeBanner: false,
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
