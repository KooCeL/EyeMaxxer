# Hardware

![The EyeMaxxer prototype](images/components.jpg)

The make-a-thon prototype was built on a breadboard around an **Arduino Nano**.
The firmware also runs unchanged on an **Arduino Uno**: both are ATmega328P
boards with the same pin names.

## Bill of materials

| Qty | Part | Purpose |
|----:|------|---------|
| 1 | Arduino Nano (or Uno) | Microcontroller: all sensor logic and the ESRS run on the board |
| 1 | HC-SR04 ultrasonic sensor | Measures screen-to-user distance (laptop-mounted, facing the user) |
| 1 | DHT11 temperature & humidity sensor | Dry-air multiplier, plus speed-of-sound compensation |
| 1 | Microphone sound-sensor module (analog out) | Noise multiplier |
| 3 | 5 mm LEDs: green, amber (yellow), red | Rested / immediate alert / strain alert |
| 3 | 220 Ω resistors | LED current limiting |
| 1 | USB power bank | Fully offline, portable operation |
| 1 | 3D-printed clip-on housing | Holds the ultrasonic sensor on top of the laptop lid ([CAD render](images/cad-design.jpg)) |
| – | Breadboard, jumper wires | |

## Wiring

> The original breadboard pin map wasn't recorded. These are the pins used by
> [`firmware/EyeMaxxer/config.h`](../firmware/EyeMaxxer/config.h). Change them
> there if your wiring is different.

| Component | Pin | Arduino |
|-----------|-----|---------|
| HC-SR04 | VCC / GND | 5V / GND |
| HC-SR04 | TRIG / ECHO | D9 / D10 |
| DHT11 | VCC / GND | 5V / GND |
| DHT11 | DATA | D2 (10 kΩ pull-up to 5V if using a bare sensor) |
| Microphone module | VCC / GND | 5V / GND |
| Microphone module | AO | A0 |
| Green LED | anode → 220 Ω | D3 |
| Amber LED | anode → 220 Ω | D5 |
| Red LED | anode → 220 Ω | D6 |
| All LEDs | cathode | GND |

```
                  ┌───────────────────────┐
  HC-SR04 TRIG ───┤ D9                 5V ├─── VCC (all sensors)
  HC-SR04 ECHO ───┤ D10               GND ├─── GND (sensors + LED cathodes)
    DHT11 DATA ───┤ D2                    │
     Mic AO ──────┤ A0    Arduino Nano    │
  Green LED ◄─────┤ D3 ─[220Ω]            │
  Amber LED ◄─────┤ D5 ─[220Ω]            │
  Red   LED ◄─────┤ D6 ─[220Ω]        USB ├─── laptop (MATLAB GUI) or power bank
                  └───────────────────────┘
```

## Calibration tips

- **Ultrasonic:** mount it on the top edge of the lid, angled slightly down at
  the user's face and chest. A 5-sample rolling median rejects one-off echoes.
  If there is no echo (nobody there), the reading counts as > 100 cm, which is
  the recovery zone.
- **Microphone:** the noise level is the microphone's peak-to-peak amplitude,
  scaled to 0–1 by `MIC_FULL_SCALE`. "Noisy" means ≥ 0.6, the same as the
  MATLAB model. Watch the `noise` column in the Serial Monitor (9600 baud) and
  adjust `MIC_FULL_SCALE` or the module's trim pot until a quiet room reads
  about 0.2 and a loud one about 0.8.
- **DHT11:** polled every 2 s. Until the first valid reading arrives, the air is
  not treated as dry.
