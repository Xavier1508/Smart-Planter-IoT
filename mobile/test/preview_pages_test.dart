import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/moss_app.dart';

void main() {
  testWidgets('history contains no fabricated chart or events', (tester) async {
    await tester.pumpWidget(
      const MossApp(render3d: false, autoConnectLocal: false),
    );
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada riwayat'), findsOneWidget);
    expect(find.textContaining('contoh'), findsNothing);
    expect(find.textContaining('simulasi'), findsNothing);
  });

  testWidgets('device page is read-only without simulated switches', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MossApp(render3d: false, autoConnectLocal: false),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Perangkat'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belum terhubung'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Kendali perangkat'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(SwitchListTile), findsNothing);
    expect(
      find.text(
        'Otomasi pompa dan lampu berjalan di ESP32; aplikasi ini hanya memantau.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('pages fit a narrow Android screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MossApp(render3d: false, autoConnectLocal: false),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada riwayat'), findsOneWidget);
    await tester.tap(find.text('Perangkat').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    expect(find.text('Mode simulasi'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
