#pragma once

#include <stdint.h>

namespace planter {

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

// Do not enable GPIO25 as a power source until the sensor's conflicting
// pin labels and its maximum supply current have been independently checked.
// Until then the diagnostic firmware reports soil_raw as null.
constexpr bool kSoilGpioPowerVerified = false;
constexpr uint32_t kSoilPowerSettleMs = 300;

// User-requested inversion: pump OFF requests LOW. Neither assumption proves
// the actual contact state, especially during power-up or reset.
constexpr bool kPumpActiveLow = false;
constexpr bool kLightActiveLow = false;
constexpr bool relayLevel(bool activeLow, bool on) {
  return activeLow ? !on : on;
}

// The original project used DHT11; the actual sensor model is still unverified.
// A successful protocol read is not proof that the selected model is correct.
constexpr bool kDhtEnabled = true;
constexpr bool kDhtModelVerified = false;

// Historical reference points for approximate relative readings, not a
// validated calibration. ADC rails do not establish that a sensor is present.
constexpr int kSoilRelativeZeroAdc = 0;
constexpr int kSoilRelativeFullAdc = 2450;
constexpr int kLightRelativeZeroAdc = 4095;
constexpr int kLightRelativeFullAdc = 0;

// DHT11 requires at least 2 seconds between samples; use 5 seconds here.
constexpr uint32_t kSampleIntervalMs = 5000;

}  // namespace planter
