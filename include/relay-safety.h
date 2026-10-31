#pragma once

#include <stdint.h>

#include "planter-config.h"

namespace planter {

// Preload both inactive output levels before enabling either GPIO. This cannot
// control boot-time levels or prove the state of an external relay or load.
template <typename Gpio>
void configureRelaysInactive(Gpio& gpio) {
  const bool pumpOffHigh = relayLevel(kPumpActiveLow, false);
  const bool lightOffHigh = relayLevel(kLightActiveLow, false);
  gpio.write(kLegacyPumpRelayPin, pumpOffHigh);
  gpio.write(kLegacyLightRelayPin, lightOffHigh);
  gpio.enableOutput(kLegacyPumpRelayPin);
  gpio.enableOutput(kLegacyLightRelayPin);
  gpio.write(kLegacyPumpRelayPin, pumpOffHigh);
  gpio.write(kLegacyLightRelayPin, lightOffHigh);
}

struct ControlStatus {
  bool pumpOn;
  bool lightOn;
  const char* pumpReason;
  const char* lightReason;
};

struct ControlInput {
  int soilPercent;
  int lightPercent;
  int waterPercent;
  bool soilScaleConfirmed;
  bool waterScaleConfirmed;
  bool watchdogReady;
  bool lightAutomationEnabled;
  // UV index in tenths, or -1 when a calibrated index is unavailable. Raw ADC
  // and a percentage are not a UV index and must never be substituted here.
  int uvIndexTenths;
};

inline bool controlPercentValid(int value) { return value >= 0 && value <= 100; }

enum class LightDecision { off, on, hold, unavailable };

// Either sensor can indicate sufficient light. Turning ON requires both
// readings; unknown input cannot be interpreted as darkness. The 65-70% band
// and exactly UV index 7 retain the previous state rather than chatter.
inline LightDecision dualSensorLightDecision(int lightPercent, int uvIndexTenths) {
  const bool lightValid = controlPercentValid(lightPercent);
  const bool uvValid = uvIndexTenths >= 0 && uvIndexTenths <= 250;
  if ((lightValid && lightPercent >= kLightOffAtOrAbovePercent) ||
      (uvValid && uvIndexTenths > kUvLightOffAboveTenths)) {
    return LightDecision::off;
  }
  if (!lightValid || !uvValid) return LightDecision::unavailable;
  if (lightPercent < kLightOnBelowPercent &&
      uvIndexTenths < kUvLightOffAboveTenths) {
    return LightDecision::on;
  }
  return LightDecision::hold;
}

inline const char* lightDecisionName(LightDecision decision) {
  switch (decision) {
    case LightDecision::off: return "off";
    case LightDecision::on: return "on";
    case LightDecision::hold: return "hold";
    default: return "unavailable";
  }
}

// A rail can be legitimate, but is ambiguous for actuator control. Keep raw
// telemetry, while forcing affected commands OFF until input is non-rail.
inline bool controlAnalogUsable(int raw) { return raw > 0 && raw < 4095; }
inline bool controlWaterAdcUsable(int raw) { return controlAnalogUsable(raw); }

inline bool controlIntervalElapsed(uint32_t nowMs, uint32_t thenMs,
                                   uint32_t intervalMs) {
  return static_cast<uint32_t>(nowMs - thenMs) >= intervalMs;
}

// This controls only requested output levels, not physical relay contacts.
// The runtime limit and stale-data checks need the loop/watchdog to execute;
// separate hardware protection is necessary for failures outside software.
class RelayController {
 public:
  void begin(uint32_t nowMs) {
    initialized_ = true;
    hasSample_ = false;
    pumpOn_ = false;
    lightOn_ = false;
    bootMs_ = nowMs;
    lastSampleMs_ = nowMs;
    pumpStartedMs_ = nowMs;
    pumpStoppedMs_ = nowMs;
    lightChangedMs_ = nowMs;
    // Require a full cooldown after boot as well as after any pump run.
    pumpCooldown_ = true;
    pumpReason_ = "boot_grace";
    lightReason_ = "boot_grace";
  }

  void tick(uint32_t nowMs) {
    if (!initialized_) return;
    if (pumpOn_ && controlIntervalElapsed(nowMs, pumpStartedMs_, kPumpMaxOnMs)) {
      stopPump(nowMs, "runtime_limit");
    }
    if (hasSample_ && controlIntervalElapsed(nowMs, lastSampleMs_, kSampleStaleMs)) {
      stopPump(nowMs, "sample_stale");
      setLight(nowMs, false, "sample_stale");
    }
  }

  void inhibit(uint32_t nowMs, const char* reason) {
    stopPump(nowMs, reason);
    setLight(nowMs, false, reason);
  }

  void accept(uint32_t nowMs, const ControlInput& input) {
    if (!initialized_) begin(nowMs);
    tick(nowMs);
    hasSample_ = true;
    lastSampleMs_ = nowMs;

    if (!input.watchdogReady) {
      inhibit(nowMs, "watchdog_unavailable");
      return;
    }
    if (!controlIntervalElapsed(nowMs, bootMs_, kBootGraceMs)) {
      inhibit(nowMs, "boot_grace");
      return;
    }

    if (!input.waterScaleConfirmed || !controlPercentValid(input.waterPercent)) {
      stopPump(nowMs, "water_unavailable");
    } else if (input.waterPercent < kWaterLowBelowPercent) {
      stopPump(nowMs, "water_low");
    } else if (!input.soilScaleConfirmed) {
      stopPump(nowMs, "soil_unverified");
    } else if (!controlPercentValid(input.soilPercent)) {
      stopPump(nowMs, "soil_unavailable");
    } else if (pumpOn_) {
      if (input.soilPercent >= kPumpOffAtPercent) {
        stopPump(nowMs, "soil_moist");
      } else {
        pumpReason_ = "watering";
      }
    } else {
      if (pumpCooldown_ &&
          controlIntervalElapsed(nowMs, pumpStoppedMs_, kPumpCooldownMs)) {
        pumpCooldown_ = false;
      }
      if (input.soilPercent >= kPumpOnBelowPercent) {
        pumpReason_ = "soil_not_dry";
      } else if (pumpCooldown_) {
        pumpReason_ = "cooldown";
      } else {
        pumpOn_ = true;
        pumpStartedMs_ = nowMs;
        pumpReason_ = "soil_dry";
      }
    }

    if (!input.lightAutomationEnabled) {
      setLight(nowMs, false, "light_inhibited");
    } else {
      const LightDecision decision =
          dualSensorLightDecision(input.lightPercent, input.uvIndexTenths);
      if (decision == LightDecision::off) {
        setLight(nowMs, false, "light_sufficient");
      } else if (decision == LightDecision::unavailable) {
        setLight(nowMs, false, "light_input_unavailable");
      } else if (decision == LightDecision::on && !lightOn_) {
        if (controlIntervalElapsed(nowMs, lightChangedMs_, kLightMinStateMs)) {
          setLight(nowMs, true, "light_low");
        } else {
          lightReason_ = "minimum_hold";
        }
      } else {
        lightReason_ = decision == LightDecision::hold ? "hysteresis" : "light_low";
      }
    }
  }

  ControlStatus status() const { return {pumpOn_, lightOn_, pumpReason_, lightReason_}; }

 private:
  void stopPump(uint32_t nowMs, const char* reason) {
    if (pumpOn_) {
      pumpOn_ = false;
      pumpStoppedMs_ = nowMs;
      pumpCooldown_ = true;
    }
    pumpReason_ = reason;
  }

  void setLight(uint32_t nowMs, bool on, const char* reason) {
    if (lightOn_ != on) {
      lightOn_ = on;
      lightChangedMs_ = nowMs;
    }
    lightReason_ = reason;
  }

  bool initialized_ = false;
  bool hasSample_ = false;
  bool pumpOn_ = false;
  bool lightOn_ = false;
  bool pumpCooldown_ = true;
  uint32_t bootMs_ = 0;
  uint32_t lastSampleMs_ = 0;
  uint32_t pumpStartedMs_ = 0;
  uint32_t pumpStoppedMs_ = 0;
  uint32_t lightChangedMs_ = 0;
  const char* pumpReason_ = "not_initialized";
  const char* lightReason_ = "not_initialized";
};

template <typename Gpio>
void writeRelayCommands(Gpio& gpio, const ControlStatus& status) {
  gpio.write(kLegacyPumpRelayPin, relayLevel(kPumpActiveLow, status.pumpOn));
  gpio.write(kLegacyLightRelayPin, relayLevel(kLightActiveLow, status.lightOn));
}

}  // namespace planter
