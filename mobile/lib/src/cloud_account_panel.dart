import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cloud_controller.dart';
import 'history_service.dart';
import 'moss_app.dart';

class CloudAccountPanel extends StatefulWidget {
  const CloudAccountPanel({super.key, required this.controller});
  final CloudController controller;

  @override
  State<CloudAccountPanel> createState() => _CloudAccountPanelState();
}

class _CloudAccountPanelState extends State<CloudAccountPanel> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _hardwareId = TextEditingController();
  final _claimCode = TextEditingController();
  bool _busy = false;
  String? _message;

  Future<void> _authenticate({required bool signUp}) async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _message = 'Isi email dan kata sandi terlebih dahulu.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (signUp) {
        final signedIn = await widget.controller.signUp(email, password);
        if (mounted) {
          setState(() {
            _message = signedIn
                ? 'Akun berhasil dibuat.'
                : 'Periksa email untuk verifikasi, lalu masuk.';
          });
        }
      } else {
        await widget.controller.signIn(email, password);
      }
      if (mounted) _password.clear();
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Tidak berhasil. Periksa akun, kata sandi, atau koneksi.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await widget.controller.signOut();
      if (mounted) _password.clear();
    } catch (_) {
      if (mounted) setState(() => _message = 'Tidak dapat keluar. Coba lagi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyTrainingCsv() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final generation = widget.controller.sessionGeneration;
    try {
      final result = await widget.controller.exportTrainingCsv();
      if (!mounted || generation != widget.controller.sessionGeneration) return;
      if (result.count == 0) {
        setState(() => _message = 'Belum ada data sensor untuk CSV.');
      } else {
        await Clipboard.setData(ClipboardData(text: result.csv));
        if (mounted && generation == widget.controller.sessionGeneration) {
          setState(() {
            _message =
                '${result.count} baris disalin. '
                'Label manual: ${result.summary.manuallyLabeled}. '
                'CSV berisi data privat; model ML belum tersedia.';
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'CSV belum dapat disalin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claimDevice() async {
    final hardwareId = _hardwareId.text.trim();
    final claimCode = _claimCode.text.trim();
    if (hardwareId.isEmpty || claimCode.isEmpty) {
      setState(() {
        _message = 'Isi ID perangkat dan kode claim dari layar LCD.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.controller.claimDevice(
        hardwareId: hardwareId,
        claimCode: claimCode,
      );
      if (mounted) {
        _claimCode.clear();
        setState(() => _message = 'Perangkat berhasil dipasangkan.');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'Pairing gagal. Periksa ID perangkat, kode claim, dan masa '
              'berlaku kode.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadDataset() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final generation = widget.controller.sessionGeneration;
    try {
      final result = await widget.controller.exportDatasetCsv();
      if (!mounted || generation != widget.controller.sessionGeneration) return;
      if (result.rows == 0) {
        setState(() => _message = 'Belum ada data sensor untuk diekspor.');
        return;
      }
      final path = await HistoryService().saveDataset(
        deviceId: result.hardwareId,
        csv: result.csv,
      );
      if (!mounted || generation != widget.controller.sessionGeneration) return;
      setState(() {
        _message = path == null
            ? '${result.rows} baris diunduh, tetapi file belum dapat disimpan.'
            : '${result.rows} baris tersimpan utuh: $path';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Dataset cloud belum dapat diunduh.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _hardwareId.dispose();
    _claimCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_outlined,
                color: context.mossColors.primary,
                size: 21,
              ),
              const SizedBox(width: 13),
              const Text(
                'Koneksi cloud',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.controller.status,
            style: TextStyle(
              color: context.mossColors.onSurfaceVariant,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (widget.controller.signedIn) ...[
            const SizedBox(height: 8),
            if (!widget.controller.hasDevice) ...[
              TextField(
                controller: _hardwareId,
                enabled: !_busy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'ID perangkat (moss-...)',
                  hintText: 'Tampil di LCD atau header lokal',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _claimCode,
                enabled: !_busy,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Kode claim LCD'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _claimDevice,
                child: const Text('Pasangkan perangkat'),
              ),
              const SizedBox(height: 4),
              const Text(
                'Kode claim hanya ditampilkan di layar fisik perangkat. '
                'Database mengikat perangkat ke akun secara atomik.',
                style: TextStyle(fontSize: 11),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : widget.controller.refreshDevice,
                    child: const Text('Periksa perangkat'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: const Text('Keluar'),
                  ),
                ],
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : widget.controller.refreshDevice,
                    child: const Text('Periksa perangkat'),
                  ),
                  FilledButton(
                    onPressed: _busy || !widget.controller.canExportCsv
                        ? null
                        : _downloadDataset,
                    child: const Text('Unduh dataset lengkap'),
                  ),
                  OutlinedButton(
                    onPressed: _busy || !widget.controller.canExportCsv
                        ? null
                        : _copyTrainingCsv,
                    child: const Text('Salin CSV ML'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: const Text('Keluar'),
                  ),
                ],
              ),
              const Text(
                'Dataset lengkap berisi semua baris cloud yang diizinkan RLS, '
                'satu header, timestamp UTC, sensor mentah, nilai turunan, '
                'perintah aktuator, dan alasan. Salinan utuh disimpan di '
                'penyimpanan privat aplikasi dan Downloads/Tunas.',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Kata sandi'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _authenticate(signUp: false),
                  child: const Text('Masuk'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _authenticate(signUp: true),
                  child: const Text('Buat akun'),
                ),
              ],
            ),
            Text(
              'Sesi disimpan di penyimpanan privat aplikasi agar dashboard '
              'tetap online setelah aplikasi dibuka ulang.',
              style: TextStyle(
                color: context.mossColors.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: TextStyle(
                color: context.mossColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
