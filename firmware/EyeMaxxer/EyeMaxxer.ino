// =============================================================================
//  EyeMaxxer - Arduino firmware (Nano / Uno)
//  Imperial x Cambridge Engineering Make-a-thon on Student Wellbeing
//
//  A laptop-mounted HC-SR04 measures how far the user sits from the screen.
//  The Eye Strain Risk Score (ESRS) builds up at a rate set by the distance
//  zone, faster still in dry or noisy surroundings, and drains when the user
//  steps away (> 100 cm). Three LEDs give the alerts:
//
//    green  steady   ESRS == 0          fully rested
//    amber  blinking distance < 30 cm   immediate danger zone
//    red    blinking ESRS >= 70         accumulated strain - take a break
//
//  "Arduino handles all sensor logic, MATLAB visualises": telemetry is
//  streamed over USB serial to the MATLAB GUI (matlab/EyeMaxxerDashboard.m).
//  On a battery pack the device works fully offline.
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
float distanceCm = NO_ECHO_CM;
float noiseLevel = 0.0f;      // normalised 0..1
float humidityPct = -1.0f;    // -1 until the first valid DHT reading
float temperatureC = 20.0f;   // used for speed-of-sound compensation

// --- scheduler ---------------------------------------------------------------
unsigned long lastTick = 0, lastDht = 0, lastReport = 0;
EsrsOutputs state;

// -----------------------------------------------------------------------------
//  Sensors
// -----------------------------------------------------------------------------
// One ultrasonic ping. Returns distance in cm, or NO_ECHO_CM if nothing echoed.
float pingCm() {
  digitalWrite(PIN_US_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_US_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_US_TRIG, LOW);

  unsigned long us = pulseIn(PIN_US_ECHO, HIGH, US_TIMEOUT_US);
  if (us == 0) return NO_ECHO_CM;

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
  for (int i = 1; i < US_MEDIAN_N; i++) {  // insertion sort, N is tiny
    float v = s[i];
    int j = i - 1;
    while (j >= 0 && s[j] > v) { s[j + 1] = s[j]; j--; }
    s[j + 1] = v;
  }
  return s[US_MEDIAN_N / 2];
}

// Microphone peak-to-peak amplitude over a short window, normalised to 0..1
// and smoothed. Adjust MIC_FULL_SCALE (or the module's trim pot) so that a
// noisy room reads above HIGH_NOISE_LEVEL (0.6) and a quiet one well below.
void sampleNoise() {
  int lo = 1023, hi = 0;
  unsigned long start = millis();
  while (millis() - start < MIC_WINDOW_MS) {
    int v = analogRead(PIN_MIC);
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  float level = (hi - lo) / MIC_FULL_SCALE;
  if (level > 1.0f) level = 1.0f;
  noiseLevel += NOISE_EMA_ALPHA * (level - noiseLevel);
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
  digitalWrite(PIN_LED_GREEN, o.greenLed);
  digitalWrite(PIN_LED_AMBER, o.amberAlert && blinkOn);
  digitalWrite(PIN_LED_RED,   o.redAlert && blinkOn);
}

void printHeader() {
  Serial.println(F("# EyeMaxxer"));
  Serial.println(F("# D,t_ms,distance_cm,humidity_pct,noise,temp_c,rate_per_min,esrs,zone,green,amber,red"));
  Serial.println(F("# zone: 0 <30cm danger | 1 30-40 fast | 2 40-60 moderate | 3 60-100 mild | 4 >100 recovery"));
  Serial.println(F("# commands: 'r' reset ESRS, '?' print this header"));
}

void report(const EsrsOutputs& o, unsigned long now) {
  Serial.print(F("D,"));
  Serial.print(now);                 Serial.print(',');
  Serial.print(distanceCm, 1);       Serial.print(',');
  Serial.print(humidityPct, 1);      Serial.print(',');
  Serial.print(noiseLevel, 2);       Serial.print(',');
  Serial.print(temperatureC, 1);     Serial.print(',');
  Serial.print(o.ratePerMin, 2);     Serial.print(',');
  Serial.print(o.score, 2);          Serial.print(',');
  Serial.print((int)o.zone);         Serial.print(',');
  Serial.print((int)o.greenLed);     Serial.print(',');
  Serial.print((int)o.amberAlert);   Serial.print(',');
  Serial.println((int)o.redAlert);
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
  const unsigned char pins[] = {PIN_LED_GREEN, PIN_LED_AMBER, PIN_LED_RED};
  for (unsigned char i = 0; i < 3; i++) {
    digitalWrite(pins[i], HIGH); delay(200); digitalWrite(pins[i], LOW);
  }
}

// -----------------------------------------------------------------------------
void setup() {
  Serial.begin(SERIAL_BAUD);
  pinMode(PIN_US_TRIG, OUTPUT);
  pinMode(PIN_US_ECHO, INPUT);
  pinMode(PIN_LED_GREEN, OUTPUT);
  pinMode(PIN_LED_AMBER, OUTPUT);
  pinMode(PIN_LED_RED, OUTPUT);

  dht.begin();
  for (unsigned char i = 0; i < US_MEDIAN_N; i++) distBuf[i] = NO_ECHO_CM;

  ledSelfTest();
  printHeader();

  sampleDht();
  state = esrs.update({NO_ECHO_CM, humidityPct, 0.0f}, 0.0f);
  lastTick = lastDht = lastReport = millis();
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

    EsrsInputs in = {distanceCm, humidityPct, noiseLevel};
    state = esrs.update(in, dt);
  }

  updateLeds(state, now);

  if (now - lastReport >= REPORT_PERIOD_MS) {
    lastReport = now;
    report(state, now);
  }
}
