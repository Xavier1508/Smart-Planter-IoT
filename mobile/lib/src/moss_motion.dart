import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Movement is an expressive UI effect, not a measurement of plant health.
class MossMotion {
  static const maxYaw = .30;
  static const maxPitch = .16;

  double targetYaw = 0;
  double targetPitch = 0;
  double _yaw = 0;
  double _pitch = 0;
  double _windTime = 0;
  double _tapTime = double.infinity;
  double windAmplitude = .06;
  bool reduceMotion = false;

  /// The character follows the pointer without requiring a 3D hit-test.
  void lookAt(Offset position, Size bounds) {
    if (bounds.width <= 0 ||
        bounds.height <= 0 ||
        !position.dx.isFinite ||
        !position.dy.isFinite ||
        !bounds.width.isFinite ||
        !bounds.height.isFinite) {
      return;
    }
    final x = ((position.dx / bounds.width) * 2 - 1).clamp(-1.0, 1.0);
    final y = ((position.dy / bounds.height) * 2 - 1).clamp(-1.0, 1.0);
    targetYaw = x * maxYaw;
    targetPitch = y * maxPitch;
  }

  void release() {
    targetYaw = 0;
    targetPitch = 0;
  }

  void tap() {
    if (!reduceMotion) _tapTime = 0;
  }

  MossFrame advance(double deltaSeconds) {
    final dt = deltaSeconds.isFinite ? deltaSeconds.clamp(0.0, .05) : 0.0;
    final blend = reduceMotion ? 1.0 : 1 - math.exp(-8 * dt);
    _yaw += (targetYaw - _yaw) * blend;
    _pitch += (targetPitch - _pitch) * blend;
    _windTime += dt;
    _tapTime += dt;

    final wind = reduceMotion ? 0.0 : math.sin(_windTime * 1.2) * windAmplitude;
    final bounce = reduceMotion || _tapTime > .45
        ? 0.0
        : math.sin((_tapTime / .45) * math.pi) * .045;
    return MossFrame(yaw: _yaw, pitch: _pitch, roll: wind, bounce: bounce);
  }
}

class MossFrame {
  const MossFrame({
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.bounce,
  });
  final double yaw;
  final double pitch;
  final double roll;
  final double bounce;
}

/// Listens to pointer events without taking over the scrolling gesture arena.
class MossTouchSurface extends StatefulWidget {
  const MossTouchSurface({
    super.key,
    required this.motion,
    required this.child,
  });
  final MossMotion motion;
  final Widget child;

  @override
  State<MossTouchSurface> createState() => _MossTouchSurfaceState();
}

class _MossTouchSurfaceState extends State<MossTouchSurface> {
  int? _pointer;
  Offset? _start;
  bool _moved = false;

  void _startPointer(PointerDownEvent event, Size size) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _start = event.position;
    _moved = false;
    widget.motion.lookAt(event.localPosition, size);
  }

  void _movePointer(PointerMoveEvent event, Size size) {
    if (event.pointer != _pointer) return;
    if (_start != null && (event.position - _start!).distance > kTouchSlop) {
      _moved = true;
    }
    widget.motion.lookAt(event.localPosition, size);
  }

  void _endPointer(int pointer, {bool cancelled = false}) {
    if (pointer != _pointer) return;
    if (!cancelled && !_moved) widget.motion.tap();
    _pointer = null;
    _start = null;
    widget.motion.release();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return Semantics(
        button: true,
        label: 'Karakter Moss; sentuh atau geser untuk berinteraksi',
        onTap: widget.motion.tap,
        child: MouseRegion(
          onHover: (event) {
            if (_pointer == null) {
              widget.motion.lookAt(event.localPosition, size);
            }
          },
          onExit: (_) {
            if (_pointer == null) widget.motion.release();
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) => _startPointer(event, size),
            onPointerMove: (event) => _movePointer(event, size),
            onPointerUp: (event) => _endPointer(event.pointer),
            onPointerCancel: (event) =>
                _endPointer(event.pointer, cancelled: true),
            child: widget.child,
          ),
        ),
      );
    },
  );
}
