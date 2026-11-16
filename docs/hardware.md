# Hardware

EyeMaxxer is built from cheap, widely available hobby parts. It runs on an
Arduino Uno or Nano (both ATmega328P, identical pin map).

## Bill of materials

| Qty | Part | Purpose |
|----:|------|---------|
| 1 | Arduino Uno R3 (or Nano) | Microcontroller |
| 1 | HC-SR04 ultrasonic sensor | Screen-to-face distance (laptop-mounted, facing the user) |
| 1 | DHT11 (or DHT22) temperature + humidity sensor | Low-humidity multiplier and speed-of-sound compensation |
| 1 | Analog sound sensor (KY-038 / MAX4466 module) | Ambient-noise multiplier |
| 3 | 5 mm LEDs: green, yellow, red | Accumulated ESRS level |
| 1 | 5 mm LED: blue (or a second red) | Immediate proximity warning (< 30 cm) |
| 4 | 220 Ω resistors | LED current limiting |
| 1 | 10 kΩ resistor | DHT data pull-up (not needed on 3-pin breakout boards) |
| 1 | USB power bank / 9 V battery pack | Fully offline, portable operation |
| – | Breadboard, jumper wires, Velcro / tape | Mounting on the laptop lid |

## Wiring

| Component | Pin | Arduino |
|-----------|-----|---------|
| HC-SR04 | VCC / GND | 5V / GND |
| HC-SR04 | TRIG | D9 |
| HC-SR04 | ECHO | D10 |
| DHT11 | VCC / GND | 5V / GND |
| DHT11 | DATA | D2 (10 kΩ pull-up to 5V) |
| Sound sensor | VCC / GND | 5V / GND |
| Sound sensor | AO (analog out) | A0 |
| Green LED | anode → 220 Ω | D3 |
| Yellow LED | anode → 220 Ω | D5 |
| Red LED | anode → 220 Ω | D6 |
| Proximity LED | anode → 220 Ω | D7 |
| All LEDs | cathode | GND |

```
                 ┌──────────────────────────┐
  HC-SR04 TRIG ──┤ D9                    5V ├── VCC (all sensors)
  HC-SR04 ECHO ──┤ D10                  GND ├── GND (all sensors + LED cathodes)
    DHT11 DATA ──┤ D2                       │
   Mic AO ───────┤ A0      Arduino Uno      │
                 │                          │
  Green  LED ◄───┤ D3 ─[220Ω]               │
  Yellow LED ◄───┤ D5 ─[220Ω]               │
  Red    LED ◄───┤ D6 ─[220Ω]               │
  Prox   LED ◄───┤ D7 ─[220Ω]           USB ├── laptop (MATLAB) or power bank
                 └──────────────────────────┘
```

All pins are defined in [`firmware/EyeMaxxer/config.h`](../firmware/EyeMaxxer/config.h),
so you can move things around without touching the logic.

## Mounting and calibration tips

- Mount the HC-SR04 on the top edge of the laptop lid, pointing at the user's
  face/chest. A slight downward tilt avoids picking up the wall behind them.
- The rolling median filter (5 samples) rejects one-off echoes from hands or
  mugs. Increase `US_MEDIAN_N` if your desk is cluttered.
- Sound modules vary a lot. Open the Serial Monitor (115200 baud), watch the
  `noise` column in a quiet room and while talking, and set `NOISE_THRESHOLD`
  between the two. Turn the module's potentiometer if the reading is stuck near 0.
- The DHT11 only updates about once per second, so it is polled every 2 s.
  Until the first valid reading arrives, the humidity multiplier stays off.
