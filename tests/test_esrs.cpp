// Host-side unit tests for the ESRS engine used in the firmware.
// Build & run:  g++ -std=c++11 -Wall -Wextra -I firmware/EyeMaxxer tests/test_esrs.cpp -o test_esrs && ./test_esrs
#include <cmath>
#include <cstdio>
#include "esrs.h"

static int failures = 0;
#define CHECK(cond, msg)                                              \
  do {                                                                \
    if (!(cond)) { std::printf("  FAIL: %s\n", msg); failures++; }   \
    else         { std::printf("  ok:   %s\n", msg); }               \
  } while (0)

static const float DT = TICK_MS / 1000.0f;
static const EsrsInputs QUIET_HUMID = {60.0f, 50.0f, 55.0f};

// Run the engine for `seconds` with fixed inputs; returns the last output.
static EsrsOutputs run(EsrsEngine& e, EsrsInputs in, float seconds) {
  EsrsOutputs o = e.update(in, 0.0f);
  int ticks = (int)std::lround(seconds / DT);
  for (int i = 0; i < ticks; i++) o = e.update(in, DT);
  return o;
}

static bool near(float a, float b, float tol = 0.05f) { return std::fabs(a - b) <= tol; }

int main() {
  std::puts("Zone classification");
  CHECK(EsrsEngine::classify(0.0f) == ZONE_AWAY, "no echo -> away");
  CHECK(EsrsEngine::classify(25.0f) == ZONE_DANGER, "25 cm -> danger");
  CHECK(EsrsEngine::classify(40.0f) == ZONE_CLOSE, "40 cm -> close");
  CHECK(EsrsEngine::classify(65.0f) == ZONE_OK, "65 cm -> ok");
  CHECK(EsrsEngine::classify(150.0f) == ZONE_AWAY, "150 cm -> away");

  std::puts("Healthy posture reaches red in ~23 min");
  {
    EsrsEngine e;
    EsrsOutputs o = run(e, QUIET_HUMID, 20 * 60);
    CHECK(near(o.score, 60.0f), "20 min at 60 cm -> ESRS 60");
    CHECK(o.level == LEVEL_RISING, "...yellow LED");
    o = run(e, QUIET_HUMID, 4 * 60);
    CHECK(o.level == LEVEL_HIGH, "24 min -> red LED");
    CHECK(!o.proximityWarning, "no proximity warning at 60 cm");
  }

  std::puts("Danger zone");
  {
    EsrsEngine e;
    EsrsOutputs o = run(e, {25.0f, 50.0f, 55.0f}, 60);
    CHECK(o.proximityWarning, "proximity LED on immediately below 30 cm");
    CHECK(near(o.score, 24.0f), "60 s at 25 cm -> ESRS 24");
  }

  std::puts("Environmental multipliers");
  {
    EsrsEngine e;
    EsrsOutputs o = run(e, {60.0f, 400.0f, 30.0f}, 100);
    CHECK(o.noisy && o.dry, "noisy and dry flags set");
    CHECK(near(o.multiplier, 1.625f, 1e-4f), "multiplier = 1.25 * 1.30");
    CHECK(near(o.score, 8.125f), "100 s noisy+dry at 60 cm -> ESRS 8.125");

    EsrsEngine e2;
    o = run(e2, {60.0f, 50.0f, -1.0f}, 100);
    CHECK(!o.dry && near(o.score, 5.0f), "no humidity reading -> no dry multiplier");
  }

  std::puts("Breaks: debounce and recovery");
  {
    EsrsEngine e;
    run(e, {25.0f, 50.0f, 55.0f}, 200);  // ESRS 80
    EsrsOutputs o = run(e, {0.0f, 50.0f, 55.0f}, 1.5f);
    CHECK(near(o.score, 80.0f), "1.5 s glance away does not count as a break");
    o = run(e, {0.0f, 50.0f, 55.0f}, 20.0f);
    CHECK(near(o.score, 80.0f - RATE_RECOVERY * (21.5f - AWAY_DEBOUNCE_S),
               RATE_RECOVERY * DT + 0.01f),  // +-1 tick at the debounce edge
          "20 s break drains ~68 points");
    CHECK(o.level == LEVEL_LOW, "...and the LEDs return to green");
    o = run(e, {0.0f, 50.0f, 55.0f}, 120.0f);
    CHECK(o.score == 0.0f, "score clamps at 0");
  }

  std::puts("Clamp and overdue level");
  {
    EsrsEngine e;
    EsrsOutputs o = run(e, {20.0f, 400.0f, 20.0f}, 600);
    CHECK(o.score == ESRS_MAX, "score clamps at 100");
    CHECK(o.level == LEVEL_BREAK_OVERDUE, "red LED blinks when overdue");
  }

  std::puts("LED hysteresis");
  {
    EsrsEngine e;
    run(e, {25.0f, 50.0f, 55.0f}, 180);  // ESRS 72 -> red
    EsrsInputs away = {0.0f, 50.0f, 55.0f};
    EsrsOutputs o = run(e, away, AWAY_DEBOUNCE_S + 3.0f / RATE_RECOVERY);  // ~69
    CHECK(o.score < LEVEL_RED && o.level == LEVEL_HIGH, "just below 70 -> still red");
    o = run(e, away, 3.0f / RATE_RECOVERY);  // ~67 - well below 70 - hysteresis
    CHECK(o.score < LEVEL_RED - LEVEL_HYSTERESIS && o.level == LEVEL_RISING,
          "below 67 -> drops to yellow");
  }

  std::printf("\n%s (%d failure%s)\n", failures ? "FAILED" : "ALL TESTS PASSED",
              failures, failures == 1 ? "" : "s");
  return failures ? 1 : 0;
}
