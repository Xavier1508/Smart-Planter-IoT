// Tunas Smart Planter firmware v52 - local-only ESP32 access point.
// AP "Moss" streams JSON on TCP 3333; HTTP 80 serves status/telemetry.
// Relay/pump transients are gated in software; electrical separation is still required.

#include <Arduino.h>
#include <DHT.h>
#include <LiquidCrystal_I2C.h>
#include <Preferences.h>
#include <WebServer.h>
#include <WiFi.h>
#include <Wire.h>
#include <driver/adc.h>
#include <esp_adc_cal.h>
#include <esp_system.h>
#include <esp_task_wdt.h>
#include <esp_wifi.h>
#include <lwip/sockets.h>
#include <math.h>
#include <string.h>

#include "adc-average.h"
#include "control-command.h"
#include "extra-sensors.h"
#include "local-wifi.h"
#if __has_include("local-wifi-secret.local.h")
#include "local-wifi-secret.local.h"
#endif
#include "planter-config.h"
#include "relay-safety.h"
#include "relay-staging.h"
#include "sensor-telemetry.h"
#include "soil-sensor.h"

namespace {

// Stable identifier reported by the health endpoint and the serial boot line.
constexpr char kDeviceId[] = "moss-local";

void applyControlLine(const char* line);
void syncRelayCommands(bool immediate = false);
bool relayTransient(uint32_t nowMs);

DHT climateSensor(planter::kDhtPin, DHT11);
LiquidCrystal_I2C lcd(0x27, 16, 2);
bool lcdBacklightOn = true;
uint32_t lcdBacklightActivityMs = 0;
bool hasSample = false;
uint32_t lastSampleMs = 0;
bool watchdogReady = false;
bool mqAdcReady = false;
bool uvAdcReady = false;
int lastStableWaterRaw = -1;
uint32_t lastStableWaterMs = 0;
planter::RelayController relayController;
planter::ControlInput lastControlInput{0, 0, 0, false, false, false, false};
bool hasControlInput = false;
planter::ObservationLabels observationLabels;
planter::LabelLineReader labelLineReader;
planter::ControlLineReader controlLineReader;
esp_adc_cal_characteristics_t mqAdcCharacteristics;
planter::AdcCalibrationMethod mqAdcCalibration = planter::AdcCalibrationMethod::unavailable;
esp_adc_cal_characteristics_t uvAdcCharacteristics;
planter::AdcCalibrationMethod uvAdcCalibration = planter::AdcCalibrationMethod::unavailable;
const IPAddress localAddress(192, 168, 4, 1);
WiFiServer localServer(localAddress, planter::kLocalTelemetryPort, 1);
WebServer localHttpServer(80);
WiFiClient localClient;
bool localWifiReady = false;
char latestTelemetry[3072] = {};
bool latestTelemetryValid = false;
char localWifiName[17] = {};
char localWifiPassword[planter::kLocalWifiPasswordLength + 1] = {};
char bootResetReason[24] = "unknown";
uint32_t bootBrownoutCount = 0;

// Relay edges start a quiet window; the timer handles millis() wraparound.
uint32_t relayQuietUntilMs = 0;
bool relayQuietSet = false;

struct HardwareRandom {
  uint32_t next() { return esp_random(); }
};

// Discard one conversion after an ADC channel switch so the sample-and-hold settles.
int readAdc1Settled(adc1_channel_t channel) {
  (void)adc1_get_raw(channel);
  delayMicroseconds(planter::kAdcSettleUs);
  return adc1_get_raw(channel);
}

int readAnalogSettled(int pin) {
  (void)analogRead(pin);
  delayMicroseconds(planter::kAdcSettleUs);
  return analogRead(pin);
}

int medianAnalogRead(int pin) {
  return planter::medianAdc([pin]() { return readAnalogSettled(pin); });
}

void applyLocalApPowerProfile(bool print) {
  WiFi.setTxPower(WIFI_POWER_11dBm);
  uint16_t beaconTu = planter::kLocalApBeaconIntervalTu;
  uint8_t maxClients = planter::kLocalApMaxClients;
  wifi_config_t config = {};
  if (esp_wifi_get_config(WIFI_IF_AP, &config) == ESP_OK) {
    config.ap.beacon_interval = beaconTu;
    config.ap.max_connection = maxClients;
    if (esp_wifi_set_config(WIFI_IF_AP, &config) != ESP_OK) {
      Serial.println("{\"type\":\"power\",\"warning\":\"ap_config_failed\"}");
    }
    wifi_config_t applied = {};
    if (esp_wifi_get_config(WIFI_IF_AP, &applied) == ESP_OK) {
      beaconTu = applied.ap.beacon_interval;
      maxClients = applied.ap.max_connection;
    }
  } else {
    Serial.println("{\"type\":\"power\",\"warning\":\"ap_config_unreadable\"}");
  }
  if (print) {
    const int txUnits = static_cast<int>(WiFi.getTxPower());
    Serial.printf(
        "{\"type\":\"power\",\"profile\":\"local_only\",\"cpu_mhz\":%lu,"
        "\"tx_units\":%d,\"tx_dbm\":%.2f,\"beacon_tu\":%u,"
        "\"max_clients\":%u}\n",
        static_cast<unsigned long>(getCpuFrequencyMhz()), txUnits,
        txUnits * 0.25f, beaconTu, maxClients);
  }
}

const char* resetReasonName(esp_reset_reason_t reason) {
  switch (reason) {
    case ESP_RST_POWERON: return "poweron";
    case ESP_RST_BROWNOUT: return "brownout";
    case ESP_RST_SW: return "software";
    case ESP_RST_PANIC: return "panic";
    case ESP_RST_INT_WDT: return "interrupt_watchdog";
    case ESP_RST_TASK_WDT: return "task_watchdog";
    case ESP_RST_WDT: return "watchdog";
    case ESP_RST_DEEPSLEEP: return "deep_sleep";
    case ESP_RST_EXT: return "external";
    default: return "unknown";
  }
}

void logBootReason() {
  Preferences prefs;
  uint32_t brownouts = 0;
  bool nvsReady = false;
  const esp_reset_reason_t reason = esp_reset_reason();
  nvsReady = prefs.begin("moss_boot", false);
  if (nvsReady) {
    brownouts = prefs.getUInt("brownouts", 0);
    if (reason == ESP_RST_BROWNOUT) {
      ++brownouts;
      prefs.putUInt("brownouts", brownouts);
    }
    prefs.end();
  }
  snprintf(bootResetReason, sizeof(bootResetReason), "%s", resetReasonName(reason));
  bootBrownoutCount = brownouts;
  Serial.printf(
      "{\"type\":\"boot\",\"firmware_version\":%u,\"reset_reason\":\"%s\","
      "\"brownout_count\":%lu,\"nvs_ready\":%s}\n",
      planter::kFirmwareVersion, resetReasonName(reason),
      static_cast<unsigned long>(brownouts), nvsReady ? "true" : "false");
}

void lcdLine(uint8_t row, const char* text) {
  static char rendered[2][17] = {};
  char padded[17];
  snprintf(padded, sizeof(padded), "%-16.16s", text);
  if (row > 1 || strcmp(rendered[row], padded) == 0) return;
  memcpy(rendered[row], padded, sizeof(padded));
  lcd.setCursor(0, row);
  lcd.print(padded);
}

void updateLcd(uint32_t nowMs) {
  // Keep the AP connection details visible on the LCD.
  char line[17] = {};
  const char* ssid = localWifiName[0] != '\0' ? localWifiName : "Moss";
  snprintf(line, sizeof(line), "WiFi:%s", ssid);
  lcdLine(0, line);
  const char* password =
      localWifiPassword[0] != '\0' ? localWifiPassword : "-";
  snprintf(line, sizeof(line), "Pass:%s", password);
  lcdLine(1, line);
  const bool client = localWifiReady && WiFi.softAPgetStationNum() > 0;
  if (client) {
    lcdBacklightActivityMs = nowMs;
    if (!lcdBacklightOn) {
      lcd.backlight();
      lcdBacklightOn = true;
    }
  } else if (planter::kLcdBacklightIdleMs > 0 && lcdBacklightOn &&
             nowMs - lcdBacklightActivityMs >= planter::kLcdBacklightIdleMs) {
    lcd.noBacklight();
    lcdBacklightOn = false;
  }
}

void sendLocalLine(const char* line) {
  if (!localWifiReady || !localClient || line == nullptr) return;
  char buffer[256];
  const size_t length = strlen(line);
  if (length + 1 >= sizeof(buffer)) return;
  memcpy(buffer, line, length);
  buffer[length] = '\n';
  const int written = send(localClient.fd(), buffer, length + 1, MSG_DONTWAIT);
  if (written != static_cast<int>(length + 1)) localClient.stop();
}

void sendLocalSample(char* output, size_t capacity) {
  if (!localWifiReady || !localClient) return;
  const size_t length = strlen(output);
  if (length + 1 >= capacity) {
    localClient.stop();
    return;
  }
  output[length] = '\n';
  // A slow or disconnected client must not block sampling or the watchdog.
  const int written = send(localClient.fd(), output, length + 1, MSG_DONTWAIT);
  if (written != static_cast<int>(length + 1)) localClient.stop();
  output[length] = '\0';
}

void sendControlAck(const planter::ControlCommand& command, bool ok,
                    const char* error) {
  char ack[256];
  const planter::ControlStatus status = relayController.status();
  const uint32_t nowMs = millis();
  const uint32_t remainingS =
      (relayController.pumpManualRemainingMs(nowMs) + 999) / 1000;
  const uint32_t lockoutS =
      (relayController.pumpCooldownRemainingMs(nowMs) + 999) / 1000;
  snprintf(ack, sizeof(ack),
           "{\"type\":\"ack\",\"id\":%lu,\"ok\":%s,\"error\":%s,"
           "\"pump_manual\":%s,\"pump_on\":%s,\"pump_remaining_s\":%lu,"
           "\"pump_cooldown_s\":%lu,\"pump_runtime_lockout\":%s,"
           "\"light_manual\":%s,\"light_on\":%s}",
           command.id, ok ? "true" : "false",
           error == nullptr ? "null" : error,
           relayController.pumpManual() ? "true" : "false",
           status.pumpOn ? "true" : "false",
           static_cast<unsigned long>(remainingS),
           static_cast<unsigned long>(lockoutS),
           relayController.pumpRuntimeLockout() ? "true" : "false",
           relayController.lightManual() ? "true" : "false",
           status.lightOn ? "true" : "false");
  sendLocalLine(ack);
}

// Manual ON also requires valid water data, a fresh sample and watchdog.
const char* pumpStartBlockReason() {
  if (millis() < planter::kBootGraceMs) return "boot_grace";
  if (strcmp(bootResetReason, "brownout") == 0 &&
      millis() < planter::kBrownoutPumpHoldMs) {
    return "brownout_hold";
  }
  if (!hasControlInput || !watchdogReady) return "sensor_unavailable";
  if (millis() - lastSampleMs > planter::kSampleStaleMs) return "sample_stale";
  if (lastControlInput.waterAdcRaw < 0) return "water_unavailable";
  if (lastControlInput.waterAdcRaw < planter::kPumpWaterLowRawAdc) {
    return "water_low";
  }
  return nullptr;
}

void applyControlCommand(const planter::ControlCommand& command, bool localAck) {
  const char* block = command.pumpSet && !command.pumpAuto && command.pumpOn
                          ? pumpStartBlockReason()
                          : nullptr;
  if (block != nullptr) {
    if (localAck) {
      char quoted[32];
      snprintf(quoted, sizeof(quoted), "\"%s\"", block);
      sendControlAck(command, false, quoted);
    }
    return;
  }

  const uint32_t nowMs = millis();
  bool autoRequested = false;
  if (command.pumpSet) {
    if (command.pumpAuto) {
      relayController.setPumpAuto(nowMs);
      autoRequested = true;
    } else {
      relayController.setPumpManual(nowMs, command.pumpOn,
                                    command.durationSeconds * 1000UL);
    }
  }
  if (command.lightSet) {
    if (command.lightAuto) {
      relayController.setLightAuto();
      autoRequested = true;
    } else {
      relayController.setLightManual(nowMs, command.lightOn,
                                     command.durationSeconds * 1000UL);
    }
  }
  if (autoRequested && hasControlInput) {
    // Re-evaluate AUTO immediately using the last sample.
    planter::ControlInput input = lastControlInput;
    input.relayTransient = relayTransient(nowMs);
    relayController.accept(nowMs, input);
  }
  syncRelayCommands(true);
  if (localAck) sendControlAck(command, true, "null");
}

void applyControlLine(const char* line) {
  const planter::ControlCommand command = planter::parseControlLine(line);
  if (!command.valid) {
    sendControlAck(command, false, "\"invalid\"");
    return;
  }
  applyControlCommand(command, true);
}

// Start the quiet window at the GPIO transition, not at the request.
void noteRelayEdge(uint32_t nowMs, const planter::ControlStatus& status) {
  relayQuietUntilMs = nowMs + planter::kRelaySettleMs;
  relayQuietSet = true;
  Serial.printf(
      "{\"type\":\"relay\",\"uptime_ms\":%lu,\"pump\":%s,\"light\":%s,"
      "\"quiet_ms\":%lu}\n",
      static_cast<unsigned long>(nowMs), status.pumpOn ? "true" : "false",
      status.lightOn ? "true" : "false",
      static_cast<unsigned long>(planter::kRelaySettleMs));
}

bool relayQuiet(uint32_t nowMs) {
  if (!relayQuietSet) return false;
  if (static_cast<int32_t>(nowMs - relayQuietUntilMs) >= 0) {
    relayQuietSet = false;
    return false;
  }
  return true;
}

// Pump and relay transients can affect ADC readings; raw values are still logged.
bool relayTransient(uint32_t nowMs) {
  return relayController.status().pumpOn || relayQuiet(nowMs);
}

struct ArduinoGpio {
  void write(int pin, bool high) { digitalWrite(pin, high ? HIGH : LOW); }
  void enableOutput(int pin) { pinMode(pin, OUTPUT); }
};

struct ArduinoSoilGpio {
  void write(int pin, bool high) { digitalWrite(pin, high ? HIGH : LOW); }
  void enableOutput(int pin) { pinMode(pin, OUTPUT); }
  void enableInput(int pin) { pinMode(pin, INPUT); }
  void delayMs(uint32_t milliseconds) { delay(milliseconds); }
  int readAnalog(int pin) { return medianAnalogRead(pin); }
};

ArduinoGpio relayGpio;
planter::RelayStager<ArduinoGpio> relayStager;

void syncRelayCommands(bool immediate) {
  const uint32_t nowMs = millis();
  const bool beforePump = relayStager.pumpOn();
  const bool beforeLight = relayStager.lightOn();
  const planter::ControlStatus status = relayController.status();
  relayStager.update(nowMs, status.pumpOn, status.lightOn, relayGpio,
                     immediate);
  if (beforePump != relayStager.pumpOn() ||
      beforeLight != relayStager.lightOn()) {
    noteRelayEdge(nowMs, status);
  }
  // Re-assert requested levels; this does not measure relay contacts.
  relayStager.reassert(relayGpio);
}

int readSoilRaw() {
  // ADC34 can be sampled without driving the unverified GPIO25 supply pin.
  ArduinoSoilGpio gpio;
  return planter::acquireSoilRaw(gpio, planter::kSoilAdcReadEnabled,
                                 planter::kSoilPowerWiringVerified);
}

// SVP/GPIO36 is ADC1 channel 0. Check module voltages separately.
int readMqRaw() {
  static_assert(extra_sensors::kMq135Pin == 36, "Update ADC1 channel for MQ pin");
  if (!mqAdcReady) return -1;
  return planter::medianAdc([]() { return readAdc1Settled(ADC1_CHANNEL_0); });
}

// GPIO35 is ADC1 channel 7; a 0 V UV reading is reported as rail_low.
void logUvProbe() {
  Serial.printf(
      "{\"type\":\"uv_probe\",\"gpio32\":%d,\"gpio33\":%d,\"gpio34\":%d,"
      "\"gpio35\":%d,\"gpio36\":%d,\"gpio39\":%d}\n",
      readAdc1Settled(ADC1_CHANNEL_4), readAdc1Settled(ADC1_CHANNEL_5),
      readAdc1Settled(ADC1_CHANNEL_6), readAdc1Settled(ADC1_CHANNEL_7),
      readAdc1Settled(ADC1_CHANNEL_0), readAdc1Settled(ADC1_CHANNEL_3));
}

int readUvRaw() {
  static_assert(planter::kUvPin == 35, "Update ADC1 channel for UV pin");
  if (!uvAdcReady) return -1;
  return planter::medianAdc([]() { return readAdc1Settled(ADC1_CHANNEL_7); });
}

bool handleDebugSerialCommand(const char* line) {
  if (line == nullptr) return false;
  if (strcmp(line, "SENSOR_SCAN") == 0) {
    int uvMin = 4096, uvMax = -1, uvSum = 0, uvCount = 0;
    int ldrMin = 4096, ldrMax = -1, ldrSum = 0, ldrCount = 0;
    int mqMin = 4096, mqMax = -1, mqSum = 0, mqCount = 0;
    for (int index = 0; index < 40; ++index) {
      const int uv = readAdc1Settled(ADC1_CHANNEL_7);
      const int ldr = readAnalogSettled(planter::kLightPin);
      const int mq = readAdc1Settled(ADC1_CHANNEL_0);
      if (uv >= 0 && uv <= 4095) {
        if (uv < uvMin) uvMin = uv;
        if (uv > uvMax) uvMax = uv;
        uvSum += uv;
        ++uvCount;
      }
      if (ldr >= 0 && ldr <= 4095) {
        if (ldr < ldrMin) ldrMin = ldr;
        if (ldr > ldrMax) ldrMax = ldr;
        ldrSum += ldr;
        ++ldrCount;
      }
      if (mq >= 0 && mq <= 4095) {
        if (mq < mqMin) mqMin = mq;
        if (mq > mqMax) mqMax = mq;
        mqSum += mq;
        ++mqCount;
      }
      delay(25);
    }
    Serial.printf(
        "{\"type\":\"sensor_scan\",\"n\":40,"
        "\"uv_min\":%d,\"uv_max\":%d,\"uv_avg\":%d,"
        "\"ldr_min\":%d,\"ldr_max\":%d,\"ldr_avg\":%d,"
        "\"mq_min\":%d,\"mq_max\":%d,\"mq_avg\":%d}\n",
        uvCount ? uvMin : -1, uvCount ? uvMax : -1,
        uvCount ? (uvSum + uvCount / 2) / uvCount : -1,
        ldrCount ? ldrMin : -1, ldrCount ? ldrMax : -1,
        ldrCount ? (ldrSum + ldrCount / 2) / ldrCount : -1,
        mqCount ? mqMin : -1, mqCount ? mqMax : -1,
        mqCount ? (mqSum + mqCount / 2) / mqCount : -1);
    return true;
  }
  if (strcmp(line, "WIFI_STATE") == 0) {
    Serial.printf(
        "{\"type\":\"debug\",\"ap\":%s,\"ap_clients\":%d,\"tx_power\":%d,"
        "\"free_heap\":%lu}\n",
        localWifiReady ? "true" : "false",
        localWifiReady ? WiFi.softAPgetStationNum() : 0,
        static_cast<int>(WiFi.getTxPower()),
        static_cast<unsigned long>(ESP.getFreeHeap()));
    return true;
  }
  return false;
}

void readObservationCommands() {
  // Bound work per loop so serial input cannot starve the watchdog.
  for (unsigned count = 0; count < 64 && Serial.available() > 0; ++count) {
    const int value = Serial.read();
    if (value < 0) break;
    const planter::LabelLineResult line = labelLineReader.push(static_cast<char>(value));
    if (line == planter::LabelLineResult::pending) continue;
    const uint32_t nowMs = millis();
    const char* rawLine =
        line == planter::LabelLineResult::ready ? labelLineReader.line() : nullptr;
    if (handleDebugSerialCommand(rawLine)) continue;
    const planter::LabelCommandResult result =
        observationLabels.apply(rawLine, nowMs);
    if (result == planter::LabelCommandResult::set) {
      const planter::ObservationLabel* label = observationLabels.current(nowMs);
      Serial.printf("{\"type\":\"annotation\",\"event\":\"set\","
                    "\"uptime_ms\":%lu,\"sensor\":\"%s\",\"condition\":\"%s\","
                    "\"source\":\"operator_reported\",\"max_duration_ms\":%lu}\n",
                    static_cast<unsigned long>(nowMs), label->sensor,
                    label->condition,
                    static_cast<unsigned long>(planter::kObservationLabelTtlMs));
    } else {
      Serial.printf("{\"type\":\"annotation\",\"event\":\"%s\","
                    "\"uptime_ms\":%lu}\n",
                    result == planter::LabelCommandResult::cleared ? "cleared"
                                                                   : "rejected_and_cleared",
                    static_cast<unsigned long>(nowMs));
    }
  }
}

void printSample(uint32_t nowMs) {
  const bool transient = relayTransient(nowMs);
  const int uvRaw = readUvRaw();
  // Keep raw 0 at 0 mV despite the ADC calibration intercept.
  const int uvPinMillivolts =
      uvRaw == 0
          ? 0
          : (uvRaw > 0 &&
                     uvAdcCalibration != planter::AdcCalibrationMethod::unavailable
                 ? static_cast<int>(
                       esp_adc_cal_raw_to_voltage(uvRaw, &uvAdcCharacteristics))
                 : -1);
  const int lightRaw = medianAnalogRead(planter::kLightPin);
  const int mqRaw = readMqRaw();
  const int waterRaw = medianAnalogRead(extra_sensors::kWaterLevelPin);
  const int mqPinMillivolts =
      planter::controlAnalogUsable(mqRaw) &&
              mqAdcCalibration != planter::AdcCalibrationMethod::unavailable
          ? static_cast<int>(esp_adc_cal_raw_to_voltage(mqRaw, &mqAdcCharacteristics))
          : -1;
  planter::SensorSnapshot sample = {
      nowMs,
      planter::kDhtEnabled ? climateSensor.readTemperature() : NAN,
      planter::kDhtEnabled ? climateSensor.readHumidity() : NAN,
      readSoilRaw(),
      lightRaw,
      uvRaw,
      planter::kDhtEnabled,
      waterRaw,
      true,
      planter::kSoilAdcReadEnabled,
      planter::kDhtModelVerified,
      mqRaw,
      digitalRead(extra_sensors::kMq135DigitalPin),
      true,
      mqRaw >= 0,
      mqPinMillivolts,
      mqAdcCalibration,
      uvPinMillivolts,
      transient,
  };

  sample.uptimeMs = millis();
  if (uvRaw == 0) {
    static uint32_t lastUvProbeMs = 0;
    if (lastUvProbeMs == 0 || sample.uptimeMs - lastUvProbeMs >= 60000) {
      lastUvProbeMs = sample.uptimeMs;
      logUvProbe();
    }
  }
  const planter::RulePreview preview = planter::previewRules(sample);
  // Rail values can indicate a fault; keep raw data visible in telemetry.
  const bool soilUsable = planter::soilAnalogUsable(sample.soilAdcRaw);
  // LDR rails are valid bright/dark extremes; a failed read is still -1.
  const bool lightUsable = planter::validAdcRaw(sample.lightAdcRaw);
  const bool waterUsable = planter::controlWaterAdcUsable(sample.waterAdcRaw);
  if (!transient && waterUsable) {
    lastStableWaterRaw = sample.waterAdcRaw;
    lastStableWaterMs = nowMs;
  }
  // Use the last valid water value for control for at most 30 seconds.
  // Telemetry still reports the current raw value.
  int controlWaterRaw = waterUsable ? sample.waterAdcRaw : -1;
  if (transient && !waterUsable && lastStableWaterRaw >= 0 &&
      static_cast<uint32_t>(nowMs - lastStableWaterMs) <= 30000) {
    controlWaterRaw = lastStableWaterRaw;
  }
  const int controlWaterPercent =
      controlWaterRaw >= 0
          ? planter::relativePercent(controlWaterRaw, planter::kWaterEmptyAdc,
                                     planter::kWaterFullAdc)
          : -1;
  const planter::ControlInput input = {
      soilUsable ? sample.soilAdcRaw : -1,
      lightUsable ? preview.lightPercent : -1,
      controlWaterPercent,
      planter::kPumpSoilScaleConfirmed || planter::kPumpAllowEstimatedSoil,
      planter::kWaterRelativeScaleEnabled,
      watchdogReady,
      planter::kLightAutomationEnabled,
      controlWaterRaw,
      transient,
  };
  lastControlInput = input;
  hasControlInput = true;
  if (strcmp(bootResetReason, "brownout") == 0 &&
      millis() < planter::kBrownoutPumpHoldMs) {
    relayController.inhibit(sample.uptimeMs, "brownout_hold");
  } else {
    relayController.accept(sample.uptimeMs, input);
  }
  syncRelayCommands();
  planter::ControlStatus control = relayController.status();
  control.pumpRuntimeLockout = relayController.pumpRuntimeLockout();
  control.pumpCooldownRemainingS =
      (relayController.pumpCooldownRemainingMs(sample.uptimeMs) + 999) / 1000;

  // Avoid placing the entire network frame on the ESP32 loop task's stack.
  static char output[3072];
  if (planter::formatTelemetry(sample, output, sizeof(output), &control,
                               observationLabels.current(sample.uptimeMs))) {
    snprintf(latestTelemetry, sizeof(latestTelemetry), "%s", output);
    latestTelemetryValid = true;
    Serial.println(output);
    sendLocalSample(output, sizeof(output));
  } else {
    Serial.println("{\"type\":\"error\",\"code\":\"encoding_failed\"}");
  }
  updateLcd(sample.uptimeMs);
}

void startLocalAccessPoint() {
  // All Wi-Fi configuration stays in RAM; the access point is the only link.
  WiFi.persistent(false);
  if (!WiFi.mode(WIFI_AP)) {
    Serial.println("{\"type\":\"wifi\",\"status\":\"ap_mode_failed\"}");
    return;
  }
  WiFi.setTxPower(WIFI_POWER_11dBm);
  // Avoid a Wi-Fi wake-up delay on the first command after idle.
  WiFi.setSleep(false);
  bool passwordReady = false;
#ifdef MOSS_LOCAL_WIFI_PASSWORD
  // Use the local AP password or generate one at boot.
  const size_t fixedLength = strlen(MOSS_LOCAL_WIFI_PASSWORD);
  if (fixedLength >= 8 && fixedLength < sizeof(localWifiPassword)) {
    memcpy(localWifiPassword, MOSS_LOCAL_WIFI_PASSWORD, fixedLength + 1);
    passwordReady = true;
  } else {
    Serial.println("{\"type\":\"wifi\",\"status\":\"local_password_rejected\"}");
  }
#endif
  if (!passwordReady) {
    HardwareRandom random;
    if (!planter::makeLocalWifiPassword(localWifiPassword,
                                        sizeof(localWifiPassword), random)) {
      Serial.println("{\"type\":\"wifi\",\"status\":\"password_failed\"}");
      WiFi.mode(WIFI_OFF);
      return;
    }
  }
  snprintf(localWifiName, sizeof(localWifiName), "Moss");
  if (!WiFi.softAPConfig(localAddress, localAddress, IPAddress(255, 255, 255, 0)) ||
      !WiFi.softAP(localWifiName, localWifiPassword, 6, false,
                   planter::kLocalApMaxClients)) {
    Serial.println("{\"type\":\"wifi\",\"status\":\"ap_failed\"}");
    WiFi.softAPdisconnect(true);
    return;
  }
  applyLocalApPowerProfile(true);
  localServer.begin();
  localWifiReady = static_cast<bool>(localServer);
  if (!localWifiReady) {
    Serial.println("{\"type\":\"wifi\",\"status\":\"server_failed\"}");
    WiFi.softAPdisconnect(true);
    return;
  }
  Serial.printf("{\"type\":\"wifi\",\"status\":\"ap_ready\",\"ssid\":\"%s\","
                "\"ip\":\"%s\",\"port\":%u}\n",
                localWifiName, localAddress.toString().c_str(),
                planter::kLocalTelemetryPort);

  localHttpServer.on("/", HTTP_GET, []() {
    localHttpServer.send(200, "text/html; charset=utf-8",
                         R"HTML(<!doctype html>
<html lang="id"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tunas Lokal</title>
<style>
:root{--ink:#213027;--forest:#315E48;--paper:#F7F5EF;--line:#DDE5DA;--muted:#6A756B}
*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.5 system-ui,-apple-system,Segoe UI,sans-serif}
main{max-width:34rem;margin:auto;padding:24px 16px 48px}
h1{font-size:24px;margin:6px 0 2px}p{margin:.2rem 0;color:var(--muted)}
.card{background:#fff;border:1px solid var(--line);border-radius:18px;padding:16px;margin:12px 0}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.cell{background:#F1F4EF;border-radius:12px;padding:10px 12px}
.cell b{display:block;font-size:11px;letter-spacing:.04em;text-transform:uppercase;color:var(--muted)}
.cell span{font-size:19px;font-weight:750}
code{font-size:12px;background:#F1F4EF;padding:2px 6px;border-radius:6px}
.badge{font-size:11px;font-weight:750;letter-spacing:.05em;color:var(--forest);text-transform:uppercase}
</style></head><body><main>
<span class="badge">Tunas Smart Planter</span>
<h1>Mode lokal</h1>
<p>HP harus terhubung ke Wi-Fi <b>Moss</b>. Data live dikirim ke port 3333.</p>
<div class="card"><div class="grid">
<div class="cell"><b>Suhu</b><span id="temp">-</span></div>
<div class="cell"><b>Kelembapan</b><span id="hum">-</span></div>
<div class="cell"><b>Tanah</b><span id="soil">-</span></div>
<div class="cell"><b>Air</b><span id="water">-</span></div>
<div class="cell"><b>Cahaya</b><span id="light">-</span></div>
<div class="cell"><b>UV ADC</b><span id="uv">-</span></div>
<div class="cell"><b>MQ135 ADC</b><span id="mq">-</span></div>
<div class="cell"><b>Pompa</b><span id="pump">-</span></div>
</div><p id="status" style="margin-top:12px">Menunggu sampel...</p></div>
<div class="card"><b>Endpoint</b>
<p><code>/api/v1/telemetry</code> satu sampel JSON terakhir</p>
<p><code>/api/v1/health</code> status perangkat</p>
<p><code>192.168.4.1:3333</code> stream JSON per baris untuk aplikasi</p></div>
<script>
const $=id=>document.getElementById(id);
function num(v){return v===null||v===undefined?'-':v}
async function poll(){
  try{
    const r=await fetch('/api/v1/telemetry',{cache:'no-store'});
    if(!r.ok) throw new Error('no sample');
    const j=await r.json();
    $('temp').textContent=num(j.dht&&j.dht.temperature_c)+' C';
    $('hum').textContent=num(j.dht&&j.dht.humidity_percent)+' %';
    $('soil').textContent=num(j.adc&&j.adc.soil_relative_percent)+' %';
    $('water').textContent=num(j.water_level&&j.water_level.relative_percent)+' %';
    $('light').textContent=num(j.adc&&j.adc.light_relative_percent)+' %';
    $('uv').textContent=num(j.adc&&j.adc.uv_raw);
    $('mq').textContent=num(j.mq135&&j.mq135.adc_raw);
    $('pump').textContent=j.pump_cmd===null?'-':(j.pump_cmd?'ON':'OFF');
    const t=j.adc&&j.adc.relay_transient;
    $('status').textContent=t?'Relay/pompa aktif: nilai analog ditandai transient.':'Data terbaru diterima.';
  }catch(e){$('status').textContent='Belum ada sampel; perangkat sedang boot.';}
  setTimeout(poll,2000);
}
poll();
</script></main></body></html>)HTML");
  });
  localHttpServer.on("/api/v1/telemetry", HTTP_GET, []() {
    if (!latestTelemetryValid) {
      localHttpServer.send(503, "application/json",
                           "{\"error\":\"no_sample_yet\"}");
      return;
    }
    localHttpServer.send(200, "application/json", latestTelemetry);
  });
  localHttpServer.on("/api/v1/health", HTTP_GET, []() {
    char body[640];
    const uint32_t nowMs = millis();
    snprintf(body, sizeof(body),
             "{\"firmware_version\":%u,\"uptime_ms\":%lu,"
             "\"hardware_id\":\"%s\",\"reset_reason\":\"%s\","
             "\"brownout_count\":%lu,\"ap_active\":%s,\"ap_clients\":%d,"
             "\"tx_power\":%d,\"free_heap\":%lu,\"sample_age_ms\":%lu,"
             "\"relay_transient\":%s}",
             planter::kFirmwareVersion,
             static_cast<unsigned long>(nowMs), kDeviceId, bootResetReason,
             static_cast<unsigned long>(bootBrownoutCount),
             localWifiReady ? "true" : "false",
             localWifiReady ? WiFi.softAPgetStationNum() : 0,
             static_cast<int>(WiFi.getTxPower()),
             static_cast<unsigned long>(ESP.getFreeHeap()),
             static_cast<unsigned long>(hasSample ? nowMs - lastSampleMs : 0),
             relayTransient(nowMs) ? "true" : "false");
    localHttpServer.send(200, "application/json", body);
  });
  localHttpServer.onNotFound([]() {
    localHttpServer.send(404, "application/json", "{\"error\":\"not_found\"}");
  });
  localHttpServer.begin();
}

void pollLocalWifi() {
  if (!localWifiReady) return;
  if (localClient && !localClient.connected()) {
    // Drop a half-open peer so a fresh phone connection can be accepted.
    localClient.stop();
  }
  if (localClient) {
    // Bound command reads so telemetry and watchdog work can continue.
    for (unsigned count = 0; count < 64 && localClient.available() > 0; ++count) {
      const int value = localClient.read();
      if (value < 0) break;
      const planter::ControlLineReader::Result result =
          controlLineReader.push(static_cast<char>(value));
      if (result == planter::ControlLineReader::Result::ready) {
        applyControlLine(controlLineReader.line());
      } else if (result == planter::ControlLineReader::Result::rejected) {
        sendControlAck(planter::ControlCommand{}, false, "\"line_too_long\"");
      }
    }
  }
  if (!localClient) {
    localClient.stop();
    localClient = localServer.available();
    if (localClient) localClient.setNoDelay(true);
  } else if (localServer.hasClient()) {
    WiFiClient extra = localServer.available();
    extra.stop();
  }
}

}  // namespace

void setup() {
  setCpuFrequencyMhz(planter::kCpuFrequencyMhz);
  ArduinoGpio gpio;
  planter::configureRelaysInactive(gpio);
  relayStager.begin(millis(), relayGpio);
  relayController.begin(millis());
  Serial.begin(115200);
  delay(50);
  logBootReason();

  const esp_err_t watchdogInit =
      esp_task_wdt_init(planter::kWatchdogTimeoutSeconds, true);
  watchdogReady =
      (watchdogInit == ESP_OK || watchdogInit == ESP_ERR_INVALID_STATE) &&
      (esp_task_wdt_status(nullptr) == ESP_OK ||
       esp_task_wdt_add(nullptr) == ESP_OK);
  if (!watchdogReady) {
    relayController.inhibit(millis(), "watchdog_unavailable");
    syncRelayCommands();
  }

  Wire.begin(planter::kLegacyI2cSdaPin, planter::kLegacyI2cSclPin);
  // Limit I2C stalls so the loop and watchdog can continue.
  Wire.setTimeOut(50);
  lcd.init();
  lcd.backlight();
  lcdLine(0, "Smart Planter");
  lcdLine(1, "v51 local");
  if (planter::kDhtEnabled) climateSensor.begin();
  analogReadResolution(12);

  // GPIO36 voltage is an estimate, not a check of the MQ135 supply or divider.
  const bool adcWidthReady = adc1_config_width(ADC_WIDTH_BIT_12) == ESP_OK;
  mqAdcReady = adcWidthReady &&
               adc1_config_channel_atten(ADC1_CHANNEL_0, ADC_ATTEN_DB_12) == ESP_OK;
  uvAdcReady = adcWidthReady &&
               adc1_config_channel_atten(ADC1_CHANNEL_7, ADC_ATTEN_DB_12) == ESP_OK;
  if (mqAdcReady) {
    const esp_adc_cal_value_t mqCal = esp_adc_cal_characterize(
        ADC_UNIT_1, ADC_ATTEN_DB_12, ADC_WIDTH_BIT_12, 1100, &mqAdcCharacteristics);
    switch (mqCal) {
      case ESP_ADC_CAL_VAL_EFUSE_TP:
        mqAdcCalibration = planter::AdcCalibrationMethod::efuse_two_point;
        break;
      case ESP_ADC_CAL_VAL_EFUSE_VREF:
        mqAdcCalibration = planter::AdcCalibrationMethod::efuse_vref;
        break;
      case ESP_ADC_CAL_VAL_DEFAULT_VREF:
        mqAdcCalibration = planter::AdcCalibrationMethod::default_vref;
        break;
      default:
        mqAdcCalibration = planter::AdcCalibrationMethod::unavailable;
    }
  }
  if (uvAdcReady) {
    const esp_adc_cal_value_t uvCal = esp_adc_cal_characterize(
        ADC_UNIT_1, ADC_ATTEN_DB_12, ADC_WIDTH_BIT_12, 1100, &uvAdcCharacteristics);
    switch (uvCal) {
      case ESP_ADC_CAL_VAL_EFUSE_TP:
        uvAdcCalibration = planter::AdcCalibrationMethod::efuse_two_point;
        break;
      case ESP_ADC_CAL_VAL_EFUSE_VREF:
        uvAdcCalibration = planter::AdcCalibrationMethod::efuse_vref;
        break;
      case ESP_ADC_CAL_VAL_DEFAULT_VREF:
        uvAdcCalibration = planter::AdcCalibrationMethod::default_vref;
        break;
      default:
        uvAdcCalibration = planter::AdcCalibrationMethod::unavailable;
    }
  }
  for (int channel = 0; channel < 8; ++channel) {
    adc1_config_channel_atten(static_cast<adc1_channel_t>(channel),
                              ADC_ATTEN_DB_12);
  }
  logUvProbe();
  pinMode(extra_sensors::kWaterLevelPin, INPUT);
  pinMode(extra_sensors::kMq135DigitalPin, INPUT);
  ArduinoSoilGpio soilGpio;
  planter::configureSoilPower(soilGpio, planter::kSoilPowerWiringVerified);

  startLocalAccessPoint();
  Serial.printf(
      "{\"type\":\"startup\",\"mode\":\"local_only\",\"version\":%u,"
      "\"hardware_id\":\"%s\",\"relay_control\":\"automatic_requested\","
      "\"soil_power\":\"%s\",\"soil_adc\":\"%s\",\"dht\":\"%s\","
      "\"water\":\"enabled_unverified\",\"mq135\":\"enabled_unverified\","
      "\"watchdog\":\"%s\",\"pump_polarity\":\"active_low_assumed\","
      "\"light_polarity\":\"active_high_assumed\","
      "\"light_automation\":\"%s\",\"annotations\":\"operator_reported\","
      "\"wifi\":\"ap_only\"}\n",
      planter::kFirmwareVersion, kDeviceId,
      planter::kSoilPowerWiringVerified ? "gpio25_switched_verified_by_operator"
                                       : "gpio25_input_unverified",
      planter::kSoilAdcReadEnabled ? "enabled_unverified" : "not_configured",
      planter::kDhtEnabled ? "DHT11_assumed" : "not_configured",
      watchdogReady ? "subscribed_unverified" : "unavailable",
      planter::kLightAutomationEnabled ? "enabled" : "inhibited");
}

void loop() {
  const uint32_t nowMs = millis();
  static uint32_t lastLcdUpdateMs = 0;
  if (nowMs - lastLcdUpdateMs >= 400) {
    lastLcdUpdateMs = nowMs;
    updateLcd(nowMs);
  }
  if (watchdogReady && esp_task_wdt_reset() != ESP_OK) {
    watchdogReady = false;
    relayController.inhibit(nowMs, "watchdog_unavailable");
  }
  relayController.tick(nowMs);
  syncRelayCommands();
  pollLocalWifi();
  if (localWifiReady) localHttpServer.handleClient();
  readObservationCommands();
  if (!hasSample ||
      planter::sampleDue(nowMs, lastSampleMs, planter::kSampleIntervalMs)) {
    hasSample = true;
    lastSampleMs = nowMs;
    printSample(nowMs);
  }
  // Re-assert requested relay levels more often while active.
  delay(relayController.status().pumpOn || relayController.status().lightOn ? 5
                                                                             : 10);
}
