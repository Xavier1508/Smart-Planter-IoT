import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'moss_app.dart';

class AppBuildInfo {
  const AppBuildInfo({
    required this.version,
    required this.build,
    required this.channel,
  });

  final String version;
  final int build;
  final String channel;

  static const _channel = MethodChannel('moss/build_info');

  static Future<AppBuildInfo?> read() async {
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>('read');
      final version = data?['version'];
      final build = data?['build'];
      final channel = data?['channel'];
      if (version is! String ||
          !RegExp(r'^[A-Za-z0-9.+-]{1,40}$').hasMatch(version) ||
          build is! int ||
          build < 0 ||
          (channel != 'production' && channel != 'beta')) {
        return null;
      }
      return AppBuildInfo(version: version, build: build, channel: channel);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

class AppVersionPanel extends StatefulWidget {
  const AppVersionPanel({super.key});

  @override
  State<AppVersionPanel> createState() => _AppVersionPanelState();
}

class _AppVersionPanelState extends State<AppVersionPanel> {
  late final Future<AppBuildInfo?> _info = AppBuildInfo.read();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.system_update_alt_rounded, color: forest, size: 21),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Versi & pembaruan',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 4),
              FutureBuilder<AppBuildInfo?>(
                future: _info,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Text(
                      'Memeriksa versi aplikasi...',
                      style: TextStyle(color: muted, fontSize: 12),
                    );
                  }
                  final info = snapshot.data;
                  if (info == null) {
                    return const Text(
                      'Info versi tidak tersedia pada perangkat ini.',
                      style: TextStyle(color: muted, fontSize: 12),
                    );
                  }
                  final description = info.channel == 'beta'
                      ? 'Beta privat dapat memeriksa pembaruan saat dibuka jika layanan dan akun tester siap. Instalasi memerlukan persetujuan.'
                      : 'Varian ini tidak memeriksa pembaruan Firebase secara otomatis.';
                  return Text(
                    'Versi ${info.version} · build ${info.build}\n$description',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
