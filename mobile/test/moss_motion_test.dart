import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/appearance.dart';
import 'package:smart_planter/src/moss_gaze.dart';
import 'package:smart_planter/src/moss_motion.dart';
import 'package:smart_planter/src/moss_sky.dart';

void main() {
  test('pointer position maps to bounded yaw and pitch', () {
    final motion = MossMotion();
    motion.lookAt(const Offset(100, 50), const Size(200, 100));
    expect(motion.targetYaw, 0);
    expect(motion.targetPitch, 0);

    motion.lookAt(const Offset(300, -50), const Size(200, 100));
    expect(motion.targetYaw, -MossMotion.maxYaw);
    expect(motion.targetPitch, -MossMotion.maxPitch);
    motion.lookAt(const Offset(double.nan, 0), const Size(200, 100));
    expect(motion.targetYaw, -MossMotion.maxYaw);
    motion.lookAt(const Offset(0, 100), const Size(200, 100));
    expect(motion.targetYaw, MossMotion.maxYaw);
    expect(motion.targetPitch, MossMotion.maxPitch);
  });

  test('movement eases toward the pointer and settles after release', () {
    final motion = MossMotion();
    motion.lookAt(const Offset(200, 100), const Size(200, 100));
    final first = motion.advance(.05);
    expect(first.yaw, lessThan(0));
    expect(first.yaw, greaterThan(-MossMotion.maxYaw));
    expect(first.shift, greaterThan(0));
    for (var i = 0; i < 40; i++) {
      motion.advance(.05);
    }
    motion.release();
    MossFrame frame = motion.advance(.05);
    for (var i = 0; i < 40; i++) {
      frame = motion.advance(.05);
    }
    expect(frame.yaw.abs(), lessThan(.001));
    expect(frame.pitch.abs(), lessThan(.001));
  });

  test('touch leans away smoothly and settles without a jump', () {
    final left = MossMotion()..windAmplitude = 0;
    final right = MossMotion()..windAmplitude = 0;
    left.tap(horizontal: -.8);
    right.tap(horizontal: .8);
    MossFrame leftFrame = left.advance(.05);
    MossFrame rightFrame = right.advance(.05);
    expect(leftFrame.reaction, greaterThan(0));
    expect(leftFrame.reaction, lessThan(1));
    for (var i = 0; i < 9; i++) {
      leftFrame = left.advance(.05);
      rightFrame = right.advance(.05);
    }
    expect(leftFrame.shift, greaterThan(0));
    expect(rightFrame.shift, lessThan(0));
    expect(leftFrame.roll, lessThan(0));
    expect(rightFrame.roll, greaterThan(0));
    expect(leftFrame.pitch, greaterThan(0));
    expect(leftFrame.blink, greaterThan(0));
    expect(leftFrame.leftArm, greaterThan(0));
    expect(leftFrame.rightArm, lessThan(0));
    for (var i = 0; i < 80; i++) {
      leftFrame = left.advance(.05);
    }
    expect(leftFrame.reaction, lessThan(.001));
    expect(leftFrame.shift.abs(), lessThan(.001));
    expect(leftFrame.pitch.abs(), lessThan(.001));
    expect(leftFrame.leftArm, closeTo(-.35, .001));
    expect(leftFrame.rightArm, closeTo(.35, .001));
  });

  test(
    'rapid taps do not reset the pose, including taps on opposite sides',
    () {
      final motion = MossMotion()..windAmplitude = 0;
      for (var i = 0; i < 60; i++) {
        motion.advance(1 / 60);
      }
      motion.tap(horizontal: -.8);
      var previous = motion.advance(1 / 60);
      for (var i = 0; i < 180; i++) {
        if (i == 18) motion.tap(horizontal: .9);
        if (i == 22) motion.tap(horizontal: -.7);
        final next = motion.advance(1 / 60);
        expect((next.reaction - previous.reaction).abs(), lessThan(.1));
        expect((next.shift - previous.shift).abs(), lessThan(.005));
        expect((next.roll - previous.roll).abs(), lessThan(.01));
        expect((next.pitch - previous.pitch).abs(), lessThan(.01));
        expect((next.leftArm - previous.leftArm).abs(), lessThan(.12));
        expect((next.rightArm - previous.rightArm).abs(), lessThan(.12));
        previous = next;
      }
    },
  );

  test('reduced motion suppresses touch, wind and pointer movement', () {
    final motion = MossMotion()..tap();
    motion.advance(.05);
    motion.reduceMotion = true;
    motion.lookAt(const Offset(200, 100), const Size(200, 100));
    motion.tap();
    final frame = motion.advance(.05);
    expect(frame.yaw, 0);
    expect(frame.pitch, 0);
    expect(frame.shift, 0);
    expect(frame.roll, 0);
    expect(frame.leftArm, -.35);
    expect(frame.rightArm, .35);
    expect(frame.blink, 0);
    expect(frame.reaction, 0);
    motion.release();
    motion.reduceMotion = false;
    expect(motion.advance(.05).reaction, 0);
  });

  test('a quick tap holds the gaze briefly before easing back', () {
    final motion = MossMotion();
    motion.lookAt(const Offset(200, 50), const Size(200, 100));
    motion.releaseAfter(.6);
    for (var i = 0; i < 8; i++) {
      motion.advance(.05);
    }
    expect(motion.targetYaw, -MossMotion.maxYaw);
    for (var i = 0; i < 5; i++) {
      motion.advance(.05);
    }
    expect(motion.targetYaw, 0);
  });

  test('gaze direction is relative to Moss, even outside the avatar', () {
    final gaze = MossGaze();
    addTearDown(gaze.dispose);
    const face = Offset(200, 300);
    const screen = Size(400, 800);
    gaze.follow(const Offset(0, 100), screen);
    expect(gaze.directionFrom(face), const Offset(-1, -.5));
    gaze.follow(const Offset(400, 700), screen);
    expect(gaze.directionFrom(face), const Offset(1, 1));
    gaze.release();
    expect(gaze.directionFrom(face), isNull);
  });

  test('finger takes priority over sky or comet and restores ambient gaze', () {
    final gaze = MossGaze();
    addTearDown(gaze.dispose);
    const screen = Size(400, 800);
    final sky = Object();
    final comet = Object();
    gaze.followAmbient(sky, const Offset(350, 100), screen);
    expect(gaze.position, const Offset(350, 100));
    gaze.follow(const Offset(20, 700), screen);
    gaze.followAmbient(comet, const Offset(200, 120), screen);
    expect(gaze.position, const Offset(20, 700));
    gaze.releaseAmbient(sky); // A stale owner cannot cancel the comet.
    gaze.release();
    expect(gaze.position, const Offset(200, 120));
    gaze.releaseAmbient(comet);
    expect(gaze.active, isFalse);
  });

  test(
    'idle head and arms move independently and stop with reduced motion',
    () {
      final motion = MossMotion()
        ..idlePersonality = true
        ..windAmplitude = 0;
      final initial = motion.advance(.05);
      MossFrame later = initial;
      for (var i = 0; i < 40; i++) {
        later = motion.advance(.05);
      }
      expect((later.yaw - initial.yaw).abs(), greaterThan(.01));
      expect((later.leftArm - initial.leftArm).abs(), greaterThan(.01));
      expect((later.rightArm - initial.rightArm).abs(), greaterThan(.01));
      expect(later.leftArm + later.rightArm, isNot(closeTo(0, .01)));
      motion.reduceMotion = true;
      final still = motion.advance(.05);
      expect(still.yaw, 0);
      expect(still.leftArm, -.35);
      expect(still.rightArm, .35);
    },
  );

  test('successive touches use three smoothly blended poses', () {
    final motion = MossMotion()..windAmplitude = 0;
    final poses = <MossFrame>[];
    for (var pose = 0; pose < 3; pose++) {
      motion.tap();
      var frame = motion.advance(.05);
      for (var i = 0; i < 5; i++) {
        frame = motion.advance(.05);
      }
      poses.add(frame);
      for (var i = 0; i < 100; i++) {
        motion.advance(.05);
      }
    }
    expect(poses[0].leftArm, greaterThan(.2));
    expect(poses[0].rightArm, lessThan(-.2));
    expect(poses[1].rightArm, greaterThan(poses[0].rightArm + .3));
    expect(poses[2].leftArm, lessThan(poses[0].leftArm - .3));
    expect(poses[2].rightArm, lessThan(-.2));
  });

  testWidgets('screen tracking observes taps without blocking buttons', (
    tester,
  ) async {
    final gaze = MossGaze();
    addTearDown(gaze.dispose);
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MossScreenTracker(
          gaze: gaze,
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => pressed++,
                child: const Text('Outside Moss'),
              ),
            ),
          ),
        ),
      ),
    );
    final position = tester.getCenter(find.text('Outside Moss'));
    final gesture = await tester.startGesture(position);
    expect(gaze.active, isTrue);
    expect(gaze.position, position);
    expect(gaze.viewport, tester.getSize(find.byType(MossScreenTracker)));
    await gesture.up();
    expect(gaze.active, isFalse);
    expect(pressed, 1);
  });

  testWidgets('a tap reacts, while a drag does not trigger a touch effect', (
    tester,
  ) async {
    final motion = MossMotion();
    var reactions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 100,
            child: MossTouchSurface(
              motion: motion,
              hitTest: (_, _) => true,
              onReact: (_) => reactions++,
              child: const ColoredBox(color: Colors.green),
            ),
          ),
        ),
      ),
    );
    final surface = find.byType(MossTouchSurface);
    await tester.tap(surface);
    expect(reactions, 1);
    expect(motion.advance(.05).reaction, greaterThan(0));
    await tester.drag(surface, const Offset(40, 0));
    expect(reactions, 1);
  });

  testWidgets('tap location chooses the side Moss leans away from', (
    tester,
  ) async {
    final motion = MossMotion()..windAmplitude = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: MossTouchSurface(
                motion: motion,
                hitTest: (_, _) => true,
                child: const ColoredBox(color: Colors.green),
              ),
            ),
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byType(MossTouchSurface));
    await tester.tapAt(Offset(bounds.left + 10, bounds.center.dy));
    MossFrame frame = motion.advance(.05);
    for (var i = 0; i < 10; i++) {
      frame = motion.advance(.05);
    }
    expect(frame.shift, greaterThan(0));
    await tester.tapAt(Offset(bounds.right - 10, bounds.center.dy));
    for (var i = 0; i < 15; i++) {
      frame = motion.advance(.05);
    }
    expect(frame.shift, lessThan(0));
  });

  testWidgets('only a hit on the character triggers a touch reaction', (
    tester,
  ) async {
    final motion = MossMotion();
    var reactions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: MossTouchSurface(
                motion: motion,
                hitTest: (point, _) =>
                    point.dx >= 70 &&
                    point.dx <= 130 &&
                    point.dy >= 40 &&
                    point.dy <= 160,
                onReact: (_) => reactions++,
                child: const ColoredBox(color: Colors.green),
              ),
            ),
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byType(MossTouchSurface));
    await tester.tapAt(bounds.topLeft + const Offset(10, 10));
    expect(reactions, 0);
    expect(motion.advance(.05).reaction, 0);
    await tester.tapAt(bounds.center);
    expect(reactions, 1);
    expect(motion.advance(.05).reaction, greaterThan(0));
  });

  testWidgets('dragging over Moss still permits vertical page scrolling', (
    tester,
  ) async {
    final motion = MossMotion();
    final scroll = ScrollController();
    final gaze = MossGaze();
    var swipes = 0;
    var reactions = 0;
    addTearDown(scroll.dispose);
    addTearDown(gaze.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MossScreenTracker(
          gaze: gaze,
          child: Scaffold(
            body: ListView(
              controller: scroll,
              children: [
                SizedBox(
                  height: 200,
                  child: MossSky(
                    sky: SkyAppearance.atHour(12),
                    onSwipe: (_) => swipes++,
                    child: MossTouchSurface(
                      key: const ValueKey('moss-touch'),
                      motion: motion,
                      hitTest: (_, _) => true,
                      onReact: (_) => reactions++,
                      child: const SizedBox.expand(
                        child: ColoredBox(color: Colors.green),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 1800),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey('moss-touch')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(swipes, 0);
    expect(reactions, 0);
    scroll.jumpTo(0);
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('moss-touch')),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    expect(swipes, 1);
    expect(reactions, 0);
  });
}
