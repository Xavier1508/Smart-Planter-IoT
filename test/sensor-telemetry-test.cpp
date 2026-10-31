#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <vector>

#include "extra-sensors.h"
#include "local-wifi.h"
#include "planter-config.h"
#include "relay-safety.h"
#include "sensor-telemetry.h"
#include "soil-sensor.h"

struct GpioCall {
  char action;
  int pin;
  bool high;
};

struct FakeGpio {
  std::vector<GpioCall> calls;
  void write(int pin, bool high) { calls.push_back({'w', pin, high}); }
  void enableOutput(int pin) { calls.push_back({'o', pin, false}); }
};

struct FakeSoilGpio {
  std::vector<GpioCall> calls;
  int raw = 2345;
  void write(int pin, bool high) { calls.push_back({'w', pin, high}); }
  void enableOutput(int pin) { calls.push_back({'o', pin, false}); }
  void enableInput(int pin) { calls.push_back({'i', pin, false}); }
  void delayMs(uint32_t milliseconds) { calls.push_back({'d', static_cast<int>(milliseconds), false}); }
  int readAnalog(int pin) { calls.push_back({'r', pin, false}); return raw; }
};

struct FakeRandom {
  uint32_t value = 0;
  uint32_t next() { return value++; }
};

int main() {
  using planter::SensorSnapshot;
  using planter::formatTelemetry;

  assert(planter::sampleDue(5000, 0, 5000));
  assert(!planter::sampleDue(4999, 0, 5000));
  assert(planter::sampleDue(0x20U, 0xfffffff0U, 48));
  assert(!planter::sampleDue(0x20U, 0xfffffff0U, 49));
  assert(!planter::relayLevel(planter::kPumpActiveLow, true));
  assert(planter::relayLevel(planter::kPumpActiveLow, false));
  assert(planter::relayLevel(planter::kLightActiveLow, true));
  assert(!planter::relayLevel(planter::kLightActiveLow, false));
  FakeGpio gpio;
  planter::configureRelaysInactive(gpio);
  assert(gpio.calls.size() == 6);
  assert(gpio.calls[0].action == 'w' && gpio.calls[0].pin == 13 && gpio.calls[0].high);
  assert(gpio.calls[1].action == 'w' && gpio.calls[1].pin == 26 && !gpio.calls[1].high);
  assert(gpio.calls[2].action == 'o' && gpio.calls[2].pin == 13);
  assert(gpio.calls[3].action == 'o' && gpio.calls[3].pin == 26);
  assert(gpio.calls[4].action == 'w' && gpio.calls[4].pin == 13 && gpio.calls[4].high);
  assert(gpio.calls[5].action == 'w' && gpio.calls[5].pin == 26 && !gpio.calls[5].high);
  FakeGpio commandGpio;
  planter::writeRelayCommands(commandGpio, {false, false, "test", "test"});
  planter::writeRelayCommands(commandGpio, {true, true, "test", "test"});
  assert(commandGpio.calls.size() == 4);
  assert(commandGpio.calls[0].pin == 13 && commandGpio.calls[0].high);
  assert(commandGpio.calls[1].pin == 26 && !commandGpio.calls[1].high);
  assert(commandGpio.calls[2].pin == 13 && !commandGpio.calls[2].high);
  assert(commandGpio.calls[3].pin == 26 && commandGpio.calls[3].high);

  const float nan = std::numeric_limits<float>::quiet_NaN();
  const float infinity = std::numeric_limits<float>::infinity();
  assert(!planter::validTemperature(nan));
  assert(!planter::validTemperature(infinity));
  assert(!planter::validTemperature(81.0f));
  assert(planter::validTemperature(-40.0f));
  assert(planter::validTemperature(80.0f));
  assert(!planter::validHumidity(nan));
  assert(!planter::validHumidity(-1.0f));
  assert(!planter::validHumidity(101.0f));
  assert(planter::validHumidity(0.0f));
  assert(planter::validHumidity(100.0f));
  assert(!planter::validAdcRaw(-1));
  assert(planter::validAdcRaw(0));
  assert(planter::validAdcRaw(4095));
  assert(!planter::validAdcRaw(4096));
  assert(std::strcmp(planter::adcSignalQuality(-1), "unavailable") == 0);
  assert(std::strcmp(planter::adcSignalQuality(0), "rail_low_unverified") == 0);
  assert(std::strcmp(planter::adcSignalQuality(1), "in_range_unverified") == 0);
  assert(std::strcmp(planter::adcSignalQuality(4094), "in_range_unverified") == 0);
  assert(std::strcmp(planter::adcSignalQuality(4095), "rail_high_unverified") == 0);
  assert(std::strcmp(planter::adcSignalQuality(5, false), "not_configured") == 0);
  assert(planter::relativePercent(0, 0, 2450) == 0);
  assert(planter::relativePercent(2450, 0, 2450) == 100);
  assert(planter::relativePercent(4095, 0, 2450) == 100);
  assert(planter::relativePercent(4095, 4095, 0) == 0);
  assert(planter::relativePercent(0, 4095, 0) == 100);
  assert(planter::relativePercent(-1, 0, 2450) == -1);
  assert(planter::relativePercent(123, 123, 123) == -1);
  // A public ESP32 project reports a different sensor with the opposite ADC
  // direction (dry 3100, wet 2200). Its numbers are test fixtures only; they
  // are never blended into this device's observation-based scale.
  // Source: https://github.com/ajinkyagorad/SoilMoistureSensor
  assert(planter::relativePercent(3100, 3100, 2200) == 0);
  assert(planter::relativePercent(2650, 3100, 2200) == 50);  // Mathematical midpoint.
  assert(planter::relativePercent(2200, 3100, 2200) == 100);
  assert(planter::kPumpOnBelowPercent == 50);
  assert(planter::kLightOnBelowPercent == 65);
  assert(planter::kLegacyLightPreviewBelowPercent == 60);
  assert(planter::kWaterLowBelowPercent == 20);
  assert(planter::belowThresholdPreview(49, planter::kPumpOnBelowPercent) == 1);
  assert(planter::belowThresholdPreview(50, planter::kPumpOnBelowPercent) == 0);
  assert(planter::belowThresholdPreview(51, planter::kPumpOnBelowPercent) == 0);
  assert(planter::belowThresholdPreview(64, planter::kLightOnBelowPercent) == 1);
  assert(planter::belowThresholdPreview(65, planter::kLightOnBelowPercent) == 0);
  assert(planter::belowThresholdPreview(66, planter::kLightOnBelowPercent) == 0);
  assert(planter::belowThresholdPreview(19, planter::kWaterLowBelowPercent) == 1);
  assert(planter::belowThresholdPreview(20, planter::kWaterLowBelowPercent) == 0);
  assert(planter::belowThresholdPreview(21, planter::kWaterLowBelowPercent) == 0);
  assert(planter::belowThresholdPreview(-1, 50) == -1);
  assert(planter::belowThresholdPreview(101, 50) == -1);
  assert(planter::belowThresholdPreview(50, -1) == -1);
  assert(planter::belowThresholdPreview(50, 101) == -1);
  assert(!planter::kWaterRelativeScaleEnabled);
  assert(planter::kWaterLowRawReferenceAdc > 0);
  assert(planter::kWaterNearRawReferenceAdc > planter::kWaterLowRawReferenceAdc);
  assert(std::strcmp(planter::waterRawReferenceBand(-1), "unavailable") == 0);
  assert(std::strcmp(planter::waterRawReferenceBand(0), "rail_unverified") == 0);
  assert(std::strcmp(planter::waterRawReferenceBand(planter::kWaterLowRawReferenceAdc),
                     "at_or_below_low") == 0);
  assert(std::strcmp(planter::waterRawReferenceBand(planter::kWaterLowRawReferenceAdc + 1),
                     "near_low") == 0);
  assert(std::strcmp(planter::waterRawReferenceBand(planter::kWaterNearRawReferenceAdc - 1),
                     "near_low") == 0);
  assert(std::strcmp(planter::waterRawReferenceBand(planter::kWaterNearRawReferenceAdc),
                     "above_reference") == 0);
  assert(std::strcmp(planter::waterRawReferenceBand(4094), "above_reference") == 0);
  assert(std::strcmp(planter::waterRawReferenceBand(4095), "rail_unverified") == 0);
  assert(std::strcmp(planter::waterRawReferenceBand(4096), "unavailable") == 0);
  assert(!planter::kPumpSoilScaleConfirmed);
  assert(planter::kPumpOffAtPercent == 55);
  assert(planter::kLightOffAtOrAbovePercent == 70);
  assert(!planter::controlAnalogUsable(0));
  assert(planter::controlAnalogUsable(1));
  assert(planter::controlAnalogUsable(4094));
  assert(!planter::controlAnalogUsable(4095));
  assert(!planter::controlWaterAdcUsable(-1));
  assert(!planter::controlWaterAdcUsable(0));
  assert(!planter::controlWaterAdcUsable(4095));
  assert(extra_sensors::kWaterLevelPin == 33);
  assert(extra_sensors::kMq135Pin == 27);
  assert(extra_sensors::kMq135DigitalPin == 14);
  assert(planter::kDhtEnabled);
  assert(!planter::kDhtModelVerified);
  assert(planter::kSoilPin == 34);
  assert(planter::kLegacySoilPowerPin == 25);
  assert(!planter::kSoilPowerWiringVerified);
  assert(planter::kSoilAdcReadEnabled);
  assert(!planter::kLightAutomationEnabled);
  assert(planter::kFirmwareVersion == 13);

  FakeRandom random;
  char wifiPassword[planter::kLocalWifiPasswordLength + 1];
  assert(planter::makeLocalWifiPassword(wifiPassword, sizeof(wifiPassword), random));
  assert(std::strlen(wifiPassword) == planter::kLocalWifiPasswordLength);
  assert(std::strcmp(wifiPassword, "ABCDEFGHJK") == 0);
  assert(!planter::makeLocalWifiPassword(nullptr, sizeof(wifiPassword), random));
  assert(!planter::makeLocalWifiPassword(wifiPassword, 10, random));
  assert(planter::lcdPageForUptime(0) == 4);
  assert(planter::lcdPageForUptime(59999) == 4);
  assert(planter::lcdPageForUptime(60000) == 0);
  assert(planter::lcdPageForUptime(64999) == 0);
  assert(planter::lcdPageForUptime(65000) == 1);
  assert(planter::lcdPageForUptime(70000) == 2);
  assert(planter::lcdPageForUptime(75000) == 3);
  assert(planter::lcdPageForUptime(80000) == 4);
  assert(planter::lcdPageForUptime(109999) == 4);
  assert(planter::lcdPageForUptime(110000) == 0);

  // These UV inputs are fixtures, not measurements from the real sensor.
  using planter::LightDecision;
  assert(planter::dualSensorLightDecision(64, 69) == LightDecision::on);
  assert(planter::dualSensorLightDecision(65, 69) == LightDecision::hold);
  assert(planter::dualSensorLightDecision(69, 69) == LightDecision::hold);
  assert(planter::dualSensorLightDecision(70, 69) == LightDecision::off);
  assert(planter::dualSensorLightDecision(10, 71) == LightDecision::off);
  assert(planter::dualSensorLightDecision(10, 70) == LightDecision::hold);
  assert(planter::dualSensorLightDecision(-1, 71) == LightDecision::off);
  assert(planter::dualSensorLightDecision(70, -1) == LightDecision::off);
  assert(planter::dualSensorLightDecision(10, -1) == LightDecision::unavailable);
  assert(planter::dualSensorLightDecision(-1, 10) == LightDecision::unavailable);

  // GPIO25 remains an input while ADC34 is sampled; no supply output is driven.
  FakeSoilGpio inputSoil;
  planter::configureSoilPower(inputSoil, false);
  assert(inputSoil.calls.size() == 1);
  assert(inputSoil.calls[0].action == 'i' && inputSoil.calls[0].pin == 25);
  assert(planter::acquireSoilRaw(inputSoil, true, false) == 2345);
  assert(inputSoil.calls.size() == 2);
  assert(inputSoil.calls[1].action == 'r' && inputSoil.calls[1].pin == 34);
  assert(planter::acquireSoilRaw(inputSoil, false, false) == -1);
  assert(inputSoil.calls.size() == 2);

  // Fixture-only exercise of the optional, operator-verified switched mode.
  FakeSoilGpio switchedSoil;
  planter::configureSoilPower(switchedSoil, true);
  assert(switchedSoil.calls.size() == 3);
  assert(switchedSoil.calls[0].action == 'w' && !switchedSoil.calls[0].high);
  assert(switchedSoil.calls[1].action == 'o' && switchedSoil.calls[1].pin == 25);
  assert(switchedSoil.calls[2].action == 'w' && !switchedSoil.calls[2].high);
  assert(planter::acquireSoilRaw(switchedSoil, true, true) == 2345);
  assert(switchedSoil.calls.size() == 7);
  assert(switchedSoil.calls[3].action == 'w' && switchedSoil.calls[3].high);
  assert(switchedSoil.calls[4].action == 'd' && switchedSoil.calls[4].pin == 300);
  assert(switchedSoil.calls[5].action == 'r' && switchedSoil.calls[5].pin == 34);
  assert(switchedSoil.calls[6].action == 'w' && !switchedSoil.calls[6].high);

  planter::ObservationLabels labels;
  assert(labels.current(0) == nullptr);
  assert(labels.apply("LABEL SOIL DRY_SOIL", 100) == planter::LabelCommandResult::set);
  assert(std::strcmp(labels.current(101)->sensor, "soil") == 0);
  assert(std::strcmp(labels.current(101)->condition, "dry_soil") == 0);
  assert(labels.current(100 + planter::kObservationLabelTtlMs - 1) != nullptr);
  assert(labels.current(100 + planter::kObservationLabelTtlMs) == nullptr);
  const uint32_t labelWrap = 0xfffffff0U;
  assert(labels.apply("LABEL WATER NEAR_FULL", labelWrap) == planter::LabelCommandResult::set);
  assert(labels.current(labelWrap + planter::kObservationLabelTtlMs - 1) != nullptr);
  assert(labels.current(labelWrap + planter::kObservationLabelTtlMs) == nullptr);
  assert(labels.apply("LABEL MQ AMBIENT", 1000) == planter::LabelCommandResult::set);
  assert(labels.apply("LABEL INVALID", 1001) == planter::LabelCommandResult::rejected);
  assert(labels.current(1001) == nullptr);
  assert(labels.apply("LABEL SOIL AIR", 2000) == planter::LabelCommandResult::set);
  assert(labels.apply("LABEL CLEAR", 2001) == planter::LabelCommandResult::cleared);
  assert(labels.current(2001) == nullptr);
  assert(labels.apply("LABEL SOIL WATER", 3000) == planter::LabelCommandResult::set);
  assert(labels.apply(nullptr, 3001) == planter::LabelCommandResult::rejected);
  assert(labels.current(3001) == nullptr);
  struct LabelFixture { const char* command; const char* sensor; const char* condition; };
  const LabelFixture labelFixtures[] = {
      {"LABEL SOIL AIR", "soil", "probe_in_air"},
      {"LABEL SOIL WATER", "soil", "probe_in_water"},
      {"LABEL SOIL DRY_SOIL", "soil", "dry_soil"},
      {"LABEL SOIL WET_SOIL", "soil", "wet_soil"},
      {"LABEL WATER LOW", "water", "low"},
      {"LABEL WATER MID", "water", "mid"},
      {"LABEL WATER NEAR_FULL", "water", "near_full"},
      {"LABEL LIGHT DARK", "light", "dark"},
      {"LABEL LIGHT AMBIENT", "light", "ambient"},
      {"LABEL UV COVERED", "uv", "covered"},
      {"LABEL UV SUN", "uv", "sun"},
      {"LABEL UV SHADE", "uv", "shade"},
      {"LABEL MQ AMBIENT", "mq135", "ambient"},
  };
  for (const auto& fixture : labelFixtures) {
    assert(labels.apply(fixture.command, 5000) == planter::LabelCommandResult::set);
    const auto* current = labels.current(5001);
    assert(current && std::strcmp(current->sensor, fixture.sensor) == 0);
    assert(std::strcmp(current->condition, fixture.condition) == 0);
  }
  assert(labels.apply("LABEL MQ CLEAN_AIR", 5002) == planter::LabelCommandResult::rejected);
  assert(labels.current(5002) == nullptr);

  planter::LabelLineReader reader;
  const char* command = "LABEL UV COVERED\r\n";
  for (size_t i = 0; command[i] != '\0'; ++i) {
    const auto result = reader.push(command[i]);
    assert(result == (command[i] == '\n' ? planter::LabelLineResult::ready
                                           : planter::LabelLineResult::pending));
  }
  assert(std::strcmp(reader.line(), "LABEL UV COVERED") == 0);
  for (int i = 0; i < 100; ++i) assert(reader.push('X') == planter::LabelLineResult::pending);
  assert(reader.push('\n') == planter::LabelLineResult::rejected);
  for (const char c : {'O', 'K'}) assert(reader.push(c) == planter::LabelLineResult::pending);
  assert(reader.push('\n') == planter::LabelLineResult::ready);
  assert(std::strcmp(reader.line(), "OK") == 0);
  assert(reader.push('\0') == planter::LabelLineResult::pending);
  assert(reader.push('\n') == planter::LabelLineResult::rejected);

  // Simulate command timing with fixture inputs; no physical GPIO is touched.
  planter::ControlInput input = {49, 64, 80, true, true, true, true, 30};
  planter::RelayController lightControl;
  lightControl.begin(0);
  lightControl.accept(0, input);
  assert(!lightControl.status().pumpOn && !lightControl.status().lightOn);
  assert(std::strcmp(lightControl.status().lightReason, "boot_grace") == 0);
  for (uint32_t now = 5000; now < 30000; now += 5000) {
    lightControl.accept(now, input);
    assert(!lightControl.status().lightOn);
  }
  lightControl.accept(30000, input);
  assert(lightControl.status().lightOn);
  input.lightPercent = 65;  // Hysteresis band keeps the previous state.
  lightControl.accept(35000, input);
  assert(lightControl.status().lightOn);
  input.lightPercent = 70;
  lightControl.accept(40000, input);
  assert(!lightControl.status().lightOn);
  input.lightPercent = 64;
  lightControl.accept(69999, input);
  assert(!lightControl.status().lightOn);
  lightControl.accept(70000, input);
  assert(lightControl.status().lightOn);
  input.uvIndexTenths = 71;  // A sufficient reading overrides the minimum hold.
  lightControl.accept(75000, input);
  assert(!lightControl.status().lightOn);
  assert(std::strcmp(lightControl.status().lightReason, "light_sufficient") == 0);
  input.uvIndexTenths = 30;
  lightControl.accept(105000, input);
  assert(lightControl.status().lightOn);
  input.uvIndexTenths = -1;
  lightControl.accept(110000, input);
  assert(!lightControl.status().lightOn);
  assert(std::strcmp(lightControl.status().lightReason, "light_input_unavailable") == 0);

  planter::RelayController pumpControl;
  pumpControl.begin(0);
  input = {49, 70, 80, true, true, true, true, 30};
  pumpControl.accept(299999, input);
  assert(!pumpControl.status().pumpOn);
  assert(std::strcmp(pumpControl.status().pumpReason, "cooldown") == 0);
  pumpControl.accept(300000, input);
  assert(pumpControl.status().pumpOn);
  input.soilPercent = 54;
  for (uint32_t now = 305000; now <= 325000; now += 5000) {
    pumpControl.accept(now, input);
    assert(pumpControl.status().pumpOn);
  }
  pumpControl.tick(329999);
  assert(pumpControl.status().pumpOn);
  pumpControl.tick(330000);
  assert(!pumpControl.status().pumpOn);
  assert(std::strcmp(pumpControl.status().pumpReason, "runtime_limit") == 0);
  input.soilPercent = 49;
  pumpControl.accept(629999, input);
  assert(!pumpControl.status().pumpOn);
  pumpControl.accept(630000, input);
  assert(pumpControl.status().pumpOn);
  input.soilPercent = 55;
  pumpControl.accept(635000, input);
  assert(!pumpControl.status().pumpOn);
  assert(std::strcmp(pumpControl.status().pumpReason, "soil_moist") == 0);

  planter::RelayController blockedPump;
  blockedPump.begin(0);
  input = {49, 70, -1, false, false, true, true, 30};
  blockedPump.accept(300000, input);
  assert(!blockedPump.status().pumpOn);
  assert(std::strcmp(blockedPump.status().pumpReason, "water_unavailable") == 0);
  input.waterScaleConfirmed = true;
  input.waterPercent = 80;
  blockedPump.accept(305000, input);
  assert(!blockedPump.status().pumpOn);
  assert(std::strcmp(blockedPump.status().pumpReason, "soil_unverified") == 0);
  input.soilScaleConfirmed = true;
  blockedPump.accept(310000, input);
  assert(blockedPump.status().pumpOn);
  input.waterPercent = 19;
  blockedPump.accept(315000, input);
  assert(!blockedPump.status().pumpOn);
  assert(std::strcmp(blockedPump.status().pumpReason, "water_low") == 0);

  planter::RelayController boundaryWater;
  boundaryWater.begin(0);
  input = {49, 70, 20, true, true, true, true, 30};
  boundaryWater.accept(300000, input);
  assert(boundaryWater.status().pumpOn);
  input.waterPercent = -1;
  boundaryWater.accept(305000, input);
  assert(!boundaryWater.status().pumpOn);
  assert(std::strcmp(boundaryWater.status().pumpReason, "water_unavailable") == 0);

  planter::RelayController invalidSoil;
  invalidSoil.begin(0);
  input = {49, 70, 80, true, true, true, true, 30};
  invalidSoil.accept(300000, input);
  assert(invalidSoil.status().pumpOn);
  input.soilPercent = -1;
  invalidSoil.accept(305000, input);
  assert(!invalidSoil.status().pumpOn);
  assert(std::strcmp(invalidSoil.status().pumpReason, "soil_unavailable") == 0);

  planter::RelayController staleControl;
  staleControl.begin(0);
  input = {49, 70, 80, true, true, true, true, 30};
  staleControl.accept(300000, input);
  assert(staleControl.status().pumpOn);
  staleControl.tick(315000);
  assert(!staleControl.status().pumpOn);
  assert(std::strcmp(staleControl.status().pumpReason, "sample_stale") == 0);

  planter::RelayController watchdogControl;
  watchdogControl.begin(0);
  input = {49, 59, 80, true, true, true, true, 30};
  watchdogControl.accept(300000, input);
  assert(watchdogControl.status().pumpOn && watchdogControl.status().lightOn);
  input.watchdogReady = false;
  watchdogControl.accept(305000, input);
  assert(!watchdogControl.status().pumpOn && !watchdogControl.status().lightOn);
  assert(std::strcmp(watchdogControl.status().pumpReason, "watchdog_unavailable") == 0);

  planter::RelayController wrapControl;
  const uint32_t nearWrap = 0xffff0000U;
  wrapControl.begin(nearWrap);
  input = {49, 70, 80, true, true, true, true, 30};
  wrapControl.accept(nearWrap + 300000U, input);
  assert(wrapControl.status().pumpOn);
  wrapControl.accept(nearWrap + 305000U, input);
  assert(wrapControl.status().pumpOn);

  planter::RelayController inhibitedLight;
  inhibitedLight.begin(0);
  input = {49, 10, 80, true, true, true, false, 30};
  inhibitedLight.accept(300000, input);
  assert(!inhibitedLight.status().lightOn);
  assert(std::strcmp(inhibitedLight.status().lightReason, "light_inhibited") == 0);

  char output[3072];
  const SensorSnapshot missing = {
      42, nan, infinity, -1, 4096, 123, true, -1, false, true,
      true, -1, -1, false, false, -1, planter::AdcCalibrationMethod::unavailable};
  assert(formatTelemetry(missing, output, sizeof(output)));
  assert(std::strstr(output, "\"temperature_c\":null") != nullptr);
  assert(std::strstr(output, "\"humidity_percent\":null") != nullptr);
  assert(std::strstr(output, "\"status\":\"unavailable\"") != nullptr);
  assert(std::strstr(output, "\"soil_raw\":null") != nullptr);
  assert(std::strstr(output, "\"soil_status\":\"unavailable\"") != nullptr);
  assert(std::strstr(output, "\"light_raw\":null") != nullptr);
  assert(std::strstr(output, "\"uv_raw\":123") != nullptr);
  assert(std::strstr(output, "\"soil_relative_percent\":null") != nullptr);
  assert(std::strstr(output, "\"status\":\"unverified\"") != nullptr);
  assert(std::strstr(output, "\"water_level\":null") != nullptr);
  assert(std::strstr(output, "\"mq135\":null") != nullptr);
  assert(std::strstr(output, "\"pump_state\":null") != nullptr);
  assert(std::strstr(output, "\"relay_control\":\"inactive_requested\"") != nullptr);
  assert(std::strstr(output, "\"control_preview\":{\"mode\":\"diagnostic_only\"") != nullptr);
  assert(std::strstr(output, "\"pump_on\":null,\"growlight_on\":null,\"water_low\":null") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';

  const SensorSnapshot valid = {
      5000, 26.5f, 64.0f, 1000, 2000, 3000, true, 1789, true, true,
      true, 1042, 1, true, true, 777, planter::AdcCalibrationMethod::efuse_vref};
  SensorSnapshot soilFixture = valid;
  soilFixture.soilAdcRaw = planter::kSoilRelativeZeroAdc;
  assert(planter::observedSoilRelativePercent(soilFixture) == 0);
  soilFixture.soilAdcRaw = planter::kSoilRelativeFullAdc;
  assert(planter::observedSoilRelativePercent(soilFixture) == 100);
  soilFixture.soilAdcRaw = 0;
  assert(planter::observedSoilRelativePercent(soilFixture) == -1);
  soilFixture.soilAdcRaw = 4095;
  assert(planter::observedSoilRelativePercent(soilFixture) == -1);
  soilFixture.soilEnabled = false;
  assert(planter::observedSoilRelativePercent(soilFixture) == -1);
  assert(formatTelemetry(valid, output, sizeof(output)));
  assert(std::strstr(output, "\"temperature_c\":26.5") != nullptr);
  assert(std::strstr(output, "\"humidity_percent\":64.0") != nullptr);
  assert(std::strstr(output, "\"status\":\"valid\"") != nullptr);
  assert(std::strstr(output, "\"soil_raw\":1000,\"soil_status\":\"unverified\"") != nullptr);
  char expectedSoil[64];
  const int expectedSoilPercent = planter::observedSoilRelativePercent(valid);
  std::snprintf(expectedSoil, sizeof(expectedSoil), "\"soil_relative_percent\":%d",
                expectedSoilPercent);
  assert(std::strstr(output, expectedSoil) != nullptr);
  assert(std::strstr(output, "\"light_relative_percent\":51") != nullptr);
  assert(std::strstr(output, "\"water_level\":{\"adc_raw\":1789,\"relative_percent\":null,"
                             "\"low\":null,\"status\":\"unverified\",\"raw_reference\":{") != nullptr);
  char expectedWaterBand[160];
  std::snprintf(expectedWaterBand, sizeof(expectedWaterBand),
                "\"band\":\"above_reference\",\"low_at_or_below\":%d,"
                "\"near_below\":%d,\"quality\":\"historical_conflicting\"",
                planter::kWaterLowRawReferenceAdc, planter::kWaterNearRawReferenceAdc);
  assert(std::strstr(output, expectedWaterBand) != nullptr);
  assert(std::strstr(output, "\"soil_supply_mode\":\"gpio25_input_supply_unverified\"") != nullptr);
  char expectedWaterScale[96];
  std::snprintf(expectedWaterScale, sizeof(expectedWaterScale),
                "\"low_mean_adc\":%d,\"near_full_mean_adc\":%d",
                planter::kWaterObservedLowMeanAdc, planter::kWaterObservedNearFullMeanAdc);
  assert(std::strstr(output, expectedWaterScale) != nullptr);
  assert(std::strstr(output, "\"quality\":\"unverified\",\"use_for_control\":false") != nullptr);
  assert(std::strstr(output, "\"mq135\":{\"adc_raw\":1042,\"digital_raw\":1,"
                             "\"adc_status\":\"unverified\",\"status\":\"unverified\","
                             "\"signal_quality\":\"in_range_unverified\"") != nullptr);
  assert(std::strstr(output, "\"co2_ppm\":null,\"air_quality\":null") != nullptr);
  assert(std::strstr(output, "\"adc_pin_mv_estimate\":777,"
                             "\"adc_calibration_source\":\"efuse_vref\"") != nullptr);
  assert(std::strstr(output, "\"environment_compensation\":\"not_applied\"") != nullptr);
  assert(std::strstr(output, "\"observation_label\":null") != nullptr);
  assert(std::strstr(output, "\"firmware_version\":13") != nullptr);
  char expectedSoilScale[96];
  std::snprintf(expectedSoilScale, sizeof(expectedSoilScale),
                "\"soil_dry_mean_adc\":%d,\"soil_immersed_mean_adc\":%d",
                planter::kSoilRelativeZeroAdc, planter::kSoilRelativeFullAdc);
  assert(std::strstr(output, expectedSoilScale) != nullptr);
  assert(std::strstr(output, "\"lighting_rule\":{\"candidate\":\"unavailable\",\"uv_index\":null") != nullptr);
  assert(std::strstr(output, "\"recorded_at_utc\":null") != nullptr);
  assert(std::strstr(output, "\"basis\":\"relative_unverified\",\"pump_on\":true,"
                             "\"growlight_on\":true,\"water_low\":null") != nullptr);
  const planter::ControlStatus reported = {false, true, "water_unavailable", "light_low"};
  assert(formatTelemetry(valid, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"control_preview\":null") != nullptr);
  assert(std::strstr(output, "\"relay_control\":\"automatic_requested\"") != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":false,\"pump_reason\":\"water_unavailable\"") != nullptr);
  assert(std::strstr(output, "\"growlight_cmd\":true,\"growlight_reason\":\"light_low\"") != nullptr);
  assert(std::strstr(output, "\"pump_gpio_level_requested\":\"HIGH\","
                             "\"growlight_gpio_level_requested\":\"HIGH\"") != nullptr);
  assert(std::strstr(output, "\"pump_state\":null,\"growlight_state\":null") != nullptr);
  assert(labels.apply("LABEL SOIL WATER", 1234) == planter::LabelCommandResult::set);
  assert(formatTelemetry(valid, output, sizeof(output), &reported, labels.current(1500)));
  assert(std::strstr(output, "\"observation_label\":{\"sensor\":\"soil\","
                             "\"condition\":\"probe_in_water\",\"source\":\"operator_reported\","
                             "\"start_uptime_ms\":1234,\"max_duration_ms\":180000}") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';
  const planter::RulePreview defaultPreview = planter::previewRules(valid);
  assert(defaultPreview.soilPercent == expectedSoilPercent);
  assert(defaultPreview.pumpOn == planter::belowThresholdPreview(expectedSoilPercent, 50));
  assert(defaultPreview.lightPercent == 51 && defaultPreview.lightOn == 1);
  assert(defaultPreview.waterPercent == -1 && defaultPreview.waterLow == -1);

  // Operator's raw reference is reported separately from the unavailable
  // 0-100% scale and cannot enable the pump interlock by itself.
  SensorSnapshot rawReferenceFixture = valid;
  rawReferenceFixture.waterAdcRaw = planter::kWaterLowRawReferenceAdc;
  assert(formatTelemetry(rawReferenceFixture, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"relative_percent\":null,\"low\":null") != nullptr);
  assert(std::strstr(output, "\"band\":\"at_or_below_low\"") != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":false") != nullptr);
  assert(planter::previewRules(rawReferenceFixture).waterPercent == -1);
  rawReferenceFixture.waterAdcRaw = planter::kWaterLowRawReferenceAdc + 1;
  assert(formatTelemetry(rawReferenceFixture, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"band\":\"near_low\"") != nullptr);
  rawReferenceFixture.waterAdcRaw = planter::kWaterNearRawReferenceAdc;
  assert(formatTelemetry(rawReferenceFixture, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"band\":\"above_reference\"") != nullptr);

  // The new mean-based water display is separate from the pump interlock.
  assert(planter::kWaterObservedNearFullMeanAdc > planter::kWaterObservedLowMeanAdc);
  rawReferenceFixture.waterAdcRaw = planter::kWaterObservedLowMeanAdc;
  assert(planter::observedWaterRelativePercent(rawReferenceFixture) == 0);
  rawReferenceFixture.waterAdcRaw = (planter::kWaterObservedLowMeanAdc +
                                     planter::kWaterObservedNearFullMeanAdc) / 2;
  assert(planter::observedWaterRelativePercent(rawReferenceFixture) == 50);
  assert(formatTelemetry(rawReferenceFixture, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"observation_scale\":{\"relative_percent\":50,") != nullptr);
  assert(std::strstr(output, "\"relative_percent\":null,\"low\":null") != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":false") != nullptr);
  assert(planter::previewRules(rawReferenceFixture).waterPercent == -1);
  std::cout << "TEST_FIXTURE " << output << '\n';
  rawReferenceFixture.waterAdcRaw = planter::kWaterObservedNearFullMeanAdc;
  assert(planter::observedWaterRelativePercent(rawReferenceFixture) == 100);
  rawReferenceFixture.waterAdcRaw = 4094;
  assert(planter::observedWaterRelativePercent(rawReferenceFixture) == 100);
  rawReferenceFixture.waterAdcRaw = 0;
  assert(planter::observedWaterRelativePercent(rawReferenceFixture) == -1);
  rawReferenceFixture.waterAdcRaw = 4095;
  assert(planter::observedWaterRelativePercent(rawReferenceFixture) == -1);
  rawReferenceFixture.waterEnabled = false;
  assert(planter::observedWaterRelativePercent(rawReferenceFixture) == -1);

  // Fixture-only endpoints exercise both directions and the exact 20% edge.
  // They are not calibration values for the real sensor.
  SensorSnapshot waterFixture = valid;
  waterFixture.waterAdcRaw = 380;
  auto preview = planter::previewRules(waterFixture, true, 0, 2000);
  assert(preview.waterPercent == 19 && preview.waterLow == 1);
  waterFixture.waterAdcRaw = 400;
  preview = planter::previewRules(waterFixture, true, 0, 2000);
  assert(preview.waterPercent == 20 && preview.waterLow == 0);
  waterFixture.waterAdcRaw = 1600;
  preview = planter::previewRules(waterFixture, true, 2000, 0);
  assert(preview.waterPercent == 20 && preview.waterLow == 0);
  preview = planter::previewRules(waterFixture, false, 0, 2000);
  assert(preview.waterPercent == -1 && preview.waterLow == -1);
  preview = planter::previewRules(waterFixture, true, 500, 500);
  assert(preview.waterPercent == -1 && preview.waterLow == -1);
  waterFixture.waterEnabled = false;
  preview = planter::previewRules(waterFixture, true, 0, 2000);
  assert(preview.waterPercent == -1 && preview.waterLow == -1);
  waterFixture = valid;
  waterFixture.soilEnabled = false;
  waterFixture.lightAdcRaw = -1;
  preview = planter::previewRules(waterFixture);
  assert(preview.pumpOn == -1 && preview.lightOn == -1);
  std::cout << "TEST_FIXTURE " << output << '\n';

  const SensorSnapshot partial = {
      5001, 24.0f, nan, 0, 0, 0, true, 4096, true, true,
      true, 2399, 0, true, false, -1, planter::AdcCalibrationMethod::unavailable};
  assert(formatTelemetry(partial, output, sizeof(output)));
  assert(std::strstr(output, "\"humidity_percent\":null") != nullptr);
  assert(std::strstr(output, "\"status\":\"partial\"") != nullptr);
  assert(std::strstr(output, "\"water_level\":{\"adc_raw\":null,\"relative_percent\":null,"
                             "\"low\":null,\"status\":\"unavailable\",\"raw_reference\":{") != nullptr);
  assert(std::strstr(output, "\"band\":\"unavailable\"") != nullptr);
  assert(std::strstr(output, "\"mq135\":{\"adc_raw\":null,\"digital_raw\":0,"
                             "\"adc_status\":\"adc_read_failed\",\"status\":\"unverified\","
                             "\"signal_quality\":\"adc_read_failed\"") != nullptr);

  const SensorSnapshot disabled = {
      5002, 24.0f, 64.0f, 123, 0, 0, false, 0, true, false,
      false, 123, 1, false, true, -1, planter::AdcCalibrationMethod::unavailable};
  assert(formatTelemetry(disabled, output, sizeof(output)));
  assert(std::strstr(output, "\"temperature_c\":null") != nullptr);
  assert(std::strstr(output, "\"humidity_percent\":null") != nullptr);
  assert(std::strstr(output, "\"status\":\"not_configured\"") != nullptr);
  assert(std::strstr(output, "\"soil_raw\":null,\"soil_status\":\"not_configured\"") != nullptr);
  // Zero is a raw ADC reading, not proof that a sensor is present or absent.
  assert(std::strstr(output, "\"water_level\":{\"adc_raw\":0,\"relative_percent\":null,"
                             "\"low\":null,\"status\":\"unverified\",\"raw_reference\":{") != nullptr);
  assert(std::strstr(output, "\"band\":\"rail_unverified\"") != nullptr);
  assert(std::strstr(output, "\"mq135\":null") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';

  const SensorSnapshot assumedDht = {
      5003, 24.0f, 64.0f, 0, 0, 0, true, 0, true, false,
      false, 4096, 2, true, true, -1, planter::AdcCalibrationMethod::unavailable};
  assert(formatTelemetry(assumedDht, output, sizeof(output)));
  assert(std::strstr(output, "\"dht\":{\"model\":\"DHT11_assumed\","
                             "\"temperature_c\":24.0,\"humidity_percent\":64.0,"
                             "\"status\":\"unverified\"}") != nullptr);
  assert(std::strstr(output, "\"mq135\":{\"adc_raw\":null,\"digital_raw\":null,"
                             "\"adc_status\":\"unavailable\",\"status\":\"unverified\","
                             "\"signal_quality\":\"unavailable\"") != nullptr);

  SensorSnapshot saturated = valid;
  saturated.mqAdcRaw = 4095;
  assert(formatTelemetry(saturated, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"signal_quality\":\"rail_high_unverified\"") != nullptr);
  assert(std::strstr(output, "\"adc_pin_mv_estimate\":null") != nullptr);
  assert(std::strstr(output, "\"co2_ppm\":null,\"air_quality\":null") != nullptr);
  assert(std::strstr(output, "\"observation_label\":null") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';
  saturated.mqAdcRaw = 0;
  assert(formatTelemetry(saturated, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"signal_quality\":\"rail_low_unverified\"") != nullptr);
  assert(std::strstr(output, "\"adc_pin_mv_estimate\":null") != nullptr);
  saturated.mqAdcRaw = 1000;
  saturated.mqAdcPinMillivolts = 3301;
  assert(formatTelemetry(saturated, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"adc_pin_mv_estimate\":null") != nullptr);

  SensorSnapshot longest = valid;
  longest.uptimeMs = 0xffffffffU;
  longest.temperatureC = -40.0f;
  longest.humidityPercent = 100.0f;
  longest.soilAdcRaw = 4094;
  longest.lightAdcRaw = 4094;
  longest.uvAdcRaw = 4094;
  longest.waterAdcRaw = 4094;
  longest.mqAdcRaw = 4094;
  longest.mqAdcPinMillivolts = 3300;
  longest.mqAdcCalibration = planter::AdcCalibrationMethod::default_vref;
  const planter::ControlStatus inhibited = {false, false, "watchdog_unavailable", "watchdog_unavailable"};
  assert(labels.apply("LABEL WATER NEAR_FULL", 0xffffff00U) == planter::LabelCommandResult::set);
  assert(formatTelemetry(longest, output, sizeof(output), &inhibited,
                         labels.current(0xffffffffU)));
  assert(std::strstr(output, "\"adc_pin_mv_estimate\":3300") != nullptr);
  assert(std::strstr(output, "\"adc_calibration_source\":\"default_vref_estimate\"") != nullptr);
  assert(std::strstr(output, "\"condition\":\"near_full\"") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';

  char tooSmall[8];
  assert(!formatTelemetry(valid, tooSmall, sizeof(tooSmall)));
  assert(!formatTelemetry(valid, nullptr, 512));
  assert(!formatTelemetry(valid, output, 0));
  std::cout << "Sensor telemetry host tests passed (fixture data only).\n";
}
