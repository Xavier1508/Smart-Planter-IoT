import 'package:flutter/material.dart';

import 'moss_app.dart';

/// Sensor history is not stored yet; never fill the page with invented data.
class JournalPage extends StatelessWidget {
  const JournalPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
    children: [
      Text(
        'JURNAL TANAMAN',
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
          color: context.mossColors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 7),
      const Text(
        'Riwayat',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 38),
        decoration: BoxDecoration(
          color: context.mossColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.mossColors.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(
              Icons.history_rounded,
              color: context.mossColors.primary,
              size: 42,
            ),
            const SizedBox(height: 16),
            const Text(
              'Belum ada riwayat',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Penyimpanan riwayat belum tersedia. Pembacaan langsung tampil di halaman utama.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.mossColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
