#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// =============================================================================
// 1. HARDWARE PINOUTS & PHYSICAL ARCHITECTURE (ESP32-S3 Mini)
// =============================================================================

// BTS7960 Dual High-Power H-Bridge Motor Driver
const int LEFT_EN    = 40;     
const int LEFT_RPWM  = 39;   
const int LEFT_LPWM  = 38;   
const int RIGHT_EN   = 3;     
const int RIGHT_RPWM = 42;  
const int RIGHT_LPWM = 41;  

// Tactile Control Buttons (Active-Low with internal pull-ups)
const int PIN_BTN_RUN = 9;  // Run / Stop toggle
const int PIN_BTN_CAL = 1;  // Auto-Calibrate sensor thresholds

// 12-Channel IR Reflectance Sensor Array (Direct ADC - No Multiplexer)
const int IR_PINS[12] = {4, 5, 6, 16, 15, 14, 17, 18, 13, 12, 11, 10};

// CAD-Extracted Physical X-Coordinates in mm (Relative to Robot Centerline)
const float SENSOR_X_MM[12] = {
  -52.52f, -46.01f, -36.47f, -25.97f, -15.58f, -5.27f,
    5.27f,  15.58f,  25.97f,  36.47f,  46.01f,  52.52f
};

// Optical Lookahead Distance (Wheel axis to sensor line)
const float LOOKAHEAD_DISTANCE_MM = 130.0f;

// Control Loop & Rate Timing
const unsigned long CONTROL_INTERVAL_MICROS = 3000; // 333.3 Hz (3000 µs)
const unsigned long TELEMETRY_INTERVAL_MS   = 45;   // ~22.2 Hz BLE
const unsigned long DEBUG_INTERVAL_MS       = 100;  // 10 Hz Serial

// =============================================================================
// 2. SYSTEM OPERATING MODES & STATE VARIABLES
// =============================================================================

enum RobotMode : uint8_t {
  MODE_IDLE = 0,
  MODE_LINE_FOLLOW_REACTIVE = 1
};

volatile RobotMode currentMode = MODE_IDLE;

// Steering PID Tuning Gains (Units: mm error -> PWM correction)
float Kp = 2.5f;           // Proportional gain (PWM per mm offset)
float Ki = 0.0f;           // Integral gain
float Kd = 0.08f;          // Derivative gain (PWM per (mm/s))
float dFilterAlpha = 0.70f; // 1st-order Low-Pass filter constant for D term

// Throttle Limits & Stiction Deadband Compensation
int baseSpeed = 70;        // Nominal straight line PWM (0-255)
int maxSpeed  = 120;       // Velocity ceiling
int minSpeed  = 30;        // Deadband compensation for BTS7960
bool invertSteering = false;

// Steering Authority Clamp (prevents inside-wheel spinout)
const float MAX_STEERING_CORRECTION = 75.0f;

// Sensor Thresholds (12-bit ADC: 0-4095) & Bitmask
int sensorThresholds[12];
uint16_t sensorMask = 0x0BFD;
float defaultThreshold = 2000.0f;

// Operational Flags & Metrics
bool motorsEnabled = false;
bool isLineLost = false;
float currentErrorMm = 0.0f;
float lastValidErrorMm = 0.0f;
unsigned long lastTelemetryTime = 0;

// Button Debounce State
unsigned long lastRunBtnPress = 0;
unsigned long lastCalBtnPress = 0;
const unsigned long BUTTON_DEBOUNCE_MS = 250;

// Forward Declarations
void setMotors(int leftSpeed, int rightSpeed);
void stopMotors();
void brakeMotors();
void dynamicBrake();
void triggerActiveBrake();
void releaseBrake();
void updateBrakingStateMachine();
void runControlLoopStep(float dt);
void resetPID();
float computePID(float errorMm, float dt);
bool readSensorArrayMetric();
void handleLineLostRecovery();
void sendTelemetry(float errorMm);
void sendThresholdsToApp();
void sendSensorMaskToApp();
void sendBleMessage(const String& msg);
void handleCommand(String rxValue);
void runAutoCalibration();

// =============================================================================
// 3. BLE STACK (NORDIC UART SERVICE)
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
  int16_t error_x100;   // Error in mm * 100 (-5252 to +5252, or 9990 when lost)
  uint8_t status_flags; // Bit 0: Enabled, Bit 1: Line Lost, Bits 4..7: Mode
};
#pragma pack(pop)

SemaphoreHandle_t bleMutex = nullptr;

class ServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServerInstance) override { 
    deviceConnected = true;
    pServerInstance->updateConnParams(pServerInstance->getConnId(), 16, 24, 0, 400);
  }
  void onDisconnect(BLEServer* pServerInstance) override { 
    deviceConnected = false; 
    motorsEnabled = false;
    currentMode = MODE_IDLE;
    triggerActiveBrake(); 
    pServerInstance->getAdvertising()->start();
  }
};

// =============================================================================
// 4. STREAM FRAMING & BLE COMMAND DISPATCHER
// =============================================================================

const size_t RX_STREAM_BUFFER_SIZE = 256;
char rxStreamBuffer[RX_STREAM_BUFFER_SIZE];
size_t rxStreamBufferLen = 0;

static inline bool isNumericStart(char c) {
  return (c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.';
}

void processRxStream(const uint8_t* data, size_t length) {
  for (size_t i = 0; i < length; i++) {
    char c = (char)data[i];
    if (c == '\n' || c == '\r') {
      if (rxStreamBufferLen > 0) {
        rxStreamBuffer[rxStreamBufferLen] = '\0';
        handleCommand(String(rxStreamBuffer));
        rxStreamBufferLen = 0;
      }
    } else {
      if (rxStreamBufferLen < RX_STREAM_BUFFER_SIZE - 1) {
        rxStreamBuffer[rxStreamBufferLen++] = c;
      } else {
        rxStreamBuffer[rxStreamBufferLen] = '\0';
        sendBleMessage("ERR:BUFFER_OVERFLOW\n");
        rxStreamBufferLen = 0;
      }
    }
  }
}

class RxCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    String val = pCharacteristic->getValue().c_str();
    if (val.length() > 0) {
      processRxStream((const uint8_t*)val.c_str(), val.length());
    }
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
  pAdv->setMinPreferred(0x10); // 20 ms
  pAdv->setMaxPreferred(0x20); // 40 ms
  BLEDevice::startAdvertising();
}

void sendBleMessage(const String& msg) {
  if (deviceConnected && pTxChar != nullptr) {
    if (bleMutex && xSemaphoreTake(bleMutex, pdMS_TO_TICKS(20)) == pdTRUE) {
      pTxChar->setValue((uint8_t*)msg.c_str(), msg.length());
      pTxChar->notify();
      xSemaphoreGive(bleMutex);
    }
  }
}

void handleCommand(String rx) {
  rx.trim();
  while (rx.endsWith("\r") || rx.endsWith("\n")) { 
    rx.remove(rx.length() - 1); 
    rx.trim(); 
  }
  if (rx.length() == 0) return;

  // 1. Exact Match Control Commands
  if (rx.equalsIgnoreCase("S") && rx.length() == 1) {
    motorsEnabled = !motorsEnabled;
    if (!motorsEnabled) {
      currentMode = MODE_IDLE;
      triggerActiveBrake();
      resetPID();
      sendBleMessage("ACK:RUN=0\n");
    } else {
      releaseBrake();
      currentMode = MODE_LINE_FOLLOW_REACTIVE;
      resetPID();
      sendBleMessage("ACK:RUN=1\n");
    }
    return;
  }

  if (rx == "RUN=1" || rx == "ROBOT,START") { 
    releaseBrake();
    currentMode = MODE_LINE_FOLLOW_REACTIVE;
    motorsEnabled = true; 
    resetPID();
    sendBleMessage("ACK:RUN=1\n");
    return; 
  }

  if (rx == "RUN=0" || rx == "ROBOT,STOP") { 
    currentMode = MODE_IDLE;
    motorsEnabled = false; 
    triggerActiveBrake();
    resetPID();
    sendBleMessage("ACK:RUN=0\n");
    return; 
  }

  if (rx == "CALIB" || rx == "CAL=AUTO") {
    currentMode = MODE_IDLE;
    motorsEnabled = false;
    triggerActiveBrake();
    runAutoCalibration();
    return;
  }

  // 2. Query Commands
  if (rx == "THRESH?") { sendThresholdsToApp(); return; }
  if (rx == "MASK?" || rx == "SENS?") { sendSensorMaskToApp(); return; }
  if (rx == "KP?")   { sendBleMessage("ACK:KP=" + String(Kp, 2) + "\n"); return; }
  if (rx == "KI?")   { sendBleMessage("ACK:KI=" + String(Ki, 2) + "\n"); return; }
  if (rx == "KD?")   { sendBleMessage("ACK:KD=" + String(Kd, 2) + "\n"); return; }
  if (rx == "BASE?") { sendBleMessage("ACK:BASE=" + String(baseSpeed) + "\n"); return; }
  if (rx == "MAX?")  { sendBleMessage("ACK:MAX=" + String(maxSpeed) + "\n"); return; }
  if (rx == "MIN?")  { sendBleMessage("ACK:MIN=" + String(minSpeed) + "\n"); return; }
  if (rx == "INV?")  { sendBleMessage("ACK:INV=" + String(invertSteering ? 1 : 0) + "\n"); return; }
  if (rx == "CONFIG?" || rx == "STATE?") {
    sendBleMessage("ACK:CONFIG=KP:" + String(Kp, 2) + ",KI:" + String(Ki, 2) + ",KD:" + String(Kd, 2) +
                   ",BASE:" + String(baseSpeed) + ",MAX:" + String(maxSpeed) + ",MIN:" + String(minSpeed) +
                   ",INV:" + String(invertSteering ? 1 : 0) + "\n");
    return;
  }

  // 3. Explicit Multi-Character Assignments
  if (rx.startsWith("THRALL=")) {
    float val = rx.substring(7).toFloat();
    if (val <= 255.0f && val > 0.0f) val *= 16.0f;
    int clamped = (int)constrain(val, 50.0f, 4095.0f);
    defaultThreshold = (float)clamped;
    for (int i = 0; i < 12; i++) sensorThresholds[i] = clamped;
    sendBleMessage("ACK:THRALL=" + String(clamped) + "\n");
    sendThresholdsToApp();
    return;
  }

  if (rx.startsWith("THR=")) {
    int comma = rx.indexOf(',');
    if (comma != -1) {
      int idx = rx.substring(4, comma).toInt();
      float val = rx.substring(comma + 1).toFloat();
      if (val <= 255.0f && val > 0.0f) val *= 16.0f;
      if (idx >= 0 && idx < 12) {
        sensorThresholds[idx] = (int)constrain(val, 50.0f, 4095.0f);
        sendBleMessage("ACK:THR=" + String(idx) + "," + String(sensorThresholds[idx]) + "\n");
        sendThresholdsToApp();
        return;
      }
    }
    sendBleMessage("ERR:INVALID_PARAM=THR\n");
    return;
  }

  if (rx.startsWith("MASK=")) {
    sensorMask = (uint16_t)rx.substring(5).toInt();
    sendBleMessage("ACK:MASK=" + String(sensorMask) + "\n");
    sendSensorMaskToApp();
    return;
  }

  if (rx.startsWith("KP=")) {
    Kp = rx.substring(3).toFloat();
    sendBleMessage("ACK:KP=" + String(Kp, 2) + "\n");
    return;
  }

  if (rx.startsWith("KI=")) {
    Ki = rx.substring(3).toFloat();
    sendBleMessage("ACK:KI=" + String(Ki, 2) + "\n");
    return;
  }

  if (rx.startsWith("KD=")) {
    Kd = rx.substring(3).toFloat();
    sendBleMessage("ACK:KD=" + String(Kd, 2) + "\n");
    return;
  }

  if (rx.startsWith("BASE=")) {
    baseSpeed = constrain(rx.substring(5).toInt(), 0, 255);
    sendBleMessage("ACK:BASE=" + String(baseSpeed) + "\n");
    return;
  }

  if (rx.startsWith("MAX=")) {
    maxSpeed = constrain(rx.substring(4).toInt(), 0, 255);
    sendBleMessage("ACK:MAX=" + String(maxSpeed) + "\n");
    return;
  }

  if (rx.startsWith("MIN=")) {
    minSpeed = constrain(rx.substring(4).toInt(), 0, 255);
    sendBleMessage("ACK:MIN=" + String(minSpeed) + "\n");
    return;
  }

  if (rx.startsWith("INV=")) {
    invertSteering = (rx.substring(4).toInt() != 0);
    sendBleMessage("ACK:INV=" + String(invertSteering ? 1 : 0) + "\n");
    return;
  }

  // 4. Guarded Single-Character Aliases
  if (rx.length() >= 2 && rx[0] == 'P' && isNumericStart(rx[1])) {
    Kp = rx.substring(1).toFloat();
    sendBleMessage("ACK:KP=" + String(Kp, 2) + "\n");
    return;
  }

  if (rx.length() >= 2 && rx[0] == 'I' && isNumericStart(rx[1])) {
    Ki = rx.substring(1).toFloat();
    sendBleMessage("ACK:KI=" + String(Ki, 2) + "\n");
    return;
  }

  if (rx.length() >= 2 && rx[0] == 'D' && isNumericStart(rx[1])) {
    Kd = rx.substring(1).toFloat();
    sendBleMessage("ACK:KD=" + String(Kd, 2) + "\n");
    return;
  }

  if (rx.length() >= 2 && rx[0] == 'M' && isNumericStart(rx[1])) {
    maxSpeed = constrain(rx.substring(1).toInt(), 0, 255);
    sendBleMessage("ACK:MAX=" + String(maxSpeed) + "\n");
    return;
  }

  if (rx.length() >= 2 && rx[0] == 'B' && isNumericStart(rx[1])) {
    baseSpeed = constrain(rx.substring(1).toInt(), 0, 255);
    sendBleMessage("ACK:BASE=" + String(baseSpeed) + "\n");
    return;
  }

  if (rx.length() >= 2 && rx[0] == 'T' && isNumericStart(rx[1])) {
    float val = rx.substring(1).toFloat();
    if (val <= 255.0f && val > 0.0f) val *= 16.0f;
    int clamped = (int)constrain(val, 50.0f, 4095.0f);
    defaultThreshold = (float)clamped;
    for (int i = 0; i < 12; i++) sensorThresholds[i] = clamped;
    sendBleMessage("ACK:THRALL=" + String(clamped) + "\n");
    sendThresholdsToApp();
    return;
  }

  // 5. Unrecognized / Malformed Command Fallback
  sendBleMessage("ERR:UNKNOWN_CMD=" + rx + "\n");
}

// =============================================================================
// 5. METRIC SENSOR ACQUISITION & CENTROID CALCULATION
// =============================================================================

uint8_t sensor8BitTelemetry[12];

bool readSensorArrayMetric() {
  float sumX = 0.0f;
  int activeCount = 0;

  for (int i = 0; i < 12; i++) {
    int raw = analogRead(IR_PINS[i]);
    sensor8BitTelemetry[i] = (uint8_t)(raw >> 4);

    bool isMasked = (sensorMask & (1 << i)) != 0;

    if (isMasked && raw > sensorThresholds[i]) {
      sumX += SENSOR_X_MM[i];
      activeCount++;
    }
  }

  if (activeCount == 0) {
    isLineLost = true;
    return false;
  }

  isLineLost = false;
  float calculatedError = sumX / (float)activeCount; // Result in true mm

  // Center deadband: snap microscopic analog noise to center
  if (abs(calculatedError) < 2.0f) {
    calculatedError = 0.0f;
  }
  currentErrorMm = invertSteering ? -calculatedError : calculatedError;
  lastValidErrorMm = currentErrorMm;
  return true;
}

// =============================================================================
// 6. CORE PID CONTROLLER WITH FILTERED DERIVATIVE
// =============================================================================

float pidIntegral = 0.0f;
float pidPrevError = 0.0f;
float pidFilteredD = 0.0f;

float computePID(float errorMm, float dt) {
  // Proportional Term
  float P = errorMm * Kp;

  // Integral Term with Anti-Windup Clamping
  pidIntegral += (errorMm * dt);
  pidIntegral = constrain(pidIntegral, -100.0f, 100.0f);
  float I = pidIntegral * Ki;

  // Filtered Derivative Term (1st-Order Low-Pass Filter)
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
// 7. MOTOR CONTROL & ACTIVE / DYNAMIC BRAKING
// =============================================================================

enum BrakeState : uint8_t {
  BRAKE_INACTIVE = 0,
  BRAKE_PLUGGING,   // Active reverse counter-torque burst
  BRAKE_LOCKED      // Low-side MOSFET clamp to ground
};

volatile BrakeState activeBrakeState = BRAKE_LOCKED;
unsigned long brakeStartTimeMicros = 0;

// Configurable Active Braking Parameters
const unsigned long PLUG_BRAKE_DURATION_MICROS = 25000; // 25 ms reverse burst
const int PLUG_BRAKE_PWM = 180;                         // Reverse torque duty cycle (0-255)

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

  // Left Motor Channel
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

  // Right Motor Channel
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

// Coasting Stop (Disable drivers)
void stopMotors() {
  digitalWrite(LEFT_EN, LOW); 
  digitalWrite(RIGHT_EN, LOW);
  analogWrite(LEFT_RPWM, 0); 
  analogWrite(LEFT_LPWM, 0);
  analogWrite(RIGHT_RPWM, 0); 
  analogWrite(RIGHT_LPWM, 0);
}

// Low-Side Dynamic Brake (Short motor terminals to GND through low-side FETs)
void dynamicBrake() {
  digitalWrite(LEFT_EN, HIGH); 
  digitalWrite(RIGHT_EN, HIGH);
  analogWrite(LEFT_RPWM, 0); 
  analogWrite(LEFT_LPWM, 0);
  analogWrite(RIGHT_RPWM, 0); 
  analogWrite(RIGHT_LPWM, 0);
}

void brakeMotors() {
  dynamicBrake();
}

// Non-blocking trigger called when stopping or when emergency braking is needed
void triggerActiveBrake() {
  if (activeBrakeState == BRAKE_INACTIVE) {
    activeBrakeState = BRAKE_PLUGGING;
    brakeStartTimeMicros = micros();
  }
}

// Service function executed at the 333 Hz rate inside runControlLoopStep()
void updateBrakingStateMachine() {
  if (activeBrakeState == BRAKE_INACTIVE) return;

  unsigned long now = micros();

  if (activeBrakeState == BRAKE_PLUGGING) {
    // Check if the 25ms reverse counter-torque phase has elapsed
    if (now - brakeStartTimeMicros < PLUG_BRAKE_DURATION_MICROS) {
      digitalWrite(LEFT_EN, HIGH);
      digitalWrite(RIGHT_EN, HIGH);

      // Apply reverse polarity across BTS7960
      analogWrite(LEFT_RPWM, 0);
      analogWrite(LEFT_LPWM, PLUG_BRAKE_PWM);
      analogWrite(RIGHT_RPWM, 0);
      analogWrite(RIGHT_LPWM, PLUG_BRAKE_PWM);
    } else {
      // Counter-torque complete: clamp to low-side dynamic brake to prevent reversing
      dynamicBrake();
      activeBrakeState = BRAKE_LOCKED;
    }
  } else if (activeBrakeState == BRAKE_LOCKED) {
    dynamicBrake();
  }
}

// Release brake when motors are commanded to drive again
void releaseBrake() {
  activeBrakeState = BRAKE_INACTIVE;
}

// Pure optical search pivot recovery
void handleLineLostRecovery() {
  resetPID();

  // Actively pivot back toward the last known line direction
  if (lastValidErrorMm > 0.0f) {
    // Line was on the right -> pivot right
    setMotors(baseSpeed, -baseSpeed);
  } else {
    // Line was on the left -> pivot left
    setMotors(-baseSpeed, baseSpeed);
  }
}

// Auto-Calibration: samples active reflectance to set dynamic baseline thresholds
void runAutoCalibration() {
  sendBleMessage("ACK:CALIB_START\n");
  int minVals[12];
  int maxVals[12];
  for (int i = 0; i < 12; i++) {
    minVals[i] = 4095;
    maxVals[i] = 0;
  }

  // Sample across 30 readings
  for (int sample = 0; sample < 30; sample++) {
    for (int i = 0; i < 12; i++) {
      int raw = analogRead(IR_PINS[i]);
      if (raw < minVals[i]) minVals[i] = raw;
      if (raw > maxVals[i]) maxVals[i] = raw;
    }
    delay(15);
  }

  // Calculate midpoints with safety bounds
  for (int i = 0; i < 12; i++) {
    int mid = (minVals[i] + maxVals[i]) / 2;
    if (maxVals[i] - minVals[i] < 300) {
      sensorThresholds[i] = (int)defaultThreshold;
    } else {
      sensorThresholds[i] = constrain(mid, 200, 3800);
    }
  }

  sendBleMessage("ACK:CALIB\n");
  sendThresholdsToApp();
}

// =============================================================================
// 8. TELEMETRY & COMPANION APP FEEDBACK
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
  packet.status_flags |= ((uint8_t)currentMode << 4);

  if (bleMutex && xSemaphoreTake(bleMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
    pTxChar->setValue((uint8_t*)&packet, sizeof(packet));
    pTxChar->notify();
    xSemaphoreGive(bleMutex);
  }
}

void sendThresholdsToApp() {
  String payload = "THRESHOLDS:";
  for (int i = 0; i < 12; i++) {
    payload += String(sensorThresholds[i]);
    if (i < 11) payload += ",";
  }
  payload += "\n";
  sendBleMessage(payload);
}

void sendSensorMaskToApp() {
  String payload = "MASK:" + String(sensorMask) + "\n";
  sendBleMessage(payload);
}

// =============================================================================
// 9. FREERTOS CONTROL TASK & INITIALIZATION
// =============================================================================

TaskHandle_t controlTaskHandle = NULL;
unsigned long lastDebugMs = 0;

void runControlLoopStep(float dt) {
  // 1. ALWAYS read sensors every loop cycle so telemetry stays live in IDLE mode!
  bool lineFound = readSensorArrayMetric();

  // 2. If actively braking, service the braking state machine and exit
  if (activeBrakeState != BRAKE_INACTIVE) {
    updateBrakingStateMachine();
    return;
  }

  // 3. If motors are disabled (STOP command or Emergency Button), engage active brake
  if (!motorsEnabled) {
    triggerActiveBrake();
    resetPID();
    return;
  }

  // 4. Normal Reactive Driving
  if (!lineFound) {
    handleLineLostRecovery();
  } else {
    // Normal PID steering...
    float rawCorrection = computePID(currentErrorMm, dt);
    // Steering correction clamped [-75.0, +75.0] to prevent inside-wheel spinout
    float clampedCorrection = constrain(rawCorrection, -MAX_STEERING_CORRECTION, MAX_STEERING_CORRECTION);
    int leftSpeed  = baseSpeed + (int)clampedCorrection;
    int rightSpeed = baseSpeed - (int)clampedCorrection;
    setMotors(leftSpeed, rightSpeed);
  }
}

void vControlLoopTask(void *pvParameters) {
  (void)pvParameters;
  TickType_t xLastWakeTime = xTaskGetTickCount();
  const TickType_t xFrequency = pdMS_TO_TICKS(3); // 3 ms period (~333.3 Hz)
  unsigned long lastTimeMicros = micros();

  for (;;) {
    vTaskDelayUntil(&xLastWakeTime, xFrequency);

    unsigned long nowMicros = micros();
    float dt = (nowMicros - lastTimeMicros) / 1000000.0f;
    if (dt <= 0.0f || dt > 0.05f) dt = 0.003f;
    lastTimeMicros = nowMicros;

    runControlLoopStep(dt);
  }
}

void setup() {
  Serial.begin(115200);
  delay(100);

  // Initialize BLE Mutex for Thread Safety across cores
  bleMutex = xSemaphoreCreateMutex();

  // Motor Driver Pins
  pinMode(LEFT_EN, OUTPUT);    
  pinMode(LEFT_RPWM, OUTPUT);  
  pinMode(LEFT_LPWM, OUTPUT);
  pinMode(RIGHT_EN, OUTPUT);   
  pinMode(RIGHT_RPWM, OUTPUT); 
  pinMode(RIGHT_LPWM, OUTPUT);
  dynamicBrake();

  // Tactile Buttons with Internal Pull-Ups
  pinMode(PIN_BTN_RUN, INPUT_PULLUP);
  pinMode(PIN_BTN_CAL, INPUT_PULLUP);

  // 12-Channel ADC Sensors
  for (int i = 0; i < 12; i++) {
    pinMode(IR_PINS[i], INPUT);
    sensorThresholds[i] = (int)defaultThreshold;
  }
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // BLE Stack (Core 0)
  initBLE();

  // Pin Deterministic 333 Hz Real-Time Control Loop strictly to Core 1 (APP CPU)
  xTaskCreatePinnedToCore(
    vControlLoopTask,
    "ControlLoopTask",
    4096,
    NULL,
    10,               // High priority for microsecond-level determinism
    &controlTaskHandle,
    1                 // Core 1
  );

  Serial.println(F("[SYSTEM] ESP32-S3 Pure Optical Line Follower Ready: Core 0 [BLE], Core 1 [333Hz Control]."));
}

void loop() {
  // --- TACTILE BUTTON POLLING & DEBOUNCING ---
  unsigned long nowMs = millis();

  // 1. Run/Stop Toggle Button (GPIO 9)
  if (digitalRead(PIN_BTN_RUN) == LOW) {
    if (nowMs - lastRunBtnPress >= BUTTON_DEBOUNCE_MS) {
      lastRunBtnPress = nowMs;
      motorsEnabled = !motorsEnabled;
      if (motorsEnabled) {
        releaseBrake();
        currentMode = MODE_LINE_FOLLOW_REACTIVE;
        resetPID();
        sendBleMessage("ACK:RUN=1\n");
      } else {
        currentMode = MODE_IDLE;
        triggerActiveBrake();
        resetPID();
        sendBleMessage("ACK:RUN=0\n");
      }
    }
  }

  // 2. Auto-Calibrate Button (GPIO 1)
  if (digitalRead(PIN_BTN_CAL) == LOW) {
    if (nowMs - lastCalBtnPress >= BUTTON_DEBOUNCE_MS) {
      lastCalBtnPress = nowMs;
      bool wasRunning = motorsEnabled;
      motorsEnabled = false;
      triggerActiveBrake();
      runAutoCalibration();
      if (wasRunning) {
        releaseBrake();
        motorsEnabled = true;
        currentMode = MODE_LINE_FOLLOW_REACTIVE;
      }
    }
  }

  // --- RATE-LIMITED BLE TELEMETRY (~22.2 Hz) ---
  if (deviceConnected) {
    sendTelemetry(currentErrorMm);
  }

  // --- DIAGNOSTIC LOGGING (10 Hz) ---
  if (nowMs - lastDebugMs >= DEBUG_INTERVAL_MS) {
    lastDebugMs = nowMs;
    if (motorsEnabled) {
      Serial.printf("[RUN] Mode: %d | Err: %5.1fmm | Lost: %d\n",
                    (int)currentMode, currentErrorMm, isLineLost);
    }
  }

  // Yield to FreeRTOS IDLE task to feed Task Watchdog (TWDT)
  vTaskDelay(pdMS_TO_TICKS(5));
}