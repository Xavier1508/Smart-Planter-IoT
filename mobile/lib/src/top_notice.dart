import 'dart:async';

import 'package:flutter/material.dart';

OverlayEntry? _activeTopNotice;
Timer? _topNoticeTimer;

/// Shows a single transient card at the top of the app. Unlike an inline
/// banner, it does not change the page layout and it is not rebuilt by the
/// dashboard. Only one notice is visible at a time.
void showTopNotice(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.wifi_off_rounded,
  Duration duration = const Duration(seconds: 4),
}) {
  dismissTopNotice();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final entry = OverlayEntry(
    builder: (context) => _TopNoticeCard(
      title: title,
      message: message,
      icon: icon,
      onClose: dismissTopNotice,
    ),
  );
  _activeTopNotice = entry;
  overlay.insert(entry);
  _topNoticeTimer = Timer(duration, dismissTopNotice);
}

void dismissTopNotice() {
  _topNoticeTimer?.cancel();
  _topNoticeTimer = null;
  _activeTopNotice?.remove();
  _activeTopNotice = null;
}

class _TopNoticeCard extends StatelessWidget {
  const _TopNoticeCard({
    required this.title,
    required this.message,
    required this.icon,
    required this.onClose,
  });

  final String title;
  final String message;
  final IconData icon;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          left: 14,
          right: 14,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * -14),
                child: child,
              ),
            ),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              color: colors.surface,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 18, color: colors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            message,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
