// =============================================================================
//  EyeMaxxer - Arduino firmware (live hardware version, Nano / Uno)
//  Imperial x Cambridge Engineering Make-a-thon on Student Wellbeing
//
//  A laptop-mounted HC-SR04 measures how far you sit from the screen. Every
//  second (one "tick") the Eye Strain Risk Score (ESRS, 0-1000) changes by an
//  amount set by your proximity zone:
//
//      <  30 cm   Immediate Danger   +6 / tick, red LED blinks + vibration
//    30-40 cm     Fast Strain        +4 / tick
//    40-60 cm     Moderate Strain    +2 / tick
//    60-100 cm    Mild Strain        +1 / tick
//    >= 100 cm    Recovery           -3 / tick
//
//  Closer than 60 cm, dry air (DHT11) and a loud room (microphone) multiply
//  the increment by 1.3 and 1.2. The LEDs show the accumulated risk:
//
//    green  ESRS < 300     safe
//    amber  300 - 699      warning
//    red    >= 700         take a break (vibration motor pulses too)
//
//  "Arduino handles all sensor logic, MATLAB visualises": one status line per
//  tick is sent over USB to the MATLAB GUI (matlab/EyeMaxxerGUI.m). On a
//  battery pack it works fully offline.
//
//  Libraries: "DHT sensor library" by Adafruit (+ "Adafruit Unified Sensor")
// =============================================================================
#include "config.h"
#include "esrs.h"
#if USE_DHT
#include <DHT.h>
DHT dht(PIN_DHT, DHT_TYPE);
#endif

EsrsEngine esrs;
TickResult state;

float distBuf[US_MEDIAN_N];
unsigned char distIdx = 0;
float distanceCm = NO_ECHO_CM;
int humidityPct = 0;           // 0 until the first valid DHT11 reading
int loudestP2P = 0;            // loudest microphone window during this tick
bool loud = false;
unsigned char alertMode = DEFAULT_ALERT_MODE;

unsigned long lastSample = 0, lastTick = 0;

// -----------------------------------------------------------------------------
//  Sensors
// -----------------------------------------------------------------------------
float pingCm() {
  digitalWrite(PIN_US_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_US_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_US_TRIG, LOW);
  unsigned long us = pulseIn(PIN_US_ECHO, HIGH, US_TIMEOUT_US);
  if (us == 0) return NO_ECHO_CM;
  return us * 0.0343f / 2.0f;
}

// Rolling median of the last US_MEDIAN_N pings - ignores one-off bad echoes.
float medianDistance(float sample) {
  distBuf[distIdx] = sample;
  distIdx = (distIdx + 1) % US_MEDIAN_N;
  float s[US_MEDIAN_N];
  for (int i = 0; i < US_MEDIAN_N; i++) s[i] = distBuf[i];
  for (int i = 1; i < US_MEDIAN_N; i++) {
    float v = s[i];
    int j = i - 1;
    while (j >= 0 && s[j] > v) { s[j + 1] = s[j]; j--; }
    s[j + 1] = v;
  }
  return s[US_MEDIAN_N / 2];
}

int micPeakToPeak() {
#if USE_MIC
  int lo = 1023, hi = 0;
  unsigned long start = millis();
  while (millis() - start < MIC_WINDOW_MS) {
    int v = analogRead(PIN_MIC);
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  return hi - lo;
#else
  return 0;
#endif
}

void readHumidity() {
#if USE_DHT
  float h = dht.readHumidity();
  if (!isnan(h)) humidityPct = (int)(h + 0.5f);
#endif
}

// -----------------------------------------------------------------------------
//  Outputs
// -----------------------------------------------------------------------------
void updateOutputs(unsigned long now) {
  bool ledsOn = alertMode != 2;
  bool vibOn = alertMode != 1;
  bool blinkPhase = (now / BLINK_MS) % 2;

  bool g = state.level == LEVEL_SAFE;
  bool a = ledsOn && state.level == LEVEL_WARNING;
  bool r = ledsOn && state.level == LEVEL_DANGER;
  if (state.blink) {                      // immediate danger overrides the level
    g = false;
    a = false;
    r = ledsOn && blinkPhase;
  }
  digitalWrite(PIN_LED_GREEN, g);
  digitalWrite(PIN_LED_AMBER, a);
  digitalWrite(PIN_LED_RED, r);

  // short buzz at the start of every tick while an alert is active
  bool buzz = vibOn && state.vibrate && (now - lastTick) < VIBRATE_ON_MS;
  digitalWrite(PIN_VIBRATION, buzz);
}

// One line per tick, e.g.
// DIST:45.2,HUM:38,SOUND:0,ZONE:2,INC:2.6,ESRS:512.4,LED:1,BLINK:0,VIB:0,MODE:0
void report() {
  Serial.print(F("DIST:"));   Serial.print(distanceCm, 1);
  Serial.print(F(",HUM:"));   Serial.print(humidityPct);
  Serial.print(F(",SOUND:")); Serial.print(loud ? 1 : 0);
  Serial.print(F(",ZONE:"));  Serial.print((int)state.zone);
  Serial.print(F(",INC:"));   Serial.print(state.increment, 1);
  Serial.print(F(",ESRS:"));  Serial.print(state.esrs, 1);
  Serial.print(F(",LED:"));   Serial.print((int)state.level);
  Serial.print(F(",BLINK:")); Serial.print(state.blink ? 1 : 0);
  Serial.print(F(",VIB:"));   Serial.print(state.vibrate && alertMode != 1 ? 1 : 0);
  Serial.print(F(",MODE:"));  Serial.println((int)alertMode);
}

// 'r' resets the ESRS, 'm' cycles the alert mode, '0'/'1'/'2' set it directly.
void handleSerial() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == 'r' || c == 'R') esrs.reset();
    else if (c == 'm' || c == 'M') alertMode = (alertMode + 1) % 3;
    else if (c >= '0' && c <= '2') alertMode = c - '0';
  }
}

// -----------------------------------------------------------------------------
void setup() {
  Serial.begin(SERIAL_BAUD);
  pinMode(PIN_US_TRIG, OUTPUT);
  pinMode(PIN_US_ECHO, INPUT);
  const unsigned char outs[] = {PIN_LED_GREEN, PIN_LED_AMBER, PIN_LED_RED, PIN_VIBRATION};
  for (unsigned char i = 0; i < 4; i++) pinMode(outs[i], OUTPUT);

  // power-on self test: green, amber, red in turn
  for (unsigned char i = 0; i < 3; i++) {
    digitalWrite(outs[i], HIGH); delay(200); digitalWrite(outs[i], LOW);
  }

#if USE_DHT
  dht.begin();
#endif
  for (int i = 0; i < US_MEDIAN_N; i++) distBuf[i] = NO_ECHO_CM;
  state = esrs.tick(NO_ECHO_CM, false, false);
  lastSample = lastTick = millis();
}

void loop() {
  unsigned long now = millis();
  handleSerial();

  if (now - lastSample >= SAMPLE_MS) {     // 10 Hz sensing
    lastSample = now;
    distanceCm = medianDistance(pingCm());
    int p2p = micPeakToPeak();
    if (p2p > loudestP2P) loudestP2P = p2p;
  }

  if (now - lastTick >= TICK_MS) {         // 1 Hz ESRS tick
    lastTick = now;
    readHumidity();
    loud = loudestP2P >= MIC_LOUD_P2P;
    loudestP2P = 0;
    bool dry = humidityPct > 0 && humidityPct < DRY_HUMIDITY_PCT;
    state = esrs.tick(distanceCm, dry, loud);
    report();
  }

  updateOutputs(now);
}
