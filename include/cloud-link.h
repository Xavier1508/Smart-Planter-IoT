#pragma once

#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/task.h>

namespace planter {

// A deliberately flat sample that can cross a FreeRTOS queue without owning
// heap memory. Negative integers and NaN mean "sensor not available".
struct CloudSample {
  uint32_t uptimeMs = 0;
  int16_t soilAdc = -1;
  int16_t waterAdc = -1;
  int16_t lightAdc = -1;
  int16_t uvAdc = -1;
  int16_t mqAdc = -1;
  int16_t mqPinMv = -1;
  int16_t soilPercent = -1;
  int16_t waterPercent = -1;
  int16_t waterObservationPercent = -1;
  int16_t lightPercent = -1;
  float temperatureC = NAN;
  int16_t humidityPercent = -1;
  int16_t uvIndexX10 = -1;
  bool hasTemperature = false;
  bool waterEmpty = false;
  bool waterLow = false;
  bool pumpOn = false;
  bool pumpRuntimeLockout = false;
  bool lightOn = false;
  uint32_t pumpCooldownS = 0;
  bool capturedAtValid = false;
  char capturedAt[24] = {};
  char pumpReason[40] = {};
  char lightReason[40] = {};
};

struct CloudCommand {
  bool valid = false;
  char id[37] = {};
  char actuator[8] = {};
  char action[8] = {};
  uint16_t durationSeconds = 0;
  uint32_t expiresInMs = 0;
};

/// HTTPS uploader and command poller. All network work runs in a dedicated
/// task so a slow TLS handshake can never delay relay timers or the watchdog.
class CloudLink {
 public:
  bool begin(const char* baseUrl, const char* deviceId, const char* token,
             const char* ssid, const char* password);
  void poll();

  bool enabled() const { return enabled_; }
  bool staConnected() const;
  bool cloudOnline() const { return online_; }
  const char* statusText() const { return status_; }
  bool storageReady() const { return storageReady_; }
  uint32_t bufferedBatches() const { return buffered_; }
  uint32_t droppedSamples() const { return dropped_; }
  const char* hardwareId() const { return deviceId_.c_str(); }

  /// Called once per sample from the main loop. This copies the struct into a
  /// bounded queue and returns immediately.
  bool enqueueSample(const CloudSample& sample);

  /// Non-blocking command handoff to the main loop.
  bool takeCommand(CloudCommand& command);

  /// Queue an acknowledgement. Safe to call from the main loop.
  void enqueueAck(const CloudCommand& command, bool ok, const char* error);

  /// Fills an ISO-8601 UTC timestamp only after NTP has produced a plausible
  /// clock. The caller must send time_quality=uptime_only otherwise.
  static bool currentUtcIso(char* output, size_t capacity);

 private:
  struct Ack {
    char id[37] = {};
    bool ok = false;
    char error[40] = {};
    uint8_t attempts = 0;
  };

  static void taskEntry(void* argument);
  void run();
  void ensureStationConnection();
  bool registerDevice();
  void pollCommands();
  void processAckQueue();
  int postJson(const char* action, const String& body, bool replay);
  int getJson(const char* action, String& response);
  bool uploadBody(const String& body, bool replay);
  bool uploadFile(const String& path, bool replay);
  bool persistBatch(const String& body, String& path);
  void flushBatch(CloudSample* batch, size_t count);
  void drainOldestBatch();
  String buildBatchBody(const CloudSample* batch, size_t count) const;
  String oldestBatchPath() const;
  String nextBatchPath();
  uint32_t countBufferedBatches() const;
  String endpoint(const char* action) const;
  bool seenBefore(const char* id) const;
  void remember(const char* id);
  void loadSeen();
  void saveSeen();
  void setStatus(const char* message);
  void logEvent(const char* event, const char* detail);

  String baseUrl_;
  String deviceId_;
  String token_;
  String ssid_;
  String password_;
  String bootId_;
  QueueHandle_t sampleQueue_ = nullptr;
  QueueHandle_t commandQueue_ = nullptr;
  QueueHandle_t ackQueue_ = nullptr;
  TaskHandle_t task_ = nullptr;
  volatile bool enabled_ = false;
  volatile bool online_ = false;
  bool storageReady_ = false;
  volatile uint32_t buffered_ = 0;
  volatile uint32_t dropped_ = 0;
  uint32_t lastReconnectMs_ = 0;
  uint32_t lastRegisterMs_ = 0;
  uint32_t lastCommandPollMs_ = 0;
  uint32_t backoffMs_ = 0;
  uint32_t retryAtMs_ = 0;
  uint32_t nextFileSequence_ = 1;
  uint8_t seenNext_ = 0;
  uint8_t seenCount_ = 0;
  char seen_[12][37] = {};
  char status_[96] = "Cloud belum aktif.";
};

}  // namespace planter
