// =============================================================================
//  EyeMaxxer - live Eye Strain Risk Score (ESRS) engine
//
//  Pure C++ (no Arduino dependencies) so it can be unit-tested on a PC
//  (tests/test_esrs.cpp). Called once per tick (1 s):
//
//    increment = zone increment (+6 / +4 / +2 / +1 / -3)
//    if closer than 60 cm:  x1.30 if the air is dry, x1.20 if it is loud
//    ESRS = clamp(ESRS + increment, 0, 1000)
//
//  Same structure as the ESRS_Update block in the Simulink model (zone rate,
//  environmental multipliers below 60 cm, clamping), on the faster
//  per-tick / 0-1000 scale used for the live demo and GUI.
// =============================================================================
#pragma once
#include "config.h"

enum Zone : unsigned char {
  ZONE_DANGER = 0,    // < 30 cm     Immediate Danger
  ZONE_FAST = 1,      // 30-40 cm    Fast Strain
  ZONE_MODERATE = 2,  // 40-60 cm    Moderate Strain
  ZONE_MILD = 3,      // 60-100 cm   Mild Strain
  ZONE_RECOVERY = 4   // >= 100 cm   Recovery (or no echo)
};

enum Level : unsigned char { LEVEL_SAFE = 0, LEVEL_WARNING = 1, LEVEL_DANGER = 2 };

struct TickResult {
  float esrs;
  float increment;  // applied this tick, after multipliers
  Zone zone;
  Level level;      // which LED is lit: green / amber / red
  bool blink;       // danger zone: red LED blinks immediately
  bool vibrate;     // an alert is active (danger zone or red level)
};

class EsrsEngine {
 public:
  EsrsEngine() : esrs_(0.0f) {}

  void reset() { esrs_ = 0.0f; }
  float esrs() const { return esrs_; }

  static Zone classify(float d) {
    if (d <= 0.0f) return ZONE_RECOVERY;  // no echo: nobody at the screen
    if (d < ZONE_DANGER_CM) return ZONE_DANGER;
    if (d < ZONE_FAST_CM) return ZONE_FAST;
    if (d < ZONE_MODERATE_CM) return ZONE_MODERATE;
    if (d < ZONE_MILD_CM) return ZONE_MILD;
    return ZONE_RECOVERY;
  }

  static float zoneIncrement(Zone z) {
    switch (z) {
      case ZONE_DANGER:   return INC_DANGER;
      case ZONE_FAST:     return INC_FAST;
      case ZONE_MODERATE: return INC_MODERATE;
      case ZONE_MILD:     return INC_MILD;
      default:            return INC_RECOVERY;
    }
  }

  static Level levelOf(float esrs) {
    if (esrs >= LEVEL_RED) return LEVEL_DANGER;
    if (esrs >= LEVEL_AMBER) return LEVEL_WARNING;
    return LEVEL_SAFE;
  }

  // One tick. `dry` / `loud` come from the DHT11 and the microphone.
  TickResult tick(float distanceCm, bool dry, bool loud) {
    TickResult r;
    r.zone = classify(distanceCm);
    float inc = zoneIncrement(r.zone);
    if (r.zone != ZONE_RECOVERY && distanceCm < ZONE_MODERATE_CM) {
      if (dry) inc *= DRY_MULT;
      if (loud) inc *= LOUD_MULT;
    }
    esrs_ += inc;
    if (esrs_ > ESRS_MAX) esrs_ = ESRS_MAX;
    if (esrs_ < 0.0f) esrs_ = 0.0f;

    r.esrs = esrs_;
    r.increment = inc;
    r.level = levelOf(esrs_);
    r.blink = (r.zone == ZONE_DANGER);
    r.vibrate = r.blink || r.level == LEVEL_DANGER;
    return r;
  }

 private:
  float esrs_;
};
