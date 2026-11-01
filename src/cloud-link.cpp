// HTTPS device transport. This file is compiled only for the ESP32 firmware.
#include "cloud-link.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <LittleFS.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <esp_system.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include "planter-config.h"

namespace planter {
namespace {

constexpr uint32_t kMaxBufferedBatches = 720;
constexpr size_t kCommandQueueLength = 8;
constexpr size_t kAckQueueLength = 8;
constexpr size_t kSampleQueueLength = 64;
constexpr uint32_t kRegisterIntervalMs = 300000;
constexpr uint32_t kCommandPollIntervalMs = 5000;
constexpr uint32_t kReconnectIntervalMs = 15000;
constexpr uint32_t kMaxBackoffMs = 60000;

const char kRootCa[] PROGMEM = R"PEM(-----BEGIN CERTIFICATE-----
MIICCTCCAY6gAwIBAgINAgPlwGjvYxqccpBQUjAKBggqhkjOPQQDAzBHMQswCQYD
VQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEUMBIG
A1UEAxMLR1RTIFJvb3QgUjQwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAwMDAw
WjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2Vz
IExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjQwdjAQBgcqhkjOPQIBBgUrgQQAIgNi
AATzdHOnaItgrkO4NcWBMHtLSZ37wWHO5t5GvWvVYRg1rkDdc/eJkTBa6zzuhXyi
QHY7qca4R9gq55KRanPpsXI5nymfopjTX15YhmUPoYRlBtHci8nHc8iMai/lxKvR
HYqjQjBAMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQW
BBSATNbrdP9JNqPV2Py1PsVq8JQdjDAKBggqhkjOPQQDAwNpADBmAjEA6ED/g94D
9J+uHXqnLrmvT/aDHQ4thQEd0dlq7A/Cr8deVl5c1RxYIigL9zC2L7F8AjEA8GE8
p/SgguMh1YQdc4acLa/KNJvxn7kjNuK8YAOdgLOaVsjh4rsUecrNIdSUtUlD
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----
)PEM";

String hexBootId() {
  const uint32_t value = esp_random();
  char buffer[9];
  snprintf(buffer, sizeof(buffer), "%08lx",
           static_cast<unsigned long>(value));
  return String(buffer);
}

void appendNullableInt(String& out, const char* key, int value) {
  out += ",\"";
  out += key;
  out += "\":";
  if (value < 0) {
    out += "null";
  } else {
    out += value;
  }
}

void appendNullableFloat(String& out, const char* key, float value,
                         bool present) {
  out += ",\"";
  out += key;
  out += "\":";
  if (!present || !isfinite(value)) {
    out += "null";
    return;
  }
  char buffer[16];
  snprintf(buffer, sizeof(buffer), "%.1f", static_cast<double>(value));
  out += buffer;
}

void appendNullableText(String& out, const char* key, const char* value) {
  out += ",\"";
  out += key;
  out += "\":";
  if (value == nullptr || value[0] == '\0') {
    out += "null";
    return;
  }
  out += '"';
  // Firmware reasons are fixed [a-z0-9_] tokens; reject anything else here so
  // a future code path cannot accidentally break the JSON body.
  for (const char* cursor = value; *cursor != '\0'; ++cursor) {
    const char c = *cursor;
    if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) {
      out += '?';
    } else {
      out += c;
    }
  }
  out += '"';
}

bool validUuid(const char* value) {
  if (value == nullptr) return false;
  size_t length = 0;
  while (value[length] != '\0') {
    const char c = value[length];
    const bool hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
                     (c >= 'A' && c <= 'F');
    if (c != '-' && !hex) return false;
    ++length;
  }
  return length == 36 && value[8] == '-' && value[13] == '-' &&
         value[18] == '-' && value[23] == '-';
}

}  // namespace

bool CloudLink::begin(const char* baseUrl, const char* deviceId,
                      const char* token, const char* ssid,
                      const char* password) {
  if (enabled_) return true;
#if !MOSS_CLOUD_ENABLED
  (void)baseUrl;
  (void)deviceId;
  (void)token;
  (void)ssid;
  (void)password;
  setStatus("Cloud disabled in local config.");
  return false;
#else
  if (baseUrl == nullptr || deviceId == nullptr || token == nullptr ||
      ssid == nullptr || password == nullptr || baseUrl[0] == '\0' ||
      deviceId[0] == '\0' || token[0] == '\0' || ssid[0] == '\0') {
    setStatus("Cloud credentials or Wi-Fi not configured.");
    return false;
  }
  baseUrl_ = baseUrl;
  while (baseUrl_.endsWith("/")) baseUrl_.remove(baseUrl_.length() - 1);
  deviceId_ = deviceId;
  token_ = token;
  ssid_ = ssid;
  password_ = password;
  bootId_ = hexBootId();

  if (!LittleFS.begin(true)) {
    setStatus("LittleFS unavailable; offline buffer disabled.");
    return false;
  }
  LittleFS.mkdir("/q");
  buffered_ = countBufferedBatches();
  nextFileSequence_ = buffered_ == 0 ? 1 : buffered_ + 1;
  sampleQueue_ = xQueueCreate(kSampleQueueLength, sizeof(CloudSample));
  commandQueue_ = xQueueCreate(kCommandQueueLength, sizeof(CloudCommand));
  ackQueue_ = xQueueCreate(kAckQueueLength, sizeof(Ack));
  if (sampleQueue_ == nullptr || commandQueue_ == nullptr ||
      ackQueue_ == nullptr) {
    setStatus("Cloud queues could not be allocated.");
    return false;
  }
  loadSeen();
  enabled_ = true;
  if (xTaskCreatePinnedToCore(taskEntry, "moss-cloud", 16384, this, 1, &task_,
                              0) != pdPASS) {
    enabled_ = false;
    task_ = nullptr;
    setStatus("Cloud task could not start.");
    return false;
  }
  setStatus("Cloud task started; waiting for Wi-Fi.");
  WiFi.setAutoReconnect(true);
  return true;
#endif
}

void CloudLink::poll() {
  if (!enabled_) return;
  ensureStationConnection();
  static bool timeConfigured = false;
  if (!timeConfigured && WiFi.status() == WL_CONNECTED) {
    // UTC only. The server timestamp remains canonical; NTP merely preserves
    // the actual capture time while a batch waits for upload.
    configTime(0, 0, "pool.ntp.org", "time.google.com");
    timeConfigured = true;
  }
}

void CloudLink::ensureStationConnection() {
  if (WiFi.status() == WL_CONNECTED) return;
  const uint32_t now = millis();
  if (lastReconnectMs_ != 0 && now - lastReconnectMs_ < kReconnectIntervalMs) {
    return;
  }
  lastReconnectMs_ = now;
  WiFi.begin(ssid_.c_str(), password_.c_str());
}

bool CloudLink::staConnected() const {
  return WiFi.status() == WL_CONNECTED;
}

void CloudLink::taskEntry(void* argument) {
  static_cast<CloudLink*>(argument)->run();
  vTaskDelete(nullptr);
}

void CloudLink::run() {
  CloudSample batch[6];
  size_t batchCount = 0;
  uint32_t batchStartedMs = 0;

  while (true) {
    const bool wifiUp = WiFi.status() == WL_CONNECTED;
    const bool timeUp = wifiUp && time(nullptr) >= 1700000000;
    static uint32_t lastHeartbeatMs = 0;
    if (millis() - lastHeartbeatMs >= 60000) {
      lastHeartbeatMs = millis();
      Serial.printf(
          "{\"type\":\"cloud\",\"event\":\"heartbeat\",\"wifi\":%s,"
          "\"ntp\":%s,\"online\":%s,\"buffered\":%lu,\"dropped\":%lu,"
          "\"rssi\":%d,\"free_heap\":%lu}\n",
          wifiUp ? "true" : "false", timeUp ? "true" : "false",
          online_ ? "true" : "false",
          static_cast<unsigned long>(buffered_),
          static_cast<unsigned long>(dropped_), WiFi.RSSI(),
          static_cast<unsigned long>(ESP.getFreeHeap()));
    }
    if (!wifiUp) {
      online_ = false;
      setStatus("Wi-Fi STA disconnected; samples are buffered.");
    } else if (!timeUp) {
      online_ = false;
      setStatus("Waiting for NTP; samples are buffered.");
    }

    if (wifiUp && timeUp) {
      const uint32_t now = millis();
      if (!online_ || lastRegisterMs_ == 0 ||
          now - lastRegisterMs_ >= kRegisterIntervalMs) {
        if (!registerDevice()) {
          online_ = false;
          setStatus("Cloud registration failed; samples stay buffered.");
          vTaskDelay(pdMS_TO_TICKS(5000));
        } else {
          lastRegisterMs_ = now;
          backoffMs_ = 0;
          retryAtMs_ = 0;
        }
      }
      if (online_) {
        if (lastCommandPollMs_ == 0 ||
            millis() - lastCommandPollMs_ >= kCommandPollIntervalMs) {
          pollCommands();
          lastCommandPollMs_ = millis();
        }
        processAckQueue();
        if (buffered_ > 0 &&
            (backoffMs_ == 0 ||
             static_cast<int32_t>(millis() - retryAtMs_) >= 0)) {
          drainOldestBatch();
        }
      }
    }

    // Network state must never stop local sampling. Even while offline or
    // waiting for NTP, samples are packed and persisted to LittleFS.
    CloudSample sample;
    if (xQueueReceive(sampleQueue_, &sample,
                      pdMS_TO_TICKS(online_ ? 200 : 800)) == pdTRUE) {
      if (batchCount == 0) batchStartedMs = millis();
      batch[batchCount++] = sample;
    }
    const uint32_t flushAfterMs = online_ ? 8000 : 30000;
    if (batchCount >= 6 ||
        (batchCount > 0 && millis() - batchStartedMs >= flushAfterMs)) {
      flushBatch(batch, batchCount);
      batchCount = 0;
    }
  }
}

bool CloudLink::registerDevice() {
  char body[48];
  snprintf(body, sizeof(body), "{\"firmware_version\":%u}",
           kFirmwareVersion);
  const int result = postJson("register", String(body), false);
  if (result != 1) {
    if (result == -1) setStatus("Cloud rejected device registration.");
    return false;
  }
  setStatus("Cloud online; device registered.");
  online_ = true;
  return true;
}

void CloudLink::pollCommands() {
  String response;
  const int result = getJson("commands", response);
  if (result == -1) {
    setStatus("Cloud rejected command polling.");
    return;
  }
  if (result != 1) return;

  JsonDocument document;
  const DeserializationError error = deserializeJson(document, response);
  if (error) {
    logEvent("cloud_commands_invalid", error.c_str());
    return;
  }
  JsonArray commands = document["commands"].as<JsonArray>();
  for (JsonObject item : commands) {
    const char* id = item["id"] | "";
    const char* actuator = item["actuator"] | "";
    const char* action = item["action"] | "";
    const uint32_t expiresInMs = item["expires_in_ms"] | 0U;
    const uint32_t duration = item["duration_seconds"] | 0U;
    if (!validUuid(id) ||
        (strcmp(actuator, "pump") != 0 && strcmp(actuator, "light") != 0) ||
        (strcmp(action, "on") != 0 && strcmp(action, "off") != 0 &&
         strcmp(action, "auto") != 0)) {
      logEvent("cloud_command_rejected", "invalid_shape");
      continue;
    }
    if (strcmp(action, "on") == 0 &&
        (duration < 1 || duration > (strcmp(actuator, "pump") == 0 ? 30U : 1800U))) {
      logEvent("cloud_command_rejected", "invalid_duration");
      continue;
    }

    CloudCommand command;
    command.valid = true;
    snprintf(command.id, sizeof(command.id), "%s", id);
    snprintf(command.actuator, sizeof(command.actuator), "%s", actuator);
    snprintf(command.action, sizeof(command.action), "%s", action);
    command.durationSeconds = static_cast<uint16_t>(duration);
    command.expiresInMs = expiresInMs;

    if (seenBefore(command.id)) {
      // The execution may have completed before an ACK was lost. A duplicate
      // delivery is acknowledged without touching the relay again.
      CloudCommand duplicate;
      snprintf(duplicate.id, sizeof(duplicate.id), "%s", command.id);
      enqueueAck(duplicate, true, "duplicate_suppressed");
      continue;
    }
    if (expiresInMs < 1500) {
      CloudCommand expired;
      snprintf(expired.id, sizeof(expired.id), "%s", command.id);
      enqueueAck(expired, false, "expired_before_execution");
      continue;
    }
    if (xQueueSend(commandQueue_, &command, 0) != pdTRUE) {
      logEvent("cloud_command_queue_full", command.id);
      continue;
    }
    remember(command.id);
  }
}

void CloudLink::processAckQueue() {
  if (ackQueue_ == nullptr || uxQueueMessagesWaiting(ackQueue_) == 0) return;
  if (backoffMs_ != 0 && static_cast<int32_t>(millis() - retryAtMs_) < 0) return;
  Ack ack;
  if (xQueuePeek(ackQueue_, &ack, 0) != pdTRUE) return;
  char body[220];
  if (ack.ok) {
    snprintf(body, sizeof(body),
             "{\"command_id\":\"%s\",\"ok\":true,\"error_code\":null,"
             "\"result\":{\"delivery\":\"acknowledged\"}}",
             ack.id);
  } else {
    snprintf(body, sizeof(body),
             "{\"command_id\":\"%s\",\"ok\":false,\"error_code\":\"%s\"}",
             ack.id, ack.error[0] == '\0' ? "device_rejected" : ack.error);
  }
  const int result = postJson("ack", String(body), false);
  if (result == 1 || result == -1) {
    xQueueReceive(ackQueue_, &ack, 0);
    return;
  }
  ++ack.attempts;
  if (ack.attempts >= 3) {
    xQueueReceive(ackQueue_, &ack, 0);
    logEvent("cloud_ack_dropped", ack.id);
    return;
  }
  // Preserve the retry count without blocking the poll loop.
  xQueueReceive(ackQueue_, &ack, 0);
  xQueueSend(ackQueue_, &ack, 0);
}

int CloudLink::postJson(const char* action, const String& body, bool replay) {
  if (WiFi.status() != WL_CONNECTED || token_.isEmpty()) return 0;
  WiFiClientSecure client;
  client.setCACert(kRootCa);
  client.setTimeout(8);
  HTTPClient http;
  http.setConnectTimeout(6000);
  http.setTimeout(9000);
  http.setReuse(false);
  const String url = endpoint(action);
  if (!http.begin(client, url)) {
    logEvent("cloud_http_begin_failed", action);
    return 0;
  }
  http.addHeader("Content-Type", "application/json");
  http.addHeader("x-device-id", deviceId_);
  http.addHeader("x-device-token", token_);
  if (replay) http.addHeader("x-moss-replay", "1");
  const int code = http.POST(
      reinterpret_cast<uint8_t*>(const_cast<char*>(body.c_str())),
      body.length());
  http.end();
  if (code >= 200 && code < 300) {
    backoffMs_ = 0;
    retryAtMs_ = 0;
    online_ = true;
    return 1;
  }
  if (code == 400 || code == 413 || code == 422) {
    char detail[24];
    snprintf(detail, sizeof(detail), "http_%d", code);
    logEvent("cloud_permanent_http_error", detail);
    return -1;
  }
  if (code == 401 || code == 403) {
    setStatus("Cloud authentication failed.");
  } else {
    char detail[24];
    snprintf(detail, sizeof(detail), "http_%d", code);
    logEvent("cloud_transient_error", detail);
  }
  return 0;
}

int CloudLink::getJson(const char* action, String& response) {
  if (WiFi.status() != WL_CONNECTED || token_.isEmpty()) return 0;
  WiFiClientSecure client;
  client.setCACert(kRootCa);
  client.setTimeout(8);
  HTTPClient http;
  http.setConnectTimeout(6000);
  http.setTimeout(9000);
  http.setReuse(false);
  if (!http.begin(client, endpoint(action))) return 0;
  http.addHeader("x-device-id", deviceId_);
  http.addHeader("x-device-token", token_);
  const int code = http.GET();
  if (code >= 200 && code < 300) response = http.getString();
  http.end();
  if (code >= 200 && code < 300) {
    online_ = true;
    return 1;
  }
  if (code == 401 || code == 403) setStatus("Cloud authentication failed.");
  return code == 404 ? -1 : 0;
}

String CloudLink::endpoint(const char* action) const {
  String url = baseUrl_;
  url += "/functions/v1/device-api?action=";
  url += action;
  return url;
}

String CloudLink::buildBatchBody(const CloudSample* batch, size_t count) const {
  String body;
  body.reserve(7000);
  body += F("{\"schema\":1,\"firmware_version\":");
  body += kFirmwareVersion;
  body += F(",\"boot_id\":\"");
  body += bootId_;
  body += F("\",\"samples\":[");
  for (size_t index = 0; index < count; ++index) {
    const CloudSample& sample = batch[index];
    if (index != 0) body += ',';
    body += F("{\"uptime_ms\":");
    body += sample.uptimeMs;
    appendNullableText(body, "captured_at",
                       sample.capturedAtValid ? sample.capturedAt : nullptr);
    body += F(",\"time_quality\":\"");
    body += sample.capturedAtValid ? F("ntp") : F("uptime_only");
    body += '"';
    appendNullableInt(body, "soil_adc", sample.soilAdc);
    appendNullableInt(body, "soil_percent", sample.soilPercent);
    appendNullableInt(body, "water_adc", sample.waterAdc);
    appendNullableInt(body, "water_percent", sample.waterPercent);
    appendNullableInt(body, "water_observation_percent",
                      sample.waterObservationPercent);
    body += F(",\"water_empty\":");
    body += sample.waterAdc >= 0 ? (sample.waterEmpty ? F("true") : F("false"))
                                 : F("null");
    body += F(",\"water_low\":");
    body += sample.waterAdc >= 0 ? (sample.waterLow ? F("true") : F("false"))
                                 : F("null");
    appendNullableInt(body, "light_adc", sample.lightAdc);
    appendNullableInt(body, "light_percent", sample.lightPercent);
    appendNullableFloat(body, "temperature_c", sample.temperatureC,
                        sample.hasTemperature);
    appendNullableInt(body, "humidity_percent", sample.humidityPercent);
    appendNullableInt(body, "uv_adc", sample.uvAdc);
    appendNullableFloat(body, "uv_index",
                        sample.uvIndexX10 >= 0 ? sample.uvIndexX10 / 10.0f : 0,
                        sample.uvIndexX10 >= 0);
    appendNullableInt(body, "mq_adc", sample.mqAdc);
    appendNullableInt(body, "mq_pin_mv", sample.mqPinMv);
    body += F(",\"pump_cmd\":");
    body += sample.pumpOn ? F("true") : F("false");
    appendNullableText(body, "pump_reason", sample.pumpReason);
    body += F(",\"pump_cooldown_s\":");
    body += sample.pumpCooldownS;
    body += F(",\"pump_runtime_lockout\":");
    body += sample.pumpRuntimeLockout ? F("true") : F("false");
    body += F(",\"light_cmd\":");
    body += sample.lightOn ? F("true") : F("false");
    appendNullableText(body, "light_reason", sample.lightReason);
    body += '}';
  }
  body += F("]}");
  return body;
}

bool CloudLink::persistBatch(const String& body, String& path) {
  if (!LittleFS.exists("/q")) LittleFS.mkdir("/q");
  path = nextBatchPath();
  File file = LittleFS.open(path, "w");
  if (!file) {
    logEvent("cloud_buffer_open_failed", path.c_str());
    return false;
  }
  const size_t written = file.print(body);
  file.close();
  if (written != body.length()) {
    LittleFS.remove(path);
    logEvent("cloud_buffer_write_failed", path.c_str());
    return false;
  }
  ++buffered_;
  if (buffered_ > kMaxBufferedBatches) {
    const String oldest = oldestBatchPath();
    if (oldest.length() > 0 && oldest != path && LittleFS.remove(oldest)) {
      --buffered_;
      dropped_ += 6;
      logEvent("cloud_buffer_evicted", oldest.c_str());
    }
  }
  return true;
}

String CloudLink::nextBatchPath() {
  while (true) {
    char path[32];
    snprintf(path, sizeof(path), "/q/%08lu.json",
             static_cast<unsigned long>(nextFileSequence_++));
    if (!LittleFS.exists(path)) return String(path);
  }
}

String CloudLink::oldestBatchPath() const {
  File directory = LittleFS.open("/q");
  if (!directory || !directory.isDirectory()) return String();
  String oldest;
  File entry = directory.openNextFile();
  while (entry) {
    if (!entry.isDirectory()) {
      const String name = entry.name();
      if (name.endsWith(".json") && (oldest.isEmpty() || name < oldest)) {
        oldest = name;
      }
    }
    entry = directory.openNextFile();
  }
  directory.close();
  if (oldest.isEmpty()) return String();
  if (!oldest.startsWith("/q/")) return "/q/" + oldest;
  return oldest;
}

uint32_t CloudLink::countBufferedBatches() const {
  File directory = LittleFS.open("/q");
  if (!directory || !directory.isDirectory()) return 0;
  uint32_t count = 0;
  File entry = directory.openNextFile();
  while (entry) {
    if (!entry.isDirectory()) {
      const String name = entry.name();
      if (name.endsWith(".json")) ++count;
    }
    entry = directory.openNextFile();
  }
  directory.close();
  return count;
}

bool CloudLink::uploadFile(const String& path, bool replay) {
  File file = LittleFS.open(path, "r");
  if (!file) return false;
  const String body = file.readString();
  file.close();
  if (body.isEmpty()) {
    LittleFS.remove(path);
    if (buffered_ > 0) --buffered_;
    return true;
  }
  const int result = postJson("ingest", body, replay);
  if (result == 1) {
    if (LittleFS.remove(path) && buffered_ > 0) --buffered_;
    setStatus("Cloud online; telemetry uploaded.");
    return true;
  }
  if (result == -1) {
    if (LittleFS.remove(path) && buffered_ > 0) --buffered_;
    dropped_ += 6;
    setStatus("Cloud rejected one batch; batch discarded.");
    return true;
  }
  backoffMs_ = backoffMs_ == 0
                   ? 5000
                   : (backoffMs_ * 2 > kMaxBackoffMs ? kMaxBackoffMs
                                                      : backoffMs_ * 2);
  retryAtMs_ = millis() + backoffMs_;
  setStatus("Cloud upload failed; retry is scheduled.");
  return false;
}

void CloudLink::drainOldestBatch() {
  const String path = oldestBatchPath();
  if (path.isEmpty()) return;
  uploadFile(path, true);
}

void CloudLink::flushBatch(CloudSample* batch, size_t count) {
  if (count == 0) return;
  const String body = buildBatchBody(batch, count);
  const bool hadBacklog = buffered_ > 0;
  String path;
  if (persistBatch(body, path)) {
    if (online_ && !hadBacklog) {
      uploadFile(path, false);
    } else if (!online_) {
      setStatus("Telemetry buffered; waiting for cloud.");
    }
    return;
  }
  if (!online_) {
    dropped_ += count;
    setStatus("Offline and no LittleFS buffer; sample dropped.");
    return;
  }
  // If LittleFS is unavailable, still try one direct upload. A failure is
  // counted but cannot be replayed after reset.
  const int result = postJson("ingest", body, false);
  if (result == 1) {
    setStatus("Cloud online; telemetry uploaded without buffer.");
  } else {
    dropped_ += count;
    setStatus("Cloud upload failed; no buffer available.");
  }
}

bool CloudLink::enqueueSample(const CloudSample& sample) {
  if (!enabled_ || sampleQueue_ == nullptr) return false;
  if (xQueueSend(sampleQueue_, &sample, 0) != pdTRUE) {
    ++dropped_;
    return false;
  }
  return true;
}

bool CloudLink::takeCommand(CloudCommand& command) {
  if (!enabled_ || commandQueue_ == nullptr) return false;
  return xQueueReceive(commandQueue_, &command, 0) == pdTRUE;
}

void CloudLink::enqueueAck(const CloudCommand& command, bool ok,
                           const char* error) {
  if (!enabled_ || ackQueue_ == nullptr || command.id[0] == '\0') return;
  Ack ack;
  snprintf(ack.id, sizeof(ack.id), "%s", command.id);
  ack.ok = ok;
  if (error != nullptr) snprintf(ack.error, sizeof(ack.error), "%s", error);
  if (xQueueSend(ackQueue_, &ack, 0) != pdTRUE) {
    logEvent("cloud_ack_queue_full", ack.id);
  }
}

void CloudLink::loadSeen() {
  Preferences preferences;
  if (!preferences.begin("moss_cmd", true)) return;
  const String stored = preferences.getString("seen", "");
  preferences.end();
  seenNext_ = 0;
  seenCount_ = 0;
  int start = 0;
  while (start < static_cast<int>(stored.length()) && seenCount_ < 12) {
    const int comma = stored.indexOf(',', start);
    const int end = comma < 0 ? stored.length() : comma;
    if (end - start == 36) {
      snprintf(seen_[seenNext_], sizeof(seen_[seenNext_]), "%s",
               stored.substring(start, end).c_str());
      ++seenNext_;
      ++seenCount_;
    }
    if (comma < 0) break;
    start = comma + 1;
  }
}

void CloudLink::saveSeen() {
  Preferences preferences;
  if (!preferences.begin("moss_cmd", false)) return;
  String stored;
  for (uint8_t index = 0; index < seenCount_; ++index) {
    if (index != 0) stored += ',';
    stored += seen_[index];
  }
  preferences.putString("seen", stored);
  preferences.end();
}

bool CloudLink::seenBefore(const char* id) const {
  for (uint8_t index = 0; index < seenCount_; ++index) {
    if (strcmp(seen_[index], id) == 0) return true;
  }
  return false;
}

void CloudLink::remember(const char* id) {
  snprintf(seen_[seenNext_], sizeof(seen_[seenNext_]), "%s", id);
  seenNext_ = (seenNext_ + 1) % 12;
  if (seenCount_ < 12) ++seenCount_;
  saveSeen();
}

void CloudLink::setStatus(const char* message) {
  snprintf(status_, sizeof(status_), "%s", message == nullptr ? "" : message);
}

void CloudLink::logEvent(const char* event, const char* detail) {
  Serial.printf("{\"type\":\"cloud\",\"event\":\"%s\",\"detail\":\"%s\","
                "\"buffered\":%lu,\"dropped\":%lu}\n",
                event == nullptr ? "unknown" : event,
                detail == nullptr ? "" : detail,
                static_cast<unsigned long>(buffered_),
                static_cast<unsigned long>(dropped_));
}

bool CloudLink::currentUtcIso(char* output, size_t capacity) {
  if (output == nullptr || capacity < 21) return false;
  const time_t now = time(nullptr);
  // Reject the ESP32 epoch and obviously pre-deployment clocks.
  if (now < 1700000000) return false;
  struct tm utc = {};
  if (gmtime_r(&now, &utc) == nullptr) return false;
  return strftime(output, capacity, "%Y-%m-%dT%H:%M:%SZ", &utc) > 0;
}

}  // namespace planter
