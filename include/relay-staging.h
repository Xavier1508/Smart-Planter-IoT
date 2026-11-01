#pragma once

#include <stdint.h>

#include "planter-config.h"
#include "relay-safety.h"

namespace planter {

// Stages relay output changes so two coils never switch in the same instant.
// OFF requests are applied immediately; ON requests are separated by at least
// kRelaySwitchGapMs. Output changes are also held inactive for
// kRelayEnableDelayMs after begin() so the supply can settle.
//
// This only reduces simultaneous inrush. It cannot fix a weak 5V supply, a
// floating relay input during the boot ROM, or a shared ground.
template <typename Gpio>
class RelayStager {
 public:
  void begin(uint32_t nowMs, Gpio& gpio) {
    initialized_ = true;
    startedMs_ = nowMs;
    lastChangeMs_ = nowMs;
    writePump(gpio, false);
    writeLight(gpio, false);
  }

  void update(uint32_t nowMs, bool pumpOn, bool lightOn, Gpio& gpio,
              bool immediate = false) {
    if (!initialized_) begin(nowMs, gpio);

    if (!controlIntervalElapsed(nowMs, startedMs_, kRelayEnableDelayMs)) {
      if (pumpOn_ || lightOn_) {
        writePump(gpio, false);
        writeLight(gpio, false);
        lastChangeMs_ = nowMs;
      }
      return;
    }

    // Safety first: a requested OFF is never delayed.
    const bool pumpOff = pumpOn_ && !pumpOn;
    const bool lightOff = lightOn_ && !lightOn;
    if (pumpOff || lightOff) {
      if (pumpOff) writePump(gpio, false);
      if (lightOff) writeLight(gpio, false);
      lastChangeMs_ = nowMs;
    }

    const bool pumpOnRequest = !pumpOn_ && pumpOn;
    const bool lightOnRequest = !lightOn_ && lightOn;
    if (!pumpOnRequest && !lightOnRequest) return;
    if (!immediate && !controlIntervalElapsed(nowMs, lastChangeMs_,
                                               kRelaySwitchGapMs)) {
      return;
    }

    if (pumpOnRequest && lightOnRequest) {
      // Start the pump first, then let the lamp follow after the gap.
      writePump(gpio, true);
      lastChangeMs_ = nowMs;
      return;
    }
    if (pumpOnRequest) {
      writePump(gpio, true);
      lastChangeMs_ = nowMs;
    }
    if (lightOnRequest) {
      writeLight(gpio, true);
      lastChangeMs_ = nowMs;
    }
  }

  bool initialized() const { return initialized_; }
  bool pumpOn() const { return pumpOn_; }
  bool lightOn() const { return lightOn_; }

 private:
  void writePump(Gpio& gpio, bool on) {
    gpio.write(kLegacyPumpRelayPin, relayLevel(kPumpActiveLow, on));
    pumpOn_ = on;
  }

  void writeLight(Gpio& gpio, bool on) {
    gpio.write(kLegacyLightRelayPin, relayLevel(kLightActiveLow, on));
    lightOn_ = on;
  }

  bool initialized_ = false;
  bool pumpOn_ = false;
  bool lightOn_ = false;
  uint32_t startedMs_ = 0;
  uint32_t lastChangeMs_ = 0;
};

}  // namespace planter
