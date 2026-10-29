// Single Smart Planter firmware. GPIO levels, wiring, and calibration remain
// unverified. Both external relay loads must remain physically disconnected.
// The firmware requests OFF; it cannot guarantee contacts or boot-time levels.

#include <Arduino.h>
#include <DHT.h>
#include <LiquidCrystal_I2C.h>
#include <Wire.h>
#include <esp_wifi.h>
#include <math.h>

#include "extra-sensors.h"
#include "planter-config.h"
#include "relay-safety.h"
#include "sensor-telemetry.h"

namespace {

DHT climateSensor(planter::kDhtPin, DHT11);
LiquidCrystal_I2C lcd(0x27, 16, 2);
bool hasSample = false;
uint32_t lastSampleMs = 0;

struct ArduinoGpio {
  void write(int pin, bool high) { digitalWrite(pin, high ? HIGH : LOW); }
  void enableOutput(int pin) { pinMode(pin, OUTPUT); }
};

int readSoilRaw() {
  if (!planter::kSoilGpioPowerVerified) return -1;
  digitalWrite(planter::kLegacySoilPowerPin, HIGH);
  delay(planter::kSoilPowerSettleMs);
  const int raw = analogRead(planter::kSoilPin);
  digitalWrite(planter::kLegacySoilPowerPin, LOW);
  return raw;
}

// GPIO27 uses ADC2, which conflicts with Wi-Fi on the classic ESP32. An
// unexpected driver error is treated conservatively as unavailable.
bool mqAdcReadable() {
  wifi_mode_t mode = WIFI_MODE_NULL;
  const esp_err_t result = esp_wifi_get_mode(&mode);
  return result == ESP_ERR_WIFI_NOT_INIT || result == ESP_ERR_WIFI_NOT_STARTED ||
         (result == ESP_OK && mode == WIFI_MODE_NULL);
}

void lcdLine(uint8_t row, const char* text) {
  char padded[17];
  snprintf(padded, sizeof(padded), "%-16.16s", text);
  lcd.setCursor(0, row);
  lcd.print(padded);
}

void updateLcd(const planter::SensorSnapshot& sample) {
  static unsigned page = 0;
  char first[17];
  char second[17];
  if (page == 0) {
    if (sample.dhtEnabled && planter::validTemperature(sample.temperatureC) &&
        planter::validHumidity(sample.humidityPercent)) {
      snprintf(first, sizeof(first), "T?%.1f H?%.0f", sample.temperatureC,
               sample.humidityPercent);
    } else {
      snprintf(first, sizeof(first), "DHT: N/A");
    }
    const int soil = sample.soilEnabled
                         ? planter::relativePercent(sample.soilAdcRaw,
                                                    planter::kSoilRelativeZeroAdc,
                                                    planter::kSoilRelativeFullAdc)
                         : -1;
    if (soil >= 0) snprintf(second, sizeof(second), "Soil?: %d%%", soil);
    else snprintf(second, sizeof(second), "Soil: N/A");
  } else if (page == 1) {
    const int light = planter::relativePercent(sample.lightAdcRaw,
                                               planter::kLightRelativeZeroAdc,
                                               planter::kLightRelativeFullAdc);
    if (light >= 0) snprintf(first, sizeof(first), "Light?: %d%%", light);
    else snprintf(first, sizeof(first), "Light: N/A");
    if (planter::validAdcRaw(sample.uvAdcRaw)) {
      snprintf(second, sizeof(second), "UV ADC?: %d", sample.uvAdcRaw);
    } else {
      snprintf(second, sizeof(second), "UV: N/A");
    }
  } else {
    if (sample.waterEnabled && planter::validAdcRaw(sample.waterAdcRaw)) {
      snprintf(first, sizeof(first), "Water ADC?:%d", sample.waterAdcRaw);
    } else {
      snprintf(first, sizeof(first), "Water: N/A");
    }
    if (sample.mqEnabled && sample.mqAdcReadable &&
        planter::validAdcRaw(sample.mqAdcRaw)) {
      snprintf(second, sizeof(second), "MQ ADC?:%d", sample.mqAdcRaw);
    } else {
      snprintf(second, sizeof(second), "MQ135: N/A");
    }
  }
  lcdLine(0, first);
  lcdLine(1, second);
  page = (page + 1) % 3;
}

void printSample(uint32_t nowMs) {
  const bool mqAdcAllowed = extra_sensors::kMq135Enabled && mqAdcReadable();
  const planter::SensorSnapshot sample = {
      nowMs,
      planter::kDhtEnabled ? climateSensor.readTemperature() : NAN,
      planter::kDhtEnabled ? climateSensor.readHumidity() : NAN,
      readSoilRaw(),
      analogRead(planter::kLightPin),
      analogRead(planter::kUvPin),
      planter::kDhtEnabled,
      extra_sensors::kWaterLevelEnabled
          ? analogRead(extra_sensors::kWaterLevelPin)
          : -1,
      extra_sensors::kWaterLevelEnabled,
      planter::kSoilGpioPowerVerified,
      planter::kDhtModelVerified,
      mqAdcAllowed ? analogRead(extra_sensors::kMq135Pin) : -1,
      extra_sensors::kMq135Enabled ? digitalRead(extra_sensors::kMq135DigitalPin) : -1,
      extra_sensors::kMq135Enabled,
      mqAdcAllowed,
  };

  char output[768];
  if (planter::formatTelemetry(sample, output, sizeof(output))) {
    Serial.println(output);
  } else {
    Serial.println("{\"type\":\"error\",\"code\":\"encoding_failed\"}");
  }
  updateLcd(sample);
}

}  // namespace

void setup() {
  ArduinoGpio gpio;
  planter::configureRelaysInactive(gpio);
  Serial.begin(115200);
  Wire.begin(planter::kLegacyI2cSdaPin, planter::kLegacyI2cSclPin);
  lcd.init();
  lcd.backlight();
  lcdLine(0, "Smart Planter");
  lcdLine(1, "Relay cmd: OFF");
  if (planter::kDhtEnabled) climateSensor.begin();
  analogReadResolution(12);
  if (extra_sensors::kWaterLevelEnabled) {
    pinMode(extra_sensors::kWaterLevelPin, INPUT);
  }
  if (extra_sensors::kMq135Enabled) {
    pinMode(extra_sensors::kMq135DigitalPin, INPUT);
  }
  if (planter::kSoilGpioPowerVerified) {
    digitalWrite(planter::kLegacySoilPowerPin, LOW);
    pinMode(planter::kLegacySoilPowerPin, OUTPUT);
    digitalWrite(planter::kLegacySoilPowerPin, LOW);
  }

  // With the default configuration GPIO25 is untouched and soil is omitted.
  Serial.printf(
      "{\"type\":\"startup\",\"mode\":\"single\",\"version\":5,"
      "\"relay_control\":\"inactive_requested\",\"soil_power\":\"%s\","
      "\"dht\":\"%s\",\"water\":\"%s\",\"mq135\":\"%s\","
      "\"wifi\":\"disabled\",\"cloud\":\"disabled\"}\n",
      planter::kSoilGpioPowerVerified ? "gpio25_switched_unverified" : "not_configured",
      planter::kDhtEnabled ? "DHT11_assumed" : "not_configured",
      extra_sensors::kWaterLevelEnabled ? "enabled_unverified" : "not_configured",
      extra_sensors::kMq135Enabled ? "enabled_unverified" : "not_configured");
}

void loop() {
  const uint32_t nowMs = millis();
  if (!hasSample ||
      planter::sampleDue(nowMs, lastSampleMs, planter::kSampleIntervalMs)) {
    hasSample = true;
    lastSampleMs = nowMs;
    printSample(nowMs);
  }
  delay(10);
}
