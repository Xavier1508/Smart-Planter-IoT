#pragma once

#include <stdint.h>
#include <string.h>

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
  ControlStatus(bool pumpOnValue, bool lightOnValue, const char* pumpReasonValue,
                const char* lightReasonValue, uint32_t cooldownSeconds = 0,
                bool runtimeLockout = false)
      : pumpOn(pumpOnValue),
        lightOn(lightOnValue),
        pumpReason(pumpReasonValue),
        lightReason(lightReasonValue),
        pumpCooldownRemainingS(cooldownSeconds),
        pumpRuntimeLockout(runtimeLockout) {}

  bool pumpOn;
  bool lightOn;
  const char* pumpReason;
  const char* lightReason;
  uint32_t pumpCooldownRemainingS;
  bool pumpRuntimeLockout;
};

struct ControlInput {
  ControlInput(int soilAdcRaw_, int lightPercent_, int waterPercent_,
               bool soilControlAllowed_, bool waterScaleEnabled_,
               bool watchdogReady_, bool lightAutomationEnabled_,
               int waterAdcRaw_ = -1, bool relayTransient_ = false)
      : soilAdcRaw(soilAdcRaw_),
        lightPercent(lightPercent_),
        waterPercent(waterPercent_),
        soilControlAllowed(soilControlAllowed_),
        waterScaleEnabled(waterScaleEnabled_),
        watchdogReady(watchdogReady_),
        lightAutomationEnabled(lightAutomationEnabled_),
        waterAdcRaw(waterAdcRaw_),
        relayTransient(relayTransient_) {}

  int soilAdcRaw;
  int lightPercent;
  int waterPercent;
  bool soilControlAllowed;
  bool waterScaleEnabled;
  bool watchdogReady;
  bool lightAutomationEnabled;
  // A negative raw value uses the relative level, mainly for older fixtures.
  int waterAdcRaw;
  // Pump and relay transients can affect ADC readings; raw values are logged.
  bool relayTransient;
};

inline bool controlPercentValid(int value) { return value >= 0 && value <= 100; }

// The pump cutoff and the 20% display warning use different thresholds.
inline bool pumpWaterLow(const ControlInput& input) {
  if (input.waterAdcRaw >= 0) return input.waterAdcRaw < kPumpWaterLowRawAdc;
  return input.waterPercent < kWaterLowBelowPercent;
}

// A soil-only diagnostic using the same raw ADC threshold as RelayController.
// It never overrides water, watchdog, timing, or other pump safety guards.
enum class PumpSoilBand { dry, hold, wet, unavailable };

// 4095 is always ambiguous. 0 is dry only when the device-specific calibration
// says the probe really reads 0 in dry air; otherwise it stays unavailable.
inline bool soilAnalogUsable(int raw) {
  if (raw < 0 || raw >= 4095) return false;
  if (raw == 0) return kSoilZeroIsDry;
  return true;
}

inline PumpSoilBand pumpSoilBand(int soilAdcRaw) {
  if (!soilAnalogUsable(soilAdcRaw)) return PumpSoilBand::unavailable;
  if (soilAdcRaw < kPumpOnBelowRawAdc) return PumpSoilBand::dry;
  if (soilAdcRaw >= kPumpOffAtOrAboveRawAdc) return PumpSoilBand::wet;
  return PumpSoilBand::hold;
}

inline const char* pumpSoilBandName(PumpSoilBand band) {
  switch (band) {
    case PumpSoilBand::dry: return "dry";
    case PumpSoilBand::hold: return "hold";
    case PumpSoilBand::wet: return "wet";
    default: return "unavailable";
  }
}

inline const char* pumpSoilBandLcd(PumpSoilBand band) {
  switch (band) {
    case PumpSoilBand::dry: return "DRY";
    case PumpSoilBand::hold: return "HOLD";
    case PumpSoilBand::wet: return "WET";
    default: return "N/A";
  }
}

enum class LightDecision { off, on, hold, unavailable };

// LDR below 65% requests ON; the hold timer limits rapid switching.
inline LightDecision ldrLightDecision(int lightPercent) {
  if (!controlPercentValid(lightPercent)) return LightDecision::unavailable;
  if (lightPercent >= kLightOffAtOrAbovePercent) return LightDecision::off;
  if (lightPercent < kLightOnBelowPercent) return LightDecision::on;
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

// Uncalibrated UV ADC proxy for monitoring only, never a lamp control input.
inline int uvAdcProxyTenths(int raw) {
  return raw >= 0 && raw < 4095 ? (raw * 140) / 4095 : -1;
}

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
    // Initial activation follows boot grace; later changes use normal guards.
    lightChangedMs_ = nowMs - kLightMinStateMs;
    pumpCooldown_ = false;
    pumpCooldownMs_ = kPumpCooldownMs;
    pumpAutoStartedMs_ = nowMs;
    pumpAutoStartSoilAdc_ = -1;
    dryConfirm_ = 0;
    lightConfirm_ = 0;
    waterLowRunningConfirm_ = 0;
    lightHoldBypass_ = false;
    pumpReason_ = "boot_grace";
    lightReason_ = "boot_grace";
  }

  void tick(uint32_t nowMs) {
    if (!initialized_) return;
    if (pumpManual_ && pumpManualOn_ &&
        controlIntervalElapsed(nowMs, pumpManualSinceMs_,
                               pumpManualDurationMs_)) {
      pumpManual_ = false;
      pumpOn_ = false;
      pumpStoppedMs_ = nowMs;
      pumpReason_ = "manual_expired";
    }
    if (lightManual_ && lightManualOn_ && lightManualDurationMs_ > 0 &&
        controlIntervalElapsed(nowMs, lightManualSinceMs_,
                               lightManualDurationMs_)) {
      // A timed lamp run stays manually OFF until AUTO is selected.
      lightManualOn_ = false;
      lightManualDurationMs_ = 0;
      lightManualExpired_ = true;
      lightOn_ = false;
      lightReason_ = "manual_expired";
    }
    if (pumpOn_ && !pumpManual_ &&
        controlIntervalElapsed(nowMs, pumpStartedMs_, kPumpMaxOnMs)) {
      stopPump(nowMs, "runtime_limit");
    }
    if (hasSample_ && controlIntervalElapsed(nowMs, lastSampleMs_, kSampleStaleMs)) {
      stopPump(nowMs, "sample_stale");
      clearManual();
      setLight(nowMs, false, "sample_stale");
    }
  }

  void inhibit(uint32_t nowMs, const char* reason) {
    stopPump(nowMs, reason);
    clearManual();
    setLight(nowMs, false, reason);
  }

  // Manual pump ON is limited to 30 seconds.
  void setPumpManual(uint32_t nowMs, bool on, uint32_t durationMs) {
    pumpManual_ = true;
    pumpManualOn_ = on;
    pumpManualSinceMs_ = nowMs;
    pumpManualDurationMs_ =
        on ? (durationMs < 1000 ? 1000 : (durationMs > kPumpManualMaxOnMs
                                              ? kPumpManualMaxOnMs
                                              : durationMs))
           : 0;
    pumpOn_ = on;
    if (on) {
      pumpStartedMs_ = nowMs;
    } else {
      pumpStoppedMs_ = nowMs;
    }
    pumpReason_ = on ? "manual_on" : "manual_off";
  }

  void setPumpAuto() { setPumpAuto(lastSampleMs_); }

  void setPumpAuto(uint32_t nowMs) {
    pumpManual_ = false;
    pumpManualOn_ = false;
    pumpManualDurationMs_ = 0;
    // Re-evaluate from OFF when releasing manual pump control.
    const bool wasOn = pumpOn_;
    pumpOn_ = false;
    if (wasOn) pumpStoppedMs_ = nowMs;
    pumpAutoStartSoilAdc_ = -1;
    dryConfirm_ = 0;
    waterLowRunningConfirm_ = 0;
    pumpReason_ = "manual_released";
  }

  /// Clear manual control after a safety stop.
  void clearManual() {
    pumpManual_ = false;
    pumpManualOn_ = false;
    pumpManualDurationMs_ = 0;
  }

  void setLightManual(bool on) { setLightManual(0, on, 0); }

  void setLightManual(uint32_t nowMs, bool on, uint32_t durationMs) {
    lightManual_ = true;
    lightManualOn_ = on;
    lightManualExpired_ = false;
    lightHoldBypass_ = false;
    lightConfirm_ = 0;
    lightManualSinceMs_ = nowMs;
    lightManualDurationMs_ =
        on && durationMs > 0
            ? (durationMs < 1000
                   ? 1000
                   : (durationMs > kLightManualMaxOnMs ? kLightManualMaxOnMs
                                                       : durationMs))
            : 0;
    lightOn_ = on;
    lightReason_ = on ? "manual_on" : "manual_off";
  }

  void setLightAuto() {
    lightManual_ = false;
    lightManualOn_ = false;
    lightManualDurationMs_ = 0;
    lightManualExpired_ = false;
    lightHoldBypass_ = true;
    lightConfirm_ = 0;
    // Re-evaluate the lamp from LDR without retaining its manual state.
    lightOn_ = false;
    lightReason_ = "manual_released";
  }

  bool pumpManual() const { return pumpManual_; }
  bool lightManual() const { return lightManual_; }
  uint32_t pumpManualRemainingMs(uint32_t nowMs) const {
    if (!pumpManual_ || !pumpManualOn_) return 0;
    if (controlIntervalElapsed(nowMs, pumpManualSinceMs_, pumpManualDurationMs_)) {
      return 0;
    }
    return pumpManualDurationMs_ -
           static_cast<uint32_t>(nowMs - pumpManualSinceMs_);
  }

  /// Remaining automatic-pump cooldown or runtime lockout.
  uint32_t pumpCooldownRemainingMs(uint32_t nowMs) const {
    if (!pumpCooldown_) return 0;
    if (controlIntervalElapsed(nowMs, pumpStoppedMs_, pumpCooldownMs_)) {
      return 0;
    }
    return pumpCooldownMs_ - static_cast<uint32_t>(nowMs - pumpStoppedMs_);
  }

  bool pumpRuntimeLockout() const {
    return pumpCooldown_ && pumpCooldownMs_ == kPumpRuntimeSoakMs;
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

    if (pumpManual_) {
      if (pumpManualOn_) {
        // Manual ON keeps the water, watchdog and stale-data interlocks.
        // The automatic soil stop does not apply to a short manual run.
        const bool waterUnavailable =
            !input.waterScaleEnabled ||
            !controlPercentValid(input.waterPercent);
        if (waterUnavailable) {
          stopPump(nowMs, "water_unavailable");
          clearManual();
        } else if (pumpWaterLow(input)) {
          stopPump(nowMs, "water_low");
          clearManual();
        } else {
          pumpOn_ = true;
          pumpReason_ = "manual_on";
        }
      } else {
        pumpOn_ = false;
        pumpReason_ = "manual_off";
      }
    }
    if (!pumpManual_) {
      if (!input.waterScaleEnabled || !controlPercentValid(input.waterPercent)) {
        stopPump(nowMs, "water_unavailable");
      } else if (!pumpOn_ && pumpWaterLow(input)) {
      // One low water sample blocks an automatic start while idle.
      stopPump(nowMs, "water_low");
    } else if (!input.soilControlAllowed) {
      stopPump(nowMs, "soil_unverified");
    } else if (!soilAnalogUsable(input.soilAdcRaw)) {
      stopPump(nowMs, "soil_unavailable");
    } else if (pumpOn_) {
      // Confirm low water while running to reduce transient stops.
      if (pumpWaterLow(input)) {
        ++waterLowRunningConfirm_;
      } else {
        waterLowRunningConfirm_ = 0;
      }
      int soilDelta = input.soilAdcRaw - pumpAutoStartSoilAdc_;
      if (soilDelta < 0) soilDelta = -soilDelta;
      const bool soilNotResponding =
          !pumpManual_ && pumpAutoStartSoilAdc_ >= 0 &&
          input.soilAdcRaw < kPumpOnBelowRawAdc &&
          controlIntervalElapsed(nowMs, pumpAutoStartedMs_,
                                 kPumpEffectCheckMs) &&
          soilDelta < kPumpEffectMinDelta;
      if (waterLowRunningConfirm_ >= kWaterLowRunningConfirmSamples) {
        stopPump(nowMs, "water_low");
      } else if (input.soilAdcRaw >= kPumpOffAtOrAboveRawAdc) {
        stopPump(nowMs, "soil_moist");
      } else if (soilNotResponding) {
        // Stop and retry later if the soil reading does not respond.
        stopPump(nowMs, "soil_no_response");
      } else {
        pumpReason_ = "watering";
      }
    } else {
      waterLowRunningConfirm_ = 0;
      if (pumpCooldown_ &&
          controlIntervalElapsed(nowMs, pumpStoppedMs_, pumpCooldownMs_)) {
        pumpCooldown_ = false;
      }
      if (input.soilAdcRaw >= kPumpOffAtOrAboveRawAdc) {
        dryConfirm_ = 0;
        pumpReason_ = "soil_not_dry";
      } else if (input.soilAdcRaw >= kPumpOnBelowRawAdc) {
        dryConfirm_ = 0;
        pumpReason_ = "dry_confirm";
      } else if (pumpCooldown_) {
        // Keep the runtime-limit reason visible during its lockout.
        pumpReason_ = pumpCooldownMs_ == kPumpRuntimeSoakMs
                          ? "runtime_limit"
                          : "cooldown";
      } else if (input.relayTransient) {
        // Do not start the pump during an analog transient.
        dryConfirm_ = 0;
        pumpReason_ = "relay_settle";
      } else {
        ++dryConfirm_;
        if (dryConfirm_ < kPumpDryConfirmSamples) {
          pumpReason_ = "dry_confirm";
        } else {
          pumpOn_ = true;
          pumpStartedMs_ = nowMs;
          pumpAutoStartedMs_ = nowMs;
          pumpAutoStartSoilAdc_ = input.soilAdcRaw;
          dryConfirm_ = 0;
          pumpReason_ = "soil_dry";
        }
      }
    }
    }

    // Lamp OFF is immediate; lamp ON needs consecutive samples and is blocked
    // while a relay/pump transient is active.
    if (!input.lightAutomationEnabled) {
      lightConfirm_ = 0;
      setLight(nowMs, false, "light_inhibited");
    } else {
      const LightDecision decision = ldrLightDecision(input.lightPercent);
      if (decision == LightDecision::off) {
        lightConfirm_ = 0;
        lightHoldBypass_ = false;
        setLight(nowMs, false, "ldr_sufficient");
      } else if (decision == LightDecision::unavailable) {
        lightConfirm_ = 0;
        lightHoldBypass_ = false;
        setLight(nowMs, false, "ldr_input_unavailable");
      } else if (decision == LightDecision::on && !lightOn_) {
        if (input.relayTransient) {
          lightConfirm_ = 0;
          lightReason_ = "relay_settle";
        } else {
          ++lightConfirm_;
          if (lightConfirm_ < kLightConfirmSamples) {
            lightReason_ = "light_confirm";
          } else if (lightHoldBypass_ ||
                     controlIntervalElapsed(nowMs, lightChangedMs_,
                                            kLightMinStateMs)) {
            lightConfirm_ = 0;
            lightHoldBypass_ = false;
            setLight(nowMs, true, "ldr_low");
          } else {
            lightReason_ = "minimum_hold";
          }
        }
      } else {
        lightConfirm_ = 0;
        lightReason_ = decision == LightDecision::hold ? "hysteresis" : "ldr_low";
      }
    }

    if (lightManual_) {
      lightOn_ = lightManualOn_;
      lightReason_ = lightManualExpired_
                         ? "manual_expired"
                         : (lightManualOn_ ? "manual_on" : "manual_off");
    }
  }

  ControlStatus status() const {
    return {pumpOn_, lightOn_, pumpReason_, lightReason_};
  }

 private:
  void stopPump(uint32_t nowMs, const char* reason) {
    if (pumpOn_) {
      pumpOn_ = false;
      pumpStoppedMs_ = nowMs;
      // Only automatic stops create an automatic cooldown or lockout.
      if (!pumpManual_) {
        pumpCooldown_ = true;
        pumpCooldownMs_ =
            strcmp(reason, "runtime_limit") == 0
                ? kPumpRuntimeSoakMs
                : (strcmp(reason, "soil_no_response") == 0
                       ? kPumpNoResponseCooldownMs
                       : kPumpCooldownMs);
      } else {
        pumpCooldown_ = false;
      }
    }
    pumpAutoStartSoilAdc_ = -1;
    dryConfirm_ = 0;
    waterLowRunningConfirm_ = 0;
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
  uint32_t pumpCooldownMs_ = kPumpCooldownMs;
  int dryConfirm_ = 0;
  int lightConfirm_ = 0;
  int waterLowRunningConfirm_ = 0;
  int pumpAutoStartSoilAdc_ = -1;
  uint32_t pumpAutoStartedMs_ = 0;
  uint32_t bootMs_ = 0;
  uint32_t lastSampleMs_ = 0;
  uint32_t pumpStartedMs_ = 0;
  uint32_t pumpStoppedMs_ = 0;
  uint32_t lightChangedMs_ = 0;
  bool pumpManual_ = false;
  bool pumpManualOn_ = false;
  uint32_t pumpManualSinceMs_ = 0;
  uint32_t pumpManualDurationMs_ = 0;
  bool lightManual_ = false;
  bool lightManualOn_ = false;
  bool lightManualExpired_ = false;
  bool lightHoldBypass_ = false;
  uint32_t lightManualSinceMs_ = 0;
  uint32_t lightManualDurationMs_ = 0;
  const char* pumpReason_ = "not_initialized";
  const char* lightReason_ = "not_initialized";
};

template <typename Gpio>
void writeRelayCommands(Gpio& gpio, const ControlStatus& status) {
  gpio.write(kLegacyPumpRelayPin, relayLevel(kPumpActiveLow, status.pumpOn));
  gpio.write(kLegacyLightRelayPin, relayLevel(kLightActiveLow, status.lightOn));
}

}  // namespace planter
