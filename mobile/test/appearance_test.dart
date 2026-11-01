import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/appearance.dart';
import 'package:smart_planter/src/moss_app.dart';
import 'package:smart_planter/src/moss_gaze.dart';
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
    expect(SkyAppearance.atHour(16.5).visibleMoonOpacity, greaterThan(0));
    expect(
      (SkyAppearance.atHour(18).visibleMoonOpacity -
              SkyAppearance.atHour(17.999).visibleMoonOpacity)
          .abs(),
      lessThan(.001),
    );
  });

  test('preset stepping wraps and starts near automatic or custom time', () {
    expect(SkyChoice.step(SkyChoice.midnight, 23, next: true), SkyChoice.dawn);
    expect(SkyChoice.step(SkyChoice.dawn, 5, next: false), SkyChoice.midnight);
    expect(
      SkyChoice.step(SkyChoice.automatic, 12, next: true),
      SkyChoice.evening,
    );
    expect(SkyChoice.step(SkyChoice.custom, .5, next: false), SkyChoice.night);
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
    await tester.pumpWidget(
      MossApp(
        render3d: false,
        autoConnectLocal: false,
        clock: () => DateTime(2026, 1, 1, 12),
      ),
    );
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
    expect(find.byType(DropdownButtonFormField<SkyChoice>), findsNothing);
    await tester.tap(find.text('Hari ini'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Suasana berikutnya'));
    await tester.tap(find.byTooltip('Suasana berikutnya'));
    await tester.pumpAndSettle();
    final sky = tester.widget<MossSky>(find.byType(MossSky)).sky;
    expect(sky.label, 'Sore');
    expect(sky.hour, 16.5);
    expect(find.text('SORE · PILIHAN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic sky refreshes after the app resumes', (tester) async {
    var now = DateTime(2026, 1, 1, 5);
    await tester.pumpWidget(
      MossApp(render3d: false, autoConnectLocal: false, clock: () => now),
    );
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
        const MossApp(render3d: false, autoConnectLocal: false),
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

  testWidgets('card swipe and accessible arrows select and restore time', (
    tester,
  ) async {
    await tester.pumpWidget(
      MossApp(
        render3d: false,
        autoConnectLocal: false,
        clock: () => DateTime(2026, 1, 1, 12),
      ),
    );
    expect(find.text('SIANG · JAM HP'), findsOneWidget);
    await tester.drag(find.byType(MossSky), const Offset(-130, 0));
    await tester.pumpAndSettle();
    expect(find.text('SORE · PILIHAN'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Suasana berikutnya'));
    await tester.tap(find.byTooltip('Suasana berikutnya'));
    await tester.pumpAndSettle();
    expect(find.text('MALAM · PILIHAN'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ruang Moss'),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(MossSky), const Offset(130, 0));
    await tester.pumpAndSettle();
    expect(find.text('SORE · PILIHAN'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Suasana sebelumnya'));
    await tester.tap(find.byTooltip('Suasana sebelumnya'));
    await tester.pumpAndSettle();
    expect(find.text('SIANG · PILIHAN'), findsOneWidget);

    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('automatic-moss-time')),
    );
    await tester.tap(find.byKey(const ValueKey('automatic-moss-time')));
    await tester.tap(find.text('Hari ini'));
    await tester.pumpAndSettle();
    expect(find.text('SIANG · JAM HP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
        autoConnectLocal: false,
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
    expect(find.text('Belum ada riwayat'), findsOneWidget);
    await tester.tap(find.text('Perangkat').last);
    await tester.pumpAndSettle();
    expect(find.text('Belum terhubung'), findsOneWidget);
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

  testWidgets(
    'sky crosses midnight smoothly and retargets interrupted swipes',
    (tester) async {
      final gaze = MossGaze();
      final atmosphere = MossAtmosphere(SkyAppearance.atHour(23));
      addTearDown(gaze.dispose);
      Widget skyAt(double hour) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 350,
              child: MossSky(
                sky: SkyAppearance.atHour(hour),
                gaze: gaze,
                atmosphere: atmosphere,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(skyAt(23));
      await tester.pumpWidget(skyAt(5));
      await tester.pump(const Duration(milliseconds: 700));
      final half = Curves.easeInOutCubic.transform(.5);
      expect(atmosphere.current.hour, closeTo((23 + 6 * half) % 24, .01));
      expect(gaze.active, isTrue);
      expect(
        gaze.position!.dx,
        lessThan(tester.getCenter(find.byType(MossSky)).dx),
      );
      final interruptedHour = atmosphere.current.hour;
      await tester.pumpWidget(skyAt(19.5));
      expect(atmosphere.current.hour, closeTo(interruptedHour, .01));
      await tester.pump(const Duration(milliseconds: 700));
      final returnDelta = ((19.5 - interruptedHour + 36) % 24) - 12;
      expect(
        atmosphere.current.hour,
        closeTo((interruptedHour + returnDelta * half + 24) % 24, .01),
      );
      expect(
        gaze.position!.dx,
        greaterThan(tester.getCenter(find.byType(MossSky)).dx),
      );
      await tester.pump(const Duration(milliseconds: 750));
      expect(atmosphere.current.hour, closeTo(19.5, .01));
      expect(gaze.active, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'night comet respects lifecycle, ticker mode and reduced motion',
    (tester) async {
      final gaze = MossGaze();
      addTearDown(gaze.dispose);
      Widget sky({bool reduced = false, bool ticking = true}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            disableAnimations: reduced,
          ),
          child: TickerMode(
            enabled: ticking,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 350,
                  child: MossSky(
                    sky: SkyAppearance.atHour(23),
                    gaze: gaze,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Future<void> startComet() async {
        await tester.pump(const Duration(seconds: 35));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(gaze.active, isTrue);
      }

      await tester.pumpWidget(sky());
      await startComet();
      final firstPosition = gaze.position!;
      await tester.pump(const Duration(milliseconds: 300));
      expect(gaze.position!.dx, lessThan(firstPosition.dx));
      expect(gaze.position!.dy, greaterThan(firstPosition.dy));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(gaze.active, isFalse);
      await tester.pump(const Duration(seconds: 40));
      expect(gaze.active, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await startComet();

      await tester.pumpWidget(sky(reduced: true));
      expect(gaze.active, isFalse);
      await tester.pump(const Duration(seconds: 40));
      expect(gaze.active, isFalse);
      await tester.pumpWidget(sky(ticking: false));
      await tester.pump(const Duration(seconds: 40));
      expect(gaze.active, isFalse);
      await tester.pumpWidget(sky());
      await startComet();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(gaze.active, isFalse);
      await tester.pump(const Duration(seconds: 40));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an interrupted sky settles when motion or activity is disabled',
    (tester) async {
      final gaze = MossGaze();
      final atmosphere = MossAtmosphere(SkyAppearance.atHour(12));
      addTearDown(gaze.dispose);
      Widget skyAt(double hour, {bool reduced = false, bool ticking = true}) =>
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(800, 600),
                disableAnimations: reduced,
              ),
              child: TickerMode(
                enabled: ticking,
                child: SizedBox(
                  width: 320,
                  height: 350,
                  child: MossSky(
                    sky: SkyAppearance.atHour(hour),
                    gaze: gaze,
                    atmosphere: atmosphere,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          );

      await tester.pumpWidget(skyAt(12));
      await tester.pumpWidget(skyAt(23));
      await tester.pump(const Duration(milliseconds: 300));
      expect(atmosphere.current.hour, isNot(23));
      expect(gaze.active, isTrue);
      await tester.pumpWidget(skyAt(23, reduced: true));
      expect(atmosphere.current.hour, 23);
      expect(gaze.active, isFalse);
      await tester.pumpWidget(skyAt(5, reduced: true));
      expect(atmosphere.current.hour, 5);

      await tester.pumpWidget(skyAt(5));
      await tester.pumpWidget(skyAt(12));
      await tester.pump(const Duration(milliseconds: 300));
      expect(gaze.active, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(atmosphere.current.hour, 12);
      expect(gaze.active, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      await tester.pumpWidget(skyAt(23));
      await tester.pump(const Duration(milliseconds: 300));
      expect(gaze.active, isTrue);
      await tester.pumpWidget(skyAt(23, ticking: false));
      expect(atmosphere.current.hour, 23);
      expect(gaze.active, isFalse);
      await tester.pumpWidget(skyAt(5, ticking: false));
      expect(atmosphere.current.hour, 5);
      expect(gaze.active, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('daytime does not schedule a comet', (tester) async {
    final gaze = MossGaze();
    addTearDown(gaze.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MossSky(
          sky: SkyAppearance.atHour(12),
          gaze: gaze,
          child: const SizedBox(height: 300),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 70));
    expect(gaze.active, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sun and moon stay large and clear of the center of the card', (
    tester,
  ) async {
    for (final width in [240.0, 276.0, 376.0]) {
      for (final hour in [5.0, 8.0, 12.0, 16.5, 19.5, 23.0, 0.0, 4.0]) {
        final sky = SkyAppearance.atHour(hour);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  height: 350,
                  child: MossSky(sky: sky, child: const SizedBox.expand()),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = tester.getRect(find.byType(MossSky));
        final centerLeft = card.left + card.width * .35;
        final centerRight = card.left + card.width * .65;
        if (sky.sunOpacity > .1) {
          final sun = tester.getRect(
            find.byKey(const ValueKey('moss-sun-disc')),
          );
          expect(
            sun.width,
            greaterThan(34),
            reason: 'sun at $hour, width $width',
          );
          expect(sun.right, lessThan(centerLeft), reason: 'sun at $hour');
          expect(card.contains(sun.topLeft), isTrue);
          expect(card.contains(sun.bottomRight), isTrue);
        }
        if (sky.moonOpacity > .1) {
          final moon = tester.getRect(
            find.byKey(const ValueKey('moss-moon-disc')),
          );
          expect(
            moon.width,
            greaterThan(34),
            reason: 'moon at $hour, width $width',
          );
          expect(moon.left, greaterThan(centerRight), reason: 'moon at $hour');
          expect(card.contains(moon.topLeft), isTrue);
          expect(card.contains(moon.bottomRight), isTrue);
        }
      }
    }
    expect(tester.takeException(), isNull);
  });
}
