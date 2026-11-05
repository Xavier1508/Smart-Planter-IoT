#pragma once

#include <stdint.h>

// Device-specific references override these generic defaults when present.
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
// Older serial tooling uses this schema; the app CSV has 25 columns.
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

// Keep GPIO25 as INPUT until the supply wiring and current are verified.
// This does not electrically isolate the other inputs.
constexpr bool kSoilPowerWiringVerified = false;
// ADC34 can be read separately; check its supply and input voltage.
constexpr bool kSoilAdcReadEnabled = true;
constexpr uint32_t kSoilPowerSettleMs = 300;

// Pump ON is LOW, lamp ON is HIGH. These levels do not prove contact state.
constexpr bool kPumpActiveLow = true;
constexpr bool kLightActiveLow = false;
constexpr bool kLightAutomationEnabled = true;
// The LCD backlight is on/off only; dimming needs additional hardware.
constexpr uint32_t kLcdBacklightIdleMs = 0;
constexpr bool relayLevel(bool activeLow, bool on) {
  return activeLow ? !on : on;
}

// Delay relay ON after boot and space ON transitions. OFF is immediate.
constexpr uint32_t kRelayEnableDelayMs = 2000;
constexpr uint32_t kRelaySwitchGapMs = 500;
// Hold automatic ON decisions after a relay edge; raw readings are still logged.
// Separate power and ground wiring remains important.
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

// LDR scale: 2100 ADC is dark and 0 ADC is bright.
constexpr int kLightRelativeZeroAdc = MOSS_LIGHT_RELATIVE_DARK_ADC;
constexpr int kLightRelativeFullAdc = MOSS_LIGHT_RELATIVE_BRIGHT_ADC;

// Pump hysteresis: ON below 1000 and OFF at or above 1200 ADC.
// Five dry samples reduce transient starts; host tests may override the count.
constexpr int kPumpOnBelowRawAdc = 1000;
constexpr int kPumpOffAtOrAboveRawAdc = 1200;
#ifndef MOSS_PUMP_DRY_CONFIRM_SAMPLES
#define MOSS_PUMP_DRY_CONFIRM_SAMPLES 5
#endif
constexpr int kPumpDryConfirmSamples = MOSS_PUMP_DRY_CONFIRM_SAMPLES;
// Confirm lamp ON over multiple samples to reduce transient switching.
#ifndef MOSS_LIGHT_CONFIRM_SAMPLES
#define MOSS_LIGHT_CONFIRM_SAMPLES 3
#endif
constexpr int kLightConfirmSamples = MOSS_LIGHT_CONFIRM_SAMPLES;
// LDR below 65% requests ON; UV is for monitoring only.
constexpr int kLightOnBelowPercent = 65;
constexpr int kLightOffAtOrAbovePercent = 65;
constexpr int kWaterLowBelowPercent = 20;
// Pump cutoff is lower than the display warning so a tilted tank can still water.
constexpr int kPumpWaterLowRawAdc = 600;
// Stop automatic watering after six consecutive low-water samples.
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

// Allow the provisional soil scale; water and watchdog guards still apply.
constexpr bool kPumpSoilScaleConfirmed = false;
constexpr bool kPumpAllowEstimatedSoil = true;

// Provisional water references; missing and rail readings remain unavailable.
constexpr bool kWaterRelativeScaleEnabled = true;
constexpr int kWaterEmptyAdc = MOSS_WATER_OBSERVED_LOW_ADC;
constexpr int kWaterFullAdc = MOSS_WATER_OBSERVED_NEAR_FULL_ADC;

// Display-only low reference bands; these do not authorize pump operation.
constexpr int kWaterLowRawReferenceAdc = MOSS_WATER_LOW_REFERENCE_ADC;
constexpr int kWaterNearRawReferenceAdc = MOSS_WATER_NEAR_REFERENCE_ADC;
// The display reports MEDIUM between LOW and FULL.
constexpr int kWaterFullRawReferenceAdc = MOSS_WATER_FULL_REFERENCE_ADC;
// EMPTY is distinct from the LOW warning.
constexpr int kWaterEmptyRawReferenceAdc = 450;

// Shared relative references, not calibrated tank volume.
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
