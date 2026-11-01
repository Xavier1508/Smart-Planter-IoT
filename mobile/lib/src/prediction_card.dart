import 'package:flutter/material.dart';

import 'character_look.dart';
import 'moss_app.dart';
import 'plant_emotion.dart';

/// A compact, honest presentation of the model and its factor breakdown. The
/// score is a presentation summary, not a medical or agronomic diagnosis.
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
    final factors = reading.factors.take(4).toList(growable: false);
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
              Expanded(
                child: Text(
                  'ANALISIS KONDISI',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Skor ${reading.score}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: reading.score / 100,
              backgroundColor: colors.outlineVariant.withValues(alpha: .35),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 11),
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
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
                        if (reading.available)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              reading.modelLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
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
          if (factors.isNotEmpty) ...[
            const SizedBox(height: 11),
            for (final factor in factors) _FactorRow(factor: factor),
          ],
          const SizedBox(height: 8),
          Text(
            reading.prediction,
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
          if (reading.actions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Tindakan: ${reading.actions.first}',
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
          const SizedBox(height: 7),
          Text(
            'Analisis adaptif ${look.name} · pola sensor + agronomi, '
            'bukan diagnosis tanaman.',
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

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.factor});
  final ConditionFactor factor;

  @override
  Widget build(BuildContext context) {
    final colors = context.mossColors;
    final color = switch (factor.severity) {
      ConditionSeverity.good => const Color(0xFF3F7D58),
      ConditionSeverity.watch => const Color(0xFFB07A2A),
      ConditionSeverity.alert => const Color(0xFFB45A45),
    };
    final icon = switch (factor.severity) {
      ConditionSeverity.good => Icons.check_circle_outline_rounded,
      ConditionSeverity.watch => Icons.info_outline_rounded,
      ConditionSeverity.alert => Icons.error_outline_rounded,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          SizedBox(
            width: 70,
            child: Text(
              factor.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              factor.detail,
              style: const TextStyle(fontSize: 10.5, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
