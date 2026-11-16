// =============================================================================
//  EyeMaxxer - Arduino firmware (Uno / Nano)
//  Imperial x Cambridge Engineering Make-a-thon on Student Wellbeing
//
//  A laptop-mounted HC-SR04 measures how far the user sits from the screen.
//  The Eye Strain Risk Score (ESRS) builds up while they are at the screen
//  (faster when they sit too close) and drains when they step away. Ambient
//  noise and low humidity multiply the build-up rate. LEDs show both the
//  immediate danger zone (< 30 cm) and the accumulated strain risk.
//
//  Telemetry is streamed over USB serial so the MATLAB dashboard
//  (matlab/EyeMaxxerDashboard.m) can plot everything live. Without a laptop
//  connected, the board runs stand-alone from a battery pack.
//
//  Libraries: "DHT sensor library" by Adafruit (+ "Adafruit Unified Sensor")
// =============================================================================
#include <DHT.h>
#include "config.h"
#include "esrs.h"

DHT dht(PIN_DHT, DHT_TYPE);
EsrsEngine esrs;

// --- sensor state ------------------------------------------------------------
float distBuf[US_MEDIAN_N];
unsigned char distIdx = 0;
float distanceCm = 0.0f;
float noiseLevel = 0.0f;
float humidityPct = -1.0f;   // -1 until the first valid DHT reading
float temperatureC = 20.0f;  // used for speed-of-sound compensation

// --- scheduler ---------------------------------------------------------------
unsigned long lastTick = 0, lastDht = 0, lastReport = 0;
EsrsOutputs state;

// -----------------------------------------------------------------------------
//  Sensors
// -----------------------------------------------------------------------------
// One ultrasonic ping. Returns distance in cm, or 0 if no echo was received.
float pingCm() {
  digitalWrite(PIN_US_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_US_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_US_TRIG, LOW);

  unsigned long us = pulseIn(PIN_US_ECHO, HIGH, US_TIMEOUT_US);
  if (us == 0) return 0.0f;

  // Speed of sound varies ~0.6 m/s per degC; use the DHT temperature.
  float cmPerUs = (331.3f + 0.606f * temperatureC) / 10000.0f;
  return us * cmPerUs / 2.0f;
}

// Rolling median filter - rejects the odd spurious echo from a hand or a cup.
float medianDistance(float sample) {
  distBuf[distIdx] = sample;
  distIdx = (distIdx + 1) % US_MEDIAN_N;

  float s[US_MEDIAN_N];
  for (unsigned char i = 0; i < US_MEDIAN_N; i++) s[i] = distBuf[i];
  for (unsigned char i = 1; i < US_MEDIAN_N; i++) {  // insertion sort, N is tiny
    float v = s[i];
    int j = i - 1;
    while (j >= 0 && s[j] > v) { s[j + 1] = s[j]; j--; }
    s[j + 1] = v;
  }
  return s[US_MEDIAN_N / 2];
}

// Peak-to-peak amplitude of the microphone over a short window, then smoothed.
void sampleNoise() {
  int lo = 1023, hi = 0;
  unsigned long start = millis();
  while (millis() - start < MIC_WINDOW_MS) {
    int v = analogRead(PIN_MIC);
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  float p2p = (float)(hi - lo);
  noiseLevel += NOISE_EMA_ALPHA * (p2p - noiseLevel);
}

void sampleDht() {
  float h = dht.readHumidity();
  float t = dht.readTemperature();
  if (!isnan(h)) humidityPct = h;  // keep the last good value on a failed read
  if (!isnan(t)) temperatureC = t;
}

// -----------------------------------------------------------------------------
//  Outputs
// -----------------------------------------------------------------------------
void updateLeds(const EsrsOutputs& o, unsigned long now) {
  bool blinkOn = (now / (BLINK_PERIOD_MS / 2)) % 2;

  digitalWrite(PIN_LED_GREEN,  o.level == LEVEL_LOW);
  digitalWrite(PIN_LED_YELLOW, o.level == LEVEL_RISING);
  digitalWrite(PIN_LED_RED,    o.level == LEVEL_HIGH ||
                               (o.level == LEVEL_BREAK_OVERDUE && blinkOn));
  digitalWrite(PIN_LED_PROX,   o.proximityWarning);
}

void printHeader() {
  Serial.println(F("# EyeMaxxer v1.0"));
  Serial.println(F("# D,t_ms,distance_cm,noise,humidity_pct,temp_c,multiplier,esrs,zone,level,prox"));
  Serial.println(F("# zone: 0=away 1=danger 2=close 3=ok | level: 0=green 1=yellow 2=red 3=red-blink"));
  Serial.println(F("# commands: 'r' reset score, '?' print this header"));
}

void report(const EsrsOutputs& o, unsigned long now) {
  Serial.print(F("D,"));
  Serial.print(now);                 Serial.print(',');
  Serial.print(distanceCm, 1);       Serial.print(',');
  Serial.print(noiseLevel, 0);       Serial.print(',');
  Serial.print(humidityPct, 1);      Serial.print(',');
  Serial.print(temperatureC, 1);     Serial.print(',');
  Serial.print(o.multiplier, 3);     Serial.print(',');
  Serial.print(o.score, 2);          Serial.print(',');
  Serial.print((int)o.zone);         Serial.print(',');
  Serial.print((int)o.level);        Serial.print(',');
  Serial.println((int)o.proximityWarning);
}

void handleSerialCommands() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == 'r' || c == 'R') { esrs.reset(); Serial.println(F("# ESRS reset")); }
    else if (c == '?')        { printHeader(); }
  }
}

// Power-on self test: sweep the LEDs so a broken one is obvious.
void ledSelfTest() {
  const unsigned char pins[] = {PIN_LED_GREEN, PIN_LED_YELLOW, PIN_LED_RED, PIN_LED_PROX};
  for (unsigned char i = 0; i < 4; i++) {
    digitalWrite(pins[i], HIGH); delay(150); digitalWrite(pins[i], LOW);
  }
}

// -----------------------------------------------------------------------------
void setup() {
  Serial.begin(SERIAL_BAUD);
  pinMode(PIN_US_TRIG, OUTPUT);
  pinMode(PIN_US_ECHO, INPUT);
  pinMode(PIN_LED_GREEN, OUTPUT);
  pinMode(PIN_LED_YELLOW, OUTPUT);
  pinMode(PIN_LED_RED, OUTPUT);
  pinMode(PIN_LED_PROX, OUTPUT);

  dht.begin();
  for (unsigned char i = 0; i < US_MEDIAN_N; i++) distBuf[i] = 0.0f;

  ledSelfTest();
  printHeader();

  lastTick = lastDht = lastReport = millis();
  sampleDht();
}

void loop() {
  unsigned long now = millis();
  handleSerialCommands();

  if (now - lastDht >= DHT_PERIOD_MS) {
    lastDht = now;
    sampleDht();
  }

  if (now - lastTick >= TICK_MS) {
    float dt = (now - lastTick) / 1000.0f;
    lastTick = now;

    distanceCm = medianDistance(pingCm());
    sampleNoise();

    EsrsInputs in = {distanceCm, noiseLevel, humidityPct};
    state = esrs.update(in, dt);
  }

  updateLeds(state, now);

  if (now - lastReport >= REPORT_PERIOD_MS) {
    lastReport = now;
    report(state, now);
  }
}
