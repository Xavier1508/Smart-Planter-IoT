#pragma once

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>

#include "planter-config.h"

namespace planter {

struct SensorSnapshot {
  uint32_t uptimeMs;
  float temperatureC;
  float humidityPercent;
  int soilAdcRaw;
  int lightAdcRaw;
  int uvAdcRaw;
  bool dhtEnabled;
  int waterAdcRaw;
  bool waterEnabled;
  bool soilEnabled;
  bool dhtModelVerified;
  int mqAdcRaw;
  int mqDigitalRaw;
  bool mqEnabled;
  bool mqAdcReadable;
};

inline bool sampleDue(uint32_t nowMs, uint32_t lastMs, uint32_t intervalMs) {
  // Unsigned subtraction continues to work when millis() wraps around.
  return static_cast<uint32_t>(nowMs - lastMs) >= intervalMs;
}

inline bool validTemperature(float value) {
  return std::isfinite(value) && value >= -40.0f && value <= 80.0f;
}

inline bool validHumidity(float value) {
  return std::isfinite(value) && value >= 0.0f && value <= 100.0f;
}

inline bool validAdcRaw(int value) { return value >= 0 && value <= 4095; }

// Approximate relative scale only; a plausible value does not prove that a
// sensor is connected, calibrated, or safe to use for an actuator.
inline int relativePercent(int raw, int zeroAdc, int fullAdc) {
  if (!validAdcRaw(raw) || !validAdcRaw(zeroAdc) || !validAdcRaw(fullAdc) ||
      zeroAdc == fullAdc) {
    return -1;
  }
  const int value = (raw - zeroAdc) * 100 / (fullAdc - zeroAdc);
  return value < 0 ? 0 : (value > 100 ? 100 : value);
}

inline void formatClimateValue(char* output, size_t capacity, float value,
                               bool valid) {
  if (valid) {
    std::snprintf(output, capacity, "%.1f", static_cast<double>(value));
  } else {
    std::snprintf(output, capacity, "null");
  }
}

inline void formatAdcValue(char* output, size_t capacity, int value) {
  if (validAdcRaw(value)) {
    std::snprintf(output, capacity, "%d", value);
  } else {
    std::snprintf(output, capacity, "null");
  }
}

// ADC values are electrical observations, not calibrated measurements and
// not proof that a sensor is attached. Missing climate values remain null.
inline bool formatTelemetry(const SensorSnapshot& sample, char* output,
                            size_t capacity) {
  if (output == nullptr || capacity == 0) return false;

  const bool temperatureValid =
      sample.dhtEnabled && validTemperature(sample.temperatureC);
  const bool humidityValid =
      sample.dhtEnabled && validHumidity(sample.humidityPercent);
  const char* climateStatus =
      !sample.dhtEnabled
          ? "not_configured"
          : (!temperatureValid && !humidityValid
                 ? "unavailable"
                 : (!sample.dhtModelVerified
                        ? "unverified"
                        : (temperatureValid && humidityValid ? "valid" : "partial")));
  const char* soilStatus =
      !sample.soilEnabled
          ? "not_configured"
          : (validAdcRaw(sample.soilAdcRaw) ? "unverified" : "unavailable");
  char temperature[16];
  char humidity[16];
  char soil[16];
  char light[16];
  char uv[16];
  char soilRelative[16];
  char lightRelative[16];
  char waterRaw[16];
  char waterLevel[80];
  char mqRaw[16];
  char mqDigital[8];
  char mq135[160];
  formatClimateValue(temperature, sizeof(temperature), sample.temperatureC,
                     temperatureValid);
  formatClimateValue(humidity, sizeof(humidity), sample.humidityPercent,
                     humidityValid);
  formatAdcValue(soil, sizeof(soil), sample.soilEnabled ? sample.soilAdcRaw : -1);
  formatAdcValue(light, sizeof(light), sample.lightAdcRaw);
  formatAdcValue(uv, sizeof(uv), sample.uvAdcRaw);
  formatAdcValue(soilRelative, sizeof(soilRelative),
                 sample.soilEnabled
                     ? relativePercent(sample.soilAdcRaw, kSoilRelativeZeroAdc,
                                       kSoilRelativeFullAdc)
                     : -1);
  formatAdcValue(lightRelative, sizeof(lightRelative),
                 relativePercent(sample.lightAdcRaw, kLightRelativeZeroAdc,
                                 kLightRelativeFullAdc));
  formatAdcValue(waterRaw, sizeof(waterRaw), sample.waterAdcRaw);
  if (sample.waterEnabled) {
    std::snprintf(waterLevel, sizeof(waterLevel),
                  "{\"adc_raw\":%s,\"status\":\"%s\"}", waterRaw,
                  validAdcRaw(sample.waterAdcRaw) ? "unverified" : "unavailable");
  } else {
    std::snprintf(waterLevel, sizeof(waterLevel), "null");
  }
  if (sample.mqEnabled) {
    formatAdcValue(mqRaw, sizeof(mqRaw),
                   sample.mqAdcReadable ? sample.mqAdcRaw : -1);
    if (sample.mqDigitalRaw == 0 || sample.mqDigitalRaw == 1) {
      std::snprintf(mqDigital, sizeof(mqDigital), "%d", sample.mqDigitalRaw);
    } else {
      std::snprintf(mqDigital, sizeof(mqDigital), "null");
    }
    const char* adcStatus =
        !sample.mqAdcReadable
            ? "wifi_active_or_unknown"
            : (validAdcRaw(sample.mqAdcRaw) ? "unverified" : "unavailable");
    std::snprintf(mq135, sizeof(mq135),
                  "{\"adc_raw\":%s,\"digital_raw\":%s,\"adc_status\":\"%s\","
                  "\"status\":\"unverified\"}", mqRaw, mqDigital, adcStatus);
  } else {
    std::snprintf(mq135, sizeof(mq135), "null");
  }

  const int written = std::snprintf(
      output, capacity,
      "{\"type\":\"sample\",\"uptime_ms\":%lu,"
      "\"dht\":{\"model\":\"DHT11_assumed\",\"temperature_c\":%s,"
      "\"humidity_percent\":%s,\"status\":\"%s\"},"
      "\"adc\":{\"soil_raw\":%s,\"soil_status\":\"%s\","
      "\"light_raw\":%s,\"uv_raw\":%s,"
      "\"soil_relative_percent\":%s,\"light_relative_percent\":%s,"
      "\"status\":\"unverified\"},"
      "\"water_level\":%s,\"mq135\":%s,"
      "\"relay_control\":\"inactive_requested\",\"pump_state\":null,"
      "\"growlight_state\":null}",
      static_cast<unsigned long>(sample.uptimeMs), temperature, humidity,
      climateStatus, soil, soilStatus, light, uv, soilRelative, lightRelative,
      waterLevel, mq135);
  return written >= 0 && static_cast<size_t>(written) < capacity;
}

}  // namespace planter
