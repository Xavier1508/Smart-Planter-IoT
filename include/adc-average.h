#pragma once

#include <cstdint>

namespace planter {

// Five consecutive conversions per sensor are combined within one five-second
// reporting cycle. No average is returned when a read fails or a rail reading
// is mixed with another value: such a window could mask a disconnected input.
constexpr unsigned kAdcSamplesPerCycle = 5;

struct AveragedAdc {
  int raw;
  bool readFailed;
};

// Median is robust to a single rail/noise sample. Used for the LDR, where 0
// and 4095 are meaningful bright/dark extremes rather than disconnected-proof.
template <typename Reader>
int medianAdc(Reader read) {
  int values[kAdcSamplesPerCycle];
  int count = 0;
  for (unsigned i = 0; i < kAdcSamplesPerCycle; ++i) {
    const int raw = read();
    if (raw >= 0 && raw <= 4095) values[count++] = raw;
  }
  if (count == 0) return -1;
  for (int i = 1; i < count; ++i) {
    const int value = values[i];
    int j = i - 1;
    while (j >= 0 && values[j] > value) {
      values[j + 1] = values[j];
      --j;
    }
    values[j + 1] = value;
  }
  return values[count / 2];
}

template <typename Reader>
AveragedAdc averageAdc(Reader read) {
  int sum = 0;
  int first = -1;
  bool allSame = true;
  bool hasRail = false;
  bool readFailed = false;
  for (unsigned i = 0; i < kAdcSamplesPerCycle; ++i) {
    const int raw = read();
    if (raw < 0 || raw > 4095) {
      readFailed = true;
      continue;
    }
    if (first < 0) first = raw;
    else if (raw != first) allSame = false;
    hasRail = hasRail || raw == 0 || raw == 4095;
    sum += raw;
  }
  if (readFailed) return {-1, true};
  if (hasRail && !allSame) return {-1, false};
  return {(sum + static_cast<int>(kAdcSamplesPerCycle / 2)) /
              static_cast<int>(kAdcSamplesPerCycle), false};
}

}  // namespace planter
