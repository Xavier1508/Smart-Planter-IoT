#pragma once

// Device-specific relative references, not laboratory calibration.
#define MOSS_DISPLAY_CALIBRATION_OBSERVED 1
// Dry was observed at 0 ADC and immersed at 1800 ADC.
// A disconnected probe can also read 0, so check the wiring before use.
#define MOSS_SOIL_RELATIVE_ZERO_ADC 0
#define MOSS_SOIL_RELATIVE_FULL_ADC 1800
#define MOSS_SOIL_ZERO_IS_DRY 1
// LDR: 0 ADC is bright and 2100 ADC is dark.
#define MOSS_LIGHT_RELATIVE_DARK_ADC 2100
#define MOSS_LIGHT_RELATIVE_BRIGHT_ADC 0
// Water references are relative and do not measure tank volume.
#define MOSS_WATER_LOW_REFERENCE_ADC 950
#define MOSS_WATER_NEAR_REFERENCE_ADC 1100
#define MOSS_WATER_OBSERVED_LOW_ADC 450
#define MOSS_WATER_OBSERVED_NEAR_FULL_ADC 1500
#define MOSS_WATER_FULL_REFERENCE_ADC 1500
