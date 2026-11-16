// =============================================================================
//  EyeMaxxer - Eye Strain Risk Score (ESRS) engine
//
//  Pure C++ with no Arduino dependencies, so the exact same code runs on the
//  board and in the host-side unit tests (tests/test_esrs.cpp).
//
//  Every tick:
//    1. Classify the screen distance into a zone (DANGER / CLOSE / OK / AWAY).
//    2. If the user is at the screen:
//         ESRS += base_rate(zone) * noise_mult * humidity_mult * dt
//       If the user has been away for longer than AWAY_DEBOUNCE_S:
//         ESRS -= RATE_RECOVERY * dt          (taking a break lets eyes recover)
//    3. Clamp to [0, ESRS_MAX] and map the score to an LED level with hysteresis.
// =============================================================================
#pragma once
#include "config.h"

enum Zone : unsigned char { ZONE_AWAY = 0, ZONE_DANGER = 1, ZONE_CLOSE = 2, ZONE_OK = 3 };
enum Level : unsigned char { LEVEL_LOW = 0, LEVEL_RISING = 1, LEVEL_HIGH = 2, LEVEL_BREAK_OVERDUE = 3 };

struct EsrsInputs {
  float distanceCm;   // <= 0 means "no echo"
  float noiseLevel;   // smoothed mic peak-to-peak, ADC counts
  float humidityPct;  // < 0 means "no valid reading yet"
};

struct EsrsOutputs {
  float score;
  float multiplier;   // combined environmental multiplier applied this tick
  Zone zone;
  Level level;
  bool proximityWarning;
  bool noisy;
  bool dry;
};

class EsrsEngine {
 public:
  EsrsEngine() { reset(); }

  void reset() {
    score_ = 0.0f;
    awayTime_ = 0.0f;
    level_ = LEVEL_LOW;
  }

  static Zone classify(float d) {
    if (d <= 0.0f || d > AWAY_CM) return ZONE_AWAY;
    if (d < DANGER_CM) return ZONE_DANGER;
    if (d < CLOSE_CM) return ZONE_CLOSE;
    return ZONE_OK;
  }

  static float baseRate(Zone z) {
    switch (z) {
      case ZONE_DANGER: return RATE_DANGER;
      case ZONE_CLOSE:  return RATE_CLOSE;
      case ZONE_OK:     return RATE_OK;
      default:          return 0.0f;
    }
  }

  EsrsOutputs update(const EsrsInputs& in, float dtSeconds) {
    EsrsOutputs out;
    out.zone = classify(in.distanceCm);
    out.noisy = in.noiseLevel > NOISE_THRESHOLD;
    out.dry = in.humidityPct >= 0.0f && in.humidityPct < HUMIDITY_LOW_PCT;
    out.multiplier = (out.noisy ? NOISE_MULT : 1.0f) * (out.dry ? HUMIDITY_MULT : 1.0f);

    if (out.zone == ZONE_AWAY) {
      awayTime_ += dtSeconds;
      if (awayTime_ >= AWAY_DEBOUNCE_S) score_ -= RATE_RECOVERY * dtSeconds;
    } else {
      awayTime_ = 0.0f;
      score_ += baseRate(out.zone) * out.multiplier * dtSeconds;
    }

    if (score_ < 0.0f) score_ = 0.0f;
    if (score_ > ESRS_MAX) score_ = ESRS_MAX;

    level_ = nextLevel(level_, score_);

    out.score = score_;
    out.level = level_;
    out.proximityWarning = (out.zone == ZONE_DANGER);
    return out;
  }

  float score() const { return score_; }

 private:
  // Thresholds for entering each level; a level is only left once the score
  // falls LEVEL_HYSTERESIS below the threshold that entered it.
  static float enterThreshold(Level l) {
    switch (l) {
      case LEVEL_RISING:        return LEVEL_YELLOW;
      case LEVEL_HIGH:          return LEVEL_RED;
      case LEVEL_BREAK_OVERDUE: return LEVEL_OVERDUE;
      default:                  return 0.0f;
    }
  }

  static Level rawLevel(float s) {
    if (s >= LEVEL_OVERDUE) return LEVEL_BREAK_OVERDUE;
    if (s >= LEVEL_RED)     return LEVEL_HIGH;
    if (s >= LEVEL_YELLOW)  return LEVEL_RISING;
    return LEVEL_LOW;
  }

  static Level nextLevel(Level current, float s) {
    Level raw = rawLevel(s);
    if (raw >= current) return raw;  // rising: switch immediately
    // falling: step down only once clearly below the current level's threshold
    Level l = current;
    while (l > raw && s < enterThreshold(l) - LEVEL_HYSTERESIS) {
      l = static_cast<Level>(l - 1);
    }
    return l;
  }

  float score_;
  float awayTime_;
  Level level_;
};
