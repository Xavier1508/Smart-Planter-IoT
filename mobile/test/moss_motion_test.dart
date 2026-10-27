import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/moss_motion.dart';

void main() {
  test('pointer position maps to bounded yaw and pitch', () {
    final motion = MossMotion();
    motion.lookAt(const Offset(100, 50), const Size(200, 100));
    expect(motion.targetYaw, 0);
    expect(motion.targetPitch, 0);

    motion.lookAt(const Offset(300, -50), const Size(200, 100));
    expect(motion.targetYaw, MossMotion.maxYaw);
    expect(motion.targetPitch, -MossMotion.maxPitch);
    motion.lookAt(const Offset(double.nan, 0), const Size(200, 100));
    expect(motion.targetYaw, MossMotion.maxYaw);
  });

  test('movement eases toward the pointer and settles after release', () {
    final motion = MossMotion();
    motion.lookAt(const Offset(200, 100), const Size(200, 100));
    final first = motion.advance(.05);
    expect(first.yaw, greaterThan(0));
    expect(first.yaw, lessThan(MossMotion.maxYaw));
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

  test('tap reacts but reduced-motion suppresses wind and bounce', () {
    final motion = MossMotion()..tap();
    expect(motion.advance(.05).bounce, greaterThan(0));
    motion.reduceMotion = true;
    motion.tap();
    final frame = motion.advance(.05);
    expect(frame.bounce, 0);
    expect(frame.roll, 0);
  });

  testWidgets('touch and drag track the finger, then return to rest', (
    tester,
  ) async {
    final motion = MossMotion();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: MossTouchSurface(
                motion: motion,
                child: const ColoredBox(color: Colors.green),
              ),
            ),
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byType(MossTouchSurface));
    final gesture = await tester.startGesture(bounds.center);
    await gesture.moveTo(bounds.centerRight);
    expect(motion.targetYaw, closeTo(MossMotion.maxYaw, .001));
    await gesture.up();
    expect(motion.targetYaw, 0);
    expect(motion.targetPitch, 0);
  });

  testWidgets('dragging over Moss still permits vertical page scrolling', (
    tester,
  ) async {
    final motion = MossMotion();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              SizedBox(
                height: 200,
                child: MossTouchSurface(
                  key: const ValueKey('moss-touch'),
                  motion: motion,
                  child: const ColoredBox(color: Colors.green),
                ),
              ),
              const SizedBox(height: 1800),
            ],
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
  });
}
