import 'package:flutter/material.dart';

import 'cloud_controller.dart';
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

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
              'Sesi hanya tersimpan selama aplikasi terbuka.',
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
