// =============================================================================
//  EyeMaxxer - Eye Strain Risk Score (ESRS) engine
//
//  C++ port of the team's ESRS_Update MATLAB Function block
//  (simulink/simulink_eyestrain.slx, also matlab/eye_strain_sim.m).
//  Pure C++ with no Arduino dependencies, so the same code runs on the board
//  and in the host-side unit tests (tests/test_esrs.cpp).
//
//  Each tick of dt seconds:
//    deltaPerMin = rate(distance zone)
//    if distance < 60 cm: deltaPerMin *= 1.30 if dry, *= 1.20 if noisy
//    ESRS = clamp(ESRS + deltaPerMin * dt / 60, 0, 100)
//
//  Alerts:
//    amber LED blinks  while distance < 30 cm      (Immediate_Alert)
//    red   LED blinks  while ESRS >= 70            (ESRS Alert)
//    green LED on      while ESRS == 0             (RestDone)
// =============================================================================
#pragma once
#include "config.h"

enum Zone : unsigned char {
  ZONE_DANGER = 0,    // < 30 cm
  ZONE_FAST = 1,      // 30-40 cm
  ZONE_MODERATE = 2,  // 40-60 cm
  ZONE_MILD = 3,      // 60-100 cm
  ZONE_RECOVERY = 4   // > 100 cm (or no echo)
};

struct EsrsInputs {
  float distanceCm;   // <= 0 means "no echo" and is treated as away (recovery)
  float humidityPct;  // < 0 means "no valid reading yet" (never counts as dry)
  float noiseLevel;   // normalised 0..1
};

struct EsrsOutputs {
  float score;
  float ratePerMin;   // rate actually applied this tick, after multipliers
  Zone zone;
  bool dry;
  bool noisy;
  bool greenLed;      // steady
  bool amberAlert;    // blink
  bool redAlert;      // blink
};

class EsrsEngine {
 public:
  EsrsEngine() : score_(ESRS_MIN) {}

  void reset() { score_ = ESRS_MIN; }
  float score() const { return score_; }

  static Zone classify(float d) {
    if (d <= 0.0f) return ZONE_RECOVERY;  // no echo: nobody in front of the screen
    if (d < ZONE_DANGER_CM) return ZONE_DANGER;
    if (d < ZONE_FAST_CM) return ZONE_FAST;
    if (d < ZONE_MODERATE_CM) return ZONE_MODERATE;
    if (d <= ZONE_MILD_CM) return ZONE_MILD;
    return ZONE_RECOVERY;
  }

  static float baseRate(Zone z) {
    switch (z) {
      case ZONE_DANGER:   return RATE_UNDER_30;
      case ZONE_FAST:     return RATE_30_40;
      case ZONE_MODERATE: return RATE_40_60;
      case ZONE_MILD:     return RATE_60_100;
      default:            return RATE_OVER_100;
    }
  }

  EsrsOutputs update(const EsrsInputs& in, float dtSeconds) {
    EsrsOutputs out;
    out.zone = classify(in.distanceCm);
    out.dry = in.humidityPct >= 0.0f && in.humidityPct < DRY_HUMIDITY_PCT;
    out.noisy = in.noiseLevel >= HIGH_NOISE_LEVEL;

    float rate = baseRate(out.zone);
    bool inMultRange = in.distanceCm > 0.0f && in.distanceCm < MULT_MAX_CM;
    if (inMultRange) {
      if (out.dry) rate *= DRY_MULT;
      if (out.noisy) rate *= NOISE_MULT;
    }
    out.ratePerMin = rate;

    score_ += rate * (dtSeconds / 60.0f);
    if (score_ > ESRS_MAX) score_ = ESRS_MAX;
    if (score_ < ESRS_MIN) score_ = ESRS_MIN;

    out.score = score_;
    out.greenLed = (score_ == ESRS_MIN);
    out.amberAlert = (out.zone == ZONE_DANGER);
    out.redAlert = (score_ >= ESRS_RED);
    return out;
  }

 private:
  float score_;
};
