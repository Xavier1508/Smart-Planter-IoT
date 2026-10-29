#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <vector>

#include "extra-sensors.h"
#include "planter-config.h"
#include "relay-safety.h"
#include "sensor-telemetry.h"

struct GpioCall {
  char action;
  int pin;
  bool high;
};

struct FakeGpio {
  std::vector<GpioCall> calls;
  void write(int pin, bool high) { calls.push_back({'w', pin, high}); }
  void enableOutput(int pin) { calls.push_back({'o', pin, false}); }
};

int main() {
  using planter::SensorSnapshot;
  using planter::formatTelemetry;

  assert(planter::sampleDue(5000, 0, 5000));
  assert(!planter::sampleDue(4999, 0, 5000));
  assert(planter::sampleDue(0x20U, 0xfffffff0U, 48));
  assert(!planter::sampleDue(0x20U, 0xfffffff0U, 49));
  assert(planter::relayLevel(planter::kPumpActiveLow, true));
  assert(!planter::relayLevel(planter::kPumpActiveLow, false));
  assert(planter::relayLevel(planter::kLightActiveLow, true));
  assert(!planter::relayLevel(planter::kLightActiveLow, false));
  FakeGpio gpio;
  planter::configureRelaysInactive(gpio);
  assert(gpio.calls.size() == 6);
  assert(gpio.calls[0].action == 'w' && gpio.calls[0].pin == 13 && !gpio.calls[0].high);
  assert(gpio.calls[1].action == 'w' && gpio.calls[1].pin == 26 && !gpio.calls[1].high);
  assert(gpio.calls[2].action == 'o' && gpio.calls[2].pin == 13);
  assert(gpio.calls[3].action == 'o' && gpio.calls[3].pin == 26);
  assert(gpio.calls[4].action == 'w' && gpio.calls[4].pin == 13 && !gpio.calls[4].high);
  assert(gpio.calls[5].action == 'w' && gpio.calls[5].pin == 26 && !gpio.calls[5].high);

  const float nan = std::numeric_limits<float>::quiet_NaN();
  const float infinity = std::numeric_limits<float>::infinity();
  assert(!planter::validTemperature(nan));
  assert(!planter::validTemperature(infinity));
  assert(!planter::validTemperature(81.0f));
  assert(planter::validTemperature(-40.0f));
  assert(planter::validTemperature(80.0f));
  assert(!planter::validHumidity(nan));
  assert(!planter::validHumidity(-1.0f));
  assert(!planter::validHumidity(101.0f));
  assert(planter::validHumidity(0.0f));
  assert(planter::validHumidity(100.0f));
  assert(!planter::validAdcRaw(-1));
  assert(planter::validAdcRaw(0));
  assert(planter::validAdcRaw(4095));
  assert(!planter::validAdcRaw(4096));
  assert(planter::relativePercent(0, 0, 2450) == 0);
  assert(planter::relativePercent(2450, 0, 2450) == 100);
  assert(planter::relativePercent(4095, 0, 2450) == 100);
  assert(planter::relativePercent(4095, 4095, 0) == 0);
  assert(planter::relativePercent(0, 4095, 0) == 100);
  assert(planter::relativePercent(-1, 0, 2450) == -1);
  assert(planter::relativePercent(123, 123, 123) == -1);
  assert(!extra_sensors::kWaterLevelEnabled);
  assert(extra_sensors::kWaterLevelPin == 33);
  assert(!extra_sensors::kMq135Enabled);
  assert(extra_sensors::kMq135Pin == 27);
  assert(extra_sensors::kMq135DigitalPin == 14);
  assert(planter::kDhtEnabled);
  assert(!planter::kDhtModelVerified);
  assert(!planter::kSoilGpioPowerVerified);

  char output[768];
  const SensorSnapshot missing = {
      42, nan, infinity, -1, 4096, 123, true, -1, false, true,
      true, -1, -1, false, false};
  assert(formatTelemetry(missing, output, sizeof(output)));
  assert(std::strstr(output, "\"temperature_c\":null") != nullptr);
  assert(std::strstr(output, "\"humidity_percent\":null") != nullptr);
  assert(std::strstr(output, "\"status\":\"unavailable\"") != nullptr);
  assert(std::strstr(output, "\"soil_raw\":null") != nullptr);
  assert(std::strstr(output, "\"soil_status\":\"unavailable\"") != nullptr);
  assert(std::strstr(output, "\"light_raw\":null") != nullptr);
  assert(std::strstr(output, "\"uv_raw\":123") != nullptr);
  assert(std::strstr(output, "\"soil_relative_percent\":null") != nullptr);
  assert(std::strstr(output, "\"status\":\"unverified\"") != nullptr);
  assert(std::strstr(output, "\"water_level\":null") != nullptr);
  assert(std::strstr(output, "\"mq135\":null") != nullptr);
  assert(std::strstr(output, "\"pump_state\":null") != nullptr);
  assert(std::strstr(output, "\"relay_control\":\"inactive_requested\"") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';

  const SensorSnapshot valid = {
      5000, 26.5f, 64.0f, 1000, 2000, 3000, true, 1789, true, true,
      true, 1042, 1, true, true};
  assert(formatTelemetry(valid, output, sizeof(output)));
  assert(std::strstr(output, "\"temperature_c\":26.5") != nullptr);
  assert(std::strstr(output, "\"humidity_percent\":64.0") != nullptr);
  assert(std::strstr(output, "\"status\":\"valid\"") != nullptr);
  assert(std::strstr(output, "\"soil_raw\":1000,\"soil_status\":\"unverified\"") != nullptr);
  assert(std::strstr(output, "\"soil_relative_percent\":40") != nullptr);
  assert(std::strstr(output, "\"light_relative_percent\":51") != nullptr);
  assert(std::strstr(output, "\"water_level\":{\"adc_raw\":1789,\"status\":\"unverified\"}") != nullptr);
  assert(std::strstr(output, "\"mq135\":{\"adc_raw\":1042,\"digital_raw\":1,"
                             "\"adc_status\":\"unverified\",\"status\":\"unverified\"}") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';

  const SensorSnapshot partial = {
      5001, 24.0f, nan, 0, 0, 0, true, 4096, true, true,
      true, 2399, 0, true, false};
  assert(formatTelemetry(partial, output, sizeof(output)));
  assert(std::strstr(output, "\"humidity_percent\":null") != nullptr);
  assert(std::strstr(output, "\"status\":\"partial\"") != nullptr);
  assert(std::strstr(output, "\"water_level\":{\"adc_raw\":null,\"status\":\"unavailable\"}") != nullptr);
  assert(std::strstr(output, "\"mq135\":{\"adc_raw\":null,\"digital_raw\":0,"
                             "\"adc_status\":\"wifi_active_or_unknown\",\"status\":\"unverified\"}") != nullptr);

  const SensorSnapshot disabled = {
      5002, 24.0f, 64.0f, 123, 0, 0, false, 0, true, false,
      false, 123, 1, false, true};
  assert(formatTelemetry(disabled, output, sizeof(output)));
  assert(std::strstr(output, "\"temperature_c\":null") != nullptr);
  assert(std::strstr(output, "\"humidity_percent\":null") != nullptr);
  assert(std::strstr(output, "\"status\":\"not_configured\"") != nullptr);
  assert(std::strstr(output, "\"soil_raw\":null,\"soil_status\":\"not_configured\"") != nullptr);
  // Zero is a raw ADC reading, not proof that a sensor is present or absent.
  assert(std::strstr(output, "\"water_level\":{\"adc_raw\":0,\"status\":\"unverified\"}") != nullptr);
  assert(std::strstr(output, "\"mq135\":null") != nullptr);
  std::cout << "TEST_FIXTURE " << output << '\n';

  const SensorSnapshot assumedDht = {
      5003, 24.0f, 64.0f, 0, 0, 0, true, 0, true, false,
      false, 4096, 2, true, true};
  assert(formatTelemetry(assumedDht, output, sizeof(output)));
  assert(std::strstr(output, "\"dht\":{\"model\":\"DHT11_assumed\","
                             "\"temperature_c\":24.0,\"humidity_percent\":64.0,"
                             "\"status\":\"unverified\"}") != nullptr);
  assert(std::strstr(output, "\"mq135\":{\"adc_raw\":null,\"digital_raw\":null,"
                             "\"adc_status\":\"unavailable\",\"status\":\"unverified\"}") != nullptr);

  char tooSmall[8];
  assert(!formatTelemetry(valid, tooSmall, sizeof(tooSmall)));
  assert(!formatTelemetry(valid, nullptr, 512));
  assert(!formatTelemetry(valid, output, 0));
  std::cout << "Sensor telemetry host tests passed (fixture data only).\n";
}
