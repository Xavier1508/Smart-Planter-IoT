#pragma once

// The user reports moving the water sensor signal to GPIO33 (ADC1). The
// physical wiring, input voltage, and sensor calibration remain unverified.
namespace extra_sensors {
constexpr int kWaterLevelPin = 33;

// The user reports A0 on GPIO27 and D0 on GPIO14. Electrical levels, heater
// supply, and sensor calibration are not verified; results are diagnostic only.
constexpr int kMq135Pin = 27;
constexpr int kMq135DigitalPin = 14;
}  // namespace extra_sensors
