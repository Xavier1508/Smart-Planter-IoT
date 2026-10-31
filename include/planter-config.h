#pragma once

#include <stdint.h>

// Optional device-specific display references stay local and are ignored by
// Git. The checked-in defaults below are generic, unverified placeholders.
#if __has_include("planter-calibration.local.h")
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

namespace planter {

constexpr unsigned kFirmwareVersion = 13;

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

// Both loads are reported on NO contacts. Restore the original pump code's
// active-LOW assumption: HIGH requests OFF. The original lamp used active-HIGH.
// Neither setting verifies the physical input, contacts, or boot-time levels.
constexpr bool kPumpActiveLow = true;
constexpr bool kLightActiveLow = false;
// The user reported a hot lamp. Do not request automatic ON until the lamp,
// relay polarity and thermal setup have been independently verified.
constexpr bool kLightAutomationEnabled = false;
constexpr bool relayLevel(bool activeLow, bool on) {
  return activeLow ? !on : on;
}

// The original project used DHT11; the actual sensor model is still unverified.
// A successful protocol read is not proof that the selected model is correct.
constexpr bool kDhtEnabled = true;
constexpr bool kDhtModelVerified = false;

// Display-only references, never measured 0/100% soil water content and never
// authorization for the pump. Local values override generic placeholders.
constexpr bool kDisplayUsesOperatorReferences = MOSS_DISPLAY_CALIBRATION_OBSERVED == 1;
constexpr int kSoilRelativeZeroAdc = MOSS_SOIL_RELATIVE_ZERO_ADC;
constexpr int kSoilRelativeFullAdc = MOSS_SOIL_RELATIVE_FULL_ADC;
// Historical LDR scale; its endpoints and direction are not verified.
constexpr int kLightRelativeZeroAdc = 4095;
constexpr int kLightRelativeFullAdc = 0;

// A legacy single-LDR diagnostic preview is retained for older app snapshots.
// The separate dual-sensor rule below is the requested future lamp logic.
constexpr int kPumpOnBelowPercent = 50;
constexpr int kPumpOffAtPercent = 55;
constexpr int kLegacyLightPreviewBelowPercent = 60;
constexpr int kLightOnBelowPercent = 65;
constexpr int kLightOffAtOrAbovePercent = 70;
// UV index 7 is not 7%; tenths retain the requested >7 boundary exactly.
constexpr int kUvLightOffAboveTenths = 70;
constexpr int kWaterLowBelowPercent = 20;

// Dedicated, read-only, password-protected local Wi-Fi access point. No router
// credentials are read or stored; the application connects to this endpoint.
constexpr uint16_t kLocalTelemetryPort = 3333;

constexpr uint32_t kBootGraceMs = 5000;
constexpr uint32_t kPumpMaxOnMs = 30000;
constexpr uint32_t kPumpCooldownMs = 300000;
constexpr uint32_t kLightMinStateMs = 30000;
constexpr uint32_t kSampleStaleMs = 15000;
constexpr uint32_t kWatchdogTimeoutSeconds = 8;

// Historical soil endpoints are not established calibration. The pump must
// remain inhibited until both the soil scale and water scale are confirmed.
constexpr bool kPumpSoilScaleConfirmed = false;

// No empty/full reference measurements are known for this water sensor yet.
// Keep the scale disabled instead of turning a raw zero into a 0% alert.
constexpr bool kWaterRelativeScaleEnabled = false;
constexpr int kWaterEmptyAdc = -1;
constexpr int kWaterFullAdc = -1;

// Display-only low reference bands; these do not authorize pump operation.
constexpr int kWaterLowRawReferenceAdc = MOSS_WATER_LOW_REFERENCE_ADC;
constexpr int kWaterNearRawReferenceAdc = MOSS_WATER_NEAR_REFERENCE_ADC;

// Display-only relative references, not measured tank volume or empty/full
// calibration. Local references are kept private; defaults are generic.
constexpr int kWaterObservedLowMeanAdc = MOSS_WATER_OBSERVED_LOW_ADC;
constexpr int kWaterObservedNearFullMeanAdc = MOSS_WATER_OBSERVED_NEAR_FULL_ADC;

// DHT11 requires at least 2 seconds between samples; use 5 seconds here.
constexpr uint32_t kSampleIntervalMs = 5000;

}  // namespace planter
