// =============================================================================
//  EyeMaxxer - configuration
//  Pin map, sensor settings and Eye Strain Risk Score (ESRS) tuning constants.
//
//  Target board: Arduino Uno (ATmega328P). The same pin map works unchanged on
//  an Arduino Nano, which is what the Simulink model was originally deployed to.
//
//  Keep the ESRS constants in sync with matlab/esrsParams.m so that the MATLAB
//  scenario tests describe exactly what the hardware does.
// =============================================================================
#pragma once

// ----------------------------------------------------------------------------
//  Pin map
// ----------------------------------------------------------------------------
#define PIN_US_TRIG      9    // HC-SR04 TRIG
#define PIN_US_ECHO      10   // HC-SR04 ECHO
#define PIN_DHT          2    // DHT11 / DHT22 data line (10k pull-up to 5V)
#define PIN_MIC          A0   // Analog sound sensor (KY-038 AO / MAX4466 OUT)

#define PIN_LED_GREEN    3    // ESRS: low risk
#define PIN_LED_YELLOW   5    // ESRS: rising risk
#define PIN_LED_RED      6    // ESRS: high risk (take a break) - blinks when overdue
#define PIN_LED_PROX     7    // Immediate danger: sitting closer than DANGER_CM

// ----------------------------------------------------------------------------
//  Sensors
// ----------------------------------------------------------------------------
#define DHT_TYPE         DHT11   // change to DHT22 if you use the white sensor
#define SERIAL_BAUD      115200

#define US_TIMEOUT_US    25000UL // ~4.3 m max range; avoids long blocking pulseIn
#define US_MEDIAN_N      5       // rolling median window for distance samples

#define MIC_WINDOW_MS    20      // peak-to-peak sampling window per tick
#define NOISE_EMA_ALPHA  0.15f   // smoothing for the noise level (0..1)

// ----------------------------------------------------------------------------
//  Scheduler (ms)
// ----------------------------------------------------------------------------
#define TICK_MS          100     // main sensing / ESRS update period (10 Hz)
#define DHT_PERIOD_MS    2000    // DHT11 cannot be read faster than ~1 Hz
#define REPORT_PERIOD_MS 200     // serial telemetry for the MATLAB dashboard (5 Hz)
#define BLINK_PERIOD_MS  400     // red LED blink period when break is overdue

// ----------------------------------------------------------------------------
//  ESRS - distance zones (cm)
//  Recommended viewing distance for a laptop is roughly 50-75 cm (arm's length).
// ----------------------------------------------------------------------------
#define DANGER_CM        30.0f   // closer than this = immediate danger zone
#define CLOSE_CM         50.0f   // 30-50 cm = too close
#define AWAY_CM          120.0f  // further than this (or no echo) = user away
#define AWAY_DEBOUNCE_S  2.0f    // must be "away" this long before recovery starts

// ----------------------------------------------------------------------------
//  ESRS - base increments (score points per second) and recovery
//  Score runs from 0 to 100. With these values, reaching the red threshold
//  (70) takes ~23 min at a healthy distance (cf. the 20-20-20 rule),
//  ~10 min when too close and ~3 min in the danger zone. A 20 s break after
//  20 min of healthy use (the 20-20-20 rule) resets the score.
// ----------------------------------------------------------------------------
#define RATE_OK          0.05f
#define RATE_CLOSE       0.12f
#define RATE_DANGER      0.40f
#define RATE_RECOVERY    3.50f   // points/s removed while the user is away

// ----------------------------------------------------------------------------
//  ESRS - environmental multipliers (applied to the increment, not recovery)
// ----------------------------------------------------------------------------
#define NOISE_THRESHOLD  200     // smoothed mic peak-to-peak (ADC counts, 0-1023)
#define NOISE_MULT       1.25f
#define HUMIDITY_LOW_PCT 40.0f   // below this the air is dry -> faster eye fatigue
#define HUMIDITY_MULT    1.30f

// ----------------------------------------------------------------------------
//  ESRS - LED thresholds
// ----------------------------------------------------------------------------
#define ESRS_MAX         100.0f
#define LEVEL_YELLOW     40.0f
#define LEVEL_RED        70.0f
#define LEVEL_OVERDUE    90.0f   // red LED starts blinking
#define LEVEL_HYSTERESIS 3.0f    // prevents LED flicker around a threshold
