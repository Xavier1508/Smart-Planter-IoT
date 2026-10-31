#pragma once

#include "planter-config.h"

namespace planter {

// The input-only branch never writes or enables GPIO25 as an output. Neither
// branch can verify physical wiring or prevent a sensor overvoltage at GPIO34.
template <typename Gpio>
void configureSoilPower(Gpio& gpio, bool switchedSupplyVerified) {
  if (!switchedSupplyVerified) {
    gpio.enableInput(kLegacySoilPowerPin);
    return;
  }
  gpio.write(kLegacySoilPowerPin, false);
  gpio.enableOutput(kLegacySoilPowerPin);
  gpio.write(kLegacySoilPowerPin, false);
}

template <typename Gpio>
int acquireSoilRaw(Gpio& gpio, bool readEnabled, bool switchedSupplyVerified) {
  if (!readEnabled) return -1;
  if (!switchedSupplyVerified) return gpio.readAnalog(kSoilPin);
  gpio.write(kLegacySoilPowerPin, true);
  gpio.delayMs(kSoilPowerSettleMs);
  const int raw = gpio.readAnalog(kSoilPin);
  gpio.write(kLegacySoilPowerPin, false);
  return raw;
}

}  // namespace planter
