import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/local_wifi.dart';
import 'package:smart_planter/src/moss_app.dart';
import 'package:smart_planter/src/plant_telemetry.dart';

class FixtureLocalWifi extends LocalWifiController {
  FixtureLocalWifi({this.waterAdc = 1200});

  final int? waterAdc;
  final List<String> commands = [];

  @override
  Future<bool> sendControlCommand(String line) async {
    commands.add(line);
    return true;
  }

  @override
  Future<void> connect() async {
    publishSoil(44);
  }

  void publishSoil(int soilPercent) {
    snapshot = SerialSensorSnapshot.parse('''
      {"type":"sample","uptime_ms":5000,
       "dht":{"temperature_c":28.7,"humidity_percent":74,"status":"unverified"},
       "adc":{"soil_raw":1000,"soil_status":"unverified","soil_relative_percent":$soilPercent,
              "light_raw":2000,"light_relative_percent":51,"uv_raw":0,"status":"unverified"},
       "water_level":{"adc_raw":$waterAdc,"relative_percent":null,"status":"unverified",
         "observation_scale":{"relative_percent":30,"basis":"operator_reported_window_means",
           "quality":"unverified","use_for_control":false}},
       "mq135":{"adc_raw":null,"digital_raw":1,"adc_status":"adc_read_failed","status":"unverified"},
       "pump_cmd":false,"pump_reason":"soil_not_dry",
       "growlight_cmd":false,"growlight_reason":"ldr_sufficient",
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

  testWidgets('real local socket frames update the dashboard', (tester) async {
    const updateChannel = MethodChannel('moss/update_progress');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(updateChannel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(updateChannel, null));
    final server = await tester.runAsync(
      () => ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    expect(server, isNotNull);
    final incoming = server!.first;
    final wifi = LocalWifiController(address: '127.0.0.1', port: server.port);
    Socket? peer;
    addTearDown(() async {
      peer?.destroy();
      wifi.dispose();
      await server.close();
    });

    String sample(
      int uptime,
      int soil, {
      int soilRaw = 1000,
      int waterRaw = 2000,
      int? waterPercent = 30,
      bool? waterLow = false,
      int? mqAdc,
      bool adc1Failure = false,
      int? mqMv = 550,
    }) => jsonEncode({
      'type': 'sample',
      'schema': 'serial_observation_2',
      'firmware_version': mqAdc != null || adc1Failure ? 19 : 18,
      'uptime_ms': uptime,
      'adc': {
        'soil_raw': soilRaw,
        'soil_status': 'unverified',
        'soil_relative_percent': soil,
        'light_raw': 2000,
        'light_relative_percent': 51,
        'uv_raw': 0,
        'status': 'unverified',
      },
      'water_level': {
        'adc_raw': waterRaw,
        'relative_percent': waterPercent,
        'low': waterLow,
        'status': 'unverified',
      },
      'mq135': {
        'adc_raw': mqAdc,
        'digital_raw': 1,
        'adc_status': mqAdc == null
            ? (adc1Failure ? 'unavailable' : 'adc_read_failed')
            : 'unverified',
        'status': 'unverified',
        if (mqAdc != null || adc1Failure) 'adc_unit': 'ADC1',
        if (adc1Failure) 'signal_quality': 'adc_read_failed',
        if (mqAdc != null && mqMv != null) 'adc_pin_mv_estimate': mqMv,
        if (mqAdc != null) 'adc_calibration_source': 'efuse_vref',
      },
      'pump_cmd': false,
      'growlight_cmd': false,
    });

    Future<void> waitForUptime(int uptime) async {
      if (wifi.snapshot?.uptimeMs == uptime) return;
      await wifi.changes
          .firstWhere((_) => wifi.snapshot?.uptimeMs == uptime)
          .timeout(const Duration(seconds: 3));
    }

    await tester.pumpWidget(MossApp(render3d: false, localWifi: wifi));
    await tester.pump();
    peer = await tester.runAsync(
      () => incoming.timeout(const Duration(seconds: 3)),
    );
    expect(peer, isNotNull);
    await tester.runAsync(() async {
      peer!.write('${sample(5000, 44, mqAdc: 500)}\n');
      await peer.flush();
      await waitForUptime(5000);
    });
    await tester.pumpAndSettle();
    expect(find.text('SENSOR'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Kelembapan tanah'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('44%'), findsOneWidget);
    expect(find.text('Full'), findsOneWidget);

    await tester.runAsync(() async {
      peer!.write(
        '${sample(10000, 68, waterPercent: 95, mqAdc: 760, mqMv: 800)}\n',
      );
      await peer.flush();
      await waitForUptime(10000);
    });
    await tester.pump();
    expect(find.text('44%'), findsNothing);
    expect(find.text('68%'), findsOneWidget);
    expect(find.text('Full'), findsOneWidget);
    // Water and LDR both use raw 2000 in this fixture.
    expect(find.text('ADC 2000'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.text('Sensor udara MQ135'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('35'), findsOneWidget);
    expect(find.text('indeks gas 0–100'), findsOneWidget);
    expect(find.text('Perubahan gas jelas · relatif'), findsOneWidget);
    expect(find.text('ADC 760 · terbaru'), findsOneWidget);
    expect(find.text('Rata-rata 2/12 sampel: 630 ADC'), findsOneWidget);
    expect(find.text('Arah sinyal: stabil dalam batas derau.'), findsNothing);
    expect(find.text('Tegangan pin: ~800 mV'), findsOneWidget);
    expect(find.text('Baseline sesi: ~554 mV'), findsOneWidget);
    expect(find.text('MQ135 · gas umum (asap/VOC)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Kelembapan tanah'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.runAsync(() async {
      peer!.write(
        '${sample(15000, 68, soilRaw: 0, waterPercent: null, waterLow: true, adc1Failure: true)}\n',
      );
      await peer.flush();
      await waitForUptime(15000);
    });
    await tester.pump();
    expect(find.text('68%'), findsNothing);
    expect(find.text('Belum terbaca'), findsOneWidget);
    expect(
      find.text('ADC 0 · sinyal tidak valid; pompa dikunci'),
      findsOneWidget,
    );
    expect(find.text('Low'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sensor udara MQ135'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Rata-rata 2/12 sampel: 630 ADC'), findsNothing);
    expect(
      find.text('Rata-rata menunggu sinyal analog non-rel.'),
      findsOneWidget,
    );
    expect(find.text('indeks gas 0–100'), findsNothing);
    expect(find.text('Analog gagal dibaca pada ADC1.'), findsOneWidget);
    expect(
      find.text('Analog gagal dibaca; ADC2 bisa berbenturan dengan Wi-Fi.'),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.text('Kelembapan tanah'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.runAsync(() async {
      peer!.write('${sample(20000, 68, waterRaw: 0, waterLow: true)}\n');
      await peer.flush();
      await waitForUptime(20000);
    });
    await tester.pump();
    expect(find.text('Low'), findsNothing);
    expect(find.text('Belum terbaca'), findsOneWidget);

    wifi.disconnect();
    await tester.pump();
    expect(find.text('68%'), findsNothing);
    expect(find.text('Full'), findsNothing);
    expect(find.text('Medium'), findsNothing);
    expect(find.text('Low'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'home connects automatically and refreshes real-data presentation',
    (tester) async {
      final wifi = FixtureLocalWifi();
      addTearDown(wifi.dispose);
      await tester.pumpWidget(MossApp(render3d: false, localWifi: wifi));
      await tester.pumpAndSettle();
      expect(find.text('SIMULASI'), findsNothing);
      expect(find.text('SENSOR'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Kelembapan tanah'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('44%'), findsOneWidget);
      wifi.publishSoil(68);
      await tester.pump();
      expect(find.text('44%'), findsNothing);
      expect(find.text('68%'), findsOneWidget);
      wifi.loseConnection();
      await tester.pump();
      expect(find.text('68%'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'local Wi-Fi selection shows fixture data and clears it on loss',
    (tester) async {
      final wifi = FixtureLocalWifi();
      addTearDown(wifi.dispose);
      await tester.pumpWidget(
        MossApp(render3d: false, localWifi: wifi, autoConnectLocal: false),
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
      expect(find.text('POLA SINTETIS'), findsNothing);
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
        find.text('Level air'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('44%'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('ADC 1200'), findsOneWidget);
      expect(find.text('UV'), findsOneWidget);
      expect(find.text('~0%'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Sensor udara MQ135'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Analog gagal dibaca; ADC2 bisa berbenturan dengan Wi-Fi.'),
        findsOneWidget,
      );
      expect(find.text('D0 = 1: level komparator, bukan ppm.'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Perangkat'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Alasan lampu: cahaya LDR 65% atau lebih'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Pompa: OFF diminta'), findsOneWidget);
      expect(
        find.text('Alasan pompa: tanah belum di bawah batas nyala'),
        findsOneWidget,
      );
      expect(find.text('Lampu: OFF diminta'), findsOneWidget);
      expect(
        find.text('Alasan lampu: cahaya LDR 65% atau lebih'),
        findsOneWidget,
      );
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

  testWidgets('manual pump ON asks for duration before sending', (
    tester,
  ) async {
    final wifi = FixtureLocalWifi();
    addTearDown(wifi.dispose);
    await tester.pumpWidget(MossApp(render3d: false, localWifi: wifi));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Perangkat'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Kendali manual'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('ON').first);
    await tester.pumpAndSettle();
    expect(find.text('Durasi pompa'), findsOneWidget);
    expect(wifi.commands, isEmpty);
    await tester.tap(find.text('Mulai'));
    await tester.pumpAndSettle();
    expect(wifi.commands.single, startsWith('CTRL pump=on dur=5 id='));
  });

  testWidgets('manual AUTO is sent immediately without a duration dialog', (
    tester,
  ) async {
    final wifi = FixtureLocalWifi();
    addTearDown(wifi.dispose);
    await tester.pumpWidget(MossApp(render3d: false, localWifi: wifi));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Perangkat'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Kendali manual'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('ON').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mulai'));
    await tester.pumpAndSettle();
    wifi.commands.clear();
    await tester.tap(find.text('AUTO').first);
    await tester.pumpAndSettle();
    expect(find.text('Durasi pompa'), findsNothing);
    expect(wifi.commands.single, startsWith('CTRL pump=auto id='));
  });

  testWidgets(
    'scheduler wizard runs an immediate job and shows its countdown',
    (tester) async {
      final wifi = FixtureLocalWifi();
      addTearDown(wifi.dispose);
      await tester.pumpWidget(MossApp(render3d: false, localWifi: wifi));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Perangkat'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Jadwal & aksi'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byIcon(Icons.add_alarm_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Aksi & waktu'), findsOneWidget);
      expect(find.text('Sekarang'), findsOneWidget);
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(find.text('Atur durasi'), findsOneWidget);
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(find.text('Konfirmasi'), findsOneWidget);
      await tester.tap(find.text('Jalankan sekarang'));
      await tester.pumpAndSettle();
      expect(wifi.commands.single, startsWith('CTRL pump=on dur=5 id='));
      expect(find.textContaining('sisa'), findsOneWidget);
    },
  );

  testWidgets('scheduler wizard exposes calendar fields on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final wifi = FixtureLocalWifi();
    addTearDown(wifi.dispose);
    await tester.pumpWidget(MossApp(render3d: false, localWifi: wifi));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Perangkat'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Jadwal & aksi'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byIcon(Icons.add_alarm_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jadwalkan'));
    await tester.pumpAndSettle();
    expect(find.text('Tanggal'), findsOneWidget);
    expect(find.text('Jam & menit'), findsOneWidget);
    expect(find.text('Detik'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device page shows availability without raw ADC values', (
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
      const MossApp(
        render3d: false,
        initialSerialJson: sample,
        autoConnectLocal: false,
      ),
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
      find.text('Kelembapan tanah'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Tersedia'), findsWidgets);
    expect(find.textContaining('ADC'), findsNothing);
    expect(find.text('Pratinjau aturan serial'), findsNothing);
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
      const MossApp(
        render3d: false,
        initialSerialJson: sample,
        autoConnectLocal: false,
      ),
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
      find.text('Level air'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('32%'), findsOneWidget);
    expect(find.text('UV'), findsOneWidget);
    expect(find.text('~0%'), findsOneWidget);
  });

  testWidgets('invalid packaged snapshot does not silently enable demo', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MossApp(
        render3d: false,
        initialSerialJson: '{}',
        autoConnectLocal: false,
      ),
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
    await tester.pumpWidget(
      const MossApp(render3d: false, autoConnectLocal: false),
    );
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
      find.text('Level air'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('32%'), findsOneWidget);
    expect(find.text('UV'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sensor udara MQ135'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('belum tersedia'), findsOneWidget);
    expect(find.text('ADC 4095 · snapshot'), findsOneWidget);
    expect(
      find.text('ADC mencapai batas; penyebab belum diketahui.'),
      findsOneWidget,
    );
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

  testWidgets('waiting view contains no invented values or demo controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MossApp(render3d: false, autoConnectLocal: false),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ruang Moss'),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('Halo, aku Moss.'), findsOneWidget);
    expect(find.text('64%'), findsNothing);
    expect(find.text('SIMULASI'), findsNothing);
    expect(find.text('Demo'), findsNothing);
    expect(find.textContaining('Ekspresi Moss menggunakan'), findsNothing);
  });

  testWidgets('history is explicitly empty rather than fabricated', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MossApp(render3d: false, autoConnectLocal: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada riwayat'), findsOneWidget);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
  });

  testWidgets('local settings do not require a cloud connection', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MossApp(
        render3d: false,
        cloudSetupNotice: 'Aplikasi belum dikonfigurasi untuk cloud.',
        autoConnectLocal: false,
      ),
    );
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    expect(
      find.text('Aplikasi belum dikonfigurasi untuk cloud.'),
      findsNothing,
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

    await tester.pumpWidget(
      const MossApp(render3d: false, autoConnectLocal: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ruang Moss'), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow sensor cards explain unavailable and estimated values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const sample = '''
      {"type":"sample",
       "adc":{"soil_raw":0,"soil_status":"unverified","soil_relative_percent":0,
              "status":"unverified"},
       "water_level":{"adc_raw":2000,"relative_percent":100,
                      "low":false,"status":"unverified"},
       "mq135":{"adc_raw":null,"digital_raw":1,"adc_status":"adc_read_failed",
                "status":"unverified"}}
    ''';
    await tester.pumpWidget(
      const MossApp(
        render3d: false,
        initialSerialJson: sample,
        autoConnectLocal: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Level air'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Belum terbaca'), findsOneWidget);
    expect(
      find.text('ADC 0 · sinyal tidak valid; pompa dikunci'),
      findsOneWidget,
    );
    expect(find.text('Full'), findsOneWidget);
    expect(find.text('ADC 2000'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sensor udara MQ135'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('D0 = 1: level komparator, bukan ppm.'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Perangkat'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Level air'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Full'), findsOneWidget);
    expect(find.textContaining('ADC'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fresh sensor data is shown and removed on disconnect', (
    tester,
  ) async {
    final readings = StreamController<PlantTelemetry>();
    await tester.pumpWidget(
      MossApp(
        render3d: false,
        telemetry: readings.stream,
        autoConnectLocal: false,
      ),
    );
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
    expect(find.text('Tanah atau air relatif rendah.'), findsOneWidget);
    expect(
      find.text(
        'Estimasi tanah atau air di bawah ambang; belum diverifikasi dan bukan diagnosis.',
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
      MossApp(
        render3d: false,
        telemetry: readings.stream,
        autoConnectLocal: false,
      ),
    );
    await tester.pump();

    readings.add(PlantTelemetry(recordedAt: DateTime.now(), uvIndex: 3.5));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('UV'),
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
      MossApp(
        render3d: false,
        telemetry: readings.stream,
        autoConnectLocal: false,
      ),
    );
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
    await tester.pump(); // Process the stream event and the resulting rebuild.
    expect(find.text('63%'), findsNothing);
    emit(42, 42);
    await tester.pump();
    await tester.pump();
    expect(find.text('42%'), findsNothing);
    emit(43, 63);
    await tester.pump();
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
      MossApp(
        render3d: false,
        telemetry: readings.stream,
        autoConnectLocal: false,
      ),
    );
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
