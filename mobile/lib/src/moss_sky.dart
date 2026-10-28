import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'appearance.dart';

/// A decorative sky driven by the phone clock or a locally selected preset.
class MossSky extends StatelessWidget {
  const MossSky({super.key, required this.sky, required this.child});

  final SkyAppearance sky;
  final Widget child;

  static Color foregroundFor(Color background) =>
      background.computeLuminance() > .179 ? Colors.black : Colors.white;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 1200);
    final sunProgress = ((sky.hour - 5) / 14).clamp(0.0, 1.0);
    final moonHour = sky.hour < 12 ? sky.hour + 24 : sky.hour;
    final moonProgress = ((moonHour - 18) / 12).clamp(0.0, 1.0);
    Alignment position(double progress) => Alignment(
      -.82 + 1.64 * progress,
      .55 - 1.2 * math.sin(progress * math.pi),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [sky.top, sky.bottom],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: duration,
                  opacity: sky.starsOpacity,
                  child: const CustomPaint(painter: _StarsPainter()),
                ),
              ),
            ),
            Positioned(
              top: 42,
              left: 12,
              right: 12,
              height: 190,
              child: IgnorePointer(
                child: Stack(
                  children: [
                    AnimatedAlign(
                      duration: duration,
                      curve: Curves.easeInOut,
                      alignment: position(sunProgress),
                      child: AnimatedOpacity(
                        duration: duration,
                        opacity: sky.sunOpacity,
                        child: const _CelestialBody(isSun: true),
                      ),
                    ),
                    AnimatedAlign(
                      duration: duration,
                      curve: Curves.easeInOut,
                      alignment: position(moonProgress),
                      child: AnimatedOpacity(
                        duration: duration,
                        opacity: sky.moonOpacity,
                        child: const _CelestialBody(isSun: false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _CelestialBody extends StatelessWidget {
  const _CelestialBody({required this.isSun});

  final bool isSun;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    height: 76,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            (isSun ? const Color(0xFFFFEDB2) : const Color(0xFFDCEAFF))
                .withValues(alpha: .42),
            Colors.transparent,
          ],
        ),
      ),
      child: Center(
        child: CustomPaint(
          size: const Size(34, 34),
          painter: _CelestialPainter(isSun: isSun),
        ),
      ),
    ),
  );
}

class _CelestialPainter extends CustomPainter {
  const _CelestialPainter({required this.isSun});

  final bool isSun;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (isSun) {
      final paint = Paint()..color = const Color(0xFFFFEAB0);
      canvas.drawCircle(center, 11, paint);
      paint
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final angle = i * math.pi / 4;
        final direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          center + direction * 14,
          center + direction * 17,
          paint,
        );
      }
    } else {
      final outer = Path()
        ..addOval(Rect.fromCircle(center: center, radius: 13));
      final cutout = Path()
        ..addOval(
          Rect.fromCircle(center: center + const Offset(6, -5), radius: 11),
        );
      canvas.drawPath(
        Path.combine(PathOperation.difference, outer, cutout),
        Paint()..color = const Color(0xFFF6F1CF),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CelestialPainter oldDelegate) =>
      oldDelegate.isSun != isSun;
}

class _StarsPainter extends CustomPainter {
  const _StarsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const points = [
      Offset(.08, .12),
      Offset(.23, .08),
      Offset(.38, .17),
      Offset(.64, .10),
      Offset(.83, .16),
      Offset(.93, .29),
      Offset(.12, .45),
      Offset(.29, .34),
      Offset(.76, .39),
      Offset(.9, .56),
      Offset(.18, .64),
      Offset(.7, .61),
    ];
    final paint = Paint()..color = const Color(0xFFE9F2FF);
    for (var i = 0; i < points.length; i++) {
      final point = Offset(
        points[i].dx * size.width,
        points[i].dy * size.height,
      );
      canvas.drawCircle(point, i % 3 == 0 ? 1.7 : 1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarsPainter oldDelegate) => false;
}
