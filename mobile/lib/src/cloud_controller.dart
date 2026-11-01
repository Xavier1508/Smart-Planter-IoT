import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_command.dart';
import 'cloud_telemetry.dart';
import 'plant_telemetry.dart';

/// Owns the authenticated account and the currently selected device stream.
class CloudController extends ChangeNotifier {
  CloudController(this.client) : _telemetrySource = CloudTelemetry(client) {
    _authSubscription = client.auth.onAuthStateChange.listen(
      (event) => unawaited(_setUser(event.session?.user.id)),
      onError: (Object _, StackTrace _) => _authUnavailable(),
    );
    unawaited(_setUser(client.auth.currentSession?.user.id));
  }

  final SupabaseClient client;
  final CloudTelemetry _telemetrySource;
  late final StreamSubscription<AuthState> _authSubscription;
  String? _userId;
  String? _deviceId;
  PlanterDevice? _device;
  int _generation = 0;
  bool _disposed = false;
  String status = 'Masuk untuk melihat perangkat Anda.';
  Stream<PlantTelemetry>? telemetry;

  bool get signedIn => _userId != null;
  bool get hasDevice => !_disposed && _userId != null && _deviceId != null;
  bool get canExportCsv => hasDevice;
  bool get canControl => hasDevice;
  String? get deviceId => _deviceId;
  String? get hardwareId => _device?.hardwareId;
  String? get deviceName => _device?.name;
  int get sessionGeneration => _generation;

  Future<void> _setUser(String? userId, {bool force = false}) async {
    if (_disposed || (!force && userId == _userId)) return;
    _userId = userId;
    final generation = ++_generation;
    telemetry = null;
    _deviceId = null;
    _device = null;
    status = userId == null
        ? 'Masuk untuk melihat perangkat Anda.'
        : 'Mencari perangkat Anda...';
    notifyListeners();
    if (userId == null) return;
    try {
      final device = await _telemetrySource.firstDevice();
      if (_disposed || generation != _generation) return;
      if (device == null) {
        if (_device == null) {
          status = 'Belum ada perangkat yang dipasangkan.';
        }
      } else {
        _bindDevice(device);
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      status = 'Perangkat belum dapat dimuat. Periksa koneksi Anda.';
    }
    notifyListeners();
  }

  void _bindDevice(PlanterDevice device) {
    _device = device;
    _deviceId = device.id;
    telemetry = _telemetrySource.watchDevice(device.id);
    status = 'Perangkat: ${device.name}';
  }

  void _authUnavailable() {
    if (_disposed) return;
    ++_generation;
    _userId = null;
    _deviceId = null;
    _device = null;
    telemetry = null;
    status = 'Sesi tidak tersedia. Silakan masuk kembali.';
    notifyListeners();
  }

  Future<void> refreshDevice() => _setUser(_userId, force: true);

  /// Physical possession is proved with the claim code shown on the LCD. The
  /// database performs an atomic claim so two users cannot both succeed.
  Future<void> claimDevice({
    required String hardwareId,
    required String claimCode,
  }) async {
    final generation = _generation;
    final device = await _telemetrySource.claimDevice(
      hardwareId: hardwareId,
      claimCode: claimCode,
    );
    if (_disposed || generation != _generation) {
      throw const CloudReadException();
    }
    _bindDevice(device);
    status = 'Perangkat terpasang: ${device.name}';
    notifyListeners();
  }

  Future<CloudDatasetExport> exportDatasetCsv() async {
    final device = _device;
    final generation = _generation;
    if (!canExportCsv || device == null) throw const CloudReadException();
    final result = await _telemetrySource.exportDatasetCsv(
      deviceId: device.id,
      hardwareId: device.hardwareId,
    );
    if (_disposed || generation != _generation || _device?.id != device.id) {
      throw const CloudReadException();
    }
    return result;
  }

  Future<List<PlantTelemetry>> recentReadings({int limit = 240}) async {
    final device = _device;
    if (!hasDevice || device == null) return const [];
    return _telemetrySource.readRecent(device.id, limit: limit);
  }

  /// Reuses the existing CTRL syntax. The request UUID is retried with the same
  /// value, so an uncertain timeout cannot turn into a second pump pulse.
  Future<bool> sendControlLine(String line) async {
    if (!canControl) return false;
    final parsed = CloudControlCommand.parse(line);
    if (parsed == null) return false;
    final requestId = newCloudRequestId();
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await client
            .rpc(
              'request_actuator_command',
              params: {
                'p_device_id': _deviceId,
                'p_actuator': parsed.actuator,
                'p_action': parsed.action,
                'p_duration_seconds': parsed.durationSeconds,
                'p_client_request_id': requestId,
              },
            )
            .timeout(const Duration(seconds: 12));
        status = 'Perintah cloud terkirim; menunggu ack perangkat.';
        notifyListeners();
        return true;
      } on PostgrestException {
        status = 'Perintah cloud ditolak.';
        notifyListeners();
        return false;
      } on TimeoutException {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          continue;
        }
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          continue;
        }
      }
    }
    // The HTTP response may have been lost after the database committed. If
    // the command row exists, the action is pending or already acknowledged.
    try {
      final rows = await client
          .from('actuator_commands')
          .select('id')
          .eq('client_request_id', requestId)
          .limit(1)
          .timeout(const Duration(seconds: 8));
      if (rows.isNotEmpty) {
        status = 'Perintah diterima cloud; status ack belum pasti.';
        notifyListeners();
        return true;
      }
    } catch (_) {
      // Fall through to an explicit failure; no local command is invented.
    }
    status = 'Perintah cloud tidak terkonfirmasi.';
    notifyListeners();
    return false;
  }

  Future<MlCsvExport> exportTrainingCsv() async {
    final device = _device;
    final generation = _generation;
    if (!canExportCsv || device == null) throw const CloudReadException();
    final result = await _telemetrySource.exportTrainingCsv(device.id);
    if (_disposed || generation != _generation || _device?.id != device.id) {
      throw const CloudReadException();
    }
    return result;
  }

  Future<void> signIn(String email, String password) => client.auth
      .signInWithPassword(email: email, password: password)
      .timeout(const Duration(seconds: 20))
      .then((_) {});

  /// Returns false when email confirmation is needed before signing in.
  Future<bool> signUp(String email, String password) async {
    final response = await client.auth
        .signUp(email: email, password: password)
        .timeout(const Duration(seconds: 20));
    return response.session != null;
  }

  Future<void> signOut() =>
      client.auth.signOut().timeout(const Duration(seconds: 20));

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_authSubscription.cancel());
    super.dispose();
  }
}
