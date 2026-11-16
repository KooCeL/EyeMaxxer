// =============================================================================
//  EyeMaxxer - configuration
//  Pin map, sensor settings and Eye Strain Risk Score (ESRS) constants.
//
//  Target board: Arduino Nano (as used at the make-a-thon) or Arduino Uno -
//  both are ATmega328P boards with the same pin names.
//
//  The ESRS constants are identical to the team's MATLAB scenario script
//  (matlab/eye_strain_sim.m) and the ESRS_Update MATLAB Function block in the
//  Simulink model (simulink/simulink_eyestrain.slx). Keep them in sync with
//  matlab/esrsParams.m.
// =============================================================================
#pragma once

// ----------------------------------------------------------------------------
//  Pin map
// ----------------------------------------------------------------------------
#define PIN_US_TRIG      9    // HC-SR04 TRIG
#define PIN_US_ECHO      10   // HC-SR04 ECHO
#define PIN_DHT          2    // DHT11 data line
#define PIN_MIC          A0   // Microphone module analog out (AO)

#define PIN_LED_GREEN    3    // ON while ESRS == 0 (fully rested)
#define PIN_LED_AMBER    5    // BLINKS while distance < 30 cm (immediate alert)
#define PIN_LED_RED      6    // BLINKS while ESRS >= 70 (accumulated strain alert)

// ----------------------------------------------------------------------------
//  Sensors
// ----------------------------------------------------------------------------
#define DHT_TYPE         DHT11
#define SERIAL_BAUD      9600

#define US_TIMEOUT_US    25000UL // ~4 m max range; no echo => treated as "away"
#define US_MEDIAN_N      5       // rolling median window for distance samples
#define NO_ECHO_CM       400.0f  // distance reported when there is no echo

#define MIC_WINDOW_MS    20      // peak-to-peak sampling window per tick
#define MIC_FULL_SCALE   512.0f  // peak-to-peak (ADC counts) that maps to noise = 1.0
#define NOISE_EMA_ALPHA  0.15f   // smoothing for the noise level (0..1)

// ----------------------------------------------------------------------------
//  Scheduler (ms)
// ----------------------------------------------------------------------------
#define TICK_MS          100     // sensing + ESRS update period
#define DHT_PERIOD_MS    2000    // DHT11 cannot be read faster than ~1 Hz
#define REPORT_PERIOD_MS 250     // serial telemetry for the MATLAB GUI
#define BLINK_PERIOD_MS  500     // amber / red LED blink period

// ----------------------------------------------------------------------------
//  ESRS - distance zones (cm) and rates (ESRS points per MINUTE)
// ----------------------------------------------------------------------------
#define ZONE_DANGER_CM   30.0f   // d <  30         immediate danger
#define ZONE_FAST_CM     40.0f   // 30 <= d <  40   fast strain
#define ZONE_MODERATE_CM 60.0f   // 40 <= d <  60   moderate strain
#define ZONE_MILD_CM     100.0f  // 60 <= d <= 100  mild strain;  d > 100 recovery

#define RATE_UNDER_30    15.0f
#define RATE_30_40       4.5f
#define RATE_40_60       2.0f
#define RATE_60_100      0.1f
#define RATE_OVER_100   -6.0f    // negative = eyes recover while you are away

// ----------------------------------------------------------------------------
//  ESRS - environmental multipliers (only applied when closer than 60 cm)
// ----------------------------------------------------------------------------
#define DRY_HUMIDITY_PCT 40.0f   // humidity below this is "dry"
#define DRY_MULT         1.30f
#define HIGH_NOISE_LEVEL 0.6f    // normalised noise (0..1) at/above this is "noisy"
#define NOISE_MULT       1.20f
#define MULT_MAX_CM      60.0f

// ----------------------------------------------------------------------------
//  ESRS - limits and alert threshold
// ----------------------------------------------------------------------------
#define ESRS_MIN         0.0f
#define ESRS_MAX         100.0f
#define ESRS_RED         70.0f   // red LED threshold
