#pragma once

#include <stddef.h>
#include <stdint.h>

namespace planter {

// Fixed password from the ignored local header, or a boot-random 10-character
// fallback shown on the LCD (50 bits of entropy).
constexpr size_t kLocalWifiPasswordLength = 10;
constexpr char kLocalWifiPasswordAlphabet[] = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
static_assert(sizeof(kLocalWifiPasswordAlphabet) == 33, "Expected 32 symbols");

template <typename Random>
bool makeLocalWifiPassword(char* output, size_t capacity, Random& random) {
  if (output == nullptr || capacity <= kLocalWifiPasswordLength) return false;
  for (size_t i = 0; i < kLocalWifiPasswordLength; ++i) {
    output[i] = kLocalWifiPasswordAlphabet[random.next() & 31U];
  }
  output[kLocalWifiPasswordLength] = '\0';
  return true;
}

// Show the access point on startup for a full minute, then interleave four
// five-second sensor/relay pages with a thirty-second Wi-Fi page. Sampling,
// telemetry and relay safety continue independently while the LCD is held.
constexpr uint32_t kLcdStartupWifiMs = 60000;
constexpr uint32_t kLcdSensorPageMs = 5000;
constexpr uint32_t kLcdWifiPageMs = 30000;

inline unsigned lcdPageForUptime(uint32_t uptimeMs) {
  if (uptimeMs < kLcdStartupWifiMs) return 4;
  const uint32_t sensorPagesMs = 4 * kLcdSensorPageMs;
  const uint32_t position = (uptimeMs - kLcdStartupWifiMs) %
                            (sensorPagesMs + kLcdWifiPageMs);
  return position < sensorPagesMs ? position / kLcdSensorPageMs : 4;
}

}  // namespace planter
