#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- FORWARD DECLARATIONS ---
void stopMotors();
void setMotors(int leftSpeed, int rightSpeed);
float readLineError();
void sendTelemetry();
void sendAck(String command, String value);
void sendThresholds();
void sendTime();
void parseCommand(String cmd);

// --- MOTOR PIN DEFINITIONS ---
const int LEFT_EN = 40;
const int LEFT_RPWM = 39;
const int LEFT_LPWM = 38;
const int RIGHT_EN = 3;
const int RIGHT_RPWM = 42;
const int RIGHT_RPWM_2 = 41;   // RIGHT_LPWM

// --- IR SENSOR PINS ---
const int IR_PINS[12] = {4, 5, 6, 16, 15, 14, 17, 18, 13, 12, 11, 10};
int  sensorAnalogValues[12];
bool isLineDetected[12];

// --- PID & TUNING VARIABLES ---
float Kp = 0.0;
float Ki = 0.0;
float Kd = 0.0;
int   maxSpeed = 100;
int   baseSpeed = 100;          // mirrors maxSpeed for now; app can set separately
int   sensorThresholds[12];     // per-sensor thresholds (0-4095)

float previousError = 0.0;
float integral     = 0.0;
bool  motorsEnabled = false;
bool  autoStop  = false;        // auto-stop when error == 999.0 continuously
bool  lineLost  = false;        // line-lost recovery flag (future use)

// --- RUN TIMER ---
unsigned long runStartTime = 0;

// --- TELEMETRY TIMER ---
unsigned long lastTelemetryTime = 0;
const int TELEMETRY_INTERVAL = 150;  // ms

// --- BLE UART UUIDs (Nordic UART Service - unchanged) ---
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLECharacteristic *pTxCharacteristic;
bool deviceConnected = false;

// ---------------------------------------------------------------------------
// BLE CONNECTION CALLBACKS  (unchanged)
// ---------------------------------------------------------------------------
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Phone Connected!");
    }
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Phone Disconnected!");
      stopMotors();
      motorsEnabled = false;
      pServer->getAdvertising()->start();
    }
};

// ---------------------------------------------------------------------------
// BLE MESSAGE PARSING
//
// The app uses the same text protocol as the classic-BT firmware:
//   KP=<value>          → set Kp
//   KI=<value>          → set Ki
//   KD=<value>          → set Kd
//   MAX=<value>         → set maxSpeed
//   BASE=<value>        → set baseSpeed
//   RUN=1 / RUN=0       → start / stop motors
//   THRESH?             → report current thresholds
//   THRALL=<value>      → set all 12 sensor thresholds to <value>
//   THR=<idx>,<value>   → set threshold for sensor <idx>
//   AUTOSTOP=0/1        → enable/disable auto-stop on line-lost
//   LINELOST=0/1        → enable/disable line-lost recovery
//   TIME?               → report elapsed run time
// ---------------------------------------------------------------------------
class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue().c_str();
      if (rxValue.length() > 0) {
        rxValue.trim();
        parseCommand(rxValue);
      }
    }
};

// ---------------------------------------------------------------------------
// COMMAND PARSER
// ---------------------------------------------------------------------------
void parseCommand(String cmd) {
  cmd.trim();

  // --- Query commands (no '=') ---
  if (cmd.equalsIgnoreCase("THRESH?")) {
    sendThresholds();
    return;
  }
  if (cmd.equalsIgnoreCase("TIME?")) {
    sendTime();
    return;
  }

  // --- Assignment commands (KEY=VALUE) ---
  int eqIdx = cmd.indexOf('=');
  if (eqIdx < 1) return;   // malformed

  String key = cmd.substring(0, eqIdx);
  String val = cmd.substring(eqIdx + 1);
  key.trim();
  val.trim();
  key.toUpperCase();

  if (key == "KP") {
    Kp = val.toFloat();
    sendAck("KP", val);
  }
  else if (key == "KI") {
    Ki = val.toFloat();
    sendAck("KI", val);
  }
  else if (key == "KD") {
    Kd = val.toFloat();
    sendAck("KD", val);
  }
  else if (key == "MAX") {
    maxSpeed = (int)val.toFloat();
    sendAck("MAX", val);
  }
  else if (key == "BASE") {
    baseSpeed = (int)val.toFloat();
    sendAck("BASE", val);
  }
  else if (key == "RUN") {
    int v = (int)val.toFloat();
    motorsEnabled = (v == 1);
    if (!motorsEnabled) {
      stopMotors();
      integral = 0;
      previousError = 0;
    } else {
      runStartTime = millis();
    }
    sendAck("RUN", val);
  }
  else if (key == "THRALL") {
    int t = (int)val.toFloat();
    t = constrain(t, 0, 4095);
    for (int i = 0; i < 12; i++) sensorThresholds[i] = t;
    sendAck("THRALL", val);
    sendThresholds();
  }
  else if (key == "THR") {
    // Format: THR=<index>,<value>
    int commaIdx = val.indexOf(',');
    if (commaIdx > 0) {
      int idx = val.substring(0, commaIdx).toInt();
      int t   = val.substring(commaIdx + 1).toInt();
      t = constrain(t, 0, 4095);
      if (idx >= 0 && idx < 12) {
        sensorThresholds[idx] = t;
        sendAck("THR", val);
        sendThresholds();
      }
    }
  }
  else if (key == "AUTOSTOP") {
    autoStop = ((int)val.toFloat() == 1);
    sendAck("AUTOSTOP", val);
  }
  else if (key == "LINELOST") {
    lineLost = ((int)val.toFloat() == 1);
    sendAck("LINELOST", val);
  }
}

// ---------------------------------------------------------------------------
// SETUP
// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);

  // Motor pins
  pinMode(LEFT_EN,    OUTPUT);
  pinMode(LEFT_RPWM,  OUTPUT);
  pinMode(LEFT_LPWM,  OUTPUT);
  pinMode(RIGHT_EN,   OUTPUT);
  pinMode(RIGHT_RPWM, OUTPUT);
  pinMode(RIGHT_RPWM_2, OUTPUT);
  stopMotors();

  // Sensor pins + default thresholds
  for (int i = 0; i < 12; i++) {
    pinMode(IR_PINS[i], INPUT);
    sensorThresholds[i] = 2000;   // matches AppConstants.defaultThreshold
  }

  // BLE init (communication layer unchanged)
  BLEDevice::init("LFR_V5_Tuner");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pTxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_TX,
      BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_RX,
      BLECharacteristic::PROPERTY_WRITE);
  pRxCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();
  pServer->getAdvertising()->start();

  Serial.println("BLE advertising as LFR_V5_Tuner");
}

// ---------------------------------------------------------------------------
// MAIN LOOP
// ---------------------------------------------------------------------------
void loop() {
  float error = readLineError();

  if (deviceConnected) {
    sendTelemetry();
  }

  if (motorsEnabled) {
    if (error == 999.0) {
      // Line completely lost — safety stop
      stopMotors();
      integral = 0;
      previousError = 0;
    } else {
      float P = error * Kp;
      integral += error;
      float I = integral * Ki;
      float D = (error - previousError) * Kd;

      float correction = P + I + D;
      previousError = error;

      int leftMotorSpeed  = maxSpeed + (int)correction;
      int rightMotorSpeed = maxSpeed - (int)correction;

      setMotors(leftMotorSpeed, rightMotorSpeed);
    }
  }
}

// ---------------------------------------------------------------------------
// SENSOR READING & ERROR CALCULATION
// ---------------------------------------------------------------------------
float readLineError() {
  float sum = 0;
  int activeSensors = 0;

  for (int i = 0; i < 12; i++) {
    sensorAnalogValues[i] = analogRead(IR_PINS[i]);
    if (sensorAnalogValues[i] > sensorThresholds[i]) {
      isLineDetected[i] = true;
      sum += (i - 5.5);
      activeSensors++;
    } else {
      isLineDetected[i] = false;
    }
  }

  if (activeSensors == 0) return 999.0;
  return sum / activeSensors;
}

// ---------------------------------------------------------------------------
// TELEMETRY — sends "SENSORS:val0,val1,...,val11\n" at TELEMETRY_INTERVAL
// This matches the app's AppConstants.respSensors protocol.
// ---------------------------------------------------------------------------
void sendTelemetry() {
  if (millis() - lastTelemetryTime < TELEMETRY_INTERVAL) return;
  lastTelemetryTime = millis();

  String msg = "SENSORS:";
  for (int i = 0; i < 12; i++) {
    msg += String(sensorAnalogValues[i]);
    if (i < 11) msg += ",";
  }
  msg += "\n";

  sendBleMessage(msg);
}

// ---------------------------------------------------------------------------
// SEND CHUNKED BLE MESSAGE (20-byte MTU limit bypass)
// ---------------------------------------------------------------------------
void sendBleMessage(String msg) {
  if (!deviceConnected) return;
  int len = msg.length();
  int offset = 0;
  while (offset < len) {
    int chunkLen = min(20, len - offset);
    pTxCharacteristic->setValue(msg.substring(offset, offset + chunkLen).c_str());
    pTxCharacteristic->notify();
    offset += chunkLen;
    delay(5);
  }
}

// ---------------------------------------------------------------------------
// SEND ACK — "ACK:<command>=<value>\n"
// ---------------------------------------------------------------------------
void sendAck(String command, String value) {
  if (!deviceConnected) return;
  String msg = "ACK:" + command + "=" + value + "\n";
  sendBleMessage(msg);
  Serial.print("ACK sent: ");
  Serial.println(msg);
}

// ---------------------------------------------------------------------------
// SEND THRESHOLDS — "THRESHOLDS:t0,t1,...,t11\n"
// ---------------------------------------------------------------------------
void sendThresholds() {
  if (!deviceConnected) return;
  String msg = "THRESHOLDS:";
  for (int i = 0; i < 12; i++) {
    msg += String(sensorThresholds[i]);
    if (i < 11) msg += ",";
  }
  msg += "\n";
  sendBleMessage(msg);
}

// ---------------------------------------------------------------------------
// SEND TIME — "TIME=<ms>\n"
// ---------------------------------------------------------------------------
void sendTime() {
  if (!deviceConnected) return;
  unsigned long elapsed = motorsEnabled ? (millis() - runStartTime) : 0;
  String msg = "TIME=" + String(elapsed) + "\n";
  pTxCharacteristic->setValue(msg.c_str());
  pTxCharacteristic->notify();
}

// ---------------------------------------------------------------------------
// MOTOR DRIVER
// ---------------------------------------------------------------------------
void setMotors(int leftSpeed, int rightSpeed) {
  leftSpeed  = constrain(leftSpeed,  -maxSpeed, maxSpeed);
  rightSpeed = constrain(rightSpeed, -maxSpeed, maxSpeed);

  digitalWrite(LEFT_EN,  HIGH);
  digitalWrite(RIGHT_EN, HIGH);

  if (leftSpeed > 0) {
    analogWrite(LEFT_RPWM, leftSpeed);  analogWrite(LEFT_LPWM, 0);
  } else if (leftSpeed < 0) {
    analogWrite(LEFT_RPWM, 0);          analogWrite(LEFT_LPWM, abs(leftSpeed));
  } else {
    analogWrite(LEFT_RPWM, 0);          analogWrite(LEFT_LPWM, 0);
  }

  if (rightSpeed > 0) {
    analogWrite(RIGHT_RPWM,   rightSpeed); analogWrite(RIGHT_RPWM_2, 0);
  } else if (rightSpeed < 0) {
    analogWrite(RIGHT_RPWM,   0);          analogWrite(RIGHT_RPWM_2, abs(rightSpeed));
  } else {
    analogWrite(RIGHT_RPWM,   0);          analogWrite(RIGHT_RPWM_2, 0);
  }
}

void stopMotors() {
  digitalWrite(LEFT_EN,  LOW);
  digitalWrite(RIGHT_EN, LOW);
  analogWrite(LEFT_RPWM,    0);  analogWrite(LEFT_LPWM,    0);
  analogWrite(RIGHT_RPWM,   0);  analogWrite(RIGHT_RPWM_2, 0);
}