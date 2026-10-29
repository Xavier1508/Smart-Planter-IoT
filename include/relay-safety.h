#pragma once

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

}  // namespace planter
