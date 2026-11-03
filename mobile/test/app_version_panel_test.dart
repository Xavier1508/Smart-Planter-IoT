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
        (_) async => {'version': '0.2.0', 'build': 17, 'channel': 'local'},
      );
      final info = await AppBuildInfo.read();
      expect(info?.version, '0.2.0');
      expect(info?.build, 17);
      expect(info?.channel, 'local');

      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'version': '0.2.0', 'build': -1, 'channel': 'unexpected'},
      );
      expect(await AppBuildInfo.read(), isNull);
    },
  );

  testWidgets('settings show the local manual update notice', (tester) async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'version': '0.2.0', 'build': 2, 'channel': 'local'},
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
      find.textContaining('Pembaruan aplikasi dilakukan manual'),
      findsOneWidget,
    );
  });
}
