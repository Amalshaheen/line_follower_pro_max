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

// =============================================================================
// PID & TUNING VARIABLES
// =============================================================================
float Kp = 70.0;
float Ki = 0.0;
float Kd = 0.0;
int maxSpeed = 100;
float thresholdT = 2000.0; 

float previousError = 0.0;
float integral = 0.0;
bool motorsEnabled = false;

// =============================================================================
// TELEMETRY TIMER (20–25 Hz -> 40–50 ms)
// =============================================================================
unsigned long lastTelemetryTime = 0;
const int TELEMETRY_INTERVAL = 45; // ~22 Hz non-blocking

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
    Serial.println(F(">>> BLE Phone Connected!")); 
  }
  
  void onDisconnect(BLEServer* pServer) override { 
    deviceConnected = false; 
    Serial.println(F(">>> BLE Phone Disconnected!")); 
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
  if (rxValue == "S" || rxValue == "s") {
    motorsEnabled = !motorsEnabled;
    if (!motorsEnabled) {
      stopMotors();
      integral = 0;
      previousError = 0;
    }
    Serial.printf("Motors Enabled: %d\n", motorsEnabled);
    return;
  }

  // 2. Single-letter prefix commands: P, I, D, M, T
  char firstChar = toupper(rxValue.charAt(0));
  String param = rxValue.substring(1);
  param.trim();

  // Full-name / legacy prefixes support
  if (rxValue.startsWith("KP=")) {
    Kp = rxValue.substring(3).toFloat();
    Serial.printf("Kp set to: %.2f\n", Kp);
    return;
  } else if (rxValue.startsWith("KI=")) {
    Ki = rxValue.substring(3).toFloat();
    Serial.printf("Ki set to: %.2f\n", Ki);
    return;
  } else if (rxValue.startsWith("KD=")) {
    Kd = rxValue.substring(3).toFloat();
    Serial.printf("Kd set to: %.2f\n", Kd);
    return;
  } else if (rxValue.startsWith("MAX=")) {
    maxSpeed = constrain(rxValue.substring(4).toInt(), 0, 255);
    Serial.printf("MaxSpeed set to: %d\n", maxSpeed);
    return;
  } else if (rxValue.startsWith("BASE=")) {
    maxSpeed = constrain(rxValue.substring(5).toInt(), 0, 255);
    Serial.printf("Base/Max Speed set to: %d\n", maxSpeed);
    return;
  } else if (rxValue.startsWith("THRALL=")) {
    float val = rxValue.substring(7).toFloat();
    if (val <= 255.0f) val *= 16.0f; // Scale 8-bit to 12-bit if needed
    thresholdT = val;
    Serial.printf("Threshold set to: %.1f\n", thresholdT);
    return;
  } else if (rxValue == "RUN=1" || rxValue == "ROBOT,START") {
    motorsEnabled = true;
    Serial.println(F("Motors Started via RUN=1"));
    return;
  } else if (rxValue == "RUN=0" || rxValue == "ROBOT,STOP") {
    motorsEnabled = false;
    stopMotors();
    integral = 0;
    previousError = 0;
    Serial.println(F("Motors Stopped via RUN=0"));
    return;
  }

  // Concise single-letter parsing
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
    case 'M':
      maxSpeed = constrain((int)val, 0, 255);
      Serial.printf("MaxSpeed: %d\n", maxSpeed);
      break;
    case 'T':
      // Support 8-bit (0–255) or 12-bit (0–4095) thresholds
      if (val <= 255.0f && val > 0.0f) {
        thresholdT = val * 16.0f;
      } else {
        thresholdT = val;
      }
      Serial.printf("ThresholdT: %.1f\n", thresholdT);
      break;
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
  pAdvertising->setMinPreferred(0x06); // Fast iPhone/Android connection interval
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println(F("BLE Advertising as: LFR_V5_Tuner"));
}

// =============================================================================
// MAIN LOOP
// =============================================================================
void loop() {
  float error = readLineError(); 
  
  // Stream rate-limited binary telemetry to companion app
  if (deviceConnected) {
    sendTelemetry(error);
  }

  // Motor PID control
  if (motorsEnabled) {
    if (error == 999.0f) {
      stopMotors();
      integral = 0;      
      previousError = 0; 
    } 
    else {
      float P = error * Kp;
      integral += error;
      float I = integral * Ki;
      float D = (error - previousError) * Kd;
      
      float correction = P + I + D;
      previousError = error;

      int leftMotorSpeed = maxSpeed + (int)correction;
      int rightMotorSpeed = maxSpeed - (int)correction;

      setMotors(leftMotorSpeed, rightMotorSpeed);
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
    
    if (raw > thresholdT) { 
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
  
  return sum / activeSensors;
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
// MOTOR CONTROLS - STRICTLY PRESERVED
// =============================================================================
void setMotors(int leftSpeed, int rightSpeed) {
  leftSpeed = constrain(leftSpeed, -maxSpeed, maxSpeed);
  rightSpeed = constrain(rightSpeed, -maxSpeed, maxSpeed);

  digitalWrite(LEFT_EN, HIGH); 
  digitalWrite(RIGHT_EN, HIGH);

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