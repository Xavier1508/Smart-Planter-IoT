import 'package:flutter/material.dart';

import 'local_wifi.dart';
import 'wifi_provisioning.dart';

/// Mandatory local-only entry gate. The dashboard is not built until the phone
/// is on the ESP32's `Moss` AP. Android still requires the system Wi-Fi consent
/// dialog; this gate never claims to force Wi-Fi silently.
class LocalMossGate extends StatefulWidget {
  const LocalMossGate({super.key, required this.child});

  final Widget child;

  @override
  State<LocalMossGate> createState() => _LocalMossGateState();
}

class _LocalMossGateState extends State<LocalMossGate> {
  final _provisioning = const WifiProvisioning();
  bool _checking = true;
  bool _connected = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<bool> _probeMoss() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final ok = await LocalWifiController.probe(
        address: '192.168.4.1',
        port: 3333,
        timeout: const Duration(milliseconds: 1500),
      );
      if (ok) return true;
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    return false;
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() {
      _checking = true;
      _message = null;
    });
    final ssid = await _provisioning.currentSsid();
    // Never trust the SSID alone: Android can keep a stale/saved Moss entry
    // while the app is bound to a different network. The TCP probe is the
    // only proof that this is the ESP32 we can actually read.
    final reachable = await _probeMoss();
    if (!mounted) return;
    setState(() {
      _connected = reachable;
      _checking = false;
      if (!reachable) {
        _message = ssid == WifiProvisioning.mossSsid
            ? 'Wi-Fi Moss terdeteksi, tetapi 192.168.4.1:3333 belum '
                  'merespons. Jika ada dua "Moss" di pengaturan Wi-Fi, '
                  'lupakan entri lama lalu sambungkan ulang.'
            : 'HP belum terhubung ke Wi-Fi Moss. Sambungkan untuk mulai '
                  'memantau tanaman. Tidak perlu internet.';
      }
    });
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _provisioning.connect();
      await _check();
      if (!mounted) return;
      if (!_connected) {
        setState(() {
          _message =
              'Wi-Fi sudah disetujui Android, tetapi perangkat belum bisa '
              'dijangkau di 192.168.4.1:3333. Jika ada dua "Moss" di '
              'pengaturan Wi-Fi, lupakan yang lama lalu coba lagi.';
        });
      }
    } on WifiProvisioningException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _messageFor(error);
      });
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  String _messageFor(WifiProvisioningException error) {
    if (error.permissionDenied) {
      return 'Izin Wi-Fi/perangkat di sekitar ditolak. Beri izin lalu coba lagi.';
    }
    if (error.unsupported) {
      return 'HP ini tidak mendukung koneksi Wi-Fi otomatis dari aplikasi. '
          'Sambungkan manual ke Wi-Fi Moss (sandi 15082005).';
    }
    if (error.unavailable) {
      return 'AP Moss belum terdeteksi. Pastikan ESP32 menyala dan berada '
          'dekat HP, lalu coba lagi.';
    }
    return error.message?.trim().isNotEmpty == true
        ? error.message!
        : 'Belum bisa terhubung ke Moss. Coba lagi.';
  }

  @override
  Widget build(BuildContext context) {
    if (_connected) return widget.child;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      Icons.wifi_tethering_rounded,
                      size: 34,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Sambungkan ke Moss',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aplikasi ini bekerja penuh di jaringan lokal. HP harus '
                    'terhubung ke Wi-Fi Moss milik ESP32; tidak perlu internet.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Wi-Fi perangkat',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'SSID: Moss\nSandi: 15082005',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            height: 1.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_checking) ...[
                    const SizedBox(height: 18),
                    const LinearProgressIndicator(minHeight: 5),
                    const SizedBox(height: 8),
                    Text(
                      'Memeriksa koneksi Moss...',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                  if (_message case final message?) ...[
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: TextStyle(
                        color: colors.error,
                        height: 1.45,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _checking || _busy ? null : _connect,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_rounded),
                    label: Text(
                      _busy ? 'Menghubungkan...' : 'Sambungkan sekarang',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _checking || _busy ? null : _check,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Cek ulang koneksi'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Jika pengaturan Wi-Fi HP menampilkan dua "Moss", lupakan '
                    'jaringan Moss lama yang tidak dipakai. Aplikasi memakai '
                    'koneksi yang benar-benar bisa membaca 192.168.4.1:3333.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Jika dialog izin Android muncul, pilih Allow. Setelah '
                    'terhubung, dashboard lokal akan terbuka otomatis.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
