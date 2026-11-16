# Eye Strain Risk Score (ESRS)

The ESRS is a single number from **0 (rested)** to **100 (break overdue)** that
summarises how much eye strain the user has accumulated. It is updated every
100 ms on the Arduino.

The same algorithm is implemented three times, and all three are kept in sync:

| Implementation | Used for |
|---|---|
| [`firmware/EyeMaxxer/esrs.h`](../firmware/EyeMaxxer/esrs.h) | Runs on the Arduino; unit-tested on the host by [`tests/test_esrs.cpp`](../tests/test_esrs.cpp) |
| [`matlab/esrsStep.m`](../matlab/esrsStep.m) | Scenario testing, the simulated dashboard, and the Simulink MATLAB Function block |
| Parameters: [`config.h`](../firmware/EyeMaxxer/config.h) ↔ [`esrsParams.m`](../matlab/esrsParams.m) | One set of tuning constants |

## 1. Distance zones

The laptop-mounted ultrasonic sensor sorts the user's distance into one of four zones:

| Zone | Distance | Base increment | Proximity LED |
|------|----------|---------------:|:---:|
| **Danger** | < 30 cm | +0.40 /s | on |
| **Close** | 30–50 cm | +0.12 /s | – |
| **OK** | 50–120 cm | +0.05 /s | – |
| **Away** | > 120 cm or no echo | −3.5 /s (recovery) | – |

Even a healthy posture builds up strain slowly, because staring at a screen
without a break is the main driver of digital eye strain. Sitting closer makes
it build up faster.

## 2. Environmental multipliers

Ambient conditions scale the increment (not the recovery):

| Condition | Test | Multiplier |
|-----------|------|-----------:|
| Noisy surroundings | smoothed mic peak-to-peak > 200 | × 1.25 |
| Dry air | relative humidity < 40 % | × 1.30 |
| Both | | × 1.625 |

Dry air speeds up tear-film evaporation, and noise adds to stress and fatigue.
Both make strain build up faster.

## 3. Update rule

```
every tick (dt = 0.1 s):
    zone = classify(distance)
    if zone == AWAY:
        away_time += dt
        if away_time >= 2 s:                 # ignore quick glances away
            ESRS -= 3.5 * dt
    else:
        away_time = 0
        ESRS += base_rate(zone) * noise_mult * humidity_mult * dt
    ESRS = clamp(ESRS, 0, 100)
```

## 4. LED levels

| ESRS | LED | Meaning |
|------|-----|---------|
| 0–40 | 🟢 green | Low risk |
| 40–70 | 🟡 yellow | Risk rising |
| 70–90 | 🔴 red | Take a break |
| 90–100 | 🔴 red, blinking | Break overdue |

Levels go up as soon as a threshold is crossed. They only come back down once
the score is 3 points below that threshold, so the LEDs don't flicker at a boundary.

## 5. What this means in practice

| Situation | Time to red LED |
|-----------|----------------:|
| Healthy distance, quiet, humid | ~23 min |
| Healthy distance, noisy **and** dry | ~14 min |
| Too close (30–50 cm) | ~10 min |
| Danger zone (< 30 cm) | ~3 min |

A **20-second break after 20 minutes** of healthy use (the 20-20-20 rule) brings
the score back to zero. Glances away shorter than 2 s don't count as a break.

These numbers are checked automatically by
[`matlab/runScenarioTests.m`](../matlab/runScenarioTests.m):

![ESRS scenario test results](images/scenario_results.png)

> The constants were tuned at the make-a-thon for a convincing, testable
> prototype. They are not clinically validated thresholds.
