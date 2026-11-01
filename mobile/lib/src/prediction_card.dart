import 'package:flutter/material.dart';

import 'character_look.dart';
import 'moss_app.dart';
import 'plant_emotion.dart';

/// A compact, honest presentation of the demo model. It never claims a plant
/// diagnosis; it shows the emotion, the strongest signal and the short trend.
class PredictionCard extends StatelessWidget {
  const PredictionCard({super.key, required this.reading, required this.look});

  final EmotionReading reading;
  final CharacterLook look;

  @override
  Widget build(BuildContext context) {
    final colors = context.mossColors;
    final accent = switch (reading.emotion) {
      PlantEmotion.happy => const Color(0xFF3F7D58),
      PlantEmotion.neutral => const Color(0xFFB07A2A),
      PlantEmotion.alert => const Color(0xFFB45A45),
    };
    final icon = switch (reading.emotion) {
      PlantEmotion.happy => Icons.sentiment_satisfied_alt_rounded,
      PlantEmotion.neutral => Icons.sentiment_neutral_rounded,
      PlantEmotion.alert => Icons.sentiment_dissatisfied_rounded,
    };
    final trendIcon = switch (reading.trend) {
      ConditionTrend.improving => Icons.trending_up_rounded,
      ConditionTrend.stable => Icons.trending_flat_rounded,
      ConditionTrend.worsening => Icons.trending_down_rounded,
      ConditionTrend.unknown => Icons.more_horiz_rounded,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
              Text(
                'PREDIKSI KONDISI',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${reading.confidencePercent}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reading.emotion.label,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: accent,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reading.signal,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Icon(trendIcon, size: 18, color: accent),
                  const SizedBox(height: 2),
                  Text(
                    reading.trend.label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            reading.prediction,
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 7),
          Text(
            'Model demo ${look.name} · label sintetis, bukan diagnosis tanaman.',
            style: TextStyle(
              fontSize: 10,
              height: 1.3,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
