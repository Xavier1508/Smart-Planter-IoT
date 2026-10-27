#pragma once

// Reserved configuration for sensors that are not installed yet. The current
// firmware does not read these sensors. Connect and integrate them only after
// checking the actual board, wiring, voltage and calibration.
namespace extra_sensors {
constexpr int kUnassignedPin = -1;
constexpr bool kWaterLevelEnabled = false;
constexpr int kWaterLevelPin = kUnassignedPin;
constexpr bool kMq135Enabled = false;
constexpr int kMq135Pin = kUnassignedPin;
}  // namespace extra_sensors
