#pragma once

// The user reports moving the water sensor signal to GPIO33 (ADC1). The
// physical wiring, input voltage, and sensor calibration remain unverified.
namespace extra_sensors {
constexpr int kWaterLevelPin = 33;

// The user reports moving A0 to SVP/GPIO36 and leaving D0 on GPIO14. Electrical
// levels, heater supply, and sensor calibration are unverified; diagnostic only.
constexpr int kMq135Pin = 36;
constexpr int kMq135DigitalPin = 14;
}  // namespace extra_sensors
