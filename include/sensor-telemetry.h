#pragma once

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>

#include "planter-config.h"
#include "observation-label.h"
#include "relay-safety.h"

namespace planter {

enum class AdcCalibrationMethod { unavailable, efuse_two_point, efuse_vref, default_vref };

inline const char* adcCalibrationName(AdcCalibrationMethod method) {
  switch (method) {
    case AdcCalibrationMethod::efuse_two_point: return "efuse_two_point";
    case AdcCalibrationMethod::efuse_vref: return "efuse_vref";
    case AdcCalibrationMethod::default_vref: return "default_vref_estimate";
    default: return "unavailable";
  }
}

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
  int mqAdcPinMillivolts;
  AdcCalibrationMethod mqAdcCalibration;
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

// Quality labels describe the electrical reading only, never sensor health or
// the environment. A rail can be a real extreme or a fault/disconnection.
inline const char* adcSignalQuality(int raw, bool enabled = true) {
  if (!enabled) return "not_configured";
  if (!validAdcRaw(raw)) return "unavailable";
  if (raw == 0) return "rail_low_unverified";
  if (raw == 4095) return "rail_high_unverified";
  return "in_range_unverified";
}

inline const char* mqSignalQuality(const SensorSnapshot& sample) {
  if (!sample.mqEnabled) return "not_configured";
  if (!sample.mqAdcReadable) return "adc_read_failed";
  return adcSignalQuality(sample.mqAdcRaw);
}

// An operator-provided raw ADC reference, not a calibrated percentage or a
// water-presence guarantee. Rails are ambiguous and remain explicitly unknown.
inline const char* waterRawReferenceBand(int raw) {
  if (!validAdcRaw(raw)) return "unavailable";
  if (raw == 0 || raw == 4095) return "rail_unverified";
  if (raw <= kWaterLowRawReferenceAdc) return "at_or_below_low";
  if (raw < kWaterNearRawReferenceAdc) return "near_low";
  return "above_reference";
}

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

// Display-only interpolation between two operator-reported observation means.
// Zero denotes the reported low level, not an empty tank; neither endpoint is
// verified. This value is deliberately separate from pump control.
inline int observedWaterRelativePercent(const SensorSnapshot& sample) {
  if (!sample.waterEnabled || !controlWaterAdcUsable(sample.waterAdcRaw)) return -1;
  return relativePercent(sample.waterAdcRaw, kWaterObservedLowMeanAdc,
                         kWaterObservedNearFullMeanAdc);
}

// Reported dry and immersed readings define a tentative display scale only.
// A rail is kept as raw ADC but is too ambiguous even for this estimate.
inline int observedSoilRelativePercent(const SensorSnapshot& sample) {
  if (!sample.soilEnabled || !controlAnalogUsable(sample.soilAdcRaw)) return -1;
  return relativePercent(sample.soilAdcRaw, kSoilRelativeZeroAdc,
                         kSoilRelativeFullAdc);
}

// Tri-state results: -1 means unavailable, 0 means false, and 1 means true.
// These are rule previews only and never commands or observed relay states.
inline int belowThresholdPreview(int percent, int threshold) {
  if (percent < 0 || percent > 100 || threshold < 0 || threshold > 100) {
    return -1;
  }
  return percent < threshold ? 1 : 0;
}

struct RulePreview {
  int soilPercent;
  int lightPercent;
  int waterPercent;
  int pumpOn;
  int lightOn;
  int waterLow;
};

// The supplied endpoints define a relative scale, not a physical calibration.
// Invalid or disabled water endpoints leave both the percentage and warning
// unavailable. Callers must not interpret a dry-run result as actuator state.
inline RulePreview previewRules(const SensorSnapshot& sample,
                                bool waterScaleEnabled, int waterEmptyAdc,
                                int waterFullAdc) {
  const int soil = observedSoilRelativePercent(sample);
  const int light = relativePercent(sample.lightAdcRaw, kLightRelativeZeroAdc,
                                    kLightRelativeFullAdc);
  const int water = sample.waterEnabled && waterScaleEnabled
                        ? relativePercent(sample.waterAdcRaw, waterEmptyAdc,
                                          waterFullAdc)
                        : -1;
  return {soil, light, water, belowThresholdPreview(soil, kPumpOnBelowPercent),
          belowThresholdPreview(light, kLegacyLightPreviewBelowPercent),
          belowThresholdPreview(water, kWaterLowBelowPercent)};
}

inline RulePreview previewRules(const SensorSnapshot& sample) {
  return previewRules(sample, kWaterRelativeScaleEnabled, kWaterEmptyAdc,
                      kWaterFullAdc);
}

inline const char* jsonPreviewBoolean(int value) {
  return value == 0 ? "false" : (value == 1 ? "true" : "null");
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
                            size_t capacity,
                            const ControlStatus* control = nullptr,
                            const ObservationLabel* label = nullptr) {
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
  char waterRelative[16];
  char waterObservedRelative[16];
  char waterLevel[640];
  char controlPreview[200];
  char mqRaw[16];
  char mqDigital[8];
  char mqPinMv[16];
  char mq135[480];
  char labelJson[200];
  formatClimateValue(temperature, sizeof(temperature), sample.temperatureC,
                     temperatureValid);
  formatClimateValue(humidity, sizeof(humidity), sample.humidityPercent,
                     humidityValid);
  formatAdcValue(soil, sizeof(soil), sample.soilEnabled ? sample.soilAdcRaw : -1);
  formatAdcValue(light, sizeof(light), sample.lightAdcRaw);
  formatAdcValue(uv, sizeof(uv), sample.uvAdcRaw);
  const RulePreview preview = previewRules(sample);
  formatAdcValue(soilRelative, sizeof(soilRelative), preview.soilPercent);
  formatAdcValue(lightRelative, sizeof(lightRelative), preview.lightPercent);
  formatAdcValue(waterRaw, sizeof(waterRaw), sample.waterAdcRaw);
  formatAdcValue(waterRelative, sizeof(waterRelative), preview.waterPercent);
  formatAdcValue(waterObservedRelative, sizeof(waterObservedRelative),
                 observedWaterRelativePercent(sample));
  if (sample.waterEnabled) {
    std::snprintf(waterLevel, sizeof(waterLevel),
                  "{\"adc_raw\":%s,\"relative_percent\":%s,\"low\":%s,"
                  "\"status\":\"%s\",\"raw_reference\":{\"band\":\"%s\","
                  "\"low_at_or_below\":%d,\"near_below\":%d,"
                  "\"quality\":\"historical_conflicting\"},"
                  "\"signal_quality\":\"%s\","
                  "\"observation_scale\":{\"relative_percent\":%s,"
                  "\"low_mean_adc\":%d,\"near_full_mean_adc\":%d,"
                  "\"basis\":\"%s\","
                  "\"quality\":\"unverified\",\"use_for_control\":false}}",
                  waterRaw, waterRelative,
                  jsonPreviewBoolean(preview.waterLow),
                  validAdcRaw(sample.waterAdcRaw) ? "unverified" : "unavailable",
                  waterRawReferenceBand(sample.waterAdcRaw),
                  kWaterLowRawReferenceAdc, kWaterNearRawReferenceAdc,
                  adcSignalQuality(sample.waterAdcRaw), waterObservedRelative,
                  kWaterObservedLowMeanAdc, kWaterObservedNearFullMeanAdc,
                  kDisplayUsesOperatorReferences ? "operator_reported_window_means"
                                                 : "generic_display_references");
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
            ? "adc_read_failed"
             : (validAdcRaw(sample.mqAdcRaw) ? "unverified" : "unavailable");
    const bool pinMvAvailable = sample.mqAdcReadable &&
                                controlAnalogUsable(sample.mqAdcRaw) &&
                                sample.mqAdcPinMillivolts >= 0 &&
                                sample.mqAdcPinMillivolts <= 3300 &&
                                sample.mqAdcCalibration != AdcCalibrationMethod::unavailable;
    if (pinMvAvailable) {
      std::snprintf(mqPinMv, sizeof(mqPinMv), "%d", sample.mqAdcPinMillivolts);
    } else {
      std::snprintf(mqPinMv, sizeof(mqPinMv), "null");
    }
    std::snprintf(mq135, sizeof(mq135),
                  "{\"adc_raw\":%s,\"digital_raw\":%s,\"adc_status\":\"%s\","
                  "\"status\":\"unverified\",\"signal_quality\":\"%s\","
                  "\"adc_pin_mv_estimate\":%s,\"adc_calibration_source\":\"%s\","
                  "\"calibration\":\"not_calibrated\",\"warmup\":\"unknown\","
                  "\"environment_compensation\":\"not_applied\","
                  "\"co2_ppm\":null,\"air_quality\":null}",
                  mqRaw, mqDigital, adcStatus, mqSignalQuality(sample), mqPinMv,
                  adcCalibrationName(sample.mqAdcCalibration));
  } else {
    std::snprintf(mq135, sizeof(mq135), "null");
  }

  // Labels are drawn only from the allowlisted operator command handler. They
  // are not automatically inferred from ADC values or water reference bands.
  if (label) {
    std::snprintf(labelJson, sizeof(labelJson),
                  "{\"sensor\":\"%s\",\"condition\":\"%s\","
                  "\"source\":\"operator_reported\",\"start_uptime_ms\":%lu,"
                  "\"max_duration_ms\":%lu}", label->sensor, label->condition,
                  static_cast<unsigned long>(label->startedMs),
                  static_cast<unsigned long>(kObservationLabelTtlMs));
  } else {
    std::snprintf(labelJson, sizeof(labelJson), "null");
  }

  // Do not put hypothetical pump_on/growlight_on values beside real commands:
  // a preview may disagree with safety interlocks and be mistaken for state.
  if (control) {
    std::snprintf(controlPreview, sizeof(controlPreview), "null");
  } else {
    std::snprintf(controlPreview, sizeof(controlPreview),
                  "{\"mode\":\"diagnostic_only\",\"basis\":\"relative_unverified\","
                  "\"pump_on\":%s,\"growlight_on\":%s,\"water_low\":%s}",
                  jsonPreviewBoolean(preview.pumpOn),
                  jsonPreviewBoolean(preview.lightOn),
                  jsonPreviewBoolean(preview.waterLow));
  }

  const int written = std::snprintf(
      output, capacity,
      "{\"type\":\"sample\",\"firmware_version\":%u,"
      "\"schema\":\"serial_observation_2\",\"uptime_ms\":%lu,"
      "\"recorded_at_utc\":null,"
      "\"dht\":{\"model\":\"DHT11_assumed\",\"temperature_c\":%s,"
      "\"humidity_percent\":%s,\"status\":\"%s\"},"
      "\"adc\":{\"soil_raw\":%s,\"soil_status\":\"%s\","
      "\"light_raw\":%s,\"uv_raw\":%s,"
      "\"soil_relative_percent\":%s,\"light_relative_percent\":%s,"
      "\"status\":\"unverified\",\"soil_signal_quality\":\"%s\","
      "\"soil_supply_mode\":\"%s\","
       "\"light_signal_quality\":\"%s\",\"uv_signal_quality\":\"%s\","
       "\"soil_calibration\":\"%s\","
       "\"soil_scale_basis\":\"%s\","
       "\"soil_dry_mean_adc\":%d,\"soil_immersed_mean_adc\":%d,"
       "\"light_calibration\":\"historical_unverified\","
       "\"uv_calibration\":\"not_available\"},"
       "\"water_level\":%s,\"mq135\":%s,"
       "\"observation_label\":%s,"
       "\"lighting_rule\":{\"candidate\":\"%s\",\"uv_index\":null,"
       "\"light_on_below_percent\":%d,\"light_off_at_or_above_percent\":%d,"
       "\"uv_off_above_index\":7,\"status\":\"diagnostic_only_unverified\","
       "\"use_for_control\":false},"
       "\"control_preview\":%s,"
      "\"relay_control\":\"%s\",\"pump_cmd\":%s,\"pump_reason\":\"%s\","
      "\"growlight_cmd\":%s,\"growlight_reason\":\"%s\","
      "\"pump_gpio_level_requested\":%s,\"growlight_gpio_level_requested\":%s,"
      "\"pump_state\":null,"
      "\"growlight_state\":null}",
      kFirmwareVersion, static_cast<unsigned long>(sample.uptimeMs), temperature, humidity,
      climateStatus, soil, soilStatus, light, uv, soilRelative, lightRelative,
      adcSignalQuality(sample.soilAdcRaw, sample.soilEnabled),
      kSoilPowerWiringVerified ? "gpio25_switched_operator_configured"
                               : "gpio25_input_supply_unverified",
       adcSignalQuality(sample.lightAdcRaw), adcSignalQuality(sample.uvAdcRaw),
       kPumpSoilScaleConfirmed ? "operator_confirmed" : "not_confirmed",
       kDisplayUsesOperatorReferences ? "reported_dry_and_immersed_means"
                                     : "generic_display_references",
       kSoilRelativeZeroAdc, kSoilRelativeFullAdc,
       waterLevel, mq135, labelJson,
       lightDecisionName(dualSensorLightDecision(
           controlAnalogUsable(sample.lightAdcRaw) ? preview.lightPercent : -1, -1)),
       kLightOnBelowPercent, kLightOffAtOrAbovePercent, controlPreview,
      control ? "automatic_requested" : "inactive_requested",
      control ? jsonPreviewBoolean(control->pumpOn ? 1 : 0) : "null",
      control ? control->pumpReason : "not_available",
      control ? jsonPreviewBoolean(control->lightOn ? 1 : 0) : "null",
      control ? control->lightReason : "not_available",
      !control ? "null" : (relayLevel(kPumpActiveLow, control->pumpOn)
                               ? "\"HIGH\"" : "\"LOW\""),
      !control ? "null" : (relayLevel(kLightActiveLow, control->lightOn)
                               ? "\"HIGH\"" : "\"LOW\""));
  return written >= 0 && static_cast<size_t>(written) < capacity;
}

}  // namespace planter
