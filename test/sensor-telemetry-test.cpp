#include <cassert>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <vector>

#include "control-command.h"
#include "extra-sensors.h"
#include "local-wifi.h"
#include "planter-config.h"
#include "relay-safety.h"
#include "relay-staging.h"
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

struct LevelGpio {
  bool pumpHigh = true;
  bool lightHigh = false;
  void write(int pin, bool high) {
    if (pin == planter::kLegacyPumpRelayPin) pumpHigh = high;
    if (pin == planter::kLegacyLightRelayPin) lightHigh = high;
  }
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

  // Relay staging: both coils start inactive, stay inactive for the 2-second
  // settle window, and two ON transitions are 150 milliseconds apart. OFF is
  // always immediate. 150 is milliseconds, not seconds.
  planter::RelayStager<LevelGpio> staged;
  LevelGpio stagedLevel;
  staged.begin(0, stagedLevel);
  assert(!staged.pumpOn() && !staged.lightOn());
  assert(stagedLevel.pumpHigh && !stagedLevel.lightHigh);
  staged.update(1999, true, true, stagedLevel);
  assert(!staged.pumpOn() && !staged.lightOn());
  staged.update(2000, true, true, stagedLevel);
  assert(staged.pumpOn());
  assert(!staged.lightOn());
  staged.update(2149, true, true, stagedLevel);
  assert(!staged.lightOn());
  staged.update(2150, true, true, stagedLevel);
  assert(staged.lightOn());
  staged.update(2151, false, false, stagedLevel);
  assert(!staged.pumpOn() && !staged.lightOn());
  assert(stagedLevel.pumpHigh && !stagedLevel.lightHigh);
  staged.update(3000, false, true, stagedLevel);
  assert(staged.lightOn() && !staged.pumpOn());
  staged.update(4000, true, false, stagedLevel);
  assert(!staged.lightOn() && !staged.pumpOn());
  staged.update(4149, true, false, stagedLevel);
  assert(!staged.pumpOn());
  staged.update(4150, true, false, stagedLevel);
  assert(staged.pumpOn());
  planter::RelayStager<LevelGpio> freshStaged;
  LevelGpio freshLevel;
  freshStaged.begin(0, freshLevel);
  freshStaged.update(2000, false, true, freshLevel);
  assert(freshStaged.lightOn() && !freshStaged.pumpOn());

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
  assert(planter::kAdcSamplesPerCycle == 5);
  const auto averageFixture = [](const std::array<int, 5>& values) {
    size_t index = 0;
    const auto result = planter::averageAdc([&]() { return values[index++]; });
    assert(index == planter::kAdcSamplesPerCycle);
    return result;
  };
  auto average = averageFixture({100, 101, 102, 103, 104});
  assert(average.raw == 102 && !average.readFailed);
  average = averageFixture({100, 100, 100, 101, 101});
  assert(average.raw == 100 && !average.readFailed);
  average = averageFixture({100, 100, 101, 101, 101});
  assert(average.raw == 101 && !average.readFailed);
  average = averageFixture({1199, 1199, 1199, 1200, 1200});
  assert(average.raw == 1199 && planter::pumpSoilBand(average.raw) == planter::PumpSoilBand::hold);
  average = averageFixture({1199, 1199, 1200, 1200, 1200});
  assert(average.raw == 1200 && planter::pumpSoilBand(average.raw) == planter::PumpSoilBand::wet);
  average = averageFixture({0, 0, 0, 0, 0});
  assert(average.raw == 0 && !average.readFailed);
  average = averageFixture({4095, 4095, 4095, 4095, 4095});
  assert(average.raw == 4095 && !average.readFailed);
  average = averageFixture({0, 900, 900, 900, 900});
  assert(average.raw == -1 && !average.readFailed);
  average = averageFixture({4095, 900, 900, 900, 900});
  assert(average.raw == -1 && !average.readFailed);
  average = averageFixture({-1, 900, 900, 900, 900});
  assert(average.raw == -1 && average.readFailed);
  average = averageFixture({4096, 900, 900, 900, 900});
  assert(average.raw == -1 && average.readFailed);
  const auto medianFixture = [](const std::array<int, 5>& values) {
    size_t index = 0;
    const int raw = planter::medianAdc([&]() { return values[index++]; });
    assert(index == planter::kAdcSamplesPerCycle);
    return raw;
  };
  assert(medianFixture({0, 0, 500, 600, 700}) == 500);
  assert(medianFixture({4095, 4095, 4095, 4095, 0}) == 4095);
  assert(medianFixture({10, 20, 30, 40, 4095}) == 30);
  assert(medianFixture({-1, -1, -1, -1, -1}) == -1);
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
  assert(planter::kPumpOnBelowRawAdc == 1000);
  assert(planter::kPumpOffAtOrAboveRawAdc == 1200);
  assert(planter::kLightOnBelowPercent == 65);
  assert(planter::kWaterLowBelowPercent == 20);
  assert(planter::kPumpWaterLowRawAdc == 600);
  assert(planter::kWaterEmptyRawReferenceAdc == 450);
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
  assert(planter::kWaterRelativeScaleEnabled);
  assert(planter::kWaterLowRawReferenceAdc > 0);
  assert(planter::kWaterNearRawReferenceAdc > planter::kWaterLowRawReferenceAdc);
  assert(std::strcmp(planter::waterRawReferenceBand(-1), "unavailable") == 0);
  assert(std::strcmp(planter::waterRawReferenceBand(0), "rail_unverified") == 0);
  assert(std::strcmp(planter::waterRawReferenceBand(planter::kWaterEmptyRawReferenceAdc),
                     "empty") == 0);
  assert(std::strcmp(planter::waterRawReferenceBand(planter::kWaterEmptyRawReferenceAdc + 1),
                     "at_or_below_low") == 0);
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
  assert(planter::kLightOffAtOrAbovePercent == 65);
  assert(planter::kLightOnBelowPercent == planter::kLightOffAtOrAbovePercent);
  assert(!planter::controlAnalogUsable(0));
  assert(planter::controlAnalogUsable(1));
  assert(planter::controlAnalogUsable(4094));
  assert(!planter::controlAnalogUsable(4095));
  assert(!planter::controlWaterAdcUsable(-1));
  assert(!planter::controlWaterAdcUsable(0));
  assert(!planter::controlWaterAdcUsable(4095));
  assert(extra_sensors::kWaterLevelPin == 33);
  assert(extra_sensors::kMq135Pin == 36);
  assert(extra_sensors::kMq135DigitalPin == 14);
  assert(planter::kDhtEnabled);
  assert(!planter::kDhtModelVerified);
  assert(planter::kSoilPin == 34);
  assert(planter::kLegacySoilPowerPin == 25);
  assert(!planter::kSoilPowerWiringVerified);
  assert(planter::kSoilAdcReadEnabled);
  assert(planter::kLightAutomationEnabled);
  assert(planter::kPumpAllowEstimatedSoil);
  assert(planter::kFirmwareVersion == 30);

  // Bounded manual-control protocol.
  auto control = planter::parseControlLine("CTRL pump=on dur=5 id=12");
  assert(control.valid && control.pumpSet && control.pumpOn &&
         !control.pumpAuto && control.durationSeconds == 5 &&
         control.hasId && control.id == 12);
  control = planter::parseControlLine("CTRL pump=auto");
  assert(control.valid && control.pumpSet && control.pumpAuto);
  control = planter::parseControlLine("CTRL light=off id=9");
  assert(control.valid && control.lightSet && !control.lightOn);
  control = planter::parseControlLine("CTRL light=on dur=300 id=10");
  assert(control.valid && control.lightSet && control.lightOn &&
         control.durationSeconds == 300);
  assert(!planter::parseControlLine("CTRL pump=maybe").valid);
  assert(!planter::parseControlLine("CTRL pump=on dur=0").valid);
  assert(!planter::parseControlLine("CTRL pump=on dur=1801").valid);
  assert(!planter::parseControlLine("CTRL light=on dur=1801").valid);
  assert(!planter::parseControlLine("CTRL").valid);
  assert(!planter::parseControlLine("HELLO pump=on").valid);
  planter::ControlLineReader controlReader;
  for (const char* text = "CTRL pump=on id=1"; *text != '\0'; ++text) {
    assert(controlReader.push(*text) ==
           planter::ControlLineReader::Result::pending);
  }
  assert(controlReader.push('\n') == planter::ControlLineReader::Result::ready);
  assert(std::strcmp(controlReader.line(), "CTRL pump=on id=1") == 0);



  // Diagnostic bands describe the soil input, not a physical relay or load.
  using planter::PumpSoilBand;
  assert(planter::pumpSoilBand(-1) == PumpSoilBand::unavailable);
  if (planter::kSoilZeroIsDry) {
    assert(planter::pumpSoilBand(0) == PumpSoilBand::dry);
    assert(planter::soilPercentForRaw(0) == 0);
  } else {
    assert(planter::pumpSoilBand(0) == PumpSoilBand::unavailable);
    assert(planter::soilPercentForRaw(0) == -1);
  }
  assert(planter::pumpSoilBand(1) == PumpSoilBand::dry);
  assert(planter::pumpSoilBand(999) == PumpSoilBand::dry);
  assert(planter::pumpSoilBand(1000) == PumpSoilBand::hold);
  assert(planter::pumpSoilBand(1199) == PumpSoilBand::hold);
  assert(planter::pumpSoilBand(1200) == PumpSoilBand::wet);
  assert(planter::pumpSoilBand(1700) == PumpSoilBand::wet);
  assert(planter::pumpSoilBand(4094) == PumpSoilBand::wet);
  assert(planter::pumpSoilBand(4095) == PumpSoilBand::unavailable);
  assert(planter::pumpSoilBand(4096) == PumpSoilBand::unavailable);
  assert(std::strcmp(planter::pumpSoilBandName(PumpSoilBand::dry), "dry") == 0);
  assert(std::strcmp(planter::pumpSoilBandName(PumpSoilBand::hold), "hold") == 0);
  assert(std::strcmp(planter::pumpSoilBandName(PumpSoilBand::wet), "wet") == 0);
  assert(std::strcmp(planter::pumpSoilBandName(PumpSoilBand::unavailable),
                     "unavailable") == 0);
  assert(std::strcmp(planter::pumpSoilBandLcd(PumpSoilBand::dry), "DRY") == 0);
  assert(std::strcmp(planter::pumpSoilBandLcd(PumpSoilBand::hold), "HOLD") == 0);
  assert(std::strcmp(planter::pumpSoilBandLcd(PumpSoilBand::wet), "WET") == 0);
  assert(std::strcmp(planter::pumpSoilBandLcd(PumpSoilBand::unavailable), "N/A") == 0);
  for (const auto band : {PumpSoilBand::dry, PumpSoilBand::hold,
                          PumpSoilBand::wet, PumpSoilBand::unavailable}) {
    char line[17];
    assert(std::snprintf(line, sizeof(line), "P:OFF cmd %s",
                         planter::pumpSoilBandLcd(band)) <= 16);
  }

  // Every non-rail ADC value follows the same threshold from either state.
  for (int raw = 1; raw < 4095; ++raw) {
    const PumpSoilBand band = planter::pumpSoilBand(raw);
    assert((band == PumpSoilBand::dry) == (raw < planter::kPumpOnBelowRawAdc));
    assert((band == PumpSoilBand::wet) == (raw >= planter::kPumpOffAtOrAboveRawAdc));
    assert((band == PumpSoilBand::hold) ==
           (raw >= planter::kPumpOnBelowRawAdc &&
            raw < planter::kPumpOffAtOrAboveRawAdc));
    planter::ControlInput probe = {raw, 70, 80, true, true, true, true};
    planter::RelayController initiallyOff;
    initiallyOff.begin(0);
    initiallyOff.accept(5000, probe);
    initiallyOff.accept(10000, probe);
    assert(initiallyOff.status().pumpOn == (band == PumpSoilBand::dry));
    planter::RelayController initiallyOn;
    initiallyOn.begin(0);
    probe.soilAdcRaw = 1;
    initiallyOn.accept(5000, probe);
    initiallyOn.accept(6000, probe);
    assert(initiallyOn.status().pumpOn);
    probe.soilAdcRaw = raw;
    initiallyOn.accept(10000, probe);
    assert(initiallyOn.status().pumpOn ==
           (raw < planter::kPumpOffAtOrAboveRawAdc));
  }

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

  // The lamp decision uses LDR only. UV is retained for monitoring.
  using planter::LightDecision;
  assert(planter::ldrLightDecision(-1) == LightDecision::unavailable);
  assert(planter::ldrLightDecision(0) == LightDecision::on);
  assert(planter::ldrLightDecision(64) == LightDecision::on);
  assert(planter::ldrLightDecision(65) == LightDecision::off);
  assert(planter::ldrLightDecision(100) == LightDecision::off);
  assert(planter::ldrLightDecision(101) == LightDecision::unavailable);
  assert(planter::uvAdcProxyTenths(-1) == -1);
  assert(planter::uvAdcProxyTenths(0) == 0);
  assert(planter::uvAdcProxyTenths(1) == 0);
  assert(planter::uvAdcProxyTenths(2047) == 69);
  assert(planter::uvAdcProxyTenths(2048) == 70);
  assert(planter::uvAdcProxyTenths(2077) == 71);
  assert(planter::uvAdcProxyTenths(4095) == -1);

  // Fixture-only trial of the actual enabled configuration: both requests
  // become ON under the requested conditions and OFF when those change.
  planter::RelayController enabledTrial;
  enabledTrial.begin(0);
  planter::ControlInput trialInput = {
      999, 39, 50,
      planter::kPumpSoilScaleConfirmed || planter::kPumpAllowEstimatedSoil,
      planter::kWaterRelativeScaleEnabled, true,
      planter::kLightAutomationEnabled};
  enabledTrial.accept(5000, trialInput);
  assert(enabledTrial.status().pumpOn && enabledTrial.status().lightOn);
  FakeGpio trialGpio;
  planter::writeRelayCommands(trialGpio, enabledTrial.status());
  assert(trialGpio.calls[0].pin == 13 && !trialGpio.calls[0].high);
  assert(trialGpio.calls[1].pin == 26 && trialGpio.calls[1].high);
  trialInput.soilAdcRaw = 1200;
  trialInput.lightPercent = 65;
  enabledTrial.accept(10000, trialInput);
  assert(!enabledTrial.status().pumpOn && !enabledTrial.status().lightOn);
  planter::writeRelayCommands(trialGpio, enabledTrial.status());
  assert(trialGpio.calls[2].pin == 13 && trialGpio.calls[2].high);
  assert(trialGpio.calls[3].pin == 26 && !trialGpio.calls[3].high);

  // Exercise the same conversions and configuration as printSample(), while
  // DHT and MQ analog happen to be unavailable. Other sensors still operate.
  const SensorSnapshot trialSample = {
      5000, nan, nan,
      900,
      planter::kLightRelativeZeroAdc, 1000, true,
      (planter::kWaterEmptyAdc + planter::kWaterFullAdc) / 2,
      true, true, false, -1, 1, true, false, -1,
      planter::AdcCalibrationMethod::unavailable};
  // LDR rails follow the local 0(dark)..2360(bright) calibration.
  // A raw 4095 is above the bright endpoint and maps to 100% brightness.
  SensorSnapshot ldrRail = trialSample;
  ldrRail.lightAdcRaw = planter::kLightRelativeZeroAdc;
  assert(planter::previewRules(ldrRail).lightOn == 1);  // Dark endpoint.
  ldrRail.lightAdcRaw = planter::kLightRelativeFullAdc;
  assert(planter::previewRules(ldrRail).lightOn == 0);  // Bright endpoint.
  const planter::RulePreview trialPreview = planter::previewRules(trialSample);
  planter::ControlInput convertedTrial = {
      trialSample.soilAdcRaw, trialPreview.lightPercent, trialPreview.waterPercent,
      planter::kPumpSoilScaleConfirmed || planter::kPumpAllowEstimatedSoil,
      planter::kWaterRelativeScaleEnabled, true,
      planter::kLightAutomationEnabled};
  planter::RelayController convertedControl;
  convertedControl.begin(0);
  convertedControl.accept(trialSample.uptimeMs, convertedTrial);
  assert(convertedControl.status().pumpOn && convertedControl.status().lightOn);
  assert(trialSample.dhtEnabled && trialSample.mqEnabled && !trialSample.mqAdcReadable);

  // The control edge is raw ADC, not the display percentage or a wet endpoint.
  const int onEdge = planter::kPumpOnBelowRawAdc;
  const auto inputForSoil = [&](int raw) {
    planter::ControlInput result = convertedTrial;
    result.soilAdcRaw = raw;
    return result;
  };
  assert(inputForSoil(onEdge - 1).soilAdcRaw == 999);
  assert(inputForSoil(onEdge).soilAdcRaw == 1000);

  planter::RelayController soilBoundary;
  soilBoundary.begin(0);
  soilBoundary.accept(5000, inputForSoil(onEdge));
  assert(!soilBoundary.status().pumpOn);
  soilBoundary.accept(10000, inputForSoil(onEdge - 1));
  assert(soilBoundary.status().pumpOn);
  soilBoundary.accept(15000, inputForSoil(planter::kPumpOffAtOrAboveRawAdc));
  assert(!soilBoundary.status().pumpOn);
  assert(std::strcmp(soilBoundary.status().pumpReason, "soil_moist") == 0);
  soilBoundary.accept(20000, inputForSoil(onEdge - 1));
  assert(!soilBoundary.status().pumpOn);
  soilBoundary.accept(45000, inputForSoil(onEdge - 1));
  assert(soilBoundary.status().pumpOn);
  FakeGpio soilGpioCommands;
  planter::writeRelayCommands(soilGpioCommands, soilBoundary.status());
  soilBoundary.accept(50000, inputForSoil(-1));
  assert(!soilBoundary.status().pumpOn);
  assert(std::strcmp(soilBoundary.status().pumpReason, "soil_unavailable") == 0);
  planter::writeRelayCommands(soilGpioCommands, soilBoundary.status());
  assert(soilGpioCommands.calls[0].pin == 13 && !soilGpioCommands.calls[0].high);
  assert(soilGpioCommands.calls[2].pin == 13 && soilGpioCommands.calls[2].high);

  // Find one raw value at 64% and one at 65%, independent of ADC direction.
  int lightOnRaw = -1;
  int lightOffRaw = -1;
  for (int raw = 0; raw <= 4095; ++raw) {
    const int percent = planter::relativePercent(
        raw, planter::kLightRelativeZeroAdc, planter::kLightRelativeFullAdc);
    if (percent == planter::kLightOnBelowPercent - 1 && lightOnRaw < 0) {
      lightOnRaw = raw;
    }
    if (percent == planter::kLightOffAtOrAbovePercent && lightOffRaw < 0) {
      lightOffRaw = raw;
    }
  }
  assert(lightOnRaw >= 0 && lightOffRaw >= 0);
  const auto inputForLight = [&](int raw, int uvRaw) {
    SensorSnapshot sample = trialSample;
    sample.lightAdcRaw = raw;
    sample.uvAdcRaw = uvRaw;
    planter::ControlInput result = convertedTrial;
    result.lightPercent = planter::controlAnalogUsable(raw)
                              ? planter::previewRules(sample).lightPercent : -1;
    return result;
  };
  assert(inputForLight(lightOnRaw, 0).lightPercent == 64);
  assert(inputForLight(lightOffRaw, 0).lightPercent == 65);
  planter::RelayController lightBoundary;
  lightBoundary.begin(0);
  lightBoundary.accept(5000, inputForLight(lightOffRaw, 0));
  assert(!lightBoundary.status().lightOn);
  lightBoundary.accept(10000, inputForLight(lightOffRaw, 0));
  assert(!lightBoundary.status().lightOn);
  lightBoundary.accept(15000, inputForLight(lightOnRaw, 0));
  assert(lightBoundary.status().lightOn);
  FakeGpio lightGpioCommands;
  planter::writeRelayCommands(lightGpioCommands, lightBoundary.status());
  lightBoundary.accept(20000, inputForLight(lightOffRaw, 0));
  assert(!lightBoundary.status().lightOn);
  planter::writeRelayCommands(lightGpioCommands, lightBoundary.status());
  assert(lightGpioCommands.calls[1].pin == 26 && lightGpioCommands.calls[1].high);
  assert(lightGpioCommands.calls[3].pin == 26 && !lightGpioCommands.calls[3].high);
  lightBoundary.accept(25000, inputForLight(lightOnRaw, 2077));
  assert(lightBoundary.status().lightOn);  // High UV cannot suppress dark LDR.
  lightBoundary.accept(30000, inputForLight(lightOnRaw, -1));
  assert(lightBoundary.status().lightOn);  // Missing UV cannot suppress it either.
  lightBoundary.accept(35000, inputForLight(-1, 0));
  assert(!lightBoundary.status().lightOn);  // Failed LDR read is unavailable.

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
  planter::ControlInput input = {39, 64, 80, true, true, true, true};

  // Manual overrides stay bounded and can be released to automatic.
  planter::RelayController manualControl;
  manualControl.begin(0);
  input = {900, 70, 80, true, true, true, true};
  manualControl.accept(5000, input);
  assert(manualControl.status().pumpOn);
  manualControl.setPumpManual(6000, true, 5000);
  manualControl.accept(6500, input);
  assert(manualControl.status().pumpOn);
  assert(std::strcmp(manualControl.status().pumpReason, "manual_on") == 0);
  manualControl.tick(11000);
  assert(!manualControl.status().pumpOn);
  assert(std::strcmp(manualControl.status().pumpReason, "manual_expired") == 0);
  manualControl.setLightManual(true);
  manualControl.accept(12000, input);
  assert(manualControl.status().lightOn);
  assert(std::strcmp(manualControl.status().lightReason, "manual_on") == 0);
  manualControl.setLightAuto();
  manualControl.accept(13000, input);
  assert(!manualControl.status().lightOn);

  // A timed lamp run ends OFF and stays manually OFF until AUTO.
  planter::RelayController lampTimer;
  lampTimer.begin(0);
  input = {39, 70, 80, true, true, true, true};
  lampTimer.setLightManual(6000, true, 5000);
  lampTimer.accept(6500, input);
  assert(lampTimer.status().lightOn);
  assert(std::strcmp(lampTimer.status().lightReason, "manual_on") == 0);
  lampTimer.tick(11000);
  assert(!lampTimer.status().lightOn);
  assert(std::strcmp(lampTimer.status().lightReason, "manual_expired") == 0);
  lampTimer.accept(15000, input);
  assert(!lampTimer.status().lightOn);
  assert(std::strcmp(lampTimer.status().lightReason, "manual_expired") == 0);
  lampTimer.setLightAuto();
  lampTimer.accept(20000, input);
  assert(!lampTimer.status().lightOn);

  manualControl.setPumpManual(14000, false, 0);
  manualControl.accept(14500, input);
  assert(!manualControl.status().pumpOn);
  assert(std::strcmp(manualControl.status().pumpReason, "manual_off") == 0);
  manualControl.setPumpAuto();
  manualControl.accept(15000, input);
  assert(manualControl.status().pumpOn);

  // Releasing a manual override re-evaluates from a neutral output immediately.
  planter::RelayController autoRelease;
  autoRelease.begin(0);
  input = {39, 70, 80, true, true, true, true};
  autoRelease.setPumpManual(6000, true, 30000);
  autoRelease.accept(6500, input);
  assert(autoRelease.status().pumpOn);
  autoRelease.setPumpAuto();
  assert(!autoRelease.status().pumpOn);
  input.soilAdcRaw = 1200;
  autoRelease.accept(7000, input);
  assert(!autoRelease.status().pumpOn);
  input.soilAdcRaw = 39;
  autoRelease.accept(8000, input);
  assert(autoRelease.status().pumpOn);
  autoRelease.setLightManual(true);
  autoRelease.accept(9000, input);
  assert(autoRelease.status().lightOn);
  autoRelease.setLightAuto();
  assert(!autoRelease.status().lightOn);
  input.lightPercent = 10;
  autoRelease.accept(10000, input);
  assert(autoRelease.status().lightOn);

  input = {39, 64, 80, true, true, true, true};
  planter::RelayController lightControl;
  lightControl.begin(0);
  lightControl.accept(0, input);
  assert(!lightControl.status().pumpOn && !lightControl.status().lightOn);
  assert(std::strcmp(lightControl.status().lightReason, "boot_grace") == 0);
  lightControl.accept(5000, input);
  assert(lightControl.status().lightOn);
  input.lightPercent = 65;  // Single edge: 65% or more requests OFF.
  lightControl.accept(10000, input);
  assert(!lightControl.status().lightOn);
  input.lightPercent = 64;
  lightControl.accept(14999, input);
  assert(!lightControl.status().lightOn);  // Minimum hold still applies.
  lightControl.accept(15000, input);
  assert(lightControl.status().lightOn);
  for (const int uvRaw : {-1, 0, 1000, 2077, 4095}) {
    SensorSnapshot lightFixture = trialSample;
    lightFixture.lightAdcRaw = lightOnRaw;
    lightFixture.uvAdcRaw = uvRaw;
    assert(planter::previewRules(lightFixture).lightOn == 1);
  }
  input.lightPercent = -1;
  lightControl.accept(25000, input);
  assert(!lightControl.status().lightOn);
  assert(std::strcmp(lightControl.status().lightReason, "ldr_input_unavailable") == 0);

  planter::RelayController pumpControl;
  pumpControl.begin(0);
  input = {39, 70, 80, true, true, true, true};
  pumpControl.accept(4999, input);
  assert(!pumpControl.status().pumpOn);
  assert(std::strcmp(pumpControl.status().pumpReason, "boot_grace") == 0);
  pumpControl.accept(5000, input);
  assert(pumpControl.status().pumpOn);
  input.soilAdcRaw = 1199;
  for (uint32_t now = 10000; now <= 300000; now += 5000) {
    pumpControl.accept(now, input);
    assert(pumpControl.status().pumpOn);
  }
  pumpControl.tick(305000);
  assert(!pumpControl.status().pumpOn);
  assert(std::strcmp(pumpControl.status().pumpReason, "runtime_limit") == 0);
  input.soilAdcRaw = 39;
  pumpControl.accept(2104999, input);
  assert(!pumpControl.status().pumpOn);
  assert(std::strcmp(pumpControl.status().pumpReason, "runtime_limit") == 0);
  pumpControl.accept(2105000, input);
  assert(pumpControl.status().pumpOn);
  input.soilAdcRaw = 1200;
  pumpControl.accept(2110000, input);
  assert(!pumpControl.status().pumpOn);
  assert(std::strcmp(pumpControl.status().pumpReason, "soil_moist") == 0);

  planter::RelayController blockedPump;
  blockedPump.begin(0);
  input = {39, 70, -1, false, false, true, true};
  blockedPump.accept(300000, input);
  assert(!blockedPump.status().pumpOn);
  assert(std::strcmp(blockedPump.status().pumpReason, "water_unavailable") == 0);
  input.waterScaleEnabled = true;
  input.waterPercent = 80;
  blockedPump.accept(305000, input);
  assert(!blockedPump.status().pumpOn);
  assert(std::strcmp(blockedPump.status().pumpReason, "soil_unverified") == 0);
  input.soilControlAllowed = true;
  blockedPump.accept(310000, input);
  assert(blockedPump.status().pumpOn);
  // A single low reading while the pump runs is treated as load disturbance,
  // because the pump itself pulls the water-level sensor down.
  input.waterPercent = 19;
  blockedPump.accept(315000, input);
  assert(blockedPump.status().pumpOn);
  assert(std::strcmp(blockedPump.status().pumpReason, "watering") == 0);
  input.waterPercent = 45;
  blockedPump.accept(320000, input);
  assert(blockedPump.status().pumpOn);
  // A low reading that persists for the full confirmation window stops it.
  input.waterPercent = 19;
  for (int i = 0; i < planter::kWaterLowRunningConfirmSamples; ++i) {
    blockedPump.accept(325000 + static_cast<uint32_t>(i) * 5000, input);
  }
  assert(!blockedPump.status().pumpOn);
  assert(std::strcmp(blockedPump.status().pumpReason, "water_low") == 0);
  // While idle, one low sample blocks the next automatic start.
  blockedPump.accept(360000, input);
  assert(!blockedPump.status().pumpOn);
  assert(std::strcmp(blockedPump.status().pumpReason, "water_low") == 0);
  input.waterPercent = 45;
  blockedPump.accept(390000, input);
  assert(blockedPump.status().pumpOn);

  // Raw water guard: 700 ADC is below the 20% display warning but above the
  // 600 ADC pump cutoff, so automatic watering may run. 590 ADC stops it.
  planter::RelayController rawWaterPump;
  rawWaterPump.begin(0);
  input = {39, 70, 0, true, true, true, true};
  input.waterAdcRaw = 700;
  rawWaterPump.accept(5000, input);
  assert(rawWaterPump.status().pumpOn);
  assert(std::strcmp(rawWaterPump.status().pumpReason, "soil_dry") == 0);
  input.waterAdcRaw = 590;
  for (int i = 0; i < planter::kWaterLowRunningConfirmSamples; ++i) {
    rawWaterPump.accept(10000 + static_cast<uint32_t>(i) * 5000, input);
  }
  assert(!rawWaterPump.status().pumpOn);
  assert(std::strcmp(rawWaterPump.status().pumpReason, "water_low") == 0);
  rawWaterPump.accept(60000, input);
  assert(!rawWaterPump.status().pumpOn);
  assert(std::strcmp(rawWaterPump.status().pumpReason, "water_low") == 0);
  input.waterAdcRaw = 700;
  rawWaterPump.accept(65000, input);
  assert(rawWaterPump.status().pumpOn);

  planter::RelayController boundaryWater;
  boundaryWater.begin(0);
  input = {39, 70, 20, true, true, true, true};
  boundaryWater.accept(300000, input);
  assert(boundaryWater.status().pumpOn);
  input.waterPercent = -1;
  boundaryWater.accept(305000, input);
  assert(!boundaryWater.status().pumpOn);
  assert(std::strcmp(boundaryWater.status().pumpReason, "water_unavailable") == 0);

  planter::RelayController invalidSoil;
  invalidSoil.begin(0);
  input = {39, 70, 80, true, true, true, true};
  invalidSoil.accept(300000, input);
  assert(invalidSoil.status().pumpOn);
  input.soilAdcRaw = -1;
  invalidSoil.accept(305000, input);
  assert(!invalidSoil.status().pumpOn);
  assert(std::strcmp(invalidSoil.status().pumpReason, "soil_unavailable") == 0);
  // Failure, either ADC rail, and mixed-rail averages independently prevent ON
  // and stop an already requested ON. The water fixture permits operation.
  const int mixedRailSoil = averageFixture({0, 1000, 1000, 1000, 1000}).raw;
  const int failedSoil = averageFixture({-1, 1000, 1000, 1000, 1000}).raw;
  std::vector<int> invalidSoils = {4095, 4096, -1, mixedRailSoil, failedSoil};
  if (!planter::kSoilZeroIsDry) invalidSoils.push_back(0);
  for (const int raw : invalidSoils) {
    planter::RelayController fromOff;
    fromOff.begin(0);
    input = {raw, 70, 80, true, true, true, true};
    fromOff.accept(5000, input);
    assert(!fromOff.status().pumpOn);
    assert(std::strcmp(fromOff.status().pumpReason, "soil_unavailable") == 0);
    planter::RelayController fromOn;
    fromOn.begin(0);
    input.soilAdcRaw = 900;
    fromOn.accept(5000, input);
    assert(fromOn.status().pumpOn);
    input.soilAdcRaw = raw;
    fromOn.accept(10000, input);
    assert(!fromOn.status().pumpOn);
    assert(std::strcmp(fromOn.status().pumpReason, "soil_unavailable") == 0);
  }
  if (planter::kSoilZeroIsDry) {
    planter::RelayController zeroDry;
    zeroDry.begin(0);
    input = {0, 70, 80, true, true, true, true};
    zeroDry.accept(5000, input);
    assert(zeroDry.status().pumpOn);
    assert(std::strcmp(zeroDry.status().pumpReason, "soil_dry") == 0);
  }

  // A mixed-rail LDR average cannot authorize light from either prior state.
  const int mixedRailLight = averageFixture({4095, 3000, 3000, 3000, 3000}).raw;
  assert(mixedRailLight == -1);
  planter::RelayController lightMixed;
  lightMixed.begin(0);
  input = {1000, 10, 80, true, true, true, true};
  lightMixed.accept(5000, input);
  assert(lightMixed.status().lightOn);
  input.lightPercent = mixedRailLight;
  lightMixed.accept(10000, input);
  assert(!lightMixed.status().lightOn);
  assert(std::strcmp(lightMixed.status().lightReason, "ldr_input_unavailable") == 0);

  planter::RelayController staleControl;
  staleControl.begin(0);
  input = {39, 70, 80, true, true, true, true};
  staleControl.accept(300000, input);
  assert(staleControl.status().pumpOn);
  staleControl.tick(315000);
  assert(!staleControl.status().pumpOn);
  assert(std::strcmp(staleControl.status().pumpReason, "sample_stale") == 0);

  planter::RelayController watchdogControl;
  watchdogControl.begin(0);
  input = {39, 39, 80, true, true, true, true};
  watchdogControl.accept(300000, input);
  assert(watchdogControl.status().pumpOn && watchdogControl.status().lightOn);
  input.watchdogReady = false;
  watchdogControl.accept(305000, input);
  assert(!watchdogControl.status().pumpOn && !watchdogControl.status().lightOn);
  assert(std::strcmp(watchdogControl.status().pumpReason, "watchdog_unavailable") == 0);

  planter::RelayController wrapControl;
  const uint32_t nearWrap = 0xffff0000U;
  wrapControl.begin(nearWrap);
  input = {39, 70, 80, true, true, true, true};
  wrapControl.accept(nearWrap + 300000U, input);
  assert(wrapControl.status().pumpOn);
  wrapControl.accept(nearWrap + 305000U, input);
  assert(wrapControl.status().pumpOn);

  planter::RelayController inhibitedLight;
  inhibitedLight.begin(0);
  input = {39, 10, 80, true, true, true, false};
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
  assert(std::strstr(output, "\"adc_sampling\":{\"method\":\"median_5\",\"samples_per_cycle\":5") != nullptr);
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
  assert(planter::observedSoilRelativePercent(soilFixture) ==
         (planter::kSoilZeroIsDry ? 0 : -1));
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
  const int expectedLightPercent = planter::relativePercent(
      valid.lightAdcRaw, planter::kLightRelativeZeroAdc, planter::kLightRelativeFullAdc);
  char expectedLight[64];
  std::snprintf(expectedLight, sizeof(expectedLight), "\"light_relative_percent\":%d",
                expectedLightPercent);
  assert(std::strstr(output, expectedLight) != nullptr);
  assert(std::strstr(output, "\"water_level\":{\"adc_raw\":1789,\"relative_percent\":100,"
                             "\"low\":false,\"empty\":false,\"status\":\"unverified\",\"raw_reference\":{") != nullptr);
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
  assert(std::strstr(output, "\"mq135\":{\"adc_raw\":1042,\"adc_percent\":25,"
                             "\"digital_raw\":1,"
                             "\"adc_status\":\"unverified\",\"status\":\"unverified\","
                             "\"signal_quality\":\"in_range_unverified\"") != nullptr);
  assert(std::strstr(output, "\"co2_ppm\":null,\"air_quality\":null") != nullptr);
  assert(std::strstr(output, "\"adc_pin_mv_estimate\":777,"
                             "\"adc_calibration_source\":\"efuse_vref\"") != nullptr);
  assert(std::strstr(output, "\"environment_compensation\":\"not_applied\"") != nullptr);
  assert(std::strstr(output, "\"observation_label\":null") != nullptr);
  assert(std::strstr(output, "\"firmware_version\":30") != nullptr);
  char expectedSoilScale[96];
  std::snprintf(expectedSoilScale, sizeof(expectedSoilScale),
                "\"soil_dry_mean_adc\":%d,\"soil_immersed_mean_adc\":%d",
                planter::kSoilRelativeZeroAdc, planter::kSoilRelativeFullAdc);
  assert(std::strstr(output, expectedSoilScale) != nullptr);
  char expectedCandidate[160];
  std::snprintf(expectedCandidate, sizeof(expectedCandidate),
                "\"lighting_rule\":{\"mode\":\"ldr_single_threshold\","
                "\"candidate\":\"%s\",\"uv_index\":null",
                planter::lightDecisionName(planter::ldrLightDecision(expectedLightPercent)));
  assert(std::strstr(output, expectedCandidate) != nullptr);
  assert(std::strstr(output, "\"uv_proxy_basis\":\"uncalibrated_adc_0_to_14\"") != nullptr);
  assert(std::strstr(output, "\"uv_role\":\"monitoring_only\"") != nullptr);
  assert(std::strstr(output, "\"recorded_at_utc\":null") != nullptr);
  char expectedPreview[128];
  const planter::RulePreview defaultPreview = planter::previewRules(valid);
  std::snprintf(expectedPreview, sizeof(expectedPreview),
                "\"basis\":\"raw_soil_relative_others_unverified\",\"pump_on\":%s,"
                "\"growlight_on\":%s,\"water_low\":false",
                planter::jsonPreviewBoolean(defaultPreview.pumpOn),
                planter::jsonPreviewBoolean(defaultPreview.lightOn));
  assert(std::strstr(output, expectedPreview) != nullptr);
  const planter::ControlStatus reported = {false, true, "water_unavailable", "ldr_low"};
  assert(formatTelemetry(valid, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"control_preview\":null") != nullptr);
  assert(std::strstr(output, "\"relay_control\":\"automatic_requested\"") != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":false,\"pump_reason\":\"water_unavailable\"") != nullptr);
  assert(std::strstr(output, "\"growlight_cmd\":true,\"growlight_reason\":\"ldr_low\"") != nullptr);
  assert(std::strstr(output, "\"pump_gpio_level_requested\":\"HIGH\","
                              "\"growlight_gpio_level_requested\":\"HIGH\"") != nullptr);
  assert(std::strstr(output, "\"pump_state\":null,\"growlight_state\":null") != nullptr);

  // The serial diagnostic and actual control result stay distinguishable.
  // All sensor values below are synthetic, not readings from the device.
  planter::RelayController pumpDebugControl;
  pumpDebugControl.begin(0);
  SensorSnapshot pumpDebugSample = trialSample;
  auto checkPumpDebug = [&](int raw, uint32_t nowMs) {
    pumpDebugSample.soilAdcRaw = raw;
    pumpDebugSample.uptimeMs = nowMs;
    planter::ControlInput next = inputForSoil(raw);
    next.waterPercent = planter::previewRules(pumpDebugSample).waterPercent;
    pumpDebugControl.accept(nowMs, next);
    const planter::ControlStatus status = pumpDebugControl.status();
    assert(formatTelemetry(pumpDebugSample, output, sizeof(output), &status));
  };
  char expectedPumpDebug[192];
  const int expectedTargetPercent =
      planter::soilPercentForRaw(planter::kPumpOnBelowRawAdc);
  checkPumpDebug(onEdge - 1, 5000);
  std::snprintf(expectedPumpDebug, sizeof(expectedPumpDebug),
                "\"pump_soil_debug\":{\"band\":\"dry\",\"moisture_percent\":%d,"
                "\"target_percent\":%d,\"dry_below_on\":true,"
                "\"wet_at_or_above_off\":false",
                planter::soilPercentForRaw(onEdge - 1), expectedTargetPercent);
  assert(std::strstr(output, expectedPumpDebug) != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":true,\"pump_reason\":\"soil_dry\"") != nullptr);
  assert(std::strstr(output, "\"pump_gpio_level_requested\":\"LOW\"") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';
  checkPumpDebug(onEdge, 10000);
  std::snprintf(expectedPumpDebug, sizeof(expectedPumpDebug),
                "\"pump_soil_debug\":{\"band\":\"hold\",\"moisture_percent\":%d,"
                "\"target_percent\":%d,\"dry_below_on\":false,"
                "\"wet_at_or_above_off\":false",
                planter::soilPercentForRaw(onEdge), expectedTargetPercent);
  assert(std::strstr(output, expectedPumpDebug) != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":true,\"pump_reason\":\"watering\"") != nullptr);
  assert(std::strstr(output, "\"pump_gpio_level_requested\":\"LOW\"") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';
  const int offEdge = planter::kPumpOffAtOrAboveRawAdc;
  checkPumpDebug(offEdge, 15000);
  std::snprintf(expectedPumpDebug, sizeof(expectedPumpDebug),
                "\"pump_soil_debug\":{\"band\":\"wet\",\"moisture_percent\":%d,"
                "\"target_percent\":%d,\"dry_below_on\":false,"
                "\"wet_at_or_above_off\":true",
                planter::soilPercentForRaw(offEdge), expectedTargetPercent);
  assert(std::strstr(output, expectedPumpDebug) != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":false,\"pump_reason\":\"soil_moist\"") != nullptr);
  assert(std::strstr(output, "\"pump_gpio_level_requested\":\"HIGH\"") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';
  checkPumpDebug(1700, 20000);
  std::snprintf(expectedPumpDebug, sizeof(expectedPumpDebug),
                "\"band\":\"wet\",\"moisture_percent\":%d",
                planter::soilPercentForRaw(1700));
  assert(std::strstr(output, expectedPumpDebug) != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":false,\"pump_reason\":\"soil_not_dry\"") != nullptr);
  pumpDebugSample.waterAdcRaw = planter::kWaterEmptyAdc;
  checkPumpDebug(onEdge - 1, 25000);
  assert(std::strstr(output, "\"pump_soil_debug\":{\"band\":\"dry\"") != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":false,\"pump_reason\":\"water_low\"") != nullptr);
  pumpDebugSample.waterAdcRaw = trialSample.waterAdcRaw;
  checkPumpDebug(-1, 30000);
  std::snprintf(expectedPumpDebug, sizeof(expectedPumpDebug),
                "\"pump_soil_debug\":{\"band\":\"unavailable\","
                "\"moisture_percent\":null,\"target_percent\":%d,"
                "\"dry_below_on\":null,\"wet_at_or_above_off\":null",
                expectedTargetPercent);
  assert(std::strstr(output, expectedPumpDebug) != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":false,\"pump_reason\":\"soil_unavailable\"") != nullptr);
  assert(std::strstr(output, "\"on_below_adc\":1000,\"off_at_or_above_adc\":1200") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';

  // Real controller reason strings prevent older apps from attributing LDR
  // decisions or an unavailable LDR to UV. These are synthetic fixtures.
  planter::RelayController lightDebugControl;
  lightDebugControl.begin(0);
  SensorSnapshot lightDebugSample = trialSample;
  const auto checkLightDebug = [&](int lightRaw, int uvRaw, uint32_t nowMs,
                                   const char* expectedReason) {
    lightDebugSample.uptimeMs = nowMs;
    lightDebugSample.lightAdcRaw = lightRaw;
    lightDebugSample.uvAdcRaw = uvRaw;
    lightDebugControl.accept(nowMs, inputForLight(lightRaw, uvRaw));
    const planter::ControlStatus status = lightDebugControl.status();
    assert(std::strcmp(status.lightReason, expectedReason) == 0);
    assert(formatTelemetry(lightDebugSample, output, sizeof(output), &status));
    std::cout << "TEST_FIXTURE " << output << '\n';
  };
  checkLightDebug(lightOnRaw, 4095, 5000, "ldr_low");
  checkLightDebug(lightOffRaw, -1, 10000, "ldr_sufficient");
  checkLightDebug(0, 0, 15000, "ldr_input_unavailable");

  assert(labels.apply("LABEL SOIL WATER", 1234) == planter::LabelCommandResult::set);
  assert(formatTelemetry(valid, output, sizeof(output), &reported, labels.current(1500)));
  assert(std::strstr(output, "\"observation_label\":{\"sensor\":\"soil\","
                             "\"condition\":\"probe_in_water\",\"source\":\"operator_reported\","
                             "\"start_uptime_ms\":1234,\"max_duration_ms\":180000}") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';
  assert(defaultPreview.soilPercent == expectedSoilPercent);
  assert(defaultPreview.pumpOn == (valid.soilAdcRaw < planter::kPumpOnBelowRawAdc ? 1 : 0));
  assert(defaultPreview.lightPercent == expectedLightPercent);
  assert(defaultPreview.lightOn ==
         (planter::ldrLightDecision(expectedLightPercent) == LightDecision::on ? 1
          : planter::ldrLightDecision(expectedLightPercent) == LightDecision::off ? 0 : -1));
  assert(defaultPreview.waterPercent == 100 && defaultPreview.waterLow == 0);

  // The raw reference and provisional water scale are reported separately.
  SensorSnapshot rawReferenceFixture = valid;
  rawReferenceFixture.waterAdcRaw = planter::kWaterLowRawReferenceAdc;
  assert(formatTelemetry(rawReferenceFixture, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"relative_percent\":null,\"low\":true,\"empty\":false") != nullptr);
  assert(std::strstr(output, "\"band\":\"at_or_below_low\"") != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":false") != nullptr);
  assert(planter::previewRules(rawReferenceFixture).waterPercent == 0);

  // A reported near-empty range remains below the pump safety threshold, but
  // the low-reference scale must not be presented as an empty-tank percentage.
  for (const int raw : {700, 750, 800}) {
    SensorSnapshot almostEmpty = trialSample;
    almostEmpty.waterAdcRaw = raw;
    const planter::RulePreview nearEmptyPreview = planter::previewRules(almostEmpty);
    assert(nearEmptyPreview.waterPercent == 0 && nearEmptyPreview.waterLow == 1);
    assert(planter::waterDisplayRelativePercent(nearEmptyPreview.waterPercent) == -1);
    assert(std::strcmp(planter::waterControlBandName(nearEmptyPreview.waterPercent, almostEmpty.waterAdcRaw),
                       "below_threshold") == 0);
    char lcdWater[17];
    planter::formatWaterLcd(lcdWater, sizeof(lcdWater), nearEmptyPreview.waterPercent, almostEmpty.waterAdcRaw);
    assert(std::strcmp(lcdWater, "Water:LOW") == 0);
    planter::RelayController lowTank;
    lowTank.begin(0);
    planter::ControlInput dryInput = convertedTrial;
    dryInput.soilAdcRaw = 20;
    dryInput.waterPercent = nearEmptyPreview.waterPercent;
    lowTank.accept(5000, dryInput);
    assert(!lowTank.status().pumpOn);
    assert(std::strcmp(lowTank.status().pumpReason, "water_low") == 0);
    const planter::ControlStatus lowStatus = lowTank.status();
    almostEmpty.uptimeMs = 15000;  // Ordered after the boundary fixtures for loopback.
    assert(formatTelemetry(almostEmpty, output, sizeof(output), &lowStatus));
    assert(std::strstr(output, "\"relative_percent\":null,\"low\":true,\"empty\":false") != nullptr);
    assert(std::strstr(output, "\"control_band\":\"below_threshold\"") != nullptr);
    assert(std::strstr(output, "\"observation_scale\":{\"relative_percent\":null") != nullptr);
    assert(std::strstr(output, "\"pump_cmd\":false,\"pump_reason\":\"water_low\"") != nullptr);
    assert(std::strstr(output, "\"pump_gpio_level_requested\":\"HIGH\"") != nullptr);
    if (raw == 750) std::cout << "TEST_FIXTURE " << output << '\n';
  }

  SensorSnapshot emptyTank = trialSample;
  emptyTank.waterAdcRaw = planter::kWaterEmptyRawReferenceAdc;
  const planter::RulePreview emptyPreview = planter::previewRules(emptyTank);
  assert(emptyPreview.waterPercent == 0 && emptyPreview.waterLow == 1);
  assert(std::strcmp(planter::waterRawReferenceBand(emptyTank.waterAdcRaw), "empty") == 0);
  assert(std::strcmp(planter::waterControlBandName(emptyPreview.waterPercent,
                                                   emptyTank.waterAdcRaw),
                     "empty") == 0);
  char lcdEmpty[17];
  planter::formatWaterLcd(lcdEmpty, sizeof(lcdEmpty), emptyPreview.waterPercent,
                          emptyTank.waterAdcRaw);
  assert(std::strcmp(lcdEmpty, "Water:EMPTY") == 0);
  emptyTank.uptimeMs = 20000;
  assert(formatTelemetry(emptyTank, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"low\":true,\"empty\":true") != nullptr);
  assert(std::strstr(output, "\"band\":\"empty\"") != nullptr);
  assert(std::strstr(output, "\"control_band\":\"empty\"") != nullptr);
  // In the reported combination, both the water guard and the ambiguous soil
  // rail independently prevent ON; restoring the water input alone is not enough.
  SensorSnapshot bothBlocked = trialSample;
  bothBlocked.soilAdcRaw = -1;
  bothBlocked.waterAdcRaw = 750;
  planter::ControlInput blockedInput = convertedTrial;
  blockedInput.soilAdcRaw = bothBlocked.soilAdcRaw;
  blockedInput.waterPercent = planter::previewRules(bothBlocked).waterPercent;
  planter::RelayController bothBlockedControl;
  bothBlockedControl.begin(0);
  bothBlockedControl.accept(5000, blockedInput);
  assert(!bothBlockedControl.status().pumpOn);
  assert(std::strcmp(bothBlockedControl.status().pumpReason, "water_low") == 0);
  const planter::ControlStatus bothBlockedStatus = bothBlockedControl.status();
  assert(formatTelemetry(bothBlocked, output, sizeof(output), &bothBlockedStatus));
  assert(std::strstr(output, "\"pump_soil_debug\":{\"band\":\"unavailable\"") != nullptr);
  assert(std::strstr(output, "\"control_band\":\"below_threshold\"") != nullptr);
  assert(std::strstr(output, "\"pump_gpio_level_requested\":\"HIGH\"") != nullptr);
  blockedInput.waterPercent = 80;
  bothBlockedControl.accept(10000, blockedInput);
  assert(!bothBlockedControl.status().pumpOn);
  assert(std::strcmp(bothBlockedControl.status().pumpReason, "soil_unavailable") == 0);
  assert(planter::waterDisplayRelativePercent(-1) == -1);
  assert(planter::waterDisplayRelativePercent(0) == -1);
  assert(planter::waterDisplayRelativePercent(1) == 1);
  assert(planter::waterDisplayRelativePercent(100) == 100);
  assert(planter::waterDisplayRelativePercent(101) == -1);
  assert(std::strcmp(planter::waterControlBandName(-1, -1), "unavailable") == 0);
  assert(std::strcmp(planter::waterControlBandName(19, 900), "at_or_above_threshold") == 0);
  assert(std::strcmp(planter::waterControlBandName(20, 900), "at_or_above_threshold") == 0);
  assert(std::strcmp(planter::waterControlBandName(20, 800), "below_threshold") == 0);
  assert(std::strcmp(planter::waterControlBandName(0, planter::kWaterEmptyRawReferenceAdc),
                     "empty") == 0);
  char lcdWaterEmpty[17];
  planter::formatWaterLcd(lcdWaterEmpty, sizeof(lcdWaterEmpty), 0,
                          planter::kWaterEmptyRawReferenceAdc);
  assert(std::strcmp(lcdWaterEmpty, "Water:EMPTY") == 0);
  char lcdWater[17];
  planter::formatWaterLcd(lcdWater, sizeof(lcdWater), -1, -1);
  assert(std::strcmp(lcdWater, "Water:--") == 0);
  planter::formatWaterLcd(lcdWater, sizeof(lcdWater), 20, 900);
  assert(std::strcmp(lcdWater, "Water:MED") == 0);
  planter::formatWaterLcd(lcdWater, sizeof(lcdWater), 100,
                          planter::kWaterFullRawReferenceAdc);
  assert(std::strcmp(lcdWater, "Water:FULL") == 0);
  rawReferenceFixture.waterAdcRaw = planter::kWaterLowRawReferenceAdc + 1;
  assert(formatTelemetry(rawReferenceFixture, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"band\":\"near_low\"") != nullptr);
  rawReferenceFixture.waterAdcRaw = planter::kWaterNearRawReferenceAdc;
  assert(formatTelemetry(rawReferenceFixture, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"band\":\"above_reference\"") != nullptr);

  // The provisional control scale and display scale use the same references.
  assert(planter::kWaterObservedNearFullMeanAdc > planter::kWaterObservedLowMeanAdc);
  rawReferenceFixture.waterAdcRaw = planter::kWaterObservedLowMeanAdc;
  assert(planter::observedWaterRelativePercent(rawReferenceFixture) == 0);
  rawReferenceFixture.waterAdcRaw = (planter::kWaterObservedLowMeanAdc +
                                     planter::kWaterObservedNearFullMeanAdc) / 2;
  assert(planter::observedWaterRelativePercent(rawReferenceFixture) == 50);
  assert(formatTelemetry(rawReferenceFixture, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"observation_scale\":{\"relative_percent\":50,") != nullptr);
  assert(std::strstr(output, "\"relative_percent\":50,\"low\":false,\"empty\":false") != nullptr);
  assert(std::strstr(output, "\"pump_cmd\":false") != nullptr);
  assert(planter::previewRules(rawReferenceFixture).waterPercent == 50);
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

  // Fixture-only endpoints exercise both directions and the raw LOW band.
  // They are not calibration values for the real sensor.
  SensorSnapshot waterFixture = valid;
  waterFixture.waterAdcRaw = 380;
  auto preview = planter::previewRules(waterFixture, true, 0, 2000);
  assert(preview.waterPercent == 19 && preview.waterLow == 1);
  waterFixture.waterAdcRaw = 400;
  preview = planter::previewRules(waterFixture, true, 0, 2000);
  assert(preview.waterPercent == 20 && preview.waterLow == 1);
  waterFixture.waterAdcRaw = planter::kWaterLowRawReferenceAdc;
  preview = planter::previewRules(waterFixture, true, 0, 2000);
  assert(preview.waterLow == 1);
  waterFixture.waterAdcRaw = planter::kWaterLowRawReferenceAdc + 1;
  preview = planter::previewRules(waterFixture, true, 0, 2000);
  assert(preview.waterLow == 0);
  waterFixture.waterAdcRaw = 1600;
  preview = planter::previewRules(waterFixture, true, 2000, 0);
  assert(preview.waterPercent == 20 && preview.waterLow == 0);
  preview = planter::previewRules(waterFixture, false, 0, 2000);
  assert(preview.waterPercent == -1 && preview.waterLow == -1);
  preview = planter::previewRules(waterFixture, true, 500, 500);
  assert(preview.waterPercent == -1 && preview.waterLow == 0);
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
                             "\"low\":null,\"empty\":false,\"status\":\"unavailable\",\"raw_reference\":{") != nullptr);
  assert(std::strstr(output, "\"band\":\"unavailable\"") != nullptr);
  assert(std::strstr(output, "\"mq135\":{\"adc_raw\":null,\"adc_percent\":null,"
                             "\"digital_raw\":0,"
                             "\"adc_status\":\"unavailable\",\"status\":\"unverified\","
                             "\"signal_quality\":\"adc_read_failed\"") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';

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
                             "\"low\":null,\"empty\":false,\"status\":\"unverified\",\"raw_reference\":{") != nullptr);
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
  assert(std::strstr(output, "\"mq135\":{\"adc_raw\":null,\"adc_percent\":null,"
                             "\"digital_raw\":null,"
                             "\"adc_status\":\"unavailable\",\"status\":\"unverified\","
                             "\"signal_quality\":\"unavailable\"") != nullptr);

  SensorSnapshot saturated = valid;
  saturated.mqAdcRaw = 4095;
  assert(formatTelemetry(saturated, output, sizeof(output), &reported));
  assert(std::strstr(output, "\"adc_percent\":100") != nullptr);
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
  // The TCP path also needs room to append its newline terminator.
  assert(std::strlen(output) + 1 < sizeof(output));
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
