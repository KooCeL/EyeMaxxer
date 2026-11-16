// =============================================================================
//  EyeMaxxer - configuration (live hardware version)
//
//  Pin map, sensor settings and the live Eye Strain Risk Score (ESRS) rules.
//  These match the "THE EyeMaxxer" MATLAB GUI used in the make-a-thon demo:
//  a 0-1000 ESRS gauge and per-tick zone increments (+4 / +2 / +1 / -3).
//
//  Target board: Arduino Nano (used at the make-a-thon) or Arduino Uno.
// =============================================================================
#pragma once

// ----------------------------------------------------------------------------
//  Pin map
// ----------------------------------------------------------------------------
#define PIN_US_TRIG      9    // HC-SR04 TRIG
#define PIN_US_ECHO      10   // HC-SR04 ECHO
#define PIN_DHT          2    // DHT11 data (optional - see USE_DHT)
#define PIN_MIC          A0   // microphone module analog out (optional - see USE_MIC)

#define PIN_LED_GREEN    3    // ESRS < LEVEL_AMBER        (safe)
#define PIN_LED_AMBER    5    // LEVEL_AMBER <= ESRS < LEVEL_RED (warning)
#define PIN_LED_RED      6    // ESRS >= LEVEL_RED, or blinking when < 30 cm
#define PIN_VIBRATION    8    // vibration motor via NPN transistor (optional)

// Optional sensors: set to 0 if the part isn't fitted. Without them the
// readings are reported as 0 / quiet and no multiplier is applied.
#define USE_DHT          1
#define USE_MIC          1
#define DHT_TYPE         DHT11

// ----------------------------------------------------------------------------
//  Timing
// ----------------------------------------------------------------------------
#define SERIAL_BAUD      9600
#define TICK_MS          1000    // one ESRS "tick" per second
#define SAMPLE_MS        100     // distance / noise sampling period
#define BLINK_MS         250     // half-period of the danger-zone blink
#define VIBRATE_ON_MS    300     // vibration pulse length within each tick

// ----------------------------------------------------------------------------
//  Sensors
// ----------------------------------------------------------------------------
#define US_TIMEOUT_US    25000UL // ~4 m max range
#define NO_ECHO_CM       400.0f  // reported when nothing echoes back (user away)
#define US_MEDIAN_N      5       // rolling median window

#define MIC_WINDOW_MS    20      // peak-to-peak window per sample
#define MIC_LOUD_P2P     300     // peak-to-peak (ADC counts) treated as "loud"
#define DRY_HUMIDITY_PCT 40      // below this the air is "dry"

// ----------------------------------------------------------------------------
//  ESRS - proximity zones (cm) and increments (points per tick)
// ----------------------------------------------------------------------------
#define ZONE_DANGER_CM   30.0f   // <  30 cm   Immediate Danger (+blink)
#define ZONE_FAST_CM     40.0f   // 30-40 cm   Fast Strain
#define ZONE_MODERATE_CM 60.0f   // 40-60 cm   Moderate Strain
#define ZONE_MILD_CM     100.0f  // 60-100 cm  Mild Strain;  >= 100 cm Recovery

#define INC_DANGER       6.0f
#define INC_FAST         4.0f
#define INC_MODERATE     2.0f
#define INC_MILD         1.0f
#define INC_RECOVERY    -3.0f

// Environmental multipliers - only applied closer than ZONE_MODERATE_CM
#define DRY_MULT         1.30f
#define LOUD_MULT        1.20f

// ----------------------------------------------------------------------------
//  ESRS - scale and LED levels
// ----------------------------------------------------------------------------
#define ESRS_MAX         1000.0f
#define LEVEL_AMBER      300.0f
#define LEVEL_RED        700.0f

// ----------------------------------------------------------------------------
//  Alert mode at power-up (change at runtime by sending 'm' over serial)
//    0 = LEDs + vibrate,  1 = LEDs only,  2 = vibrate only
// ----------------------------------------------------------------------------
#define DEFAULT_ALERT_MODE 0
