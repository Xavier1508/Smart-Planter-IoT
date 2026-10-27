import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/plant_state.dart';

void main() {
  test('unconnected state never presents demonstration values', () {
    const state = PlantState.waiting();
    expect(state.isDemo, isFalse);
    expect(state.soilPercent, isNull);
    expect(state.waterPercent, isNull);
    expect(state.mood, PlantMood.waiting);
  });

  test('demonstration scenarios produce distinct expressions', () {
    expect(PlantState.demo(DemoScenario.content).mood, PlantMood.content);
    expect(PlantState.demo(DemoScenario.thirsty).mood, PlantMood.thirsty);
    expect(PlantState.demo(DemoScenario.airConcern).mood, PlantMood.airConcern);
  });

  test('low water and dry soil take priority over simulated air changes', () {
    const state = PlantState(
      isDemo: true,
      soilPercent: 29,
      waterPercent: 50,
      airChanged: true,
    );
    expect(state.mood, PlantMood.thirsty);
    expect(
      const PlantState(isDemo: true, soilPercent: 30, waterPercent: 20).mood,
      PlantMood.content,
    );
    expect(
      const PlantState(isDemo: true, soilPercent: 50, waterPercent: 19).mood,
      PlantMood.thirsty,
    );
  });
}
