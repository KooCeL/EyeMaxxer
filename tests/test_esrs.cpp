// Host-side unit tests for the live ESRS engine (firmware/EyeMaxxer/esrs.h).
// Build & run:
//   g++ -std=c++11 -Wall -Wextra -I firmware/EyeMaxxer tests/test_esrs.cpp -o test_esrs && ./test_esrs
#include <cmath>
#include <cstdio>
#include "esrs.h"

static int failures = 0;
#define CHECK(cond, msg)                                              \
  do {                                                                \
    if (!(cond)) { std::printf("  FAIL: %s\n", msg); failures++; }   \
    else         { std::printf("  ok:   %s\n", msg); }               \
  } while (0)

static bool near(float a, float b) { return std::fabs(a - b) < 1e-3f; }

static TickResult runTicks(EsrsEngine& e, int n, float d, bool dry = false, bool loud = false) {
  TickResult r = {};
  for (int i = 0; i < n; i++) r = e.tick(d, dry, loud);
  return r;
}

int main() {
  std::puts("Proximity zones (GUI legend)");
  CHECK(EsrsEngine::classify(25) == ZONE_DANGER, "25 cm -> Immediate Danger");
  CHECK(EsrsEngine::classify(35) == ZONE_FAST, "35 cm -> Fast Strain");
  CHECK(EsrsEngine::classify(50) == ZONE_MODERATE, "50 cm -> Moderate Strain");
  CHECK(EsrsEngine::classify(80) == ZONE_MILD, "80 cm -> Mild Strain");
  CHECK(EsrsEngine::classify(100) == ZONE_RECOVERY, "100 cm -> Recovery (>= 100)");
  CHECK(EsrsEngine::classify(NO_ECHO_CM) == ZONE_RECOVERY, "no echo (400 cm) -> Recovery");

  std::puts("Increments per tick");
  {
    EsrsEngine e;
    CHECK(near(e.tick(35, false, false).increment, 4), "Fast Strain +4");
    CHECK(near(e.tick(50, false, false).increment, 2), "Moderate Strain +2");
    CHECK(near(e.tick(80, false, false).increment, 1), "Mild Strain +1");
    CHECK(near(e.tick(150, false, false).increment, -3), "Recovery -3");
    CHECK(near(e.esrs(), 4), "ESRS = 4 + 2 + 1 - 3 = 4");
  }

  std::puts("Environmental multipliers (closer than 60 cm only)");
  {
    EsrsEngine e;
    CHECK(near(e.tick(35, true, false).increment, 4 * 1.3f), "dry: x1.3");
    CHECK(near(e.tick(35, false, true).increment, 4 * 1.2f), "loud: x1.2");
    CHECK(near(e.tick(35, true, true).increment, 4 * 1.3f * 1.2f), "dry + loud: x1.56");
    CHECK(near(e.tick(80, true, true).increment, 1), "80 cm: no multiplier");
    CHECK(near(e.tick(150, true, true).increment, -3), "recovery: no multiplier");
  }

  std::puts("Immediate danger (< 30 cm)");
  {
    EsrsEngine e;
    TickResult r = e.tick(25, false, false);
    CHECK(r.blink && r.vibrate, "blinks and vibrates on the very first tick");
    CHECK(r.level == LEVEL_SAFE, "...even though the ESRS is still low");
  }

  std::puts("LED levels");
  {
    EsrsEngine e;
    TickResult r = runTicks(e, 74, 35);            // 296
    CHECK(r.level == LEVEL_SAFE && !r.vibrate, "ESRS 296 -> green");
    r = runTicks(e, 1, 35);                        // 300
    CHECK(r.level == LEVEL_WARNING, "ESRS 300 -> amber");
    r = runTicks(e, 100, 35);                      // 700
    CHECK(r.level == LEVEL_DANGER && r.vibrate, "ESRS 700 -> red + vibration");
    CHECK(near(r.esrs, 700), "Fast Strain reaches red after 175 ticks (~3 min)");
  }

  std::puts("Limits and recovery");
  {
    EsrsEngine e;
    TickResult r = runTicks(e, 400, 25);
    CHECK(near(r.esrs, ESRS_MAX), "ESRS clamps at 1000");
    r = runTicks(e, 100, 150);                     // 1000 - 300
    CHECK(near(r.esrs, 700) && r.level == LEVEL_DANGER, "100 s away: 1000 -> 700");
    r = runTicks(e, 1, 150);
    CHECK(r.level == LEVEL_WARNING, "one more tick: back to amber");
    r = runTicks(e, 400, 150);
    CHECK(near(r.esrs, 0) && r.level == LEVEL_SAFE, "full recovery to 0, green");
    e.tick(35, false, false);
    e.reset();
    CHECK(near(e.esrs(), 0), "reset() clears the score");
  }

  std::printf("\n%s (%d failure%s)\n", failures ? "FAILED" : "ALL TESTS PASSED",
              failures, failures == 1 ? "" : "s");
  return failures ? 1 : 0;
}
