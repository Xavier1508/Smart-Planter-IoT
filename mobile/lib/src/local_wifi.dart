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
    this.sampleTimeout = const Duration(seconds: 30),
    this.reconnectDelay = const Duration(seconds: 3),
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
  int? lastCommandId;
  bool? lastCommandOk;
  String? lastCommandError;
  int? lastPumpRemainingSeconds;

  Future<bool> sendControlCommand(String line) async {
    final socket = _socket;
    if (socket == null || _disposed) return false;
    try {
      socket.write('$line\n');
      await socket.flush().timeout(const Duration(seconds: 3));
      lastCommandError = null;
      return true;
    } on TimeoutException {
      lastCommandError = 'timeout';
      _fail(_generation, 'Perintah timeout; koneksi terputus.');
      return false;
    } catch (_) {
      lastCommandError = 'socket';
      _fail(_generation, 'Perintah gagal dikirim; koneksi terputus.');
      return false;
    }
  }

  void notifyListeners() {
    if (!_disposed) _changes.add(null);
  }

  /// Lightweight reachability check used by the dashboard to distinguish
  /// "phone is on the Moss AP" from "phone is on home Wi-Fi/cloud".
  static Future<bool> probe({
    String address = '192.168.4.1',
    int port = 3333,
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<void> connect() async {
    if (_disposed) return;
    // Pull-to-refresh and the settings button must not tear down a healthy
    // socket. Reconnect only after an explicit disconnect or a failed link;
    // the deadline/retry path still recovers a half-open stream.
    if (_wanted && status != LocalWifiStatus.disconnected) return;
    _wanted = true;
    _retry?.cancel();
    _retry = null;
    final generation = ++_generation;
    _closeTransport();
    // Keep the last good sample while reconnecting. The status and message
    // still say the link is down, so the UI can mark the values as stale
    // instead of incorrectly clearing every reading.
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
        'Tidak terhubung. Pilih Wi-Fi Moss di ponsel; mencoba lagi.',
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
      if (json is Map<String, dynamic> && json['type'] == 'ack') {
        lastCommandId = json['id'] is int ? json['id'] as int : null;
        lastCommandOk = json['ok'] == true;
        lastCommandError = json['error'] is String
            ? json['error'] as String
            : null;
        lastPumpRemainingSeconds = json['pump_remaining_s'] is int
            ? json['pump_remaining_s'] as int
            : null;
        notifyListeners();
        return true;
      }
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
    // A transient timeout or peer reset must not erase the last reading. The
    // disconnected status is enough to mark it stale; manual disconnect still
    // clears it explicitly.
    status = LocalWifiStatus.disconnected;
    message = reason;
    notifyListeners();
    // An explicit connection selection remains active until the user stops it.
    // The retained sample is marked stale by status/message, never presented
    // as a fresh live reading.
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
