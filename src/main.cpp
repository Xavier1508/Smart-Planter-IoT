// Single Smart Planter firmware. GPIO levels, wiring, and calibration remain
// unverified. Disconnect external loads during flashing and initial checks.
// Requested commands cannot guarantee relay contacts or boot-time levels.

#include <Arduino.h>
#include <DHT.h>
#include <LiquidCrystal_I2C.h>
#include <Preferences.h>
#include <WiFi.h>
#include <Wire.h>
#include <driver/adc.h>
#include <esp_adc_cal.h>
#include <esp_system.h>
#include <esp_task_wdt.h>
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

DHT climateSensor(planter::kDhtPin, DHT11);
LiquidCrystal_I2C lcd(0x27, 16, 2);
bool hasSample = false;
uint32_t lastSampleMs = 0;
bool watchdogReady = false;
bool mqAdcReady = false;
planter::RelayController relayController;
planter::ControlInput lastControlInput{0, 0, 0, false, false, false, false};
bool hasControlInput = false;
planter::ObservationLabels observationLabels;
planter::LabelLineReader labelLineReader;
planter::ControlLineReader controlLineReader;
esp_adc_cal_characteristics_t mqAdcCharacteristics;
planter::AdcCalibrationMethod mqAdcCalibration = planter::AdcCalibrationMethod::unavailable;
const IPAddress localAddress(192, 168, 4, 1);
WiFiServer localServer(localAddress, planter::kLocalTelemetryPort, 1);
WiFiClient localClient;
bool localWifiReady = false;
char localWifiName[17] = {};
char localWifiPassword[planter::kLocalWifiPasswordLength + 1] = {};

void applyControlLine(const char* line);
void sendControlAck(const planter::ControlCommand& command, bool ok,
                    const char* error);
void syncRelayCommands(bool immediate = false);

struct HardwareRandom {
  uint32_t next() { return esp_random(); }
};

void startLocalWifi() {
  // All Wi-Fi configuration stays in RAM. This is an isolated AP rather than
  // a router connection; no router password is requested, stored or printed.
  WiFi.persistent(false);
  if (!WiFi.mode(WIFI_AP)) {
    Serial.println("{\"type\":\"wifi\",\"status\":\"ap_mode_failed\"}");
    return;
  }
  // The planter is mains-powered. Disable modem sleep so the first command
  // after a long idle does not wait for a Wi-Fi wake-up interval.
  WiFi.setSleep(false);
  bool passwordReady = false;
#ifdef MOSS_LOCAL_WIFI_PASSWORD
  // Fixed local-only WPA2 password from an ignored header. The phone stores it
  // once and can reconnect automatically after every ESP32 reboot. An invalid
  // local value must not disable the AP; fall back to the boot-random password
  // so the LCD can still show a usable network.
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
  snprintf(localWifiName, sizeof(localWifiName), "Moss-%04X",
           static_cast<unsigned>(ESP.getEfuseMac() & 0xffffU));
  if (!WiFi.softAPConfig(localAddress, localAddress, IPAddress(255, 255, 255, 0)) ||
      !WiFi.softAP(localWifiName, localWifiPassword, 1, false, 1)) {
    Serial.println("{\"type\":\"wifi\",\"status\":\"ap_failed\"}");
    WiFi.softAPdisconnect(true);
    return;
  }
  localServer.begin();
  localWifiReady = static_cast<bool>(localServer);
  if (!localWifiReady) {
    Serial.println("{\"type\":\"wifi\",\"status\":\"server_failed\"}");
    WiFi.softAPdisconnect(true);
  } else {
    Serial.printf("{\"type\":\"wifi\",\"status\":\"ap_ready\",\"ssid\":\"%s\"}\n",
                  localWifiName);
  }
}

void pollLocalWifi() {
  if (!localWifiReady) return;
  if (localClient && !localClient.connected()) {
    // Drop a half-open peer so a fresh phone connection can be accepted.
    localClient.stop();
  }
  if (localClient) {
    // Read a bounded number of command bytes per loop so serial/telemetry and
    // the watchdog are never starved. The command reader is line-bounded.
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

void sendControlAck(const planter::ControlCommand& command, bool ok,
                    const char* error) {
  char ack[256];
  const planter::ControlStatus status = relayController.status();
  const uint32_t nowMs = millis();
  const uint32_t remainingS =
      (relayController.pumpManualRemainingMs(nowMs) + 999) / 1000;
  snprintf(ack, sizeof(ack),
           "{\"type\":\"ack\",\"id\":%lu,\"ok\":%s,\"error\":%s,"
           "\"pump_manual\":%s,\"pump_on\":%s,\"pump_remaining_s\":%lu,"
           "\"light_manual\":%s,\"light_on\":%s}",
           command.id, ok ? "true" : "false",
           error == nullptr ? "null" : error,
           relayController.pumpManual() ? "true" : "false",
           status.pumpOn ? "true" : "false",
           static_cast<unsigned long>(remainingS),
           relayController.lightManual() ? "true" : "false",
           status.lightOn ? "true" : "false");
  sendLocalLine(ack);
}

void applyControlLine(const char* line) {
  const planter::ControlCommand command = planter::parseControlLine(line);
  if (!command.valid) {
    sendControlAck(command, false, "\"invalid\"");
    return;
  }
  const uint32_t nowMs = millis();
  bool autoRequested = false;
  if (command.pumpSet) {
    if (command.pumpAuto) {
      relayController.setPumpAuto();
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
    // Apply the last measured sample immediately so AUTO does not keep a
    // manual ON output until the next 5-second sample.
    relayController.accept(nowMs, lastControlInput);
  }
  syncRelayCommands(true);
  sendControlAck(command, true, "null");
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
  // Serial diagnostic only; this line is never sent over the TCP telemetry
  // stream, so the Android parser is unaffected.
  Serial.printf(
      "{\"type\":\"boot\",\"firmware_version\":%u,\"reset_reason\":\"%s\","
      "\"brownout_count\":%lu,\"nvs_ready\":%s}\n",
      planter::kFirmwareVersion, resetReasonName(reason),
      static_cast<unsigned long>(brownouts), nvsReady ? "true" : "false");
}

struct ArduinoGpio {
  void write(int pin, bool high) { digitalWrite(pin, high ? HIGH : LOW); }
  void enableOutput(int pin) { pinMode(pin, OUTPUT); }
};

int medianAnalogRead(int pin) {
  return planter::medianAdc([pin]() { return analogRead(pin); });
}

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
  const planter::ControlStatus status = relayController.status();
  relayStager.update(millis(), status.pumpOn, status.lightOn, relayGpio,
                     immediate);
}

int readSoilRaw() {
  // ADC34 can be sampled without driving the unverified GPIO25 supply pin.
  ArduinoSoilGpio gpio;
  return planter::acquireSoilRaw(gpio, planter::kSoilAdcReadEnabled,
                                 planter::kSoilPowerWiringVerified);
}

void readObservationCommands() {
  // Bound work per loop so serial input cannot starve the watchdog.
  for (unsigned count = 0; count < 64 && Serial.available() > 0; ++count) {
    const int value = Serial.read();
    if (value < 0) break;
    const planter::LabelLineResult line = labelLineReader.push(static_cast<char>(value));
    if (line == planter::LabelLineResult::pending) continue;
    const uint32_t nowMs = millis();
    const planter::LabelCommandResult result = observationLabels.apply(
        line == planter::LabelLineResult::ready ? labelLineReader.line() : nullptr,
        nowMs);
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

// User-reported SVP/GPIO36 is ADC1 channel 0. ADC1 remains usable while Wi-Fi
// runs; neither an ADC value nor firmware can verify safe module voltages.
int readMqRaw() {
  static_assert(extra_sensors::kMq135Pin == 36, "Update ADC1 channel for MQ pin");
  if (!mqAdcReady) return -1;
  return planter::medianAdc([]() { return adc1_get_raw(ADC1_CHANNEL_0); });
}

void lcdLine(uint8_t row, const char* text) {
  char padded[17];
  snprintf(padded, sizeof(padded), "%-16.16s", text);
  lcd.setCursor(0, row);
  lcd.print(padded);
}

void updateLcd(const planter::SensorSnapshot& sample,
               const planter::ControlStatus& control) {
  const unsigned page = planter::lcdPageForUptime(sample.uptimeMs);
  char first[17];
  char second[17];
  if (page == 0) {
    char temperature[8] = "--";
    char humidity[8] = "--";
    if (sample.dhtEnabled && planter::validTemperature(sample.temperatureC))
      snprintf(temperature, sizeof(temperature), "%.0fC", sample.temperatureC);
    if (sample.dhtEnabled && planter::validHumidity(sample.humidityPercent))
      snprintf(humidity, sizeof(humidity), "%.0f%%", sample.humidityPercent);
    snprintf(first, sizeof(first), "T:%s H:%s", temperature, humidity);
    const int soil = planter::observedSoilRelativePercent(sample);
    if (soil >= 0) snprintf(second, sizeof(second), "Soil:~%d%%", soil);
    else snprintf(second, sizeof(second), "Soil:--");
  } else if (page == 1) {
    const int light = planter::relativePercent(sample.lightAdcRaw,
                                               planter::kLightRelativeZeroAdc,
                                               planter::kLightRelativeFullAdc);
    if (light >= 0) snprintf(first, sizeof(first), "Light:~%d%%", light);
    else snprintf(first, sizeof(first), "Light:--");
    const int uvAdcPercent = planter::relativePercent(sample.uvAdcRaw, 0, 4095);
    if (uvAdcPercent >= 0) {
      // ADC fraction only; this is not a UV index or lamp control input.
      snprintf(second, sizeof(second), "UV ADC:~%d%%", uvAdcPercent);
    } else {
      snprintf(second, sizeof(second), "UV:--");
    }
  } else if (page == 2) {
    const int water = planter::observedWaterRelativePercent(sample);
    planter::formatWaterLcd(first, sizeof(first), water, sample.waterAdcRaw);
    if (sample.mqEnabled && sample.mqAdcReadable &&
        planter::validAdcRaw(sample.mqAdcRaw)) {
      const int mqAdcPercent = planter::relativePercent(sample.mqAdcRaw, 0, 4095);
      // ADC fraction only; not a gas concentration or air-quality percentage.
      snprintf(second, sizeof(second), "MQ ADC:~%d%%", mqAdcPercent);
    } else if (sample.mqEnabled &&
               (sample.mqDigitalRaw == 0 || sample.mqDigitalRaw == 1)) {
      snprintf(second, sizeof(second), "MQ digital: %d", sample.mqDigitalRaw);
    } else {
      snprintf(second, sizeof(second), "MQ:--");
    }
  } else if (page == 3) {
    // "cmd" is the requested output, not a measured relay/contact state.
    // The soil band is diagnostic only and never bypasses the pump guards.
    const planter::PumpSoilBand soilBand = sample.soilEnabled
        ? planter::pumpSoilBand(sample.soilAdcRaw)
        : planter::PumpSoilBand::unavailable;
    snprintf(first, sizeof(first), "P:%s cmd %s", control.pumpOn ? "ON" : "OFF",
             planter::pumpSoilBandLcd(soilBand));
    snprintf(second, sizeof(second), "L:%s cmd", control.lightOn ? "ON" : "OFF");
  } else if (localWifiReady) {
    // The password is shown only on the physical LCD, not serial or telemetry.
    snprintf(first, sizeof(first), "%s", localWifiName);
    snprintf(second, sizeof(second), "PW:%s", localWifiPassword);
  } else {
    snprintf(first, sizeof(first), "WiFi:--");
    snprintf(second, sizeof(second), "Local AP failed");
  }
  lcdLine(0, first);
  lcdLine(1, second);
}

void printSample(uint32_t nowMs) {
  const int mqRaw = readMqRaw();
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
      medianAnalogRead(planter::kLightPin),
      medianAnalogRead(planter::kUvPin),
      planter::kDhtEnabled,
      medianAnalogRead(extra_sensors::kWaterLevelPin),
      true,
      planter::kSoilAdcReadEnabled,
      planter::kDhtModelVerified,
      mqRaw,
      digitalRead(extra_sensors::kMq135DigitalPin),
      true,
      mqRaw >= 0,
      mqPinMillivolts,
      mqAdcCalibration,
  };

  sample.uptimeMs = millis();
  const planter::RulePreview preview = planter::previewRules(sample);
  // A rail can be a real extreme or a disconnected signal. For actuator
  // control, reject the ambiguity rather than interpreting it as darkness or
  // dryness. The unmodified raw values remain visible in telemetry.
  const bool soilUsable = planter::soilAnalogUsable(sample.soilAdcRaw);
  // LDR rails are valid bright/dark extremes; a failed read is still -1.
  const bool lightUsable = planter::validAdcRaw(sample.lightAdcRaw);
  const bool waterUsable = planter::controlWaterAdcUsable(sample.waterAdcRaw);
  const planter::ControlInput input = {
      soilUsable ? sample.soilAdcRaw : -1,
      lightUsable ? preview.lightPercent : -1,
      waterUsable ? preview.waterPercent : -1,
      planter::kPumpSoilScaleConfirmed || planter::kPumpAllowEstimatedSoil,
      planter::kWaterRelativeScaleEnabled,
      watchdogReady,
      planter::kLightAutomationEnabled,
      waterUsable ? sample.waterAdcRaw : -1,
  };
  lastControlInput = input;
  hasControlInput = true;
  relayController.accept(sample.uptimeMs, input);
  syncRelayCommands();
  const planter::ControlStatus control = relayController.status();

  // Avoid placing the entire network frame on the ESP32 loop task's stack.
  static char output[3072];
  if (planter::formatTelemetry(sample, output, sizeof(output), &control,
                                observationLabels.current(sample.uptimeMs))) {
    Serial.println(output);
    sendLocalSample(output, sizeof(output));
  } else {
    Serial.println("{\"type\":\"error\",\"code\":\"encoding_failed\"}");
  }
  updateLcd(sample, control);
}

}  // namespace

void setup() {
  ArduinoGpio gpio;
  planter::configureRelaysInactive(gpio);
  relayStager.begin(millis(), relayGpio);
  relayController.begin(millis());
  Serial.begin(115200);
  delay(50);
  logBootReason();
  const esp_err_t watchdogInit =
      esp_task_wdt_init(planter::kWatchdogTimeoutSeconds, true);
  watchdogReady = (watchdogInit == ESP_OK || watchdogInit == ESP_ERR_INVALID_STATE) &&
                  (esp_task_wdt_status(nullptr) == ESP_OK ||
                   esp_task_wdt_add(nullptr) == ESP_OK);
  if (!watchdogReady) {
    relayController.inhibit(millis(), "watchdog_unavailable");
    syncRelayCommands();
  }
  Wire.begin(planter::kLegacyI2cSdaPin, planter::kLegacyI2cSclPin);
  lcd.init();
  lcd.backlight();
  lcdLine(0, "Smart Planter");
  lcdLine(1, "Relay cmd: OFF");
  if (planter::kDhtEnabled) climateSensor.begin();
  analogReadResolution(12);
  // ADC characterization estimates GPIO36 voltage from the averaged sample.
  // It does not establish the module's supply, divider ratio, or electrical safety.
  mqAdcReady = adc1_config_width(ADC_WIDTH_BIT_12) == ESP_OK &&
               adc1_config_channel_atten(ADC1_CHANNEL_0, ADC_ATTEN_DB_12) == ESP_OK;
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
  pinMode(extra_sensors::kWaterLevelPin, INPUT);
  pinMode(extra_sensors::kMq135DigitalPin, INPUT);
  ArduinoSoilGpio soilGpio;
  planter::configureSoilPower(soilGpio, planter::kSoilPowerWiringVerified);
  startLocalWifi();

  Serial.printf(
      "{\"type\":\"startup\",\"mode\":\"single\",\"version\":%u,"
      "\"relay_control\":\"automatic_requested\",\"soil_power\":\"%s\","
      "\"soil_adc\":\"%s\",\"dht\":\"%s\",\"water\":\"%s\",\"mq135\":\"%s\","
      "\"control_preview\":\"diagnostic_only\",\"watchdog\":\"%s\","
      "\"pump_polarity\":\"active_low_assumed\","
      "\"light_polarity\":\"active_high_assumed\","
      "\"light_automation\":\"%s\",\"annotations\":\"operator_reported\","
      "\"wifi\":\"%s\",\"cloud\":\"disabled\"}\n",
      planter::kFirmwareVersion,
      planter::kSoilPowerWiringVerified ? "gpio25_switched_verified_by_operator"
                                       : "gpio25_input_unverified",
      planter::kSoilAdcReadEnabled ? "enabled_unverified" : "not_configured",
      planter::kDhtEnabled ? "DHT11_assumed" : "not_configured",
      "enabled_unverified", "enabled_unverified",
      watchdogReady ? "subscribed_unverified" : "unavailable",
      planter::kLightAutomationEnabled ? "enabled" : "inhibited",
      localWifiReady ? "local_ap_requested" : "local_ap_unavailable");
}

void loop() {
  const uint32_t nowMs = millis();
  if (watchdogReady && esp_task_wdt_reset() != ESP_OK) {
    watchdogReady = false;
    relayController.inhibit(nowMs, "watchdog_unavailable");
  }
  relayController.tick(nowMs);
  syncRelayCommands();
  pollLocalWifi();
  readObservationCommands();
  if (!hasSample ||
      planter::sampleDue(nowMs, lastSampleMs, planter::kSampleIntervalMs)) {
    hasSample = true;
    lastSampleMs = nowMs;
    printSample(nowMs);
  }
  delay(10);
}
