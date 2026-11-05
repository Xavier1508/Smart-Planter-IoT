#pragma once

// Water sensor on GPIO33. Check wiring, input voltage and calibration.
namespace extra_sensors {
constexpr int kWaterLevelPin = 33;

// MQ135 A0 uses GPIO36 and D0 uses GPIO14. Check voltage and heater supply.
constexpr int kMq135Pin = 36;
constexpr int kMq135DigitalPin = 14;
}  // namespace extra_sensors
