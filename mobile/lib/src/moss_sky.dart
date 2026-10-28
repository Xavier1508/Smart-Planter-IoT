import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'appearance.dart';
import 'moss_gaze.dart';

/// A decorative sky driven by the phone clock or a locally selected preset.
class MossSky extends StatefulWidget {
  const MossSky({
    super.key,
    required this.sky,
    required this.child,
    this.gaze,
    this.atmosphere,
    this.onSwipe,
  });

  final SkyAppearance sky;
  final Widget child;
  final MossGaze? gaze;
  final MossAtmosphere? atmosphere;
  final ValueChanged<bool>? onSwipe;

  static Color foregroundFor(Color background) =>
      background.computeLuminance() > .179 ? Colors.black : Colors.white;

  @override
  State<MossSky> createState() => _MossSkyState();
}

class _MossSkyState extends State<MossSky>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _skyKey = GlobalKey();
  final _sunKey = GlobalKey();
  final _moonKey = GlobalKey();
  final _skyLook = Object();
  final _cometLook = Object();
  late final AnimationController _transition;
  late final AnimationController _comet;
  late SkyAppearance _visibleSky;
  late double _fromHour;
  late double _toHour;
  Timer? _cometTimer;
  Size _viewport = Size.zero;
  bool _reducedMotion = false;
  bool _tickerEnabled = true;
  bool _appActive = true;
  double _dragDistance = 0;

  @override
  void initState() {
    super.initState();
    _visibleSky = widget.sky;
    _fromHour = _toHour = widget.sky.hour;
    widget.atmosphere?.current = _visibleSky;
    _transition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      value: 1,
    )..addListener(_updateSky);
    _transition.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.gaze?.releaseAmbient(_skyLook);
        _scheduleComet();
      }
    });
    _comet = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addListener(_updateCometGaze);
    _comet.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.gaze?.releaseAmbient(_cometLook);
        _scheduleComet();
      }
    });
    _appActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewport = MediaQuery.sizeOf(context);
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if ((_reducedMotion || !_tickerEnabled) && _transition.isAnimating) {
      _finishTransition();
    }
    _scheduleComet();
  }

  @override
  void didUpdateWidget(covariant MossSky oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gaze != widget.gaze) {
      oldWidget.gaze?.releaseAmbient(_skyLook);
      oldWidget.gaze?.releaseAmbient(_cometLook);
    }
    widget.atmosphere?.current = _visibleSky;
    if (oldWidget.sky.hour == widget.sky.hour) return;
    _cometTimer?.cancel();
    _cometTimer = null;
    _comet.stop();
    _comet.value = 0;
    widget.gaze?.releaseAmbient(_cometLook);
    if (_reducedMotion || !_tickerEnabled || !_appActive) {
      _transition.stop();
      _fromHour = _toHour = widget.sky.hour;
      _visibleSky = widget.sky;
      widget.atmosphere?.current = _visibleSky;
      widget.gaze?.releaseAmbient(_skyLook);
      _scheduleComet();
      return;
    }
    _fromHour = _visibleSky.hour;
    // Traverse the shortest arc, including across midnight.
    final delta = ((widget.sky.hour - _fromHour + 36) % 24) - 12;
    _toHour = _fromHour + delta;
    _transition.forward(from: 0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive && _transition.isAnimating) _finishTransition();
    _scheduleComet();
  }

  void _finishTransition() {
    _transition.stop();
    _fromHour = _toHour = widget.sky.hour;
    // Notify the sky builder as well as updating the atmosphere immediately.
    _transition.value = 1;
    widget.gaze?.releaseAmbient(_skyLook);
  }

  bool get _canShowComet =>
      !_reducedMotion &&
      _tickerEnabled &&
      _appActive &&
      (_visibleSky.hour >= 18 || _visibleSky.hour < 4.5);

  void _scheduleComet() {
    _cometTimer?.cancel();
    _cometTimer = null;
    if (!_canShowComet) {
      _comet.stop();
      _comet.value = 0;
      widget.gaze?.releaseAmbient(_cometLook);
      return;
    }
    if (_transition.isAnimating || _comet.isAnimating) return;
    _cometTimer = Timer(const Duration(seconds: 35), () {
      _cometTimer = null;
      if (mounted && _canShowComet && !_transition.isAnimating) {
        _comet.forward(from: 0);
      }
    });
  }

  void _updateSky() {
    final value = Curves.easeInOutCubic.transform(_transition.value);
    _visibleSky = SkyAppearance.atHour(
      _fromHour + (_toHour - _fromHour) * value,
    );
    widget.atmosphere?.current = _visibleSky;
    if (_transition.isAnimating) {
      // Dawn looks to the sun; evening and night look to the moon.
      final hour = widget.sky.hour;
      final useMoon = hour >= 15 || hour < 4.5;
      _lookAtKey(useMoon ? _moonKey : _sunKey, _skyLook);
    }
  }

  void _updateCometGaze() {
    if (_comet.isAnimating) {
      final box = _skyKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        _lookAt(
          box.localToGlobal(_CometPainter.point(box.size, _comet.value)),
          _cometLook,
        );
      }
    }
  }

  void _lookAtKey(GlobalKey key, Object owner) {
    final box = key.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize && box.attached) {
      _lookAt(box.localToGlobal(box.size.center(Offset.zero)), owner);
    }
  }

  void _lookAt(Offset position, Object owner) {
    if (_viewport.width <= 0 || _viewport.height <= 0) return;
    widget.gaze?.followAmbient(owner, position, _viewport);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cometTimer?.cancel();
    widget.gaze?.releaseAmbient(_skyLook);
    widget.gaze?.releaseAmbient(_cometLook);
    _transition.dispose();
    _comet.dispose();
    super.dispose();
  }

  Alignment _position(double progress, {required bool isSun}) {
    final arc = math.sin(progress * math.pi);
    final side = .98 - .14 * arc;
    return Alignment(isSun ? -side : side, .38 - .70 * arc);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: widget.onSwipe == null
          ? null
          : (_) => _dragDistance = 0,
      onHorizontalDragUpdate: widget.onSwipe == null
          ? null
          : (event) => _dragDistance += event.primaryDelta ?? 0,
      onHorizontalDragEnd: widget.onSwipe == null
          ? null
          : (event) {
              final velocity = event.primaryVelocity ?? 0;
              if (_dragDistance.abs() >= 35 || velocity.abs() >= 450) {
                widget.onSwipe!(
                  (_dragDistance.abs() >= 35 ? _dragDistance : velocity) < 0,
                );
              }
            },
      child: ClipRRect(
        key: _skyKey,
        borderRadius: BorderRadius.circular(26),
        child: AnimatedBuilder(
          animation: _transition,
          child: widget.child,
          builder: (context, child) {
            final sky = _visibleSky;
            final sunProgress = ((sky.hour - 5) / 14).clamp(0.0, 1.0);
            final moonHour = sky.hour < 12 ? sky.hour + 24 : sky.hour;
            final moonProgress = ((moonHour - 18) / 12).clamp(0.0, 1.0);
            final moonOpacity = sky.visibleMoonOpacity;
            return AnimatedContainer(
              duration: Duration.zero,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [sky.top, sky.bottom],
                ),
              ),
              child: Stack(
                children: [
                  for (final glow in [
                    (
                      _position(sunProgress, isSun: true),
                      const Color(0xFFFFE3A9),
                      sky.sunOpacity,
                    ),
                    (
                      _position(moonProgress, isSun: false),
                      const Color(0xFFBDD9FF),
                      moonOpacity,
                    ),
                  ])
                    Positioned(
                      top: 38,
                      left: 0,
                      right: 0,
                      height: 200,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: glow.$1,
                              radius: .85,
                              colors: [
                                glow.$2.withValues(alpha: .13 * glow.$3),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: sky.starsOpacity,
                        child: CustomPaint(painter: const _StarsPainter()),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _CometPainter(_comet)),
                    ),
                  ),
                  Positioned(
                    top: 42,
                    left: 12,
                    right: 12,
                    height: 190,
                    child: IgnorePointer(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final diameter = math.min(
                            constraints.maxWidth,
                            (constraints.maxWidth * .34).clamp(62.0, 94.0),
                          );
                          return Stack(
                            children: [
                              Align(
                                alignment: _position(sunProgress, isSun: true),
                                child: Opacity(
                                  opacity: sky.sunOpacity,
                                  child: _CelestialBody(
                                    key: _sunKey,
                                    isSun: true,
                                    diameter: diameter,
                                    angle: sunProgress * math.pi * 2,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: _position(
                                  moonProgress,
                                  isSun: false,
                                ),
                                child: Opacity(
                                  opacity: moonOpacity,
                                  child: _CelestialBody(
                                    key: _moonKey,
                                    isSun: false,
                                    diameter: diameter,
                                    angle: moonProgress * .7 - .35,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  child!,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CelestialBody extends StatelessWidget {
  const _CelestialBody({
    super.key,
    required this.isSun,
    required this.diameter,
    required this.angle,
  });

  final bool isSun;
  final double diameter;
  final double angle;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: diameter,
    height: diameter,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            (isSun ? const Color(0xFFFFEDB2) : const Color(0xFFDCEAFF))
                .withValues(alpha: .50),
            Colors.transparent,
          ],
        ),
      ),
      child: Center(
        child: SizedBox(
          key: ValueKey(isSun ? 'moss-sun-disc' : 'moss-moon-disc'),
          width: diameter * .55,
          height: diameter * .55,
          child: Transform.rotate(
            angle: angle,
            child: CustomPaint(painter: _CelestialPainter(isSun: isSun)),
          ),
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
    final unit = size.shortestSide;
    if (isSun) {
      final radius = unit * .32;
      final paint = Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.35, -.35),
          colors: [Color(0xFFFFF6D3), Color(0xFFFFD579)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
      final rays = Paint()
        ..color = const Color(0xFFFFEAB0)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final angle = i * math.pi / 4;
        final direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          center + direction * (unit * .39),
          center + direction * (unit * .48),
          rays,
        );
      }
    } else {
      final outer = Path()
        ..addOval(Rect.fromCircle(center: center, radius: unit * .38));
      final cutout = Path()
        ..addOval(
          Rect.fromCircle(
            center: center + Offset(unit * .18, -unit * .15),
            radius: unit * .32,
          ),
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

class _CometPainter extends CustomPainter {
  _CometPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  static Offset point(Size size, double progress) => Offset(
    size.width * (.85 - .58 * progress),
    size.height * (.10 + .27 * progress),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final head = point(size, t);
    final direction = Offset(-size.width * .58, size.height * .27);
    if (direction.distance <= 0) return;
    final tail = head - direction / direction.distance * 25;
    final alpha = math.sin(math.pi * t).clamp(0.0, 1.0);
    final streak = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Colors.transparent,
          const Color(0xFFE8F3FF).withValues(alpha: alpha * .75),
        ],
      ).createShader(Rect.fromPoints(tail, head))
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tail, head, streak);
    canvas.drawCircle(
      head,
      1.8,
      Paint()..color = const Color(0xFFF6FBFF).withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(covariant _CometPainter oldDelegate) =>
      oldDelegate.progress != progress;
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
