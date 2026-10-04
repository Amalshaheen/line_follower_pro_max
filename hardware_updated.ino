#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// =============================================================================
// 1. HARDWARE PINOUTS & MECHANICAL CONSTANTS
// =============================================================================

// BTS7960 Motor Driver Pins (ESP32-S3 Mini)
const int LEFT_EN    = 40;     
const int LEFT_RPWM  = 39;   
const int LEFT_LPWM  = 38;   
const int RIGHT_EN   = 3;     
const int RIGHT_RPWM = 42;  
const int RIGHT_LPWM = 41;  

// Encoder Hall Sensor Pins
const int PIN_ENC_LEFT  = 7;
const int PIN_ENC_RIGHT = 8;

// 12 IR Sensor Pins (Direct ADC)
const int IR_PINS[12] = {4, 5, 6, 16, 15, 14, 17, 18, 13, 12, 11, 10};

// CAD-Extracted Physical X-Coordinates in mm (Relative to Robot Centerline)
const float SENSOR_X_MM[12] = {
  -52.52f, -46.01f, -36.47f, -25.97f, -15.58f, -5.27f,
    5.27f,  15.58f,  25.97f,  36.47f,  46.01f,  52.52f
};

// Distance per magnet pulse: (pi * 40mm) / 8 magnets = 15.708 mm
const float MM_PER_TICK = 15.708f;

// Loop Timing: 3.0 ms = 3000 microseconds (333.3 Hz)
const unsigned long CONTROL_INTERVAL_MICROS = 3000;
const unsigned long TELEMETRY_INTERVAL_MS   = 45;   // ~22 Hz BLE
const unsigned long DEBUG_INTERVAL_MS       = 100;  // 10 Hz Serial

// =============================================================================
// 2. ENCODER SYSTEM & ODOMETRY (INTERRUPT DRIVEN)
// =============================================================================
volatile uint32_t encLeftTicks = 0;
volatile uint32_t encRightTicks = 0;

void IRAM_ATTR isrLeftEncoder() {
  encLeftTicks++;
}

void IRAM_ATTR isrRightEncoder() {
  encRightTicks++;
}

// =============================================================================
// 3. SYSTEM STATE & PID TUNING VARIABLES
// =============================================================================
// Units: mm error -> PWM correction
float Kp = 4.5f;   // Proportional gain (PWM per mm of lateral offset)
float Ki = 0.0f;   // Integral gain
float Kd = 12.0f;  // Derivative gain (PWM per (mm/s))
float dFilterAlpha = 0.65f; // 1st-order Low-Pass filter constant for D term

int baseSpeed = 110; // Nominal straight line PWM (0-255)
int maxSpeed  = 255;
int minSpeed  = 30;  // Deadband compensation for BTS7960
bool invertSteering = false;

// Sensor thresholds (12-bit ADC: 0-4095)
int sensorThresholds[12];
uint16_t sensorMask = 0x0FFF;
float defaultThreshold = 2000.0f;

// Operational Flags
bool motorsEnabled = false;
bool isLineLost = false;
float currentErrorMm = 0.0f;
float lastValidErrorMm = 0.0f;

// Encoder-Assisted Gap Recovery
uint32_t lineLostStartTick = 0;
const uint32_t GAP_BLIND_DISTANCE_TICKS = 8; // ~125 mm blind tracking before safety stop

// Forward Declarations
void setMotors(int leftSpeed, int rightSpeed);
void stopMotors();
void sendTelemetry(float error);
void sendThresholdsToApp();
void sendSensorMaskToApp();
void handleCommand(String rxValue);

// =============================================================================
// 4. BLE STACK (NORDIC UART SERVICE)
// =============================================================================
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer *pServer = nullptr;
BLECharacteristic *pTxChar = nullptr;
BLECharacteristic *pRxChar = nullptr;
bool deviceConnected = false;

#pragma pack(push, 1)
struct TelemetryPacket {
  uint8_t sensors[12];  // 8-bit downscaled ADC (0-255)
  int16_t error_x100;   // Error in mm * 100
  uint8_t status_flags; // Bit 0: Enabled, Bit 1: Line Lost
};
#pragma pack(pop)

class ServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override { deviceConnected = true; }
  void onDisconnect(BLEServer* pServer) override { 
    deviceConnected = false; 
    stopMotors(); 
    motorsEnabled = false;
    pServer->getAdvertising()->start();
  }
};

class RxCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    handleCommand(pCharacteristic->getValue().c_str());
  }
};

void initBLE() {
  BLEDevice::init("LFR_V5_Tuner");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pTxChar = pService->createCharacteristic(CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  pTxChar->addDescriptor(new BLE2902());

  pRxChar = pService->createCharacteristic(CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  pRxChar->setCallbacks(new RxCallbacks());

  pService->start();
  BLEAdvertising *pAdv = BLEDevice::getAdvertising();
  pAdv->addServiceUUID(SERVICE_UUID);
  pAdv->setScanResponse(true);
  BLEDevice::startAdvertising();
}

// =============================================================================
// 5. COMMAND PARSER
// =============================================================================
void handleCommand(String rx) {
  rx.trim();
  while (rx.endsWith("\r") || rx.endsWith("\n")) { rx.remove(rx.length() - 1); rx.trim(); }
  if (rx.length() == 0) return;

  if (rx.equalsIgnoreCase("S")) {
    motorsEnabled = !motorsEnabled;
    if (!motorsEnabled) stopMotors();
    return;
  }
  if (rx == "RUN=1" || rx == "ROBOT,START") { motorsEnabled = true; return; }
  if (rx == "RUN=0" || rx == "ROBOT,STOP")  { motorsEnabled = false; stopMotors(); return; }
  if (rx == "THRESH?") { sendThresholdsToApp(); return; }
  if (rx == "MASK?" || rx == "SENS?") { sendSensorMaskToApp(); return; }

  if (rx.startsWith("INV="))  { invertSteering = (rx.substring(4).toInt() != 0); return; }
  if (rx.startsWith("KP="))   { Kp = rx.substring(3).toFloat(); return; }
  if (rx.startsWith("KI="))   { Ki = rx.substring(3).toFloat(); return; }
  if (rx.startsWith("KD="))   { Kd = rx.substring(3).toFloat(); return; }
  if (rx.startsWith("BASE=")) { baseSpeed = constrain(rx.substring(5).toInt(), 0, 255); return; }
  if (rx.startsWith("MAX="))  { maxSpeed  = constrain(rx.substring(4).toInt(), 0, 255); return; }
  if (rx.startsWith("MIN="))  { minSpeed  = constrain(rx.substring(4).toInt(), 0, 255); return; }

  // Individual Sensor Threshold: THR=<sensor_idx>,<val>
  if (rx.startsWith("THR=")) {
    int comma = rx.indexOf(',');
    if (comma != -1) {
      int idx = rx.substring(4, comma).toInt();
      float val = rx.substring(comma + 1).toFloat();
      if (val <= 255.0f && val > 0.0f) val *= 16.0f; // Scale 8-bit to 12-bit
      if (idx >= 0 && idx < 12) {
        sensorThresholds[idx] = (int)constrain(val, 50.0f, 4095.0f);
        sendThresholdsToApp();
      }
    }
    return;
  }

  // Global Threshold: THRALL=<val>
  if (rx.startsWith("THRALL=")) {
    float val = rx.substring(7).toFloat();
    if (val <= 255.0f && val > 0.0f) val *= 16.0f;
    defaultThreshold = constrain(val, 50.0f, 4095.0f);
    for (int i = 0; i < 12; i++) sensorThresholds[i] = (int)defaultThreshold;
    sendThresholdsToApp();
    return;
  }

  if (rx.startsWith("MASK=")) {
    sensorMask = (uint16_t)rx.substring(5).toInt();
    sendSensorMaskToApp();
    return;
  }
}

// =============================================================================
// 6. METRIC SENSOR ACQUISITION & CENTROID CALCULATION
// =============================================================================
uint8_t sensor8BitTelemetry[12];

bool readSensorArrayMetric() {
  float weightedSum = 0.0f;
  float totalWeight = 0.0f;
  int activeCount = 0;

  for (int i = 0; i < 12; i++) {
    int raw = analogRead(IR_PINS[i]);
    sensor8BitTelemetry[i] = (uint8_t)(raw >> 4);

    bool isMasked = (sensorMask & (1 << i)) != 0;

    if (isMasked && raw > sensorThresholds[i]) {
      // Calculate normalized intensity weight above threshold
      float weight = (float)(raw - sensorThresholds[i]);
      weightedSum += (weight * SENSOR_X_MM[i]);
      totalWeight += weight;
      activeCount++;
    }
  }

  if (activeCount == 0 || totalWeight == 0.0f) {
    isLineLost = true;
    return false;
  }

  isLineLost = false;
  float calculatedError = weightedSum / totalWeight; // Result is in true millimeters
  currentErrorMm = invertSteering ? -calculatedError : calculatedError;
  lastValidErrorMm = currentErrorMm;
  return true;
}

// =============================================================================
// 7. CORE PID CONTROLLER WITH FILTERED DERIVATIVE
// =============================================================================
float pidIntegral = 0.0f;
float pidPrevError = 0.0f;
float pidFilteredD = 0.0f;

float computePID(float errorMm, float dt) {
  // Proportional Term
  float P = errorMm * Kp;

  // Integral Term with Anti-Windup
  pidIntegral += (errorMm * dt);
  pidIntegral = constrain(pidIntegral, -100.0f, 100.0f);
  float I = pidIntegral * Ki;

  // Filtered Derivative Term
  float rawD = (errorMm - pidPrevError) / dt;
  pidFilteredD = (dFilterAlpha * pidFilteredD) + ((1.0f - dFilterAlpha) * rawD);
  float D = pidFilteredD * Kd;
  pidPrevError = errorMm;

  return P + I + D;
}

void resetPID() {
  pidIntegral = 0.0f;
  pidPrevError = 0.0f;
  pidFilteredD = 0.0f;
}

// =============================================================================
// 8. MOTOR CONTROL & LINE-LOST BEHAVIOR
// =============================================================================
void setMotors(int leftSpeed, int rightSpeed) {
  int ceiling = constrain(maxSpeed, 0, 255);
  leftSpeed  = constrain(leftSpeed, -ceiling, ceiling);
  rightSpeed = constrain(rightSpeed, -ceiling, ceiling);

  // Overcome Static Friction
  if (minSpeed > 0) {
    if (leftSpeed > 0 && leftSpeed < minSpeed)   leftSpeed = minSpeed;
    if (leftSpeed < 0 && leftSpeed > -minSpeed)  leftSpeed = -minSpeed;
    if (rightSpeed > 0 && rightSpeed < minSpeed)  rightSpeed = minSpeed;
    if (rightSpeed < 0 && rightSpeed > -minSpeed) rightSpeed = -minSpeed;
  }

  digitalWrite(LEFT_EN, HIGH); 
  digitalWrite(RIGHT_EN, HIGH);

  // Left Channel
  if (leftSpeed > 0) {
    analogWrite(LEFT_RPWM, leftSpeed);
    analogWrite(LEFT_LPWM, 0);
  } else if (leftSpeed < 0) {
    analogWrite(LEFT_RPWM, 0);
    analogWrite(LEFT_LPWM, abs(leftSpeed));
  } else {
    analogWrite(LEFT_RPWM, 0);
    analogWrite(LEFT_LPWM, 0);
  }

  // Right Channel
  if (rightSpeed > 0) {
    analogWrite(RIGHT_RPWM, rightSpeed);
    analogWrite(RIGHT_LPWM, 0);
  } else if (rightSpeed < 0) {
    analogWrite(RIGHT_RPWM, 0);
    analogWrite(RIGHT_LPWM, abs(rightSpeed));
  } else {
    analogWrite(RIGHT_RPWM, 0);
    analogWrite(RIGHT_LPWM, 0);
  }
}

void stopMotors() {
  digitalWrite(LEFT_EN, LOW); 
  digitalWrite(RIGHT_EN, LOW);
  analogWrite(LEFT_RPWM, 0); 
  analogWrite(LEFT_LPWM, 0);
  analogWrite(RIGHT_RPWM, 0); 
  analogWrite(RIGHT_LPWM, 0);
}

void handleLineLostRecovery() {
  resetPID();

  // If lost near center (< 15 mm), assume a track gap/dashed line
  if (abs(lastValidErrorMm) < 15.0f) {
    uint32_t currentTicks = (encLeftTicks + encRightTicks) / 2;
    if (lineLostStartTick == 0) lineLostStartTick = currentTicks;

    // Drive forward using encoder distance dead-reckoning
    if ((currentTicks - lineLostStartTick) < GAP_BLIND_DISTANCE_TICKS) {
      setMotors(baseSpeed, baseSpeed);
      return;
    }
  }

  // If lost far to the side (> 15 mm), actively pivot back toward the line
  if (lastValidErrorMm > 0.0f) {
    // Line was on the right -> pivot right
    setMotors(baseSpeed, -baseSpeed / 2);
  } else {
    // Line was on the left -> pivot left
    setMotors(-baseSpeed / 2, baseSpeed);
  }
}

// =============================================================================
// 9. TELEMETRY & APP FEEDBACK
// =============================================================================
void sendTelemetry(float errorMm) {
  unsigned long now = millis();
  if (now - lastTelemetryTime < TELEMETRY_INTERVAL_MS) return;
  lastTelemetryTime = now;

  if (!deviceConnected || pTxChar == nullptr) return;

  TelemetryPacket packet;
  memcpy(packet.sensors, sensor8BitTelemetry, 12);
  packet.error_x100 = isLineLost ? 9990 : (int16_t)constrain((int)(errorMm * 100.0f), -32767, 32767);
  packet.status_flags = 0;
  if (motorsEnabled) packet.status_flags |= (1 << 0);
  if (isLineLost)    packet.status_flags |= (1 << 1);

  pTxChar->setValue((uint8_t*)&packet, sizeof(packet));
  pTxChar->notify();
}

void sendThresholdsToApp() {
  String payload = "THRESHOLDS:";
  for (int i = 0; i < 12; i++) {
    payload += String(sensorThresholds[i]);
    if (i < 11) payload += ",";
  }
  payload += "\n";
  if (deviceConnected && pTxChar != nullptr) {
    pTxChar->setValue((uint8_t*)payload.c_str(), payload.length());
    pTxChar->notify();
  }
}

void sendSensorMaskToApp() {
  String payload = "MASK:" + String(sensorMask) + "\n";
  if (deviceConnected && pTxChar != nullptr) {
    pTxChar->setValue((uint8_t*)payload.c_str(), payload.length());
    pTxChar->notify();
  }
}

// =============================================================================
// 10. SETUP & MAIN EXECUTION
// =============================================================================
unsigned long lastControlMicros = 0;
unsigned long lastDebugMs = 0;

void setup() {
  Serial.begin(115200);
  delay(100);

  // Motor Driver Pins
  pinMode(LEFT_EN, OUTPUT);    
  pinMode(LEFT_RPWM, OUTPUT);  
  pinMode(LEFT_LPWM, OUTPUT);
  pinMode(RIGHT_EN, OUTPUT);   
  pinMode(RIGHT_RPWM, OUTPUT); 
  pinMode(RIGHT_LPWM, OUTPUT);
  stopMotors();

  // Encoder Pins with Internal Pull-Ups
  pinMode(PIN_ENC_LEFT, INPUT_PULLUP);
  pinMode(PIN_ENC_RIGHT, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC_LEFT), isrLeftEncoder, FALLING);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC_RIGHT), isrRightEncoder, FALLING);

  // 12-Channel ADC Sensors
  for (int i = 0; i < 12; i++) {
    pinMode(IR_PINS[i], INPUT);
    sensorThresholds[i] = (int)defaultThreshold;
  }
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // BLE Communications
  initBLE();

  lastControlMicros = micros();
  Serial.println(F("[SYSTEM] Calibrated Arc Line Follower Initialized"));
}

void loop() {
  unsigned long nowMicros = micros();

  // --- DETERMINISTIC 333 Hz CONTROL LOOP (Every 3.0 ms) ---
  if (nowMicros - lastControlMicros >= CONTROL_INTERVAL_MICROS) {
    float dt = (nowMicros - lastControlMicros) / 1000000.0f;
    lastControlMicros = nowMicros;

    bool lineFound = readSensorArrayMetric();

    if (motorsEnabled) {
      if (!lineFound) {
        handleLineLostRecovery();
      } else {
        lineLostStartTick = 0; // Reset gap dead-reckoning counter
        float correction = computePID(currentErrorMm, dt);

        int leftSpeed  = baseSpeed + (int)correction;
        int rightSpeed = baseSpeed - (int)correction;
        setMotors(leftSpeed, rightSpeed);
      }
    } else {
      stopMotors();
      resetPID();
      lineLostStartTick = 0;
    }
  }

  // --- RATE-LIMITED BLE TELEMETRY (~22 Hz) ---
  if (deviceConnected) {
    sendTelemetry(currentErrorMm);
  }

  // --- DIAGNOSTIC LOGGING (10 Hz) ---
  unsigned long nowMs = millis();
  if (nowMs - lastDebugMs >= DEBUG_INTERVAL_MS) {
    lastDebugMs = nowMs;
    if (motorsEnabled) {
      Serial.printf("[RUN] Err: %5.1fmm | L_Tick: %u | R_Tick: %u | Lost: %d\n",
                    currentErrorMm, encLeftTicks, encRightTicks, isLineLost);
    }
  }
}