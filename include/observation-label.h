#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace planter {

// A bounded, operator-reported annotation, never an inferred ground truth.
// It applies to one sensor only and never changes calibration or relay control.
constexpr uint32_t kObservationLabelTtlMs = 180000;

struct ObservationLabel {
  const char* sensor;
  const char* condition;
  uint32_t startedMs;
};

enum class LabelCommandResult { rejected, set, cleared };

class ObservationLabels {
 public:
  LabelCommandResult apply(const char* line, uint32_t nowMs) {
    if (line == nullptr) {
      active_ = false;
      return LabelCommandResult::rejected;
    }
    if (std::strcmp(line, "LABEL CLEAR") == 0) {
      active_ = false;
      return LabelCommandResult::cleared;
    }
    struct Entry { const char* command; const char* sensor; const char* condition; };
    static const Entry entries[] = {
        {"LABEL SOIL AIR", "soil", "probe_in_air"},
        {"LABEL SOIL WATER", "soil", "probe_in_water"},
        {"LABEL SOIL DRY_SOIL", "soil", "dry_soil"},
        {"LABEL SOIL WET_SOIL", "soil", "wet_soil"},
        {"LABEL WATER LOW", "water", "low"},
        {"LABEL WATER MID", "water", "mid"},
        {"LABEL WATER NEAR_FULL", "water", "near_full"},
        {"LABEL LIGHT DARK", "light", "dark"},
        {"LABEL LIGHT AMBIENT", "light", "ambient"},
        {"LABEL UV COVERED", "uv", "covered"},
        {"LABEL UV SUN", "uv", "sun"},
        {"LABEL UV SHADE", "uv", "shade"},
        {"LABEL MQ AMBIENT", "mq135", "ambient"},
    };
    for (const auto& entry : entries) {
      if (std::strcmp(line, entry.command) == 0) {
        label_ = {entry.sensor, entry.condition, nowMs};
        startedMs_ = nowMs;
        active_ = true;
        return LabelCommandResult::set;
      }
    }
    // A mistyped transition must not silently keep the previous label active.
    active_ = false;
    return LabelCommandResult::rejected;
  }

  const ObservationLabel* current(uint32_t nowMs) {
    if (active_ && static_cast<uint32_t>(nowMs - startedMs_) >=
                       kObservationLabelTtlMs) {
      active_ = false;
    }
    return active_ ? &label_ : nullptr;
  }

 private:
  ObservationLabel label_ = {nullptr, nullptr, 0};
  uint32_t startedMs_ = 0;
  bool active_ = false;
};

// Fixed-size, nonblocking line assembly: oversized or control-byte input is
// discarded until newline. Unknown input is never echoed into JSON or executed.
enum class LabelLineResult { pending, ready, rejected };

class LabelLineReader {
 public:
  LabelLineResult push(char byte) {
    if (byte == '\n') {
      if (discard_) {
        discard_ = false;
        length_ = 0;
        return LabelLineResult::rejected;
      }
      buffer_[length_] = '\0';
      length_ = 0;
      return LabelLineResult::ready;
    }
    if (byte == '\r') return LabelLineResult::pending;
    const unsigned char value = static_cast<unsigned char>(byte);
    if (discard_ || value < 32 || value > 126 || length_ + 1 >= sizeof(buffer_)) {
      discard_ = true;
      return LabelLineResult::pending;
    }
    buffer_[length_++] = byte;
    return LabelLineResult::pending;
  }

  const char* line() const { return buffer_; }

 private:
  char buffer_[48] = {};
  size_t length_ = 0;
  bool discard_ = false;
};

}  // namespace planter
