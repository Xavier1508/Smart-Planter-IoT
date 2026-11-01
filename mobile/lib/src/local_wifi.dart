import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mq_gas_index.dart';
import 'mq_signal_average.dart';
import 'plant_telemetry.dart';

enum LocalWifiStatus { disconnected, connecting, waiting, live }

/// Read-only, newline-delimited JSON stream from the ESP32's own WPA2 AP.
/// The default target is fixed; no scanning, cloud access or commands occur.
class LocalWifiController {
  LocalWifiController({
    this.address = '192.168.4.1',
    this.port = 3333,
    this.connectTimeout = const Duration(seconds: 5),
    this.sampleTimeout = const Duration(seconds: 20),
    this.reconnectDelay = const Duration(seconds: 5),
  });

  final String address;
  final int port;
  final Duration connectTimeout;
  final Duration sampleTimeout;
  final Duration reconnectDelay;

  LocalWifiStatus status = LocalWifiStatus.disconnected;
  String message = 'Menunggu koneksi ke ESP32.';
  SerialSensorSnapshot? snapshot;
  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;
  Timer? _deadline;
  Timer? _retry;
  final List<int> _pending = [];
  final MqSignalAverage _mqAverage = MqSignalAverage();
  final MqGasIndex _mqGas = MqGasIndex();
  int? _lastUptime;
  int _generation = 0;
  int _invalidFrames = 0;
  bool _disposed = false;
  bool _wanted = false;
  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );

  Stream<void> get changes => _changes.stream;
  int? get mqAverageAdc => _mqAverage.average;
  int get mqAverageSamples => _mqAverage.count;
  int? get mqTrend => _mqAverage.trend;
  int? get mqGasIndex => _mqGas.index;
  String get mqGasStatus => _mqGas.status;
  int? get mqGasBaselineMv => _mqGas.baselineMv;

  void notifyListeners() {
    if (!_disposed) _changes.add(null);
  }

  Future<void> connect() async {
    if (_disposed) return;
    _wanted = true;
    _retry?.cancel();
    _retry = null;
    final generation = ++_generation;
    _closeTransport();
    snapshot = null;
    status = LocalWifiStatus.connecting;
    message = 'Menghubungkan Wi-Fi lokal…';
    notifyListeners();
    try {
      final socket = await Socket.connect(
        address,
        port,
        timeout: connectTimeout,
      );
      if (_disposed || generation != _generation) {
        socket.destroy();
        return;
      }
      _socket = socket;
      status = LocalWifiStatus.waiting;
      message = 'Wi-Fi lokal terhubung; menunggu sampel ESP32.';
      notifyListeners();
      if (_disposed || generation != _generation) return;
      _armDeadline(generation);
      _subscription = socket.listen(
        (bytes) => _receive(bytes, generation),
        onError: (Object _, StackTrace _) =>
            _fail(generation, 'Koneksi terputus; mencoba lagi.'),
        onDone: () => _fail(generation, 'Koneksi terputus; mencoba lagi.'),
        cancelOnError: true,
      );
    } catch (_) {
      _fail(
        generation,
        'Tidak terhubung. Pilih Wi-Fi Moss-xxxx di ponsel; mencoba lagi.',
      );
    }
  }

  void _receive(List<int> bytes, int generation) {
    if (_disposed || generation != _generation) return;
    for (final byte in bytes) {
      if (_disposed || generation != _generation) return;
      if (byte == 10) {
        final line = List<int>.of(_pending);
        _pending.clear();
        if (!_acceptLine(line, generation)) return;
      } else {
        _pending.add(byte);
        if (_pending.length > 4096) {
          _fail(generation, 'Data Wi-Fi lokal tidak valid.');
          return;
        }
      }
    }
  }

  bool _acceptLine(List<int> bytes, int generation) {
    try {
      final line = utf8.decode(bytes).trim();
      final json = jsonDecode(line);
      if (json is! Map<String, dynamic> ||
          json['type'] != 'sample' ||
          json['schema'] != 'serial_observation_2' ||
          json['firmware_version'] is! int ||
          (json['firmware_version'] as int) < 12) {
        throw const FormatException('Unexpected local sample');
      }
      final next = SerialSensorSnapshot.parse(line);
      final uptime = next.uptimeMs;
      if (uptime == null) throw const FormatException('Missing uptime');
      final previous = _lastUptime;
      if (previous != null) {
        final delta = (uptime - previous) & 0xffffffff;
        // Duplicate/old samples never refresh the live-data deadline.
        if (delta == 0 || delta >= 0x80000000) return true;
      }
      _lastUptime = uptime;
      _invalidFrames = 0;
      _mqAverage.add(next.mqAdc, uptime);
      _mqGas.update(next.mqPinMillivolts);
      snapshot = next;
      status = LocalWifiStatus.live;
      message = 'Wi-Fi lokal: sampel terbaru diterima di ponsel.';
      _armDeadline(generation);
      notifyListeners();
      return !_disposed && generation == _generation;
    } catch (_) {
      // One damaged line should not tear down a working stream. Keep the last
      // good sample until several consecutive frames are unusable.
      _invalidFrames++;
      if (_invalidFrames >= 3) {
        _fail(generation, 'Data Wi-Fi lokal tidak valid.');
        return false;
      }
      return true;
    }
  }

  void _armDeadline(int generation) {
    _deadline?.cancel();
    _deadline = Timer(
      sampleTimeout,
      () => _fail(generation, 'Data Wi-Fi lokal terlambat; mencoba lagi.'),
    );
  }

  void _fail(int generation, String reason) {
    if (_disposed || generation != _generation) return;
    final retryGeneration = ++_generation;
    _closeTransport();
    snapshot = null;
    status = LocalWifiStatus.disconnected;
    message = reason;
    notifyListeners();
    // An explicit connection selection remains active until the user stops it.
    // Never retain a stale value while waiting for the next connection.
    if (_wanted && !_disposed && _generation == retryGeneration) {
      _retry?.cancel();
      _retry = Timer(reconnectDelay, () {
        _retry = null;
        if (_wanted && !_disposed && _generation == retryGeneration) {
          unawaited(connect());
        }
      });
    }
  }

  void disconnect() {
    if (_disposed) return;
    _wanted = false;
    _retry?.cancel();
    _retry = null;
    ++_generation;
    _closeTransport();
    snapshot = null;
    status = LocalWifiStatus.disconnected;
    message = 'Wi-Fi lokal belum terhubung.';
    notifyListeners();
  }

  void _closeTransport() {
    _deadline?.cancel();
    _deadline = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    _socket?.destroy();
    _socket = null;
    _pending.clear();
    _lastUptime = null;
    _invalidFrames = 0;
    _mqAverage.clear();
    _mqGas.reset();
  }

  void dispose() {
    _wanted = false;
    _retry?.cancel();
    _retry = null;
    _disposed = true;
    ++_generation;
    _closeTransport();
    unawaited(_changes.close());
  }
}
