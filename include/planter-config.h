#pragma once

#include <stdint.h>

// Device-specific calibration is optional and Git-ignored; defaults are generic.
#if !defined(MOSS_DISABLE_LOCAL_CALIBRATION) && __has_include("planter-calibration.local.h")
#include "planter-calibration.local.h"
#endif
#ifndef MOSS_DISPLAY_CALIBRATION_OBSERVED
#define MOSS_DISPLAY_CALIBRATION_OBSERVED 0
#endif
#ifndef MOSS_SOIL_RELATIVE_ZERO_ADC
#define MOSS_SOIL_RELATIVE_ZERO_ADC 300
#endif
#ifndef MOSS_SOIL_RELATIVE_FULL_ADC
#define MOSS_SOIL_RELATIVE_FULL_ADC 1900
#endif
#ifndef MOSS_LIGHT_RELATIVE_DARK_ADC
#define MOSS_LIGHT_RELATIVE_DARK_ADC 2100
#endif
#ifndef MOSS_LIGHT_RELATIVE_BRIGHT_ADC
#define MOSS_LIGHT_RELATIVE_BRIGHT_ADC 0
#endif
#ifndef MOSS_WATER_LOW_REFERENCE_ADC
#define MOSS_WATER_LOW_REFERENCE_ADC 950
#endif
#ifndef MOSS_WATER_NEAR_REFERENCE_ADC
#define MOSS_WATER_NEAR_REFERENCE_ADC 1100
#endif
#ifndef MOSS_WATER_OBSERVED_LOW_ADC
#define MOSS_WATER_OBSERVED_LOW_ADC 450
#endif
#ifndef MOSS_WATER_OBSERVED_NEAR_FULL_ADC
#define MOSS_WATER_OBSERVED_NEAR_FULL_ADC 1500
#endif
#ifndef MOSS_WATER_FULL_REFERENCE_ADC
#define MOSS_WATER_FULL_REFERENCE_ADC 1500
#endif
#ifndef MOSS_SOIL_ZERO_IS_DRY
#define MOSS_SOIL_ZERO_IS_DRY 0
#endif


namespace planter {

constexpr unsigned kFirmwareVersion = 52;
// Kept for older tooling that still reads the serial JSON. The active local
// CSV is the fixed 25-column HistoryCsv in the app.
constexpr unsigned kDatasetSchemaVersion = 2;

// Historical project assignments, not a verified wiring diagram.
constexpr int kDhtPin = 4;
constexpr int kSoilPin = 34;
constexpr int kLightPin = 32;
constexpr int kUvPin = 35;
constexpr int kLegacySoilPowerPin = 25;
constexpr int kLegacyPumpRelayPin = 13;
constexpr int kLegacyLightRelayPin = 26;
constexpr int kLegacyI2cSdaPin = 21;
constexpr int kLegacyI2cSclPin = 22;

// GPIO25 was switched as the soil sensor's supply in the original program.
// Leave it as INPUT until the conflicting wiring, pinout and current have been
// independently verified. This does not electrically isolate other inputs.
constexpr bool kSoilPowerWiringVerified = false;
// Try the ADC input independently of GPIO25. The sensor supply and pin voltage
// are still unverified; a number may come from a floating or unsafe circuit.
constexpr bool kSoilAdcReadEnabled = true;
constexpr uint32_t kSoilPowerSettleMs = 300;

// The working reference uses an active-LOW pump module (ON = LOW, OFF = HIGH)
// and an active-HIGH lamp module (ON = HIGH, OFF = LOW). Neither setting proves
// the physical contact state.
constexpr bool kPumpActiveLow = true;
constexpr bool kLightActiveLow = false;
constexpr bool kLightAutomationEnabled = true;
// The I2C LCD backpack exposes the backlight as a single PCF8574 bit, not a
// PWM channel. Firmware can only turn it off after this idle window; 50% dim
// requires a hardware PWM/MOSFET or a series resistor.
constexpr uint32_t kLcdBacklightIdleMs = 0;
constexpr bool relayLevel(bool activeLow, bool on) {
  return activeLow ? !on : on;
}

// Relay staging: hold both coils inactive after boot and space ON transitions
// by 500 ms. OFF is always immediate.
constexpr uint32_t kRelayEnableDelayMs = 2000;
constexpr uint32_t kRelaySwitchGapMs = 500;
// Freeze automatic pump/lamp decisions for 3 s after a relay edge; raw values
// are still logged. Hardware separation remains the real transient fix.
constexpr uint32_t kRelaySettleMs = 3000;
// DHT11 is assumed; a successful read does not verify the model.
constexpr bool kDhtEnabled = true;
constexpr bool kDhtModelVerified = false;

// Relative display references, not measured volumetric values.
constexpr bool kDisplayUsesOperatorReferences = MOSS_DISPLAY_CALIBRATION_OBSERVED == 1;
constexpr int kSoilRelativeZeroAdc = MOSS_SOIL_RELATIVE_ZERO_ADC;
constexpr int kSoilRelativeFullAdc = MOSS_SOIL_RELATIVE_FULL_ADC;
// A disconnected probe can also read 0; pump guards still apply.
constexpr bool kSoilZeroIsDry = MOSS_SOIL_ZERO_IS_DRY == 1;

// Brightness scale: 0% at the dark endpoint, 100% at the bright endpoint.
// This LDR is descending: ~2100 ADC dark, 0 ADC bright.
constexpr int kLightRelativeZeroAdc = MOSS_LIGHT_RELATIVE_DARK_ADC;
constexpr int kLightRelativeFullAdc = MOSS_LIGHT_RELATIVE_BRIGHT_ADC;

// Hysteresis for the pump. ON below 1000, OFF at/above 1200. The gap keeps a
// just-lifted, still-wet probe from starting the pump on a transient drop.
// A single 0/rail-like soil sample (for example a relay/load transient) must
// not start the pump; require five consecutive dry samples = ~10 s at 2 s.
// Host tests may override this to keep their short fixtures.
constexpr int kPumpOnBelowRawAdc = 1000;
constexpr int kPumpOffAtOrAboveRawAdc = 1200;
#ifndef MOSS_PUMP_DRY_CONFIRM_SAMPLES
#define MOSS_PUMP_DRY_CONFIRM_SAMPLES 5
#endif
constexpr int kPumpDryConfirmSamples = MOSS_PUMP_DRY_CONFIRM_SAMPLES;
// A lamp ON request must also persist. One dark reading during a relay edge is
// not enough to click the lamp relay.
#ifndef MOSS_LIGHT_CONFIRM_SAMPLES
#define MOSS_LIGHT_CONFIRM_SAMPLES 3
#endif
constexpr int kLightConfirmSamples = MOSS_LIGHT_CONFIRM_SAMPLES;
// User-requested single LDR edge: below 65% relative brightness requests ON,
// 65% or more requests OFF. UV remains monitoring only and never controls it.
constexpr int kLightOnBelowPercent = 65;
constexpr int kLightOffAtOrAbovePercent = 65;
constexpr int kWaterLowBelowPercent = 20;
// Pump cutoff is lower than the display warning so a tilted tank can still water.
constexpr int kPumpWaterLowRawAdc = 600;
// While running, require six consecutive low samples (12 s) before stopping.
constexpr int kWaterLowRunningConfirmSamples = 6;

// Local-only WPA2 access point; no router credentials are stored.
constexpr uint16_t kLocalTelemetryPort = 3333;

constexpr uint32_t kBootGraceMs = 5000;
// Hard cap for automatic watering; manual runs are capped separately.
constexpr uint32_t kPumpMaxOnMs = 300000;
constexpr uint32_t kPumpManualMaxOnMs = 30000;
constexpr uint32_t kLightManualMaxOnMs = 1800000;  // 30 minutes
constexpr uint32_t kPumpCooldownMs = 30000;
// Ten-minute lockout after hitting the runtime cap.
constexpr uint32_t kPumpRuntimeSoakMs = 600000;
// Stop if the soil reading does not move within two minutes.
constexpr uint32_t kPumpEffectCheckMs = 120000;
constexpr int kPumpEffectMinDelta = 20;
constexpr uint32_t kPumpNoResponseCooldownMs = 300000;
// Hold automatic watering for one minute after a brownout boot.
constexpr uint32_t kBrownoutPumpHoldMs = 60000;
constexpr uint32_t kLightMinStateMs = 5000;
constexpr uint32_t kSampleStaleMs = 15000;
constexpr uint32_t kWatchdogTimeoutSeconds = 8;

// Explicitly allow the user-requested test with the unverified soil input;
// missing/rail inputs, low water and watchdog failures still prevent ON.
constexpr bool kPumpSoilScaleConfirmed = false;
constexpr bool kPumpAllowEstimatedSoil = true;

// Provisional low-to-near-full references for the water safety condition, not
// measured empty/full calibration. Rails and missing reads remain unavailable.
constexpr bool kWaterRelativeScaleEnabled = true;
constexpr int kWaterEmptyAdc = MOSS_WATER_OBSERVED_LOW_ADC;
constexpr int kWaterFullAdc = MOSS_WATER_OBSERVED_NEAR_FULL_ADC;

// Display-only low reference bands; these do not authorize pump operation.
constexpr int kWaterLowRawReferenceAdc = MOSS_WATER_LOW_REFERENCE_ADC;
constexpr int kWaterNearRawReferenceAdc = MOSS_WATER_NEAR_REFERENCE_ADC;
// User-requested scale: FULL starts at 1500 ADC. Values between LOW and FULL
// are MEDIUM, so the display does not jump from LOW straight to FULL.
constexpr int kWaterFullRawReferenceAdc = MOSS_WATER_FULL_REFERENCE_ADC;
// The user observed ~400 ADC only when the level sensor was completely out of
// water. At or below this raw value the UI reports EMPTY, distinct from LOW.
constexpr int kWaterEmptyRawReferenceAdc = 450;

// Relative references shared by the display and provisional water control;
// they are not measured tank volume or verified empty/full calibration.
constexpr int kWaterObservedLowMeanAdc = MOSS_WATER_OBSERVED_LOW_ADC;
constexpr int kWaterObservedNearFullMeanAdc = MOSS_WATER_OBSERVED_NEAR_FULL_ADC;

// Two-second cadence is the DHT11 minimum and keeps dataset rows uniform.
constexpr uint32_t kSampleIntervalMs = 2000;

// Local AP power profile; this does not replace a supply sized for Wi-Fi peaks.
#ifndef MOSS_CPU_MHZ
#define MOSS_CPU_MHZ 240
#endif
constexpr uint32_t kCpuFrequencyMhz = MOSS_CPU_MHZ;
constexpr uint16_t kLocalApBeaconIntervalTu = 100;          // 102.4 ms
constexpr uint8_t kLocalApMaxClients = 4;
// Settling delay after an ADC channel switch.
constexpr uint32_t kAdcSettleUs = 200;

}  // namespace planter
