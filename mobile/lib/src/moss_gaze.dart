import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Transient pointer coordinates only; no page content or taps are recorded.
class MossGaze extends ChangeNotifier {
  Offset? _pointerPosition;
  Size? _pointerViewport;
  bool _pointerActive = false;
  Offset? _ambientPosition;
  Size? _ambientViewport;
  Object? _ambientOwner;

  Offset? get position => _pointerActive ? _pointerPosition : _ambientPosition;
  Size? get viewport => _pointerActive ? _pointerViewport : _ambientViewport;
  bool get active => _pointerActive || _ambientOwner != null;

  /// Normalized direction from the rendered face to the last pointer.
  Offset? directionFrom(Offset face) {
    final point = position;
    final size = viewport;
    if (!active ||
        point == null ||
        size == null ||
        !face.dx.isFinite ||
        !face.dy.isFinite) {
      return null;
    }
    return Offset(
      ((point.dx - face.dx) / (size.width / 2)).clamp(-1.0, 1.0),
      ((point.dy - face.dy) / (size.height / 2)).clamp(-1.0, 1.0),
    );
  }

  void follow(Offset point, Size size) {
    if (!point.dx.isFinite ||
        !point.dy.isFinite ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    _pointerPosition = point;
    _pointerViewport = size;
    _pointerActive = true;
    notifyListeners();
  }

  void release() {
    if (!_pointerActive) return;
    _pointerActive = false;
    notifyListeners();
  }

  /// The user's pointer always has priority over visual sky events.
  void followAmbient(Object owner, Offset point, Size size) {
    if (!point.dx.isFinite ||
        !point.dy.isFinite ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    _ambientOwner = owner;
    _ambientPosition = point;
    _ambientViewport = size;
    if (!_pointerActive) notifyListeners();
  }

  void releaseAmbient(Object owner) {
    if (!identical(_ambientOwner, owner)) return;
    _ambientOwner = null;
    _ambientPosition = null;
    _ambientViewport = null;
    if (!_pointerActive) notifyListeners();
  }
}

/// Observes pointers above the app without entering its gesture arena.
class MossScreenTracker extends StatefulWidget {
  const MossScreenTracker({super.key, required this.gaze, required this.child});

  final MossGaze gaze;
  final Widget child;

  @override
  State<MossScreenTracker> createState() => _MossScreenTrackerState();
}

class _MossScreenTrackerState extends State<MossScreenTracker> {
  int? _pointer;

  void _finish(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    widget.gaze.release();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return MouseRegion(
        onExit: (_) {
          if (_pointer == null) widget.gaze.release();
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            if (_pointer != null) return;
            _pointer = event.pointer;
            widget.gaze.follow(event.position, size);
          },
          onPointerMove: (event) {
            if (event.pointer == _pointer) {
              widget.gaze.follow(event.position, size);
            }
          },
          onPointerHover: (event) {
            if (_pointer == null && event.kind == PointerDeviceKind.mouse) {
              widget.gaze.follow(event.position, size);
            }
          },
          onPointerUp: (event) => _finish(event.pointer),
          onPointerCancel: (event) => _finish(event.pointer),
          child: widget.child,
        ),
      );
    },
  );
}
