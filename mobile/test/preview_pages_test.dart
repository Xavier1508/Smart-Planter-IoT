import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/moss_app.dart';

void main() {
  testWidgets('journal preview is labelled and charts are selectable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(const MossApp(render3d: false));
      await tester.tap(find.text('Riwayat'));
      await tester.pumpAndSettle();
      expect(find.text('RIWAYAT SIMULASI'), findsOneWidget);
      expect(find.text('Belum ada riwayat'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('example-chart')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.bySemanticsLabel('Grafik simulasi tanah, bukan data sensor'),
        findsOneWidget,
      );
      final chart = find.byKey(const ValueKey('example-chart'));
      await tester.ensureVisible(chart);
      final rect = tester.getRect(chart);
      await tester.tapAt(Offset(rect.center.dx, rect.center.dy));
      await tester.pump();
      expect(find.text('Titik contoh 3: 54%'), findsOneWidget);
      final node = tester.getSemantics(chart);
      expect(node.getSemanticsData().value, 'Titik contoh 3: 54 persen');
      expect(
        node.getSemanticsData().increasedValue,
        'Titik contoh 4: 66 persen',
      );
      expect(
        node.getSemanticsData().decreasedValue,
        'Titik contoh 2: 58 persen',
      );
      tester
          .renderObject(chart)
          .owner!
          .semanticsOwner!
          .performAction(node.id, SemanticsAction.increase);
      await tester.pump();
      expect(find.text('Titik contoh 4: 66%'), findsOneWidget);
      await tester.tap(find.text('Cahaya'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Grafik simulasi cahaya, bukan data sensor'),
        findsOneWidget,
      );
      expect(find.text('Titik contoh 4: 63%'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('device switches are clearly local simulations', (tester) async {
    await tester.pumpWidget(const MossApp(render3d: false));
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Perangkat'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pratinjau perangkat'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Simulasi pompa'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(
        'SIMULASI — saklar ini tidak mengendalikan pompa atau lampu nyata.',
      ),
      findsOneWidget,
    );
    final pump = find.widgetWithText(SwitchListTile, 'Simulasi pompa');
    expect(tester.widget<SwitchListTile>(pump).value, isFalse);
    await tester.tap(pump);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(pump).value, isTrue);
    expect(find.text('Contoh: menyala'), findsOneWidget);
  });

  testWidgets('real mode never shows simulated device switches or history', (
    tester,
  ) async {
    await tester.pumpWidget(const MossApp(render3d: false));
    await tester.ensureVisible(find.text('Tutup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Perangkat'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Simulasi pompa'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Kendali perangkat'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(
        'Kendali nyata belum tersedia. Aplikasi tidak menyalakan atau mematikan aktuator.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada riwayat'), findsOneWidget);
    expect(find.text('RIWAYAT SIMULASI'), findsNothing);
  });

  testWidgets('preview pages fit a narrow Android screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MossApp(render3d: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Home at 320 pixels');
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Journal at 320 pixels');
    await tester.scrollUntilVisible(
      find.text('Moss mengenali perubahan'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull, reason: 'Journal events');
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Perangkat'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Simulasi lampu'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull, reason: 'Device controls');
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Versi & pembaruan'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull, reason: 'Settings');
  });
}
