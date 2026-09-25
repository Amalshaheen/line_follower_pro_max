#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================
void stopMotors();
void setMotors(int leftSpeed, int rightSpeed);
float readLineError();
void sendTelemetry(float error);
void handleCommand(String rxValue);
void sendThresholdsToApp();

// =============================================================================
// MOTOR PIN DEFINITIONS (ESP32-S3 Mini) - STRICTLY PRESERVED
// =============================================================================
const int LEFT_EN    = 40;     
const int LEFT_RPWM  = 39;   
const int LEFT_LPWM  = 38;   
const int RIGHT_EN   = 3;     
const int RIGHT_RPWM = 42;  
const int RIGHT_LPWM = 41;  

// =============================================================================
// 12 IR SENSOR PIN DEFINITIONS (Direct ADC) - STRICTLY PRESERVED
// =============================================================================
const int IR_PINS[12] = {4, 5, 6, 16, 15, 14, 17, 18, 13, 12, 11, 10};
int sensorAnalogValues[12]; 
bool isLineDetected[12];    
uint8_t sensor8BitValues[12]; // Option A downscaled (0–255)
int sensorThresholds[12];     // Per-sensor 12-bit ADC threshold (0–4095)

// =============================================================================
// PID & SPEED & STEERING CONFIGURATION
// =============================================================================
float Kp = 50.0;
float Ki = 0.0;
float Kd = 0.0;

// Speed Control Decoupling:
// - baseSpeed: Cruising forward speed in straight line (0–255)
// - maxSpeed:  Upper PWM saturation ceiling for outside wheel (0–255)
// - minSpeed:  Deadband compensation threshold to overcome motor stiction (0–255)
int baseSpeed = 100;
int maxSpeed  = 255;
int minSpeed  = 0;     // Set to e.g. 25-40 if motors stall at low PWM

// Threshold Configuration (12-bit ADC: 0-4095)
// Black line ~3000-4095, White surface ~0-800. Default 2000 is mid-scale.
float thresholdT = 2000.0; 

// Steering Polarity Inversion:
// - FALSE (Default): Sensor 0 = Left, Sensor 11 = Right. Line on right -> Robot steers right.
// - TRUE: Inverted physical mounting / sensor wiring. Flip via "INV=1" over BLE.
bool invertSteering = false;

// PID Runtime State
float previousError = 0.0;
float integral = 0.0;
bool motorsEnabled = false;

// =============================================================================
// TIMERS (Telemetry ~22 Hz, Diagnostics 10 Hz)
// =============================================================================
unsigned long lastTelemetryTime = 0;
const int TELEMETRY_INTERVAL = 45; // ~22 Hz non-blocking

unsigned long lastDebugTime = 0;
const int DEBUG_INTERVAL = 100;    // 10 Hz diagnostic logging

// =============================================================================
// PACKED BINARY TELEMETRY PACKET (EXACTLY 15 BYTES)
// =============================================================================
#pragma pack(push, 1)
struct TelemetryPacket {
  uint8_t sensors[12];  // 12 bytes: 8-bit analog reflectance per sensor (0–255)
  int16_t error_x100;   // 2 bytes: (int16_t)(error * 100.0f) or 9990 if line lost
  uint8_t status_flags; // 1 byte: Bit 0 = motorsEnabled, Bit 1 = lineLost (error == 999.0f)
};
#pragma pack(pop)

// =============================================================================
// BLE UART UUIDs (Nordic UART Service - NUS)
// =============================================================================
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer *pServer = nullptr;
BLECharacteristic *pTxCharacteristic = nullptr;
BLECharacteristic *pRxCharacteristic = nullptr;
bool deviceConnected = false;

// =============================================================================
// BLE CONNECTION CALLBACKS
// =============================================================================
class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override { 
    deviceConnected = true; 
    Serial.println(F(">>> BLE Connected!")); 
  }
  
  void onDisconnect(BLEServer* pServer) override { 
    deviceConnected = false; 
    Serial.println(F(">>> BLE Disconnected!")); 
    stopMotors(); 
    motorsEnabled = false;
    pServer->getAdvertising()->start();
  }
};

// =============================================================================
// BLE MESSAGE RECEPTION & COMMAND PARSING
// =============================================================================
class MyCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    String rxValue = pCharacteristic->getValue().c_str();
    handleCommand(rxValue);
  }
};

void handleCommand(String rxValue) {
  rxValue.trim();
  // Strip trailing carriage return or newline
  while (rxValue.endsWith("\r") || rxValue.endsWith("\n")) {
    rxValue.remove(rxValue.length() - 1);
    rxValue.trim();
  }
  
  if (rxValue.length() == 0) return;

  Serial.print(F("BLE RX Command: "));
  Serial.println(rxValue);

  // 1. Single-character command: Toggle Run/Stop
  if (rxValue.equalsIgnoreCase("S")) {
    motorsEnabled = !motorsEnabled;
    if (!motorsEnabled) {
      stopMotors();
      integral = 0;
      previousError = 0;
    }
    Serial.printf("Motors Enabled: %d\n", motorsEnabled);
    return;
  }

  // 2. Start / Stop explicit commands
  if (rxValue == "RUN=1" || rxValue == "ROBOT,START") {
    motorsEnabled = true;
    Serial.println(F("Motors Started via RUN=1 / ROBOT,START"));
    return;
  } 
  if (rxValue == "RUN=0" || rxValue == "ROBOT,STOP") {
    motorsEnabled = false;
    stopMotors();
    integral = 0;
    previousError = 0;
    Serial.println(F("Motors Stopped via RUN=0 / ROBOT,STOP"));
    return;
  }

  // 3. Status queries (safe from prefix collision)
  if (rxValue == "THRESH?") {
    sendThresholdsToApp();
    return;
  }
  if (rxValue == "TIME?") {
    Serial.printf("TIME=%lu\n", millis());
    return;
  }

  // 4. Steering Polarity Inversion
  if (rxValue.startsWith("INV=")) {
    invertSteering = (rxValue.substring(4).toInt() != 0);
    Serial.printf("Invert Steering set to: %d\n", invertSteering);
    return;
  }
  if (rxValue.equalsIgnoreCase("INV") || rxValue.equalsIgnoreCase("INVERT")) {
    invertSteering = !invertSteering;
    Serial.printf("Invert Steering toggled to: %d\n", invertSteering);
    return;
  }

  // 5. Compound commands: S,B,<val> and S,M,<val>
  if (rxValue.startsWith("S,B,") || rxValue.startsWith("S,b,")) {
    baseSpeed = constrain(rxValue.substring(4).toInt(), 0, 255);
    Serial.printf("BaseSpeed set to: %d\n", baseSpeed);
    return;
  }
  if (rxValue.startsWith("S,M,") || rxValue.startsWith("S,m,")) {
    maxSpeed = constrain(rxValue.substring(4).toInt(), 0, 255);
    Serial.printf("MaxSpeed set to: %d\n", maxSpeed);
    return;
  }

  // 6. Compound PID: P,<kp>,<ki>
  if (rxValue.startsWith("P,") || rxValue.startsWith("p,")) {
    int commaIndex = rxValue.indexOf(',', 2);
    if (commaIndex != -1) {
      Kp = rxValue.substring(2, commaIndex).toFloat();
      Ki = rxValue.substring(commaIndex + 1).toFloat();
      Serial.printf("Compound PID set: Kp=%.2f, Ki=%.2f\n", Kp, Ki);
    } else {
      Kp = rxValue.substring(2).toFloat();
      Serial.printf("Kp set to: %.2f\n", Kp);
    }
    return;
  }

  // 7. Explicit prefix commands (KP=, KI=, KD=, BASE=, MAX=, MIN=, THRALL=, THR=)
  if (rxValue.startsWith("KP=")) {
    Kp = rxValue.substring(3).toFloat();
    Serial.printf("Kp set to: %.2f\n", Kp);
    return;
  } 
  if (rxValue.startsWith("KI=")) {
    Ki = rxValue.substring(3).toFloat();
    Serial.printf("Ki set to: %.2f\n", Ki);
    return;
  } 
  if (rxValue.startsWith("KD=")) {
    Kd = rxValue.substring(3).toFloat();
    Serial.printf("Kd set to: %.2f\n", Kd);
    return;
  } 
  if (rxValue.startsWith("BASE=")) {
    baseSpeed = constrain(rxValue.substring(5).toInt(), 0, 255);
    Serial.printf("BaseSpeed set to: %d\n", baseSpeed);
    return;
  } 
  if (rxValue.startsWith("MAX=")) {
    maxSpeed = constrain(rxValue.substring(4).toInt(), 0, 255);
    Serial.printf("MaxSpeed set to: %d\n", maxSpeed);
    return;
  } 
  if (rxValue.startsWith("MIN=")) {
    minSpeed = constrain(rxValue.substring(4).toInt(), 0, 255);
    Serial.printf("MinSpeed (deadband) set to: %d\n", minSpeed);
    return;
  } 
  if (rxValue.startsWith("THRALL=")) {
    float val = rxValue.substring(7).toFloat();
    if (val <= 255.0f && val > 0.0f) val *= 16.0f; // Scale 8-bit to 12-bit if needed
    if (val > 0.0f) {
      thresholdT = constrain(val, 100.0f, 4000.0f);
      for (int i = 0; i < 12; i++) {
        sensorThresholds[i] = (int)thresholdT;
      }
      Serial.printf("All Thresholds set to: %.1f\n", thresholdT);
      sendThresholdsToApp();
    }
    return;
  }
  if (rxValue.startsWith("THR=")) {
    int comma = rxValue.indexOf(',');
    if (comma != -1) {
      int idx = rxValue.substring(4, comma).toInt();
      float val = rxValue.substring(comma + 1).toFloat();
      if (val <= 255.0f && val > 0.0f) val *= 16.0f;
      if (idx >= 0 && idx < 12 && val > 0.0f) {
        sensorThresholds[idx] = (int)constrain(val, 100.0f, 4000.0f);
        Serial.printf("Sensor %d threshold set to: %d\n", idx, sensorThresholds[idx]);
      }
    }
    return;
  }

  // 8. Concise single-letter prefix commands (P, I, D, B, M, T)
  // Ensure the parameter begins with a numeric character (+, -, or digit)
  char firstChar = toupper(rxValue.charAt(0));
  String param = rxValue.substring(1);
  param.trim();

  if (param.length() == 0) return;
  char firstParamChar = param.charAt(0);
  if (!isDigit(firstParamChar) && firstParamChar != '-' && firstParamChar != '+') {
    Serial.printf("Ignored non-numeric command: %s\n", rxValue.c_str());
    return;
  }

  float val = param.toFloat();
  switch (firstChar) {
    case 'P':
      Kp = val;
      Serial.printf("Kp: %.2f\n", Kp);
      break;
    case 'I':
      Ki = val;
      Serial.printf("Ki: %.2f\n", Ki);
      break;
    case 'D':
      Kd = val;
      Serial.printf("Kd: %.2f\n", Kd);
      break;
    case 'B':
      baseSpeed = constrain((int)val, 0, 255);
      Serial.printf("BaseSpeed: %d\n", baseSpeed);
      break;
    case 'M':
      maxSpeed = constrain((int)val, 0, 255);
      Serial.printf("MaxSpeed: %d\n", maxSpeed);
      break;
    case 'T':
      // Support 8-bit (0–255) or 12-bit (0–4095) thresholds; ignore non-positive numbers
      if (val > 0.0f) {
        if (val <= 255.0f) {
          thresholdT = val * 16.0f;
        } else {
          thresholdT = val;
        }
        thresholdT = constrain(thresholdT, 100.0f, 4000.0f);
        for (int i = 0; i < 12; i++) {
          sensorThresholds[i] = (int)thresholdT;
        }
        Serial.printf("ThresholdT set to: %.1f\n", thresholdT);
        sendThresholdsToApp();
      }
      break;
    default:
      Serial.printf("Unknown command letter '%c'\n", firstChar);
      break;
  }
}

// =============================================================================
// SEND THRESHOLDS OVER BLE / SERIAL
// =============================================================================
void sendThresholdsToApp() {
  String payload = "THRESHOLDS:";
  for (int i = 0; i < 12; i++) {
    payload += String(sensorThresholds[i]);
    if (i < 11) payload += ",";
  }
  payload += "\n";
  Serial.print(payload);

  if (deviceConnected && pTxCharacteristic != nullptr) {
    pTxCharacteristic->setValue((uint8_t*)payload.c_str(), payload.length());
    pTxCharacteristic->notify();
  }
}

// =============================================================================
// SETUP
// =============================================================================
void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println(F("\n=============================================="));
  Serial.println(F("ESP32-S3 Mini Line Follower - Binary Telemetry"));
  Serial.println(F("=============================================="));

  // Configure Motor Pins
  pinMode(LEFT_EN, OUTPUT);    
  pinMode(LEFT_RPWM, OUTPUT);  
  pinMode(LEFT_LPWM, OUTPUT);
  pinMode(RIGHT_EN, OUTPUT);   
  pinMode(RIGHT_RPWM, OUTPUT); 
  pinMode(RIGHT_LPWM, OUTPUT);
  stopMotors();

  // Configure 12 IR Sensor Pins
  for (int i = 0; i < 12; i++) {
    pinMode(IR_PINS[i], INPUT);
    sensorThresholds[i] = (int)thresholdT;
  }

  // Fast 12-bit ADC Configuration on ESP32-S3
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // Initialize BLE Device
  BLEDevice::init("LFR_V5_Tuner");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Nordic UART Service (NUS)
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  // TX Characteristic (Notify)
  pTxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_TX, 
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTxCharacteristic->addDescriptor(new BLE2902());

  // RX Characteristic (Write / Write Without Response)
  pRxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_RX, 
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pRxCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();

  // Configure Advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06); // Fast iOS/Android connection interval
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println(F("BLE Advertising as: LFR_V5_Tuner"));
  Serial.printf("Initial Config: BaseSpeed=%d | MaxSpeed=%d | Kp=%.1f | Thresh=%.0f | Invert=%d\n",
                baseSpeed, maxSpeed, Kp, thresholdT, invertSteering);
}

// =============================================================================
// MAIN LOOP
// =============================================================================
void loop() {
  float error = readLineError(); 
  
  // Stream rate-limited binary telemetry to companion app (~22 Hz)
  if (deviceConnected) {
    sendTelemetry(error);
  }

  // Motor PID control
  if (motorsEnabled) {
    if (error == 999.0f) {
      // Line lost: stop motors safely and reset PID integral
      stopMotors();
      integral = 0;      
      previousError = 0; 

      // Periodic diagnostic logging while line lost
      unsigned long now = millis();
      if (now - lastDebugTime >= DEBUG_INTERVAL) {
        lastDebugTime = now;
        Serial.println(F("[RUN] LINE LOST (error=999.0) -> Motors Stopped"));
      }
    } 
    else {
      // PID calculation
      float P = error * Kp;
      integral += error;
      // Integral anti-windup clamp
      integral = constrain(integral, -100.0f, 100.0f);
      float I = integral * Ki;
      float D = (error - previousError) * Kd;
      
      float correction = P + I + D;
      previousError = error;

      // Dynamic differential speed calculation:
      // - baseSpeed provides forward momentum
      // - correction steers robot by speeding up outer wheel and slowing down inner wheel
      int leftMotorSpeed  = baseSpeed + (int)correction;
      int rightMotorSpeed = baseSpeed - (int)correction;

      setMotors(leftMotorSpeed, rightMotorSpeed);

      // Temporary diagnostic logging (100ms interval)
      unsigned long now = millis();
      if (now - lastDebugTime >= DEBUG_INTERVAL) {
        lastDebugTime = now;
        Serial.printf("[RUN] Err:%5.2f | Corr:%6.1f | L:%4d | R:%4d | Base:%3d | Max:%3d | Inv:%d\n",
                      error, correction, leftMotorSpeed, rightMotorSpeed, baseSpeed, maxSpeed, invertSteering);
      }
    }
  } else {
    stopMotors();
  }
}

// =============================================================================
// IR SENSOR READING & ERROR CALCULATION
// =============================================================================
float readLineError() {
  float sum = 0;
  int activeSensors = 0;
  
  for (int i = 0; i < 12; i++) {
    int raw = analogRead(IR_PINS[i]);
    sensorAnalogValues[i] = raw;
    // Option A downscaling: 12-bit (0–4095) >> 4 -> 8-bit (0–255)
    sensor8BitValues[i] = (uint8_t)(raw >> 4);
    
    // Check against individual sensor threshold
    if (raw > sensorThresholds[i]) { 
      isLineDetected[i] = true;
      sum += (i - 5.5f); 
      activeSensors++;
    } else {
      isLineDetected[i] = false;
    }
  }
  
  if (activeSensors == 0) {
    return 999.0f; // Line lost flag
  }
  
  float error = sum / (float)activeSensors;

  // Steering polarity check:
  // If sensor array orientation or motor wiring is reversed, invert error sign
  if (invertSteering) {
    error = -error;
  }
  
  return error;
}

// =============================================================================
// COMPACT 15-BYTE BINARY TELEMETRY (Non-blocking ~22 Hz)
// =============================================================================
void sendTelemetry(float error) {
  unsigned long now = millis();
  if (now - lastTelemetryTime < TELEMETRY_INTERVAL) {
    return; // Rate limit without blocking
  }
  lastTelemetryTime = now;

  if (!deviceConnected || pTxCharacteristic == nullptr) {
    return;
  }

  TelemetryPacket packet;

  // 1. Copy 12 downscaled 8-bit analog values
  for (int i = 0; i < 12; i++) {
    packet.sensors[i] = sensor8BitValues[i];
  }

  // 2. Signed line error * 100 (clamp 999.0f to 9990 to safely fit int16_t without overflow)
  if (error == 999.0f) {
    packet.error_x100 = 9990;
  } else {
    packet.error_x100 = (int16_t)constrain((int)(error * 100.0f), -32767, 32767);
  }

  // 3. Status flags byte
  // Bit 0 = motorsEnabled
  // Bit 1 = lineLost (error == 999.0f)
  packet.status_flags = 0;
  if (motorsEnabled) {
    packet.status_flags |= (1 << 0);
  }
  if (error == 999.0f) {
    packet.status_flags |= (1 << 1);
  }

  // Dispatch binary payload over BLE
  pTxCharacteristic->setValue((uint8_t*)&packet, sizeof(packet));
  pTxCharacteristic->notify();
}

// =============================================================================
// MOTOR CONTROLS (BTS7960 Dual H-Bridge Drivers)
// =============================================================================
void setMotors(int leftSpeed, int rightSpeed) {
  // Constrain speeds to dynamic allowable range [-maxSpeed, maxSpeed] within standard 8-bit PWM bounds [-255, 255]
  int speedCeiling = constrain(maxSpeed, 0, 255);
  leftSpeed = constrain(leftSpeed, -speedCeiling, speedCeiling);
  rightSpeed = constrain(rightSpeed, -speedCeiling, speedCeiling);

  // Deadband compensation: ensure motor delivers enough torque to overcome static friction
  if (minSpeed > 0) {
    if (leftSpeed > 0 && leftSpeed < minSpeed) leftSpeed = minSpeed;
    else if (leftSpeed < 0 && leftSpeed > -minSpeed) leftSpeed = -minSpeed;

    if (rightSpeed > 0 && rightSpeed < minSpeed) rightSpeed = minSpeed;
    else if (rightSpeed < 0 && rightSpeed > -minSpeed) rightSpeed = -minSpeed;
  }

  digitalWrite(LEFT_EN, HIGH); 
  digitalWrite(RIGHT_EN, HIGH);

  // Left Motor Direction & PWM
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

  // Right Motor Direction & PWM
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