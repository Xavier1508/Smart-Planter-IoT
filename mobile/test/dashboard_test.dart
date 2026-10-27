import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/moss_app.dart';

void main() {
  testWidgets('demo is labelled and scenarios change Moss expression', (
    tester,
  ) async {
    await tester.pumpWidget(const MossApp(render3d: false));
    await tester.pumpAndSettle();
    expect(find.text('SIMULASI'), findsOneWidget);
    expect(find.text('Simulasi — bukan data sensor.'), findsOneWidget);
    expect(find.text('Aku merasa nyaman hari ini.'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Butuh air'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Butuh air'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ruang Moss'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sepertinya aku butuh air.'), findsOneWidget);
  });

  testWidgets('turning demo off shows no fake values and disabled controls', (
    tester,
  ) async {
    await tester.pumpWidget(const MossApp(render3d: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('Halo, aku Moss.'), findsOneWidget);
    expect(find.text('64%'), findsNothing);
    expect(find.text('Perangkat dan cloud belum terhubung.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pompa & lampu'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Kontrol tersedia setelah ESP32 terhubung.'),
      findsOneWidget,
    );
  });

  testWidgets('history is explicitly empty rather than fabricated', (
    tester,
  ) async {
    await tester.pumpWidget(const MossApp(render3d: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada riwayat'), findsOneWidget);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
  });

  testWidgets('dashboard remains usable at a narrow Android width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MossApp(render3d: false));
    await tester.pumpAndSettle();
    expect(find.text('Ruang Moss'), findsOneWidget);
    expect(find.text('SIMULASI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
