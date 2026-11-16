// Host-side unit tests for the firmware ESRS engine.
//
// The five scenarios are the ones from the team's MATLAB script
// (matlab/eye_strain_sim.m). The firmware must reproduce the same LED timings
// that the script printed and that are shown in the presentation.
//
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

struct Segment { float untilMin, distance, humidity, noise; };

struct Result {
  float firstAmberMin = -1, firstRedMin = -1, redOffMin = -1;
  float finalScore = 0, maxScore = 0;
};

// Same sampling as eye_strain_sim.m: t = 0:dt:duration, dt = 1 s, the score
// is updated at every sample (including t = 0).
static Result simulate(const Segment* segs, int nSegs, float durationMin) {
  EsrsEngine e;
  Result r;
  bool wasRed = false;
  int n = (int)std::lround(durationMin * 60.0f);
  for (int k = 0; k <= n; k++) {
    float tmin = k / 60.0f;
    int s = 0;
    while (s < nSegs - 1 && tmin >= segs[s].untilMin) s++;
    EsrsOutputs o = e.update({segs[s].distance, segs[s].humidity, segs[s].noise}, 1.0f);
    if (o.amberAlert && r.firstAmberMin < 0) r.firstAmberMin = tmin;
    if (o.redAlert && r.firstRedMin < 0) r.firstRedMin = tmin;
    if (wasRed && !o.redAlert && r.redOffMin < 0) r.redOffMin = tmin;
    wasRed = o.redAlert;
    if (o.score > r.maxScore) r.maxScore = o.score;
    r.finalScore = o.score;
  }
  return r;
}

static bool near2dp(float a, float b) { return std::fabs(a - b) < 0.006f; }

int main() {
  std::puts("Zones");
  CHECK(EsrsEngine::classify(25) == ZONE_DANGER, "25 cm -> immediate danger");
  CHECK(EsrsEngine::classify(35) == ZONE_FAST, "35 cm -> fast strain");
  CHECK(EsrsEngine::classify(50) == ZONE_MODERATE, "50 cm -> moderate strain");
  CHECK(EsrsEngine::classify(100) == ZONE_MILD, "100 cm -> mild strain (inclusive)");
  CHECK(EsrsEngine::classify(120) == ZONE_RECOVERY, "120 cm -> recovery");
  CHECK(EsrsEngine::classify(0) == ZONE_RECOVERY, "no echo -> recovery");

  std::puts("Multipliers only apply closer than 60 cm");
  {
    EsrsEngine e;
    EsrsOutputs o = e.update({35, 28, 0.8f}, 1.0f);
    CHECK(std::fabs(o.ratePerMin - 4.5f * 1.3f * 1.2f) < 1e-4f, "35 cm, dry + noisy -> 4.5 x 1.3 x 1.2");
    o = e.update({75, 28, 0.8f}, 1.0f);
    CHECK(std::fabs(o.ratePerMin - 0.1f) < 1e-6f, "75 cm, dry + noisy -> 0.1 (no multiplier)");
    o = e.update({35, -1, 0.2f}, 1.0f);
    CHECK(std::fabs(o.ratePerMin - 4.5f) < 1e-6f, "no humidity reading yet -> not dry");
  }

  std::puts("Scenario 1 - immediate under 30 cm");
  {
    Segment s[] = {{2, 70, 50, 0.2f}, {5, 25, 50, 0.2f}, {15, 75, 50, 0.2f}};
    Result r = simulate(s, 3, 15);
    CHECK(near2dp(r.firstAmberMin, 2.00f), "amber LED at 2.00 min");
    CHECK(r.firstRedMin < 0, "red LED never on");
  }

  std::puts("Scenario 2 - 35 cm, dry");
  {
    Segment s[] = {{5, 70, 28, 0.2f}, {25, 35, 28, 0.2f}, {35, 75, 28, 0.2f}};
    Result r = simulate(s, 3, 35);
    CHECK(near2dp(r.firstRedMin, 16.87f), "red LED at 16.87 min");
    CHECK(r.maxScore == ESRS_MAX, "ESRS saturates at 100");
  }

  std::puts("Scenario 3 - 35 cm, humid");
  {
    Segment s[] = {{5, 70, 55, 0.2f}, {25, 35, 55, 0.2f}, {35, 75, 55, 0.2f}};
    Result r = simulate(s, 3, 35);
    CHECK(near2dp(r.firstRedMin, 20.43f), "red LED at 20.43 min (later than dry)");
  }

  std::puts("Scenario 4 - 50 cm, humid, noisy after 20 min");
  {
    Segment s[] = {{5, 75, 55, 0.2f}, {20, 50, 55, 0.2f}, {55, 50, 55, 0.8f}, {60, 75, 55, 0.8f}};
    Result r = simulate(s, 4, 60);
    CHECK(near2dp(r.firstRedMin, 36.45f), "red LED at 36.45 min");
  }

  std::puts("Scenario 5 - recovery above 100 cm");
  {
    Segment s[] = {{12, 35, 30, 0.2f}, {20, 45, 30, 0.2f}, {22, 45, 50, 0.2f},
                   {35, 120, 50, 0.2f}, {50, 70, 50, 0.2f}};
    Result r = simulate(s, 5, 50);
    CHECK(near2dp(r.firstRedMin, 11.95f), "red LED at 11.95 min");
    CHECK(r.redOffMin > 22.0f && r.redOffMin < 35.0f, "red LED clears during the break");
    CHECK(r.finalScore < 30.0f, "ESRS recovered to below 30");
  }

  std::puts("Green LED");
  {
    EsrsEngine e;
    CHECK(e.update({120, 50, 0.2f}, 1.0f).greenLed, "green on while ESRS == 0");
    CHECK(!e.update({50, 50, 0.2f}, 1.0f).greenLed, "green off once strain accumulates");
    EsrsOutputs o;
    for (int i = 0; i < 60; i++) o = e.update({150, 50, 0.2f}, 1.0f);
    CHECK(o.greenLed && o.score == 0.0f, "green back on after recovering to 0");
  }

  std::printf("\n%s (%d failure%s)\n", failures ? "FAILED" : "ALL TESTS PASSED",
              failures, failures == 1 ? "" : "s");
  return failures ? 1 : 0;
}
