import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/local_wifi.dart';
import 'package:smart_planter/src/moss_app.dart';
import 'package:smart_planter/src/plant_telemetry.dart';

class FixtureLocalWifi extends LocalWifiController {
  FixtureLocalWifi({this.waterAdc = 1200});

  final int? waterAdc;

  @override
  Future<void> connect() async {
    snapshot = SerialSensorSnapshot.parse('''
      {"type":"sample","uptime_ms":5000,
       "dht":{"temperature_c":28.7,"humidity_percent":74,"status":"unverified"},
       "adc":{"soil_raw":1000,"soil_status":"unverified","soil_relative_percent":44,
              "light_raw":2000,"light_relative_percent":51,"uv_raw":0,"status":"unverified"},
       "water_level":{"adc_raw":$waterAdc,"relative_percent":null,"status":"unverified",
         "observation_scale":{"relative_percent":50,"basis":"operator_reported_window_means",
           "quality":"unverified","use_for_control":false}},
       "mq135":{"adc_raw":null,"digital_raw":1,"adc_status":"adc_read_failed","status":"unverified"},
       "pump_cmd":false,"growlight_cmd":false,
       "lighting_rule":{"candidate":"unavailable","status":"diagnostic_only_unverified",
                        "use_for_control":false}}
    ''');
    status = LocalWifiStatus.live;
    message = 'Wi-Fi lokal: sampel terbaru diterima di ponsel.';
    notifyListeners();
  }

  void loseConnection() {
    snapshot = null;
    status = LocalWifiStatus.disconnected;
    message = 'Koneksi Wi-Fi lokal terputus.';
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String bundledModel;

  setUpAll(() async {
    bundledModel = await rootBundle.loadString('assets/ml/pattern-models.json');
  });

  testWidgets(
    'local Wi-Fi selection shows fixture data and clears it on loss',
    (tester) async {
      final wifi = FixtureLocalWifi();
      addTearDown(wifi.dispose);
      await tester.pumpWidget(
        MossApp(
          render3d: false,
          localWifi: wifi,
          modelAssetLoader: () async => bundledModel,
        ),
      );
      await tester.tap(find.text('Pengaturan'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Hubungkan Wi-Fi lokal'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Hubungkan Wi-Fi lokal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hari ini'));
      await tester.pumpAndSettle();
      expect(find.text('SENSOR'), findsOneWidget);
      expect(find.text('POLA SINTETIS'), findsOneWidget);
      expect(find.text('Pola tanah relatif rendah.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Wi-Fi lokal: sampel terbaru diterima di ponsel.'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Wi-Fi lokal: sampel terbaru diterima di ponsel.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Air (relatif)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('44%'), findsOneWidget);
      expect(find.text('~50%'), findsOneWidget);
      expect(find.text('UV (skala ADC)'), findsOneWidget);
      expect(find.text('~0%'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Sensor udara MQ135'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Analog gagal · digital 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('ML XGBoost · sintetis'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Skor model sintetis'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Perangkat'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Aturan lampu (pratinjau): belum tersedia'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Pompa: OFF diminta'), findsOneWidget);
      expect(find.text('Lampu: OFF diminta'), findsOneWidget);
      await tester.tap(find.text('Hari ini'));
      await tester.pumpAndSettle();

      wifi.loseConnection();
      await tester.pump();
      expect(find.text('44%'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Ruang Moss'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('Koneksi Wi-Fi lokal terputus.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final waterAdc in <int?>[null, 0]) {
    testWidgets('local model waits when water ADC is $waterAdc', (
      tester,
    ) async {
      final wifi = FixtureLocalWifi(waterAdc: waterAdc);
      addTearDown(wifi.dispose);
      await tester.pumpWidget(
        MossApp(
          render3d: false,
          localWifi: wifi,
          modelAssetLoader: () async => bundledModel,
        ),
      );
      await tester.tap(find.text('Pengaturan'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Hubungkan Wi-Fi lokal'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Hubungkan Wi-Fi lokal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hari ini'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('ML XGBoost · sintetis'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Menunggu data tanah, air, dan cahaya yang dapat dibaca.'),
        findsOneWidget,
      );
      expect(find.textContaining('Skor model sintetis'), findsNothing);
    });
  }

  testWidgets('malformed model is reported without a fabricated score', (
    tester,
  ) async {
    final wifi = FixtureLocalWifi();
    addTearDown(wifi.dispose);
    await tester.pumpWidget(
      MossApp(
        render3d: false,
        localWifi: wifi,
        modelAssetLoader: () async => '{}',
      ),
    );
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Hubungkan Wi-Fi lokal'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Hubungkan Wi-Fi lokal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hari ini'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ML XGBoost · sintetis'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Model tidak tersedia.'), findsOneWidget);
    expect(find.textContaining('Skor model sintetis'), findsNothing);
  });

  testWidgets('serial rule previews are shown without claiming relay control', (
    tester,
  ) async {
    const sample = '''
      {"type":"sample","uptime_ms":5000,
       "adc":{"soil_raw":1000,"soil_status":"unverified","soil_relative_percent":40,
              "light_raw":2000,"light_relative_percent":51,"uv_raw":0,"status":"unverified"},
       "water_level":{"adc_raw":0,"relative_percent":null,"status":"unverified"},
       "control_preview":{"mode":"diagnostic_only","basis":"relative_unverified",
                          "pump_on":true,"growlight_on":true,"water_low":null}}
    ''';
    await tester.pumpWidget(
      const MossApp(render3d: false, initialSerialJson: sample),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Perangkat'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Air <20%: Belum tersedia'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Pompa <50%: Menyala (pratinjau)'), findsOneWidget);
    expect(find.text('Lampu <60%: Menyala (pratinjau)'), findsOneWidget);
    expect(find.text('Air <20%: Belum tersedia'), findsOneWidget);
    expect(
      find.textContaining('bukan perintah, status relay, atau notifikasi live'),
      findsOneWidget,
    );
  });

  testWidgets('packaged serial snapshot starts as offline data, not demo', (
    tester,
  ) async {
    const sample = '''
      {"type":"sample","uptime_ms":12345,
       "dht":{"temperature_c":23.4,"humidity_percent":62.5,"status":"unverified"},
       "adc":{"soil_raw":800,"soil_status":"unverified","soil_relative_percent":32,
              "light_raw":2000,"light_relative_percent":51,"uv_raw":0,"status":"unverified"},
       "water_level":{"adc_raw":0,"status":"unverified"},
       "mq135":{"adc_raw":4095,"digital_raw":1,"adc_status":"unverified","status":"unverified"}}
    ''';
    await tester.pumpWidget(
      const MossApp(render3d: false, initialSerialJson: sample),
    );
    await tester.pumpAndSettle();
    expect(find.text('SERIAL'), findsOneWidget);
    expect(find.text('SIMULASI'), findsNothing);
    expect(find.text('SENSOR'), findsNothing);
    expect(
      find.text('Data serial tersimpan; waktu pembacaan tidak diketahui.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Air (relatif)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('32%'), findsOneWidget);
    expect(find.text('UV (skala ADC)'), findsOneWidget);
    expect(find.text('~0%'), findsOneWidget);
  });

  testWidgets('invalid packaged snapshot does not silently enable demo', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MossApp(render3d: false, initialSerialJson: '{}'),
    );
    await tester.pumpAndSettle();
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('SIMULASI'), findsNothing);
    expect(
      find.text('Snapshot serial tidak valid; menunggu sumber data.'),
      findsOneWidget,
    );
  });

  testWidgets('pasted serial snapshot is visible but never labelled live', (
    tester,
  ) async {
    var reads = 0;
    var clipboard = 'not a serial sample';
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        reads++;
        return {'text': clipboard};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(const MossApp(render3d: false));
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    expect(reads, 0);
    await tester.scrollUntilVisible(
      find.text('Tempel data serial'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Tempel data serial'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(
      find.text('Salin satu baris JSON sample dari monitor serial.'),
      findsOneWidget,
    );

    clipboard = '''
      {"type":"sample","uptime_ms":12345,
       "dht":{"temperature_c":23.4,"humidity_percent":62.5,"status":"unverified"},
       "adc":{"soil_raw":800,"soil_status":"unverified","soil_relative_percent":32,
              "light_raw":2000,"light_relative_percent":51,"uv_raw":0,"status":"unverified"},
       "water_level":{"adc_raw":0,"status":"unverified"},
       "mq135":{"adc_raw":4095,"digital_raw":1,"adc_status":"unverified","status":"unverified"}}
    ''';
    await tester.tap(find.text('Tempel data serial'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('SERIAL'), findsOneWidget);
    expect(find.text('SENSOR'), findsNothing);
    expect(
      find.text('Data serial tersimpan; waktu pembacaan tidak diketahui.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Air (relatif)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('32%'), findsOneWidget);
    expect(find.text('UV (skala ADC)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sensor udara MQ135'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('~100% ADC'), findsOneWidget);
    expect(find.text('ADC 4095 · bukan kualitas udara'), findsOneWidget);
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Hapus snapshot'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Hapus snapshot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hari ini'));
    await tester.pumpAndSettle();
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('SERIAL'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
    await tester.ensureVisible(find.text('Tutup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ruang Moss'),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('Halo, aku Moss.'), findsOneWidget);
    expect(find.text('64%'), findsNothing);
    expect(find.text('Perangkat dan cloud belum terhubung.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pompa & lampu'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Kendali nyata belum tersedia.'), findsOneWidget);
  });

  testWidgets('history is explicitly empty rather than fabricated', (
    tester,
  ) async {
    await tester.pumpWidget(const MossApp(render3d: false));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tutup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tutup'));
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
    await tester.ensureVisible(find.text('Tutup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tutup'));
    await tester.pump();
    expect(find.text('Menunggu pembacaan sensor.'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Ruang Moss'),
      -150,
      scrollable: find.byType(Scrollable).first,
    );

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
    expect(
      find.text(
        'Estimasi tanah di bawah ambang; belum diverifikasi dan bukan diagnosis.',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Kelembapan tanah'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('DATA SENSOR'), findsOneWidget);
    expect(find.text('24%'), findsOneWidget);
    expect(
      find.text(
        'Nilai sensor belum diverifikasi; tanah dan cahaya berupa skala relatif.',
      ),
      findsOneWidget,
    );
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

  testWidgets('UV estimate is labelled unverified and cleared on disconnect', (
    tester,
  ) async {
    final readings = StreamController<PlantTelemetry>();
    await tester.pumpWidget(
      MossApp(render3d: false, telemetry: readings.stream),
    );
    await tester.ensureVisible(find.text('Tutup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tutup'));
    await tester.pump();

    readings.add(PlantTelemetry(recordedAt: DateTime.now(), uvIndex: 3.5));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('UV (perkiraan)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('3.5'), findsOneWidget);
    expect(find.text('Belum diverifikasi'), findsOneWidget);

    readings.addError(StateError('connection lost'));
    await tester.pump();
    expect(find.text('3.5'), findsNothing);

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
    await tester.ensureVisible(find.text('Tutup'));
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(find.text('Tutup'));
    await tester.pumpAndSettle();
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
