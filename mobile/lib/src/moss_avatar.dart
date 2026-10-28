import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:vector_math/vector_math.dart' as vm;

import 'moss_app.dart';
import 'moss_motion.dart';
import 'plant_state.dart';

/// An original, low-poly placeholder character composed from 3D primitives.
/// It can be replaced with a properly rigged character without changing the
/// dashboard's plant-state interface.
class MossAvatar extends StatefulWidget {
  const MossAvatar({super.key, required this.mood});
  final PlantMood mood;

  @override
  State<MossAvatar> createState() => _MossAvatarState();
}

class _MossAvatarState extends State<MossAvatar>
    with SingleTickerProviderStateMixin {
  late final Future<void> _ready;
  late final scene.SphereGeometry _sphere;
  late final scene.CylinderGeometry _pot;
  late final scene.CylinderGeometry _soil;
  late final scene.CylinderGeometry _rim;
  late final scene.CylinderGeometry _dress;
  late final scene.UnlitMaterial _skin;
  late final scene.UnlitMaterial _hair;
  late final scene.UnlitMaterial _leaf;
  late final scene.UnlitMaterial _leafLight;
  late final scene.UnlitMaterial _clothes;
  late final scene.UnlitMaterial _potColor;
  late final scene.UnlitMaterial _soilColor;
  late final scene.UnlitMaterial _ink;
  late final scene.UnlitMaterial _cheek;
  late final scene.UnlitMaterial _highlight;
  late final scene.UnlitMaterial _potLight;
  final _motion = MossMotion();
  late final _sway = _Sway(_motion);
  late final _leftBlink = _Blink(_motion);
  late final _rightBlink = _Blink(_motion);
  late final AnimationController _touchFeedback;
  Offset _touchPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _touchFeedback = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _ready = _prepare();
  }

  @override
  void dispose() {
    _touchFeedback.dispose();
    super.dispose();
  }

  void _react(Offset position) {
    if (_motion.reduceMotion) return;
    setState(() => _touchPosition = position);
    _touchFeedback.forward(from: 0);
  }

  scene.UnlitMaterial _material(double r, double g, double b) =>
      scene.UnlitMaterial()..baseColorFactor = vm.Vector4(r, g, b, 1);

  Future<void> _prepare() async {
    await scene.Scene.initializeStaticResources();
    _sphere = scene.SphereGeometry(radius: 1, segments: 20, rings: 12);
    _pot = scene.CylinderGeometry(
      bottomRadius: .31,
      topRadius: .42,
      height: .45,
      radialSegments: 24,
    );
    _soil = scene.CylinderGeometry(
      bottomRadius: .40,
      topRadius: .40,
      height: .025,
      radialSegments: 24,
    );
    _rim = scene.CylinderGeometry(
      bottomRadius: .42,
      topRadius: .43,
      height: .08,
      radialSegments: 24,
    );
    _dress = scene.CylinderGeometry(
      bottomRadius: .30,
      topRadius: .12,
      height: .56,
      radialSegments: 20,
    );
    _skin = _material(.85, .68, .51);
    _hair = _material(.12, .26, .19);
    _leaf = _material(.22, .42, .29);
    _leafLight = _material(.43, .63, .36);
    _clothes = _material(.31, .50, .32);
    _potColor = _material(.65, .34, .24);
    _soilColor = _material(.25, .18, .12);
    _ink = _material(.11, .16, .12);
    _cheek = _material(.82, .43, .37);
    _highlight = _material(.98, .91, .72);
    _potLight = _material(.79, .48, .34);
  }

  scene.SceneMesh _oval({
    required scene.Material material,
    required double x,
    required double y,
    required double z,
    required double sx,
    required double sy,
    required double sz,
    double angle = 0,
  }) => scene.SceneMesh(
    geometry: _sphere,
    material: material,
    position: vm.Vector3(x, y, z),
    scale: vm.Vector3(sx, sy, sz),
    rotation: vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), angle),
  );

  scene.SceneNode _eye(double x, _Blink blink) => scene.SceneNode(
    position: vm.Vector3(x, .81, .355),
    components: [blink],
    children: [
      _oval(material: _ink, x: 0, y: 0, z: 0, sx: .027, sy: .037, sz: .02),
      _oval(
        material: _highlight,
        x: -.007,
        y: .010,
        z: .019,
        sx: .008,
        sy: .009,
        sz: .006,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Karakter Moss, ${widget.mood.label}',
      child: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Icon(Icons.spa_outlined, color: forest, size: 80),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          _motion.windAmplitude = widget.mood == PlantMood.content ? .07 : .025;
          _motion.reduceMotion = MediaQuery.disableAnimationsOf(context);
          final concerned =
              widget.mood == PlantMood.thirsty ||
              widget.mood == PlantMood.airConcern;
          final mouthY = concerned ? .76 : .72;
          return MossTouchSurface(
            motion: _motion,
            onReact: _react,
            child: Stack(
              fit: StackFit.expand,
              children: [
                scene.SceneView.declarative(
                  pixelRatio: MediaQuery.devicePixelRatioOf(context)
                      .clamp(1.0, 1.5),
                  camera: scene.PerspectiveCamera(
                    position: vm.Vector3(0, .45, 3.2),
                    target: vm.Vector3(0, .42, 0),
                  ),
                  children: [
                    scene.SceneMesh(
                      geometry: _pot,
                      material: _potColor,
                      position: vm.Vector3(0, -.38, 0),
                    ),
                    scene.SceneMesh(
                      geometry: _soil,
                      material: _soilColor,
                      position: vm.Vector3(0, -.14, 0),
                    ),
                    scene.SceneMesh(
                      geometry: _rim,
                      material: _potLight,
                      position: vm.Vector3(0, -.17, 0),
                    ),
                    scene.SceneNode(
                      position: vm.Vector3(0, -.12, 0),
                      components: [_sway],
                      children: [
                        scene.SceneMesh(
                          geometry: _dress,
                          material: _clothes,
                          position: vm.Vector3(0, .19, 0),
                        ),
                        _oval(
                          material: _leafLight,
                          x: 0,
                          y: .28,
                          z: .17,
                          sx: .055,
                          sy: .075,
                          sz: .018,
                          angle: .55,
                        ),
                        _oval(
                          material: _skin,
                          x: 0,
                          y: .51,
                          z: .01,
                          sx: .09,
                          sy: .12,
                          sz: .08,
                        ),
                        _oval(
                          material: _hair,
                          x: 0,
                          y: .79,
                          z: -.08,
                          sx: .37,
                          sy: .40,
                          sz: .29,
                        ),
                        _oval(
                          material: _skin,
                          x: 0,
                          y: .77,
                          z: .12,
                          sx: .30,
                          sy: .31,
                          sz: .25,
                        ),
                        _oval(
                          material: _hair,
                          x: -.27,
                          y: .67,
                          z: .02,
                          sx: .10,
                          sy: .29,
                          sz: .14,
                          angle: -.12,
                        ),
                        _oval(
                          material: _hair,
                          x: .27,
                          y: .67,
                          z: .02,
                          sx: .10,
                          sy: .29,
                          sz: .14,
                          angle: .12,
                        ),
                        _oval(
                          material: _leaf,
                          x: -.18,
                          y: 1.14,
                          z: -.02,
                          sx: .10,
                          sy: .22,
                          sz: .045,
                          angle: -.75,
                        ),
                        _oval(
                          material: _leafLight,
                          x: .10,
                          y: 1.16,
                          z: -.02,
                          sx: .09,
                          sy: .19,
                          sz: .04,
                          angle: .55,
                        ),
                        _eye(-.115, _leftBlink),
                        _eye(.115, _rightBlink),
                        _oval(
                          material: _highlight,
                          x: 0,
                          y: .765,
                          z: .372,
                          sx: .018,
                          sy: .014,
                          sz: .009,
                        ),
                        _oval(
                          material: _cheek,
                          x: -.18,
                          y: .70,
                          z: .335,
                          sx: .045,
                          sy: .022,
                          sz: .01,
                        ),
                        _oval(
                          material: _cheek,
                          x: .18,
                          y: .70,
                          z: .335,
                          sx: .045,
                          sy: .022,
                          sz: .01,
                        ),
                        _oval(
                          material: _ink,
                          x: -.035,
                          y: mouthY,
                          z: .366,
                          sx: .018,
                          sy: .014,
                          sz: .01,
                        ),
                        _oval(
                          material: _ink,
                          x: 0,
                          y: concerned ? mouthY + .015 : mouthY - .015,
                          z: .372,
                          sx: .019,
                          sy: .014,
                          sz: .01,
                        ),
                        _oval(
                          material: _ink,
                          x: .035,
                          y: mouthY,
                          z: .366,
                          sx: .018,
                          sy: .014,
                          sz: .01,
                        ),
                        _oval(
                          material: _skin,
                          x: -.27,
                          y: .27,
                          z: .02,
                          sx: .055,
                          sy: .18,
                          sz: .055,
                          angle: -.35,
                        ),
                        _oval(
                          material: _skin,
                          x: .27,
                          y: .27,
                          z: .02,
                          sx: .055,
                          sy: .18,
                          sz: .055,
                          angle: .35,
                        ),
                      ],
                    ),
                  ],
                ),
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _touchFeedback,
                    builder: (context, _) => CustomPaint(
                      painter: _TouchSparkles(
                        _touchPosition,
                        _touchFeedback.value,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Sway extends scene.Component {
  _Sway(this.motion);
  final MossMotion motion;

  @override
  void update(double deltaSeconds) {
    final frame = motion.advance(deltaSeconds);
    final yaw = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), frame.yaw);
    final pitch = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), frame.pitch);
    final wind = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), frame.roll);
    node.rotation = yaw * pitch * wind;
    node.position = vm.Vector3(frame.shift, -.12 + frame.bounce, 0);
  }
}

class _Blink extends scene.Component {
  _Blink(this.motion);

  final MossMotion motion;

  @override
  void update(double deltaSeconds) {
    node.scale = vm.Vector3(1, 1 - motion.lastFrame.blink * .86, 1);
  }
}

class _TouchSparkles extends CustomPainter {
  const _TouchSparkles(this.position, this.progress);

  final Offset position;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(
      position.dx.clamp(0.0, size.width),
      position.dy.clamp(0.0, size.height),
    );
    final opacity = math.sin(progress * math.pi).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = const Color(0xFFFFF2CA).withValues(alpha: opacity)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final ring = Paint()
      ..color = const Color(0xFFFFF2CA).withValues(alpha: opacity * .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 6 + progress * 21, ring);
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2 + math.pi / 4;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final point = center + direction * (14 + progress * 27);
      canvas.drawLine(point - direction * 3, point + direction * 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TouchSparkles oldDelegate) =>
      oldDelegate.position != position || oldDelegate.progress != progress;
}
