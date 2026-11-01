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
  double _reaction = 0;
  double _reactionHold = 0;
  double _reactionSide = 0;
  double _targetReactionSide = -.55;
  double _lookHold = 0;
  int _nextPose = 0;
  int _targetPose = 0;
  final List<double> _poseWeights = [1, 0, 0];
  double windAmplitude = .06;
  bool idlePersonality = false;
  bool reduceMotion = false;

  /// Idle tempo multiplier. 1.0 is the original Moss rhythm.
  double speed = 1.0;
  MossFrame lastFrame = const MossFrame(
    yaw: 0,
    pitch: 0,
    roll: 0,
    shift: 0,
    leftArm: -.35,
    rightArm: .35,
    blink: 0,
    reaction: 0,
  );

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
    _lookHold = 0;
    // Reverse horizontal rotation based on the tester's observed direction.
    targetYaw = -x * maxYaw;
    targetPitch = y * maxPitch;
  }

  void release() {
    _lookHold = 0;
    targetYaw = 0;
    targetPitch = 0;
  }

  /// Briefly hold a gaze after a quick tap, then return to the neutral pose.
  void releaseAfter(double seconds) {
    if (!seconds.isFinite || seconds <= 0) {
      release();
    } else {
      _lookHold = seconds;
    }
  }

  /// A tap makes Moss gently lean away; repeated taps extend the reaction
  /// instead of restarting it abruptly. [horizontal] is -1 at the left edge.
  void tap({double horizontal = 0}) {
    if (reduceMotion) return;
    final x = horizontal.isFinite ? horizontal.clamp(-1.0, 1.0) : 0.0;
    _targetReactionSide = x.abs() < .12 ? -.55 : -x;
    _targetPose = _nextPose;
    _nextPose = (_nextPose + 1) % _poseWeights.length;
    _reactionHold = .38;
  }

  MossFrame advance(double deltaSeconds) {
    final dt = deltaSeconds.isFinite ? deltaSeconds.clamp(0.0, .05) : 0.0;
    if (reduceMotion) {
      _yaw = 0;
      _pitch = 0;
      _reaction = 0;
      _reactionHold = 0;
      _reactionSide = 0;
      _lookHold = 0;
      lastFrame = const MossFrame(
        yaw: 0,
        pitch: 0,
        roll: 0,
        shift: 0,
        leftArm: -.35,
        rightArm: .35,
        blink: 0,
        reaction: 0,
      );
      return lastFrame;
    }

    if (_lookHold > 0) {
      _lookHold -= dt;
      if (_lookHold <= 0) release();
    }
    final blend = 1 - math.exp(-6 * dt);
    _yaw += (targetYaw - _yaw) * blend;
    _pitch += (targetPitch - _pitch) * blend;
    _windTime += dt * (speed.isFinite ? speed.clamp(.5, 2.0) : 1.0);
    final reactionTarget = _reactionHold > 0 ? 1.0 : 0.0;
    _reactionHold = math.max(0.0, _reactionHold - dt);
    final responseTime = reactionTarget > _reaction ? .16 : .45;
    _reaction +=
        (reactionTarget - _reaction) * (1 - math.exp(-dt / responseTime));
    _reactionSide += (_targetReactionSide - _reactionSide) * blend;
    for (var i = 0; i < _poseWeights.length; i++) {
      final target = i == _targetPose ? 1.0 : 0.0;
      _poseWeights[i] += (target - _poseWeights[i]) * blend;
    }

    final wind = math.sin(_windTime * 1.2) * windAmplitude;
    final idleYaw = idlePersonality ? math.sin(_windTime * .43) * .08 : 0.0;
    final leftIdle = idlePersonality
        ? math.sin(_windTime * .8) * (.07 + .04 * math.sin(_windTime * .21))
        : 0.0;
    final rightIdle = idlePersonality
        ? math.sin(_windTime * .67 + 1.3) *
              (.07 + .04 * math.sin(_windTime * .25))
        : 0.0;
    final shy = _poseWeights[0];
    final wave = _poseWeights[1];
    final hide = _poseWeights[2];
    final idleBlinkTime = _windTime % 5.5;
    final idleBlink = idleBlinkTime > .18
        ? 0.0
        : math.sin((idleBlinkTime / .18) * math.pi);
    lastFrame = MossFrame(
      yaw: _yaw + idleYaw * (1 - _reaction) + _reactionSide * _reaction * .08,
      pitch: _pitch + _reaction * (.10 * shy + .035 * wave + .13 * hide),
      roll: wind - _reactionSide * _reaction * .085,
      shift: -_yaw / maxYaw * .05 + _reactionSide * _reaction * .035,
      // Both arms pivot toward the chest independently of the body.
      leftArm:
          -.35 +
          leftIdle * (1 - _reaction) +
          _reaction * (1.15 * shy + 1.05 * wave + .35 * hide),
      rightArm:
          .35 +
          rightIdle * (1 - _reaction) -
          _reaction * (1.15 * shy + .35 * wave + 1.05 * hide),
      blink: math.max(idleBlink, _reaction * .65),
      reaction: _reaction,
    );
    return lastFrame;
  }
}

class MossFrame {
  const MossFrame({
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.shift,
    required this.leftArm,
    required this.rightArm,
    required this.blink,
    required this.reaction,
  });
  final double yaw;
  final double pitch;
  final double roll;
  final double shift;
  final double leftArm;
  final double rightArm;
  final double blink;
  final double reaction;
}

/// Detects taps on a caller-provided 3D hit test without taking over scrolling.
class MossTouchSurface extends StatefulWidget {
  const MossTouchSurface({
    super.key,
    required this.motion,
    required this.child,
    required this.hitTest,
    this.onReact,
  });
  final MossMotion motion;
  final Widget child;
  final bool Function(Offset position, Size bounds) hitTest;
  final ValueChanged<Offset>? onReact;

  @override
  State<MossTouchSurface> createState() => _MossTouchSurfaceState();
}

class _MossTouchSurfaceState extends State<MossTouchSurface> {
  int? _pointer;
  Offset? _start;
  bool _moved = false;

  void _startPointer(PointerDownEvent event, Size size) {
    if (_pointer != null || !widget.hitTest(event.localPosition, size)) return;
    _pointer = event.pointer;
    _start = event.position;
    _moved = false;
  }

  void _movePointer(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if (_start != null && (event.position - _start!).distance > kTouchSlop) {
      _moved = true;
    }
  }

  void _endPointer(
    int pointer,
    Offset position,
    Size size, {
    bool cancelled = false,
  }) {
    if (pointer != _pointer) return;
    if (!cancelled && !_moved) {
      final horizontal = size.width > 0
          ? position.dx / size.width * 2 - 1
          : 0.0;
      widget.motion.tap(horizontal: horizontal);
      widget.onReact?.call(position);
    }
    _pointer = null;
    _start = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return Semantics(
        button: true,
        label: 'Karakter Moss; sentuh atau geser untuk berinteraksi',
        onTap: () {
          widget.motion.tap();
          widget.onReact?.call(Offset(size.width / 2, size.height / 2));
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _startPointer(event, size),
          onPointerMove: _movePointer,
          onPointerUp: (event) =>
              _endPointer(event.pointer, event.localPosition, size),
          onPointerCancel: (event) => _endPointer(
            event.pointer,
            event.localPosition,
            size,
            cancelled: true,
          ),
          child: widget.child,
        ),
      );
    },
  );
}
