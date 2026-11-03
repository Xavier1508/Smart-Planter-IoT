import 'package:flutter/material.dart';

/// Status reported by the Android update bridge, not a simulated percentage.
class UpdateProgress {
  const UpdateProgress({
    required this.status,
    required this.downloaded,
    required this.total,
  });

  final String status;
  final int downloaded;
  final int total;

  static UpdateProgress? fromEvent(Object? event) {
    if (event is! Map) return null;
    final status = event['status'];
    final downloaded = event['downloaded'];
    final total = event['total'];
    if (status is! String) return null;
    return UpdateProgress(
      status: status,
      downloaded: downloaded is int ? downloaded : -1,
      total: total is int ? total : -1,
    );
  }

  double? get fraction {
    if (downloaded < 0 || total <= 0 || downloaded > total) return null;
    return downloaded / total;
  }

  bool get isVisible => switch (status) {
    'PENDING' ||
    'DOWNLOADING' ||
    'DOWNLOADED' ||
    'DOWNLOAD_FAILED' ||
    'INSTALL_CANCELED' ||
    'INSTALL_FAILED' ||
    'UPDATE_FAILED' ||
    'REDIRECTED_TO_PLAY' => true,
    _ => false,
  };

  bool get isError => switch (status) {
    'DOWNLOAD_FAILED' ||
    'INSTALL_CANCELED' ||
    'INSTALL_FAILED' ||
    'UPDATE_FAILED' => true,
    _ => false,
  };

  bool get canDismiss =>
      isError || status == 'DOWNLOADED' || status == 'REDIRECTED_TO_PLAY';

  String get message => switch (status) {
    'CHECKING' => 'Memeriksa pembaruan Moss…',
    'PENDING' => 'Menyiapkan pembaruan…',
    'DOWNLOADING' => 'Mengunduh pembaruan Moss…',
    'DOWNLOADED' => 'Unduhan selesai. Lanjutkan pemasangan di Android.',
    'DOWNLOAD_FAILED' => 'Unduhan gagal. Coba lagi nanti.',
    'NEW_RELEASE_CHECK_FAILED' =>
      'Pembaruan belum dapat diperiksa. Coba lagi nanti.',
    'INSTALL_CANCELED' => 'Pemasangan dibatalkan; Moss yang lama tetap ada.',
    'INSTALL_FAILED' => 'Pemasangan gagal. Moss yang lama tetap ada.',
    'UPDATE_FAILED' => 'Pembaruan tidak selesai. Coba lagi nanti.',
    'REDIRECTED_TO_PLAY' => 'Lanjutkan pembaruan di Google Play.',
    _ => '',
  };
}

/// Displays SDK progress above every page without intercepting installer consent.
class UpdateProgressHost extends StatelessWidget {
  const UpdateProgressHost({
    super.key,
    required this.events,
    required this.child,
  });

  final Stream<Object?> events;
  final Widget child;

  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: events,
    builder: (context, snapshot) {
      final progress = snapshot.hasError
          ? null
          : UpdateProgress.fromEvent(snapshot.data);
      return Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (progress != null && progress.isVisible)
            Positioned(
              top: 8,
              left: 14,
              right: 14,
              child: SafeArea(
                bottom: false,
                child: _UpdateNotice(
                  key: ValueKey(progress.status),
                  progress: progress,
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _UpdateNotice extends StatefulWidget {
  const _UpdateNotice({super.key, required this.progress});
  final UpdateProgress progress;

  @override
  State<_UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends State<_UpdateNotice> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final progress = widget.progress;
    final colors = Theme.of(context).colorScheme;
    final downloading = progress.status == 'DOWNLOADING';
    final waiting =
        progress.status == 'CHECKING' || progress.status == 'PENDING';
    final fraction = downloading ? progress.fraction : null;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: colors.surfaceContainerHighest,
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    progress.isError
                        ? Icons.info_outline_rounded
                        : Icons.system_update_alt_rounded,
                    color: colors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      progress.message,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (fraction != null)
                    Text(
                      '${(fraction * 100).floor()}%',
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (progress.canDismiss)
                    IconButton(
                      tooltip: 'Tutup informasi pembaruan',
                      onPressed: () => setState(() => _dismissed = true),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              if (downloading || waiting) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: fraction,
                  semanticsLabel: downloading
                      ? 'Unduhan pembaruan'
                      : 'Pemeriksaan pembaruan',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
