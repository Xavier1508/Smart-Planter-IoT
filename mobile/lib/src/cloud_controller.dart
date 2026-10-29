import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  int _generation = 0;
  bool _disposed = false;
  String status = 'Masuk untuk melihat perangkat Anda.';
  Stream<PlantTelemetry>? telemetry;

  bool get signedIn => _userId != null;
  bool get canExportCsv => !_disposed && _userId != null && _deviceId != null;
  int get sessionGeneration => _generation;

  Future<void> _setUser(String? userId, {bool force = false}) async {
    if (_disposed || (!force && userId == _userId)) return;
    _userId = userId;
    final generation = ++_generation;
    telemetry = null;
    _deviceId = null;
    status = userId == null
        ? 'Masuk untuk melihat perangkat Anda.'
        : 'Mencari perangkat Anda...';
    notifyListeners();
    if (userId == null) return;
    try {
      final device = await _telemetrySource.firstDevice();
      if (_disposed || generation != _generation) return;
      if (device == null) {
        status = 'Belum ada perangkat yang dipasangkan.';
      } else {
        _deviceId = device.id;
        telemetry = _telemetrySource.watchDevice(device.id);
        status = 'Perangkat: ${device.name}';
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      status = 'Perangkat belum dapat dimuat. Periksa koneksi Anda.';
    }
    notifyListeners();
  }

  void _authUnavailable() {
    if (_disposed) return;
    ++_generation;
    _userId = null;
    _deviceId = null;
    telemetry = null;
    status = 'Sesi tidak tersedia. Silakan masuk kembali.';
    notifyListeners();
  }

  Future<void> refreshDevice() => _setUser(_userId, force: true);

  Future<MlCsvExport> exportTrainingCsv() async {
    final deviceId = _deviceId;
    final generation = _generation;
    if (!canExportCsv || deviceId == null) throw const CloudReadException();
    final result = await _telemetrySource.exportTrainingCsv(deviceId);
    if (_disposed || generation != _generation || deviceId != _deviceId) {
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
