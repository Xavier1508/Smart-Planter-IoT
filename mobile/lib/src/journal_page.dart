import 'package:flutter/material.dart';

import 'character_look.dart';
import 'moss_app.dart';
import 'plant_emotion.dart';
import 'plant_state.dart';
import 'profile_store.dart';

/// One phone-reception timestamp plus the decoded sample. The device uptime is
/// still the measurement clock; the local time is for the session timeline only.
class HistoryPoint {
  const HistoryPoint(this.at, this.state);

  final DateTime at;
  final PlantState state;
}

/// Session history. It is intentionally not presented as a permanent archive:
/// persistence is a separate feature and must not be implied by this page.
class JournalPage extends StatelessWidget {
  const JournalPage({
    super.key,
    required this.history,
    required this.profile,
    required this.emotion,
  });

  final List<HistoryPoint> history;
  final DeviceProfile profile;
  final EmotionReading emotion;

  @override
  Widget build(BuildContext context) {
    final colors = context.mossColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text(
          'JURNAL TANAMAN',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w800,
            color: colors.onSurfaceVariant,
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
        const SizedBox(height: 18),
        _CharacterSummary(profile: profile, emotion: emotion),
        const SizedBox(height: 16),
        if (history.isEmpty)
          _EmptyHistory(
            message: 'Belum ada sampel pada sesi ini. Hubungkan perangkat dan biarkan halaman terbuka agar riwayat terisi.',
          )
        else ...[
          _HistoryChart(history: history),
          const SizedBox(height: 10),
          Row(
            children: [
              _LegendDot(color: const Color(0xFF3F7D58), label: 'Tanah'),
              const SizedBox(width: 12),
              _LegendDot(color: const Color(0xFF3F7FA8), label: 'Air'),
              const SizedBox(width: 12),
              _LegendDot(color: const Color(0xFFB8862E), label: 'Cahaya'),
              const Spacer(),
              Text(
                '${history.length} sampel',
                style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'SESI INI',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final point in history.reversed.take(14))
            _HistoryRow(point: point),
          const SizedBox(height: 8),
          Text(
            'Riwayat sesi ini belum disimpan permanen; menutup aplikasi akan mengosongkannya.',
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _CharacterSummary extends StatelessWidget {
  const _CharacterSummary({required this.profile, required this.emotion});

  final DeviceProfile profile;
  final EmotionReading emotion;

  @override
  Widget build(BuildContext context) {
    final colors = context.mossColors;
    final look = profile.look;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(
              look.accentColor.withValues(alpha: .18),
              colors.surfaceContainerLowest,
            ),
            colors.surfaceContainerLowest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: look.clothesColor,
              shape: BoxShape.circle,
              border: Border.all(color: look.accentColor, width: 2),
            ),
            child: Icon(
              switch (look.accessory) {
                CharacterAccessory.leafCrown => Icons.eco_rounded,
                CharacterAccessory.sunHat => Icons.wb_sunny_rounded,
                CharacterAccessory.rainCloud => Icons.water_drop_rounded,
              },
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.charName,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  profile.deviceName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  emotion.available
                      ? '${emotion.emotion.label} · ${emotion.confidencePercent}%'
                      : 'Menunggu perangkat',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: look.accentColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
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
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.mossColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class _HistoryChart extends StatelessWidget {
  const _HistoryChart({required this.history});

  final List<HistoryPoint> history;

  @override
  Widget build(BuildContext context) => Container(
    height: 180,
    padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
    decoration: BoxDecoration(
      color: context.mossColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.mossColors.outlineVariant),
    ),
    child: CustomPaint(
      painter: _HistoryPainter(
        history: history.length > 60
            ? history.sublist(history.length - 60)
            : history,
        gridColor: context.mossColors.outlineVariant,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _HistoryPainter extends CustomPainter {
  const _HistoryPainter({required this.history, required this.gridColor});

  final List<HistoryPoint> history;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (history.isEmpty || size.width <= 0) return;
    _line(canvas, size, const Color(0xFF3F7D58), (state) => state.soilPercent);
    _line(
      canvas,
      size,
      const Color(0xFF3F7FA8),
      (state) => state.waterObservationPercent ?? state.waterPercent,
    );
    _line(canvas, size, const Color(0xFFB8862E), (state) => state.lightPercent);
  }

  void _line(
    Canvas canvas,
    Size size,
    Color color,
    int? Function(PlantState) valueOf,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final path = Path();
    var started = false;
    for (var i = 0; i < history.length; i++) {
      final value = valueOf(history[i].state);
      if (value == null) {
        started = false;
        continue;
      }
      final x = history.length == 1
          ? size.width / 2
          : size.width * i / (history.length - 1);
      final y = size.height * (1 - value.clamp(0, 100) / 100);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) =>
      oldDelegate.history != history || oldDelegate.gridColor != gridColor;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10)),
    ],
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.point});

  final HistoryPoint point;

  @override
  Widget build(BuildContext context) {
    final time = point.at;
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    final state = point.state;
    final soil = state.soilPercent;
    final water = state.waterObservationPercent ?? state.waterPercent;
    final light = state.lightPercent;
    final temperature = state.temperatureC;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.mossColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.mossColors.outlineVariant),
      ),
      child: Row(
        children: [
          Text(
            stamp,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.mossColors.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tanah ${_value(soil)} · Air ${_value(water)} · '
              'Cahaya ${_value(light)}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          if (temperature != null)
            Text(
              '${temperature.toStringAsFixed(1)}°C',
              style: TextStyle(
                fontSize: 10,
                color: context.mossColors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  static String _value(int? value) => value == null ? '—' : '$value%';
}
