#pragma once

#include <stdint.h>

// Optional device-specific display references stay local and are ignored by
// Git. The checked-in defaults below are generic, unverified placeholders.
// Host tests can also exercise generic references without modifying the local
// file. Production builds use local references whenever they are present.
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
#define MOSS_LIGHT_RELATIVE_DARK_ADC 4095
#endif
#ifndef MOSS_LIGHT_RELATIVE_BRIGHT_ADC
#define MOSS_LIGHT_RELATIVE_BRIGHT_ADC 0
#endif
#ifndef MOSS_WATER_LOW_REFERENCE_ADC
#define MOSS_WATER_LOW_REFERENCE_ADC 800
#endif
#ifndef MOSS_WATER_NEAR_REFERENCE_ADC
#define MOSS_WATER_NEAR_REFERENCE_ADC 900
#endif
#ifndef MOSS_WATER_OBSERVED_LOW_ADC
#define MOSS_WATER_OBSERVED_LOW_ADC 1000
#endif
#ifndef MOSS_WATER_OBSERVED_NEAR_FULL_ADC
#define MOSS_WATER_OBSERVED_NEAR_FULL_ADC 1400
#endif
#ifndef MOSS_SOIL_ZERO_IS_DRY
#define MOSS_SOIL_ZERO_IS_DRY 0
#endif


namespace planter {

constexpr unsigned kFirmwareVersion = 28;

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
constexpr bool relayLevel(bool activeLow, bool on) {
  return activeLow ? !on : on;
}

// Relay output staging. Both coils are held inactive for a short settle window
// after boot, and two ON transitions are separated by 150 milliseconds so the
// coil inrush events do not coincide. OFF is always immediate. These values are
// milliseconds, not seconds.
constexpr uint32_t kRelayEnableDelayMs = 2000;
constexpr uint32_t kRelaySwitchGapMs = 150;

// The original project used DHT11; the actual sensor model is still unverified.
// A successful protocol read is not proof that the selected model is correct.
constexpr bool kDhtEnabled = true;
constexpr bool kDhtModelVerified = false;

// Unverified relative references; local values override generic placeholders.
// They are not measured 0/100% soil water content.
constexpr bool kDisplayUsesOperatorReferences = MOSS_DISPLAY_CALIBRATION_OBSERVED == 1;
constexpr int kSoilRelativeZeroAdc = MOSS_SOIL_RELATIVE_ZERO_ADC;
constexpr int kSoilRelativeFullAdc = MOSS_SOIL_RELATIVE_FULL_ADC;
// Device-specific: the user verified a truly dry stem reads a stable 0 ADC.
// A disconnected probe can also read 0, so water/runtime/cooldown guards stay.
constexpr bool kSoilZeroIsDry = MOSS_SOIL_ZERO_IS_DRY == 1;

// Brightness scale: 0 = reported darkness, 100 = reported light. The default
// endpoints are generic; local references are estimates, not measured lux.
constexpr int kLightRelativeZeroAdc = MOSS_LIGHT_RELATIVE_DARK_ADC;
constexpr int kLightRelativeFullAdc = MOSS_LIGHT_RELATIVE_BRIGHT_ADC;

// Hysteresis for the pump. ON below 1000, OFF at/above 1200. The gap keeps a
// just-lifted, still-wet probe from starting the pump on a transient drop.
// ADC 4095 remains unavailable.
constexpr int kPumpOnBelowRawAdc = 1000;
constexpr int kPumpOffAtOrAboveRawAdc = 1200;
constexpr int kPumpDryConfirmSamples = 1;
// User-requested single LDR edge: below 65% relative brightness requests ON,
// 65% or more requests OFF. UV remains monitoring only and never controls it.
constexpr int kLightOnBelowPercent = 65;
constexpr int kLightOffAtOrAbovePercent = 65;
constexpr int kWaterLowBelowPercent = 20;
// The display can warn at the 826 ADC low reference, but the pump guard is
// intentionally lower so a tilted or partly empty tank can still water. The
// user observed ~400 ADC only when the level sensor was completely dry.
constexpr int kPumpWaterLowRawAdc = 600;
// The pump's own load pulls the water-level reading down while it runs, so a
// single low sample is not proof of an empty reservoir. A running pump stops
// only after this many consecutive low samples (6 x 5 s = 30 s). While the
// pump is idle, one low sample is enough to block the next start.
constexpr int kWaterLowRunningConfirmSamples = 6;

// Dedicated, read-only, password-protected local Wi-Fi access point. No router
// credentials are read or stored; the application connects to this endpoint.
constexpr uint16_t kLocalTelemetryPort = 3333;

constexpr uint32_t kBootGraceMs = 5000;
// Automatic watering may run continuously until the soil sensor reaches the
// upper threshold. The hard cap prevents an endless run if the sensor or
// water path fails; manual commands remain capped separately at 30 seconds.
constexpr uint32_t kPumpMaxOnMs = 300000;
constexpr uint32_t kPumpManualMaxOnMs = 30000;
constexpr uint32_t kLightManualMaxOnMs = 1800000;  // 30 minutes
constexpr uint32_t kPumpCooldownMs = 30000;
// After hitting the hard cap, lock out automatic watering for 30 minutes so a
// failed sensor cannot flood the pot. A manual command can still be used.
constexpr uint32_t kPumpRuntimeSoakMs = 1800000;
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
// The user observed ~400 ADC only when the level sensor was completely out of
// water. At or below this raw value the UI reports EMPTY, distinct from LOW.
constexpr int kWaterEmptyRawReferenceAdc = 450;

// Relative references shared by the display and provisional water control;
// they are not measured tank volume or verified empty/full calibration.
constexpr int kWaterObservedLowMeanAdc = MOSS_WATER_OBSERVED_LOW_ADC;
constexpr int kWaterObservedNearFullMeanAdc = MOSS_WATER_OBSERVED_NEAR_FULL_ADC;

// DHT11 requires at least 2 seconds between samples; use 5 seconds here.
constexpr uint32_t kSampleIntervalMs = 5000;

}  // namespace planter
