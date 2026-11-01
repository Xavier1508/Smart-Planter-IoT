import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:vector_math/vector_math.dart' as vm;

import 'appearance.dart';
import 'character_look.dart';
import 'moss_app.dart';
import 'moss_gaze.dart';
import 'moss_motion.dart';
import 'plant_emotion.dart';
import 'plant_state.dart';

/// An original, stylized placeholder character composed from 3D primitives.
/// It can be replaced with a properly rigged character without changing the
/// dashboard's plant-state interface.
class MossAvatar extends StatefulWidget {
  const MossAvatar({
    super.key,
    required this.mood,
    required this.sky,
    required this.gaze,
    required this.atmosphere,
    this.look = CharacterLook.moss,
    this.emotion,
  });
  final PlantMood mood;
  final SkyAppearance sky;
  final MossGaze gaze;
  final MossAtmosphere atmosphere;
  final CharacterLook look;

  /// Presentation emotion from the demo model. Null keeps the original mood
  /// behavior for callers that only know the plant state.
  final PlantEmotion? emotion;

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
  late final scene.CylinderGeometry _hatBrim;
  late final scene.CylinderGeometry _hatTop;
  late final scene.PhysicallyBasedMaterial _skin;
  late final scene.PhysicallyBasedMaterial _hair;
  late final scene.PhysicallyBasedMaterial _leaf;
  late final scene.PhysicallyBasedMaterial _leafLight;
  late final scene.PhysicallyBasedMaterial _clothes;
  late final scene.PhysicallyBasedMaterial _potColor;
  late final scene.PhysicallyBasedMaterial _soilColor;
  late final scene.UnlitMaterial _ink;
  late final scene.PhysicallyBasedMaterial _cheek;
  late final scene.UnlitMaterial _highlight;
  late final scene.PhysicallyBasedMaterial _potLight;
  late final scene.PhysicallyBasedMaterial _hat;
  late final scene.PhysicallyBasedMaterial _cloud;
  late final scene.PhysicallyBasedMaterial _rain;
  final _sunLight = scene.DirectionalLight(
    color: vm.Vector3(1, .84, .65),
    intensity: 0,
    cacheStaticShadows: false,
    shadowCascadeCount: 1,
    shadowMapResolution: 512,
    shadowMaxDistance: 8,
    shadowSoftness: .08,
    shadowDepthBias: .008,
    shadowNormalBias: .012,
    shadowAmbientStrength: .12,
  );
  final _moonLight = scene.DirectionalLight(
    color: vm.Vector3(.58, .72, 1),
    intensity: 0,
    cacheStaticShadows: false,
    shadowCascadeCount: 1,
    shadowMapResolution: 512,
    shadowMaxDistance: 8,
    shadowSoftness: .08,
    shadowDepthBias: .008,
    shadowNormalBias: .012,
    shadowAmbientStrength: .12,
  );
  late final _sunKey = scene.DirectionalLightComponent(_sunLight);
  late final _moonKey = scene.DirectionalLightComponent(_moonLight);
  late final _sunAim = _SkyLightAim(
    widget.atmosphere,
    _sunLight,
    _moonLight,
    isSun: true,
  );
  late final _moonAim = _SkyLightAim(
    widget.atmosphere,
    _sunLight,
    _moonLight,
    isSun: false,
  );
  final _motion = MossMotion();
  late final _sway = _Sway(_motion);
  late final _headSway = _HeadSway(_motion);
  late final _leftArm = _ArmSway(_motion, isLeft: true);
  late final _rightArm = _ArmSway(_motion, isLeft: false);
  late final _leftBlink = _Blink(_motion);
  late final _rightBlink = _Blink(_motion);
  late final _leftBlush = _Blush(_motion);
  late final _rightBlush = _Blush(_motion);
  late final AnimationController _touchFeedback;
  final _sceneKey = GlobalKey();
  final _camera = scene.PerspectiveCamera(
    position: vm.Vector3(0, .45, 3.2),
    target: vm.Vector3(0, .42, 0),
  );
  Offset _touchPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _touchFeedback = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    widget.gaze.addListener(_followScreenPointer);
    _ready = _prepare();
  }

  @override
  void didUpdateWidget(covariant MossAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gaze != widget.gaze) {
      oldWidget.gaze.removeListener(_followScreenPointer);
      widget.gaze.addListener(_followScreenPointer);
    }
    if (oldWidget.atmosphere != widget.atmosphere) {
      _sunAim.atmosphere = widget.atmosphere;
      _moonAim.atmosphere = widget.atmosphere;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_motion.reduceMotion && _touchFeedback.value != 0) {
      _touchFeedback.stop();
      _touchFeedback.value = 0;
    }
  }

  @override
  void dispose() {
    widget.gaze.removeListener(_followScreenPointer);
    _touchFeedback.dispose();
    super.dispose();
  }

  void _followScreenPointer() {
    if (!widget.gaze.active) {
      _motion.releaseAfter(.6);
      return;
    }
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize || !render.attached) {
      return;
    }
    final face = _camera.worldToScreen(vm.Vector3(0, .65, .12), render.size);
    if (face == null) return;
    final direction = widget.gaze.directionFrom(render.localToGlobal(face));
    if (direction == null) return;
    _motion.lookAt(
      Offset(direction.dx + 1, direction.dy + 1),
      const Size(2, 2),
    );
  }

  bool _hitCharacter(Offset position, Size bounds) {
    if (!position.dx.isFinite ||
        !position.dy.isFinite ||
        !bounds.width.isFinite ||
        !bounds.height.isFinite ||
        bounds.width <= 0 ||
        bounds.height <= 0 ||
        !(Offset.zero & bounds).contains(position)) {
      return false;
    }
    final sceneContext = _sceneKey.currentContext;
    final scope = sceneContext
        ?.getInheritedWidgetOfExactType<scene.SceneScope>();
    if (scope == null) return false;
    final ray = _camera.screenPointToRay(position, bounds);
    return scope.scene.raycast(ray) != null;
  }

  void _react(Offset position) {
    if (_motion.reduceMotion) return;
    setState(() => _touchPosition = position);
    _touchFeedback.forward(from: 0);
  }

  scene.UnlitMaterial _unlit(double r, double g, double b) =>
      scene.UnlitMaterial()..baseColorFactor = vm.Vector4(r, g, b, 1);

  scene.PhysicallyBasedMaterial _material(
    double r,
    double g,
    double b, {
    double roughness = .8,
  }) => scene.PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(r, g, b, 1)
    ..metallicFactor = 0
    ..roughnessFactor = roughness;

  Future<void> _prepare() async {
    await scene.Scene.initializeStaticResources();
    _sphere = scene.SphereGeometry(radius: 1, segments: 32, rings: 20);
    _pot = scene.CylinderGeometry(
      bottomRadius: .31,
      topRadius: .42,
      height: .45,
      radialSegments: 32,
    );
    _soil = scene.CylinderGeometry(
      bottomRadius: .40,
      topRadius: .40,
      height: .025,
      radialSegments: 32,
    );
    _rim = scene.CylinderGeometry(
      bottomRadius: .42,
      topRadius: .43,
      height: .08,
      radialSegments: 32,
    );
    _dress = scene.CylinderGeometry(
      bottomRadius: .30,
      topRadius: .12,
      height: .56,
      radialSegments: 32,
    );
    _hatBrim = scene.CylinderGeometry(
      bottomRadius: .44,
      topRadius: .44,
      height: .035,
      radialSegments: 32,
    );
    _hatTop = scene.CylinderGeometry(
      bottomRadius: .23,
      topRadius: .19,
      height: .19,
      radialSegments: 32,
    );
    final look = widget.look;
    final skin = look.skinColor;
    final hair = look.hairColor;
    final clothes = look.clothesColor;
    final accent = look.accentColor;
    final accentLight = Color.lerp(accent, Colors.white, .30)!;
    _skin = _material(skin.r, skin.g, skin.b);
    _hair = _material(hair.r, hair.g, hair.b, roughness: .72);
    _leaf = _material(
      accent.r * .72,
      accent.g * .72,
      accent.b * .72,
      roughness: .58,
    );
    _leafLight = _material(
      accentLight.r,
      accentLight.g,
      accentLight.b,
      roughness: .58,
    );
    _clothes = _material(clothes.r, clothes.g, clothes.b);
    _potColor = _material(.65, .34, .24);
    _soilColor = _material(.25, .18, .12);
    _ink = _unlit(.11, .16, .12);
    final cheek = Color.lerp(skin, const Color(0xFFE06B5A), .45)!;
    _cheek = _material(cheek.r, cheek.g, cheek.b);
    _highlight = _unlit(.98, .91, .72);
    _potLight = _material(.79, .48, .34);
    _hat = _material(accent.r, accent.g, accent.b, roughness: .9);
    _cloud = _material(.92, .95, .96, roughness: .95);
    _rain = _material(
      accent.r * .55,
      accent.g * .72,
      accent.b * .95,
      roughness: .55,
    );
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

  scene.SceneNode _arm(double side, _ArmSway movement) => scene.SceneNode(
    position: vm.Vector3(side * .22, .41, .19),
    components: [movement],
    children: [
      _oval(material: _skin, x: 0, y: -.14, z: .01, sx: .050, sy: .15, sz: .05),
      _oval(
        material: _skin,
        x: 0,
        y: -.28,
        z: .025,
        sx: .06,
        sy: .06,
        sz: .055,
      ),
    ],
  );

  PlantEmotion get _expression {
    final explicit = widget.emotion;
    if (explicit != null) return explicit;
    return switch (widget.mood) {
      PlantMood.content => PlantEmotion.happy,
      PlantMood.thirsty || PlantMood.airConcern => PlantEmotion.alert,
      PlantMood.waiting => PlantEmotion.neutral,
    };
  }

  List<Widget> _accessory() => switch (widget.look.accessory) {
    CharacterAccessory.leafCrown => [
      _oval(
        material: _leaf,
        x: -.20,
        y: 1.18,
        z: -.02,
        sx: .080,
        sy: .155,
        sz: .035,
        angle: -.85,
      ),
      _oval(
        material: _leafLight,
        x: 0,
        y: 1.235,
        z: -.02,
        sx: .075,
        sy: .17,
        sz: .035,
        angle: .08,
      ),
      _oval(
        material: _leaf,
        x: .20,
        y: 1.18,
        z: -.02,
        sx: .080,
        sy: .155,
        sz: .035,
        angle: .85,
      ),
    ],
    CharacterAccessory.sunHat => [
      scene.SceneNode(
        position: vm.Vector3(0, 1.135, -.01),
        rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -.10),
        children: [
          scene.SceneMesh(geometry: _hatBrim, material: _hat),
          scene.SceneMesh(
            geometry: _hatTop,
            material: _hat,
            position: vm.Vector3(0, .105, 0),
          ),
        ],
      ),
    ],
    CharacterAccessory.rainCloud => [
      _oval(
        material: _cloud,
        x: -.13,
        y: 1.255,
        z: -.02,
        sx: .125,
        sy: .100,
        sz: .100,
      ),
      _oval(
        material: _cloud,
        x: 0,
        y: 1.315,
        z: -.02,
        sx: .150,
        sy: .120,
        sz: .110,
      ),
      _oval(
        material: _cloud,
        x: .14,
        y: 1.255,
        z: -.02,
        sx: .110,
        sy: .090,
        sz: .090,
      ),
      _oval(
        material: _rain,
        x: -.06,
        y: 1.125,
        z: .02,
        sx: .025,
        sy: .050,
        sz: .020,
      ),
      _oval(
        material: _rain,
        x: .07,
        y: 1.095,
        z: .02,
        sx: .022,
        sy: .045,
        sz: .020,
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Karakter ${widget.look.name}, ${_expression.label}',
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
          _motion.speed = widget.look.motionSpeed;
          _motion.windAmplitude = switch (_expression) {
            PlantEmotion.happy => .035,
            PlantEmotion.neutral => .022,
            PlantEmotion.alert => .012,
          };
          _motion.idlePersonality = _expression != PlantEmotion.alert;
          final expression = _expression;
          final mouthY = .72;
          final mouthCurve = switch (expression) {
            PlantEmotion.happy => -.018,
            PlantEmotion.neutral => 0.0,
            PlantEmotion.alert => .020,
          };
          final browAngle = switch (expression) {
            PlantEmotion.happy => .06,
            PlantEmotion.neutral => 0.0,
            PlantEmotion.alert => .34,
          };
          return MossTouchSurface(
            motion: _motion,
            hitTest: _hitCharacter,
            onReact: _react,
            child: Stack(
              fit: StackFit.expand,
              children: [
                scene.SceneView.declarative(
                  pixelRatio: MediaQuery.devicePixelRatioOf(context)
                      .clamp(1.0, 1.8),
                  environmentIntensity: .65 + widget.sky.sunOpacity * .25,
                  camera: _camera,
                  children: [
                    // Only the dominant light casts one small, soft shadow map.
                    scene.SceneNode(
                      key: _sceneKey,
                      components: [_sunAim, _sunKey],
                    ),
                    scene.SceneNode(components: [_moonAim, _moonKey]),
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
                        scene.SceneNode(
                          position: vm.Vector3(0, .50, 0),
                          components: [_headSway],
                          children: [
                            // The inner offset preserves the existing face
                            // geometry while making the neck the head pivot.
                            scene.SceneNode(
                              position: vm.Vector3(0, -.50, 0),
                              children: [
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
                                  material: _hair,
                                  x: -.115,
                                  y: .905,
                                  z: .345,
                                  sx: .055,
                                  sy: .013,
                                  sz: .012,
                                  angle: browAngle,
                                ),
                                _oval(
                                  material: _hair,
                                  x: .115,
                                  y: .905,
                                  z: .345,
                                  sx: .055,
                                  sy: .013,
                                  sz: .012,
                                  angle: -browAngle,
                                ),
                                _oval(
                                  material: _highlight,
                                  x: 0,
                                  y: .765,
                                  z: .372,
                                  sx: .018,
                                  sy: .014,
                                  sz: .009,
                                ),
                                scene.SceneNode(
                                  position: vm.Vector3(-.18, .70, .335),
                                  components: [_leftBlush],
                                  children: [
                                    _oval(
                                      material: _cheek,
                                      x: 0,
                                      y: 0,
                                      z: 0,
                                      sx: .045,
                                      sy: .022,
                                      sz: .01,
                                    ),
                                  ],
                                ),
                                scene.SceneNode(
                                  position: vm.Vector3(.18, .70, .335),
                                  components: [_rightBlush],
                                  children: [
                                    _oval(
                                      material: _cheek,
                                      x: 0,
                                      y: 0,
                                      z: 0,
                                      sx: .045,
                                      sy: .022,
                                      sz: .01,
                                    ),
                                  ],
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
                                  y: mouthY + mouthCurve,
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
                                ..._accessory(),
                              ],
                            ),
                          ],
                        ),
                        _arm(-1, _leftArm),
                        _arm(1, _rightArm),
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

class _SkyLightAim extends scene.Component {
  _SkyLightAim(this.atmosphere, this.sun, this.moon, {required this.isSun});

  MossAtmosphere atmosphere;
  final scene.DirectionalLight sun;
  final scene.DirectionalLight moon;
  final bool isSun;

  @override
  void update(double deltaSeconds) {
    final sky = atmosphere.current;
    final sunStrength = sky.sunOpacity * 1.5;
    final moonStrength = sky.visibleMoonOpacity * .8;
    if (isSun) {
      sun.intensity = sunStrength;
      moon.intensity = moonStrength;
      sun.castsShadow = sunStrength > .05 && sunStrength >= moonStrength;
      moon.castsShadow = moonStrength > .05 && moonStrength > sunStrength;
    }
    final moonHour = sky.hour < 12 ? sky.hour + 24 : sky.hour;
    final progress = isSun
        ? ((sky.hour - 5) / 14).clamp(0.0, 1.0)
        : ((moonHour - 18) / 12).clamp(0.0, 1.0);
    final rise = math.sin(progress * math.pi);
    final direction = vm.Vector3(
      (isSun ? 1 : -1) * (.8 * (.98 - .14 * rise)),
      -(.4 + .8 * rise),
      -1.25,
    )..normalize();
    node.rotation = vm.Quaternion.fromTwoVectors(
      vm.Vector3(0, 0, 1),
      direction,
    );
  }
}

class _Sway extends scene.Component {
  _Sway(this.motion);
  final MossMotion motion;

  @override
  void update(double deltaSeconds) {
    final frame = motion.advance(deltaSeconds);
    final yaw = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), frame.yaw * .2);
    final pitch = vm.Quaternion.axisAngle(
      vm.Vector3(1, 0, 0),
      frame.pitch * .18,
    );
    final wind = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), frame.roll * .26);
    node.rotation = yaw * pitch * wind;
    // Keep the body and pot anchored; the head and arms carry the reaction.
    node.position = vm.Vector3(0, -.12, 0);
  }
}

class _HeadSway extends scene.Component {
  _HeadSway(this.motion);
  final MossMotion motion;

  @override
  void update(double deltaSeconds) {
    final frame = motion.lastFrame;
    final yaw = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), frame.yaw * .8);
    final pitch = vm.Quaternion.axisAngle(
      vm.Vector3(1, 0, 0),
      frame.pitch * .82,
    );
    final roll = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), frame.roll * .74);
    node.rotation = yaw * pitch * roll;
    node.position = vm.Vector3(frame.shift * .22, .50, 0);
  }
}

class _ArmSway extends scene.Component {
  _ArmSway(this.motion, {required this.isLeft});
  final MossMotion motion;
  final bool isLeft;

  @override
  void update(double deltaSeconds) {
    final frame = motion.lastFrame;
    node.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 0, 1),
      isLeft ? frame.leftArm : frame.rightArm,
    );
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

class _Blush extends scene.Component {
  _Blush(this.motion);

  final MossMotion motion;

  @override
  void update(double deltaSeconds) {
    final scale = 1 + motion.lastFrame.reaction * .18;
    node.scale = vm.Vector3(scale, scale, 1);
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
