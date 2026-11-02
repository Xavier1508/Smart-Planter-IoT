import 'package:flutter/material.dart';

import 'cloud_controller.dart';

const _forest = Color(0xFF315E48);
const _ink = Color(0xFF213027);
const _terracotta = Color(0xFFAE674F);

/// First-run gate for cloud mode. It is intentionally separate from Settings:
/// selecting online mode means signing in before the dashboard exists.
class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.controller,
    required this.onOffline,
  });

  final CloudController controller;
  final Future<void> Function() onOffline;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _obscure = true;
  String? _message;
  bool _messageIsError = false;

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_signUp) {
        final signedIn = await widget.controller.signUp(
          _email.text.trim(),
          _password.text,
        );
        if (!mounted) return;
        _messageIsError = false;
        _message = signedIn
            ? 'Akun dibuat. Anda sudah masuk ke mode online.'
            : 'Akun dibuat. Cek email untuk verifikasi, lalu masuk.';
      } else {
        await widget.controller.signIn(_email.text.trim(), _password.text);
        if (!mounted) return;
        _password.clear();
      }
    } catch (_) {
      if (mounted) {
        _messageIsError = true;
        _message = _signUp
            ? 'Pendaftaran gagal. Periksa email, kata sandi, dan koneksi.'
            : 'Masuk gagal. Periksa email dan kata sandi.';
      }
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BrandHero(
                        title: 'Selamat datang di Tunas',
                        subtitle:
                            'Masuk ke mode online untuk menyimpan sensor, '
                            'perintah, dan riwayat di cloud.',
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: colors.outlineVariant),
                          boxShadow: [
                            BoxShadow(
                              color: _ink.withValues(alpha: 0.05),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  label: Text('Masuk'),
                                  icon: Icon(Icons.login_rounded, size: 18),
                                ),
                                ButtonSegment(
                                  value: true,
                                  label: Text('Buat akun'),
                                  icon: Icon(Icons.person_add_alt_1, size: 18),
                                ),
                              ],
                              selected: {_signUp},
                              showSelectedIcon: false,
                              onSelectionChanged: _busy
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _signUp = value.first;
                                        _message = null;
                                      });
                                    },
                            ),
                            const SizedBox(height: 18),
                            TextFormField(
                              controller: _email,
                              enabled: !_busy,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.mail_outline_rounded),
                              ),
                              validator: (value) {
                                final text = value?.trim() ?? '';
                                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch(text)) {
                                  return 'Masukkan email yang valid.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _password,
                              enabled: !_busy,
                              obscureText: _obscure,
                              enableSuggestions: false,
                              autocorrect: false,
                              autofillHints: [
                                _signUp
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Kata sandi',
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Tampilkan kata sandi'
                                      : 'Sembunyikan kata sandi',
                                  onPressed: _busy
                                      ? null
                                      : () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if ((value ?? '').length < 6) {
                                  return 'Minimal 6 karakter.';
                                }
                                return null;
                              },
                            ),
                            if (_message != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _messageIsError
                                      ? colors.errorContainer
                                      : colors.secondaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _message!,
                                  style: TextStyle(
                                    color: _messageIsError
                                        ? colors.onErrorContainer
                                        : colors.onSecondaryContainer,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: _forest,
                                foregroundColor: Colors.white,
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _signUp ? 'Buat akun' : 'Masuk',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _signUp
                                  ? 'Setelah mendaftar, cek email jika verifikasi '
                                        'diaktifkan pada project Supabase.'
                                  : 'Sesi disimpan di penyimpanan privat '
                                        'aplikasi agar tidak perlu login ulang.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : widget.onOffline,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.wifi_off_rounded, size: 19),
                        label: const Text('Gunakan mode offline'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mode offline tidak meminta akun dan hanya memakai '
                        'Wi-Fi lokal perangkat. Riwayat tetap tersimpan di '
                        'penyimpanan aplikasi, tetapi tidak masuk cloud.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Mode online membutuhkan internet. Setelah setup '
                          'perangkat, pindah dari Wi-Fi Moss ke Wi-Fi rumah '
                          'atau data seluler. Jangan login saat ponsel masih '
                          'terhubung ke AP Moss yang tidak memiliki internet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PairingPage extends StatefulWidget {
  const PairingPage({
    super.key,
    required this.controller,
    required this.onOffline,
    required this.onSignOut,
  });

  final CloudController controller;
  final Future<void> Function() onOffline;
  final Future<void> Function() onSignOut;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final _hardware = TextEditingController();
  final _claimCode = TextEditingController();
  bool _busy = false;
  String? _message;

  Future<void> _claim() async {
    if (_busy) return;
    final hardware = _hardware.text.trim();
    final claim = _claimCode.text.trim();
    if (hardware.isEmpty || claim.isEmpty) {
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
        hardwareId: hardware,
        claimCode: claim,
      );
      if (mounted) {
        setState(() {
          _claimCode.clear();
          _message = 'Perangkat berhasil dipasangkan.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'Pairing gagal. Periksa ID, kode claim, dan masa berlaku kode.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _hardware.dispose();
    _claimCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BrandHero(
                    title: 'Pasangkan planter',
                    subtitle:
                        'Akun sudah aktif. Tinggal hubungkan perangkat '
                        'fisik ke akun ini.',
                  ),
                  const SizedBox(height: 18),
                  _StepStrip(
                    steps: const [
                      ('Akun', true),
                      ('Perangkat', false),
                      ('Dashboard', false),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.controller.status,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _busy
                                ? null
                                : widget.controller.refreshDevice,
                            icon: const Icon(Icons.refresh_rounded, size: 17),
                            label: const Text('Muat ulang perangkat'),
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _hardware,
                          enabled: !_busy,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'ID perangkat',
                            hintText: 'moss-c31c-xxxxxxxx',
                            prefixIcon: Icon(Icons.memory_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _claimCode,
                          enabled: !_busy,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Kode claim dari LCD',
                            prefixIcon: Icon(Icons.key_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          title: const Text(
                            'Di mana kode ini terlihat?',
                            style: TextStyle(fontSize: 13),
                          ),
                          children: [
                            Text(
                              'Sambungkan ponsel ke Wi-Fi Moss, buka '
                              'http://192.168.4.1/ untuk melihat ID perangkat. '
                              'Kode claim tampil di LCD selama 12 detik '
                              'pertama setelah perangkat menyala. Restart '
                              'perangkat jika terlewat.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _message!,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _busy ? null : _claim,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: _forest,
                            foregroundColor: Colors.white,
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Pasangkan perangkat',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _busy ? null : widget.onSignOut,
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text('Keluar akun'),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _busy ? null : widget.onOffline,
                          icon: const Icon(Icons.wifi_off_rounded, size: 18),
                          label: const Text('Mode offline'),
                        ),
                      ),
                    ],
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

class MossLoadingPage extends StatelessWidget {
  const MossLoadingPage({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFFDDE9DA),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.eco_rounded, color: _forest, size: 34),
          ),
          const SizedBox(height: 18),
          const CircularProgressIndicator(strokeWidth: 2.6),
          const SizedBox(height: 14),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    ),
  );
}

/// Shown inside Settings when the user chose local-only mode.
class OfflineModePanel extends StatelessWidget {
  const OfflineModePanel({
    super.key,
    required this.onGoOnline,
    this.onSignOut,
    this.signedIn = false,
  });
  final VoidCallback onGoOnline;
  final Future<void> Function()? onSignOut;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: _terracotta, size: 20),
              const SizedBox(width: 10),
              const Text(
                'Mode offline',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Aplikasi memakai Wi-Fi lokal ESP32. Data tidak dikirim ke cloud, '
            'tidak ada akun, dan tidak ada sinkronisasi antar perangkat.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: onGoOnline,
                icon: const Icon(Icons.cloud_outlined, size: 18),
                label: const Text('Masuk ke mode online'),
              ),
              if (signedIn && onSignOut != null)
                TextButton.icon(
                  onPressed: () => onSignOut!(),
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  label: const Text('Keluar akun'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: const Color(0xFFDDE9DA),
            borderRadius: BorderRadius.circular(23),
          ),
          child: const Icon(Icons.eco_rounded, color: _forest, size: 36),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StepStrip extends StatelessWidget {
  const _StepStrip({required this.steps});
  final List<(String, bool)> steps;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          if (index != 0)
            Expanded(
              child: Container(
                height: 1.5,
                color: colors.outlineVariant,
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: steps[index].$2
                      ? _forest
                      : colors.surfaceContainerHighest,
                ),
                child: Icon(
                  steps[index].$2 ? Icons.check_rounded : Icons.circle_outlined,
                  size: 15,
                  color: steps[index].$2 ? Colors.white : colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[index].$1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: steps[index].$2 ? _forest : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
