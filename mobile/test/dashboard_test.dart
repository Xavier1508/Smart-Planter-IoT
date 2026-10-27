import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/moss_app.dart';
import 'package:smart_planter/src/plant_telemetry.dart';

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

  testWidgets('unconfigured cloud is clearly reported in settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MossApp(
        render3d: false,
        cloudSetupNotice: 'Aplikasi belum dikonfigurasi untuk cloud.',
      ),
    );
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    expect(
      find.text('Aplikasi belum dikonfigurasi untuk cloud.'),
      findsOneWidget,
    );
    expect(find.text('Masuk'), findsNothing);
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

  testWidgets('fresh sensor data is shown and removed on disconnect', (
    tester,
  ) async {
    final readings = StreamController<PlantTelemetry>();
    await tester.pumpWidget(
      MossApp(render3d: false, telemetry: readings.stream),
    );
    await tester.tap(find.text('Tutup'));
    await tester.pump();
    expect(find.text('Menunggu pembacaan sensor.'), findsOneWidget);

    readings.add(
      PlantTelemetry(
        recordedAt: DateTime.now(),
        soilPercent: 24,
        temperatureC: 26.2,
        humidityPercent: 65,
        lightPercent: 40,
      ),
    );
    await tester.pump();
    expect(find.text('SENSOR'), findsOneWidget);
    expect(find.text('Sepertinya aku butuh air.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Kelembapan tanah'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('DATA SENSOR'), findsOneWidget);
    expect(find.text('24%'), findsOneWidget);
    expect(find.text('78%'), findsNothing);

    readings.addError(StateError('connection lost'));
    await tester.pump();
    expect(find.text('24%'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Ruang Moss'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('Koneksi data terputus.'), findsOneWidget);

    final closing = readings.close();
    await tester.pump();
    await closing;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('equal timestamps use row IDs and recover after disconnect', (
    tester,
  ) async {
    final readings = StreamController<PlantTelemetry>();
    await tester.pumpWidget(
      MossApp(render3d: false, telemetry: readings.stream),
    );
    await tester.tap(find.text('Tutup'));
    await tester.pump();

    final now = DateTime.now();
    void emit(int? sequence, int soilPercent) {
      readings.add(
        PlantTelemetry(
          recordedAt: now,
          sequence: sequence,
          soilPercent: soilPercent,
        ),
      );
    }

    emit(42, 42);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Kelembapan tanah'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('42%'), findsOneWidget);

    emit(41, 11);
    emit(null, 12);
    emit(42, 13);
    await tester.pump();
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('11%'), findsNothing);
    expect(find.text('12%'), findsNothing);
    expect(find.text('13%'), findsNothing);

    emit(43, 63);
    await tester.pump();
    expect(find.text('63%'), findsOneWidget);

    readings.addError(StateError('connection lost'));
    await tester.pump();
    expect(find.text('63%'), findsNothing);
    emit(42, 42);
    await tester.pump();
    expect(find.text('42%'), findsNothing);
    emit(43, 63);
    await tester.pump();
    expect(find.text('63%'), findsOneWidget);

    final closing = readings.close();
    await tester.pump();
    await closing;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stale and invalid readings never remain visible as live', (
    tester,
  ) async {
    final readings = StreamController<PlantTelemetry>();
    await tester.pumpWidget(
      MossApp(render3d: false, telemetry: readings.stream),
    );
    await tester.tap(find.text('Tutup'));
    await tester.pump();

    final now = DateTime.now();
    readings.add(PlantTelemetry(recordedAt: now, soilPercent: 50));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Kelembapan tanah'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('50%'), findsOneWidget);

    readings.add(
      PlantTelemetry(
        recordedAt: now.subtract(const Duration(seconds: 1)),
        soilPercent: 20,
      ),
    );
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('20%'), findsNothing);

    readings.add(
      PlantTelemetry(
        recordedAt: now.add(const Duration(milliseconds: 1)),
        soilPercent: 101,
      ),
    );
    await tester.pump();
    expect(find.text('50%'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Ruang Moss'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('Menunggu pembacaan sensor yang valid.'), findsOneWidget);

    readings.add(
      PlantTelemetry(
        recordedAt: now.add(const Duration(milliseconds: 2)),
        soilPercent: 45,
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Kelembapan tanah'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('45%'), findsOneWidget);
    await tester.pump(const Duration(minutes: 2, seconds: 1));
    expect(find.text('45%'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Ruang Moss'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(
      find.text('Data sensor sudah lama; menunggu pembaruan.'),
      findsOneWidget,
    );

    final closing = readings.close();
    await tester.pump();
    await closing;
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
