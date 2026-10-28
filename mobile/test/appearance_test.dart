import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/appearance.dart';
import 'package:smart_planter/src/moss_app.dart';
import 'package:smart_planter/src/moss_sky.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local time chooses the expected part of the day', () {
    expect(SkyAppearance.atHour(3).label, 'Tengah malam');
    expect(SkyAppearance.atHour(5).label, 'Subuh');
    expect(SkyAppearance.atHour(8).label, 'Pagi');
    expect(SkyAppearance.atHour(12).label, 'Siang');
    expect(SkyAppearance.atHour(16).label, 'Sore');
    expect(SkyAppearance.atHour(20).label, 'Malam');
    expect(SkyAppearance.atHour(23).label, 'Tengah malam');
    expect(SkyAppearance.atHour(24).top, SkyAppearance.atHour(0).top);
    expect(SkyAppearance.atHour(12).sunOpacity, 1);
    expect(SkyAppearance.atHour(0).moonOpacity, 1);
    expect(SkyAppearance.atHour(0).starsOpacity, greaterThan(0));
  });

  test('automatic time changes continuously but manual time is fixed', () {
    final morning = DateTime(2026, 1, 1, 8, 0);
    final later = DateTime(2026, 1, 1, 8, 30);
    final automatic = SkyAppearance.resolve(SkyChoice.automatic, morning);
    final automaticLater = SkyAppearance.resolve(SkyChoice.automatic, later);
    expect(automatic.top, isNot(automaticLater.top));
    expect(automatic.hour, 8);
    expect(automaticLater.hour, 8.5);
    final chosen = SkyAppearance.resolve(SkyChoice.evening, morning);
    expect(chosen.hour, SkyAppearance.resolve(SkyChoice.evening, later).hour);
    expect(chosen.label, 'Sore');
    final custom = SkyAppearance.resolve(
      SkyChoice.custom,
      morning,
      manualMinute: 22 * 60 + 30,
    );
    expect(custom.hour, 22.5);
    expect(custom.label, 'Tengah malam');
  });

  test('sky text has readable contrast throughout the day', () {
    for (var minute = 0; minute < 24 * 60; minute += 15) {
      final sky = SkyAppearance.atHour(minute / 60);
      for (final background in [sky.top, sky.bottom]) {
        final foreground = MossSky.foregroundFor(background);
        final foregroundLight = foreground.computeLuminance();
        final backgroundLight = background.computeLuminance();
        final lighter = foregroundLight > backgroundLight
            ? foregroundLight
            : backgroundLight;
        final darker = foregroundLight < backgroundLight
            ? foregroundLight
            : backgroundLight;
        expect((lighter + .05) / (darker + .05), greaterThanOrEqualTo(4.5));
      }
    }
  });

  test('invalid stored settings fall back safely', () {
    final settings = AppearanceSettings.fromMap({
      'theme': 'invalid',
      'sky': 42,
    });
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.sky, SkyChoice.automatic);
  });

  test(
    'display preferences are saved and restored through the Android channel',
    () async {
      const channel = MethodChannel('moss/appearance');
      Map<Object?, Object?>? stored;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'write') {
          stored = Map<Object?, Object?>.from(call.arguments as Map);
        }
        if (call.method == 'read') return stored;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const store = AppearanceStore();
      const settings = AppearanceSettings(
        themeMode: ThemeMode.dark,
        sky: SkyChoice.custom,
        manualMinute: 1350,
      );
      expect(await store.write(settings), isTrue);
      final restored = await store.read();
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.sky, SkyChoice.custom);
      expect(restored.manualMinute, 1350);
    },
  );

  testWidgets('theme and sky can be selected independently', (tester) async {
    await tester.pumpWidget(const MossApp(render3d: false));
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gelap').last);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Tampilan & suasana'))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byType(DropdownButtonFormField<SkyChoice>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sore').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hari ini'));
    await tester.pumpAndSettle();
    final sky = tester.widget<MossSky>(find.byType(MossSky)).sky;
    expect(sky.label, 'Sore');
    expect(sky.hour, 16.5);
    expect(find.text('SORE · PILIHAN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic sky refreshes after the app resumes', (tester) async {
    var now = DateTime(2026, 1, 1, 5);
    await tester.pumpWidget(MossApp(render3d: false, clock: () => now));
    expect(tester.widget<MossSky>(find.byType(MossSky)).sky.label, 'Subuh');
    now = DateTime(2026, 1, 1, 20);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.widget<MossSky>(find.byType(MossSky)).sky.label, 'Malam');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a custom hour can be selected without changing the phone clock',
    (tester) async {
      tester.platformDispatcher.alwaysUse24HourFormatTestValue = false;
      addTearDown(tester.platformDispatcher.clearAlwaysUse24HourTestValue);
      await tester.pumpWidget(
        const MossApp(
          render3d: false,
          initialAppearance: AppearanceSettings(sky: SkyChoice.custom),
        ),
      );
      await tester.tap(find.text('Pengaturan'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pick-moss-time')));
      await tester.tap(find.byKey(const ValueKey('pick-moss-time')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '10');
      await tester.enterText(find.byType(TextField).at(1), '30');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hari ini'));
      await tester.pumpAndSettle();
      expect(tester.widget<MossSky>(find.byType(MossSky)).sky.hour, 22.5);
      expect(find.text('TENGAH MALAM · PILIHAN'), findsOneWidget);
    },
  );

  testWidgets('restored dark mode remains usable across the app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MossApp(
        render3d: false,
        initialAppearance: AppearanceSettings(
          themeMode: ThemeMode.dark,
          sky: SkyChoice.midnight,
        ),
      ),
    );
    final homeContext = tester.element(find.text('Ruang Moss'));
    final colors = Theme.of(homeContext).colorScheme;
    expect(Theme.of(homeContext).brightness, Brightness.dark);
    expect(colors.surfaceContainerLowest.computeLuminance(), lessThan(.1));
    expect(colors.onSurface.computeLuminance(), greaterThan(.7));
    expect(find.text('TENGAH MALAM · PILIHAN'), findsOneWidget);
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(find.text('RIWAYAT SIMULASI'), findsOneWidget);
    await tester.tap(find.text('Perangkat').last);
    await tester.pumpAndSettle();
    expect(find.text('Pratinjau perangkat'), findsOneWidget);
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    expect(find.text('Tampilan & suasana'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion disables sky transitions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MossSky(
            sky: SkyAppearance.atHour(12),
            child: const SizedBox(height: 250),
          ),
        ),
      ),
    );
    expect(
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
      Duration.zero,
    );
  });
}
