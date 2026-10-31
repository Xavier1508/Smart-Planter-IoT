import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/app_version_panel.dart';
import 'package:smart_planter/src/moss_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('moss/build_info');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'build info comes from the platform and rejects malformed values',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'version': '0.2.0', 'build': 17, 'channel': 'beta'},
      );
      final info = await AppBuildInfo.read();
      expect(info?.version, '0.2.0');
      expect(info?.build, 17);
      expect(info?.channel, 'beta');

      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'version': '0.2.0', 'build': -1, 'channel': 'unexpected'},
      );
      expect(await AppBuildInfo.read(), isNull);
    },
  );

  testWidgets('settings distinguish local builds from beta updates', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'version': '0.2.0', 'build': 2, 'channel': 'production'},
    );
    await tester.pumpWidget(
      const MossApp(render3d: false, autoConnectLocal: false),
    );
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Versi & pembaruan'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Versi 0.2.0 · build 2'), findsOneWidget);
    expect(
      find.textContaining('Varian ini tidak memeriksa pembaruan Firebase'),
      findsOneWidget,
    );
  });

  testWidgets('beta update information still requires tester approval', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'version': '0.2.0', 'build': 18, 'channel': 'beta'},
    );
    await tester.pumpWidget(
      const MossApp(render3d: false, autoConnectLocal: false),
    );
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Versi & pembaruan'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Versi 0.2.0 · build 18'), findsOneWidget);
    expect(
      find.textContaining('Instalasi memerlukan persetujuan'),
      findsOneWidget,
    );
  });
}
