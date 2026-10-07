#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

enum StepType : uint8_t {
  STEP_NONE = 0,
  STEP_MOVE_FWD,
  STEP_MOVE_REV,
  STEP_TURN_LEFT,
  STEP_TURN_RIGHT,
  STEP_PAUSE
};

struct SequenceStep {
  StepType type;
  float param; // distance_cm, degrees, or milliseconds
};

// =============================================================================
// 1. HARDWARE PINOUTS & PHYSICAL CONSTANTS (ESP32-S3 Mini)
// =============================================================================

// BTS7960 Dual H-Bridge Motor Driver
const int LEFT_EN    = 40;     
const int LEFT_RPWM  = 39;   
const int LEFT_LPWM  = 38;   
const int RIGHT_EN   = 3;     
const int RIGHT_RPWM = 42;  
const int RIGHT_LPWM = 41;  

// 8-Magnet Hall Sensor Encoders
const int PIN_ENC_LEFT  = 7;
const int PIN_ENC_RIGHT = 8;

// 12-Channel IR Sensor Array (Direct ADC)
const int IR_PINS[12] = {4, 5, 6, 16, 15, 14, 17, 18, 13, 12, 11, 10};

// CAD-Extracted Physical X-Coordinates in mm (Relative to Robot Centerline)
const float SENSOR_X_MM[12] = {
  -52.52f, -46.01f, -36.47f, -25.97f, -15.58f, -5.27f,
    5.27f,  15.58f,  25.97f,  36.47f,  46.01f,  52.52f
};

// Mechanical & Kinematic Dimensions
const float WHEEL_DIAMETER_MM       = 40.0f;
const float WHEEL_CIRCUMFERENCE_MM  = 125.6637f; // pi * 40 mm
const float WHEEL_TRACK_WIDTH_MM    = 162.0f;    // W_track
const float LOOKAHEAD_DISTANCE_MM   = 130.0f;    // L
const int   TICKS_PER_REV           = 8;         // 8 magnet pulses per revolution
const float MM_PER_TICK             = 15.708f;   // 125.6637 / 8 ≈ 15.708 mm per tick
const float TICKS_PER_90_DEG_TURN   = 8.1f;      // (pi * 162) / (4 * 15.708) ≈ 8.1 ticks

// Control Loop & Rate Timing
const unsigned long CONTROL_INTERVAL_MICROS = 3000; // 333.3 Hz (3000 µs)
const unsigned long TELEMETRY_INTERVAL_MS   = 45;   // ~22 Hz BLE
const unsigned long DEBUG_INTERVAL_MS       = 100;  // 10 Hz Serial

// =============================================================================
// 2. ENCODER SYSTEM & INTERRUPTS
// =============================================================================
volatile uint32_t encLeftTicks  = 0;
volatile uint32_t encRightTicks = 0;

void IRAM_ATTR isrLeftEncoder() {
  encLeftTicks++;
}

void IRAM_ATTR isrRightEncoder() {
  encRightTicks++;
}

// =============================================================================
// 3. SYSTEM OPERATING MODES & STATE VARIABLES
// =============================================================================

enum RobotMode : uint8_t {
  MODE_IDLE = 0,
  MODE_LINE_FOLLOW_REACTIVE,
  MODE_LINE_FOLLOW_MAP,
  MODE_LINE_FOLLOW_RACE,
  MODE_SEQUENCE_RUN
};

volatile RobotMode currentMode = MODE_IDLE;

// Units: mm error -> PWM correction
float Kp = 2.5f;           // Proportional gain (PWM per mm offset)
float Ki = 0.0f;           // Integral gain
float Kd = 0.08f;          // Derivative gain (PWM per (mm/s))
float dFilterAlpha = 0.70f; // 1st-order Low-Pass filter constant for D term

int baseSpeed = 70;       // Nominal straight line PWM (0-255)
int maxSpeed  = 120;
int minSpeed  = 30;        // Deadband compensation for BTS7960
int mapSpeed  = 55;        // Independent Sector Mapping Speed (0-255)
bool invertSteering = false;

// Sensor thresholds (12-bit ADC: 0-4095)
int sensorThresholds[12];
uint16_t sensorMask = 0x0FFF;
float defaultThreshold = 2000.0f;

// Operational Flags & Metrics
bool motorsEnabled = false;
bool isLineLost = false;
float currentErrorMm = 0.0f;
float lastValidErrorMm = 0.0f;
unsigned long lastTelemetryTime = 0;

// Encoder-Assisted Gap Recovery
uint32_t lineLostStartTick = 0;
const uint32_t GAP_BLIND_DISTANCE_TICKS = 8; // ~125 mm blind tracking before safety stop

// Forward Declarations
enum StepType : uint8_t;
void setMotors(int leftSpeed, int rightSpeed);
void stopMotors();
void brakeMotors();
void dynamicBrake();
void activePlugBrake(int plugPwm = 200, uint32_t maxDurationMs = 30);
void resetPID();
float computePID(float errorMm, float dt);
bool readSensorArrayMetric();
void handleLineLostRecovery();
void sendTelemetry(float errorMm);
void sendThresholdsToApp();
void sendSensorMaskToApp();
void sendBleMessage(const String& msg);
void handleCommand(String rxValue);

// =============================================================================
// 4. SECTOR / SEGMENT MAPPING & PRE-BRAKING (RACELINE OPTIMIZATION)
// =============================================================================
enum SegmentType : uint8_t {
  SEG_STRAIGHT = 0,
  SEG_TURN_LEFT = 1,
  SEG_TURN_RIGHT = 2
};

struct TrackSegment {
  SegmentType type;
  uint32_t lengthTicks;
  int targetSpeed;
};

const int MAX_MAP_SEGMENTS = 64;
TrackSegment trackMap[MAX_MAP_SEGMENTS];
int mapSegmentCount = 0;

// Mapping run runtime variables
uint32_t mapLastSegTick = 0;
SegmentType mapCurrentSegType = SEG_STRAIGHT;
SegmentType mapCandidateType  = SEG_STRAIGHT;
uint8_t mapCandidateDebounce  = 0;
const uint8_t MAP_DEBOUNCE_CYCLES = 15; // ~45 ms debounce
const uint32_t MIN_SEG_TICKS      = 8;  // Minimum length to confirm discrete segment (~125 mm)

// Race mode runtime variables
int raceSegIndex = 0;
uint32_t raceSegStartTick = 0;

void clearTrackMap() {
  mapSegmentCount = 0;
  mapLastSegTick = (encLeftTicks + encRightTicks) / 2;
  mapCurrentSegType = SEG_STRAIGHT;
  mapCandidateType  = SEG_STRAIGHT;
  mapCandidateDebounce = 0;
}

void finalizeTrackMap() {
  uint32_t totalTicks = (encLeftTicks + encRightTicks) / 2;
  uint32_t segLength = totalTicks - mapLastSegTick;
  if (segLength > 0 && mapSegmentCount < MAX_MAP_SEGMENTS) {
    trackMap[mapSegmentCount].type = mapCurrentSegType;
    trackMap[mapSegmentCount].lengthTicks = segLength;
    trackMap[mapSegmentCount].targetSpeed = baseSpeed;
    mapSegmentCount++;
    mapLastSegTick = totalTicks;
  }
}

void calculateSpeedProfiles() {
  for (int i = 0; i < mapSegmentCount; i++) {
    if (trackMap[i].type == SEG_STRAIGHT) {
      if (trackMap[i].lengthTicks > 45) { // Long straight (> ~70 cm)
        trackMap[i].targetSpeed = maxSpeed;
      } else if (trackMap[i].lengthTicks > 20) { // Medium straight (> ~31 cm)
        trackMap[i].targetSpeed = constrain((baseSpeed + maxSpeed) / 2, baseSpeed, maxSpeed);
      } else {
        trackMap[i].targetSpeed = baseSpeed;
      }
    } else {
      // Cornering speed
      trackMap[i].targetSpeed = constrain(baseSpeed, minSpeed, 140);
    }
  }
}

void executeMappingMode(bool lineFound, float dt) {
  if (!lineFound) {
    handleLineLostRecovery();
    return;
  }
  lineLostStartTick = 0;
  // Safe mapping speed PID using independent mapSpeed
  float correction = computePID(currentErrorMm, dt);
  int leftSpeed  = mapSpeed + (int)correction;
  int rightSpeed = mapSpeed - (int)correction;
  setMotors(leftSpeed, rightSpeed);

  // Classify current curvature from lateral error
  SegmentType detected;
  if (currentErrorMm < -8.0f) {
    detected = SEG_TURN_LEFT;
  } else if (currentErrorMm > 8.0f) {
    detected = SEG_TURN_RIGHT;
  } else {
    detected = SEG_STRAIGHT;
  }

  if (detected == mapCandidateType) {
    if (mapCandidateDebounce < 255) mapCandidateDebounce++;
  } else {
    mapCandidateType = detected;
    mapCandidateDebounce = 1;
  }

  uint32_t totalTicks = (encLeftTicks + encRightTicks) / 2;

  // Confirm transition upon debounce threshold
  if (mapCandidateDebounce >= MAP_DEBOUNCE_CYCLES && mapCandidateType != mapCurrentSegType) {
    uint32_t segLength = totalTicks - mapLastSegTick;
    if (segLength >= MIN_SEG_TICKS) {
      if (mapSegmentCount < MAX_MAP_SEGMENTS) {
        trackMap[mapSegmentCount].type = mapCurrentSegType;
        trackMap[mapSegmentCount].lengthTicks = segLength;
        trackMap[mapSegmentCount].targetSpeed = baseSpeed;
        mapSegmentCount++;
        mapLastSegTick = totalTicks;
        mapCurrentSegType = mapCandidateType;
      }
    }
  }
}

void executeRaceMode(bool lineFound, float dt) {
  if (mapSegmentCount == 0) {
    // No map recorded; fallback to reactive
    currentMode = MODE_LINE_FOLLOW_REACTIVE;
    return;
  }

  if (!lineFound) {
    handleLineLostRecovery();
    return;
  }
  lineLostStartTick = 0;

  uint32_t totalTicks = (encLeftTicks + encRightTicks) / 2;
  uint32_t segTraversed = totalTicks - raceSegStartTick;

  // Advance segment if distance reached
  if (segTraversed >= trackMap[raceSegIndex].lengthTicks) {
    raceSegIndex = (raceSegIndex + 1) % mapSegmentCount;
    raceSegStartTick = totalTicks;
    segTraversed = 0;
  }

  int effectiveSpeed = trackMap[raceSegIndex].targetSpeed;

  // Pre-braking logic: On straightaways approaching sharp turns
  if (trackMap[raceSegIndex].type == SEG_STRAIGHT && mapSegmentCount > 1) {
    int nextIdx = (raceSegIndex + 1) % mapSegmentCount;
    if (trackMap[nextIdx].type != SEG_STRAIGHT) {
      const uint32_t PRE_BRAKE_TICKS = 6; // Decelerate ~94 mm before turn entrance
      uint32_t remainingTicks = (trackMap[raceSegIndex].lengthTicks > segTraversed) 
                                ? (trackMap[raceSegIndex].lengthTicks - segTraversed) : 0;
      if (remainingTicks <= PRE_BRAKE_TICKS) {
        effectiveSpeed = trackMap[nextIdx].targetSpeed;
      }
    }
  }

  float correction = computePID(currentErrorMm, dt);
  int leftSpeed  = effectiveSpeed + (int)correction;
  int rightSpeed = effectiveSpeed - (int)correction;
  setMotors(leftSpeed, rightSpeed);
}

// =============================================================================
// 5. STEP-BY-STEP SEQUENCE EXECUTOR (AUTONOMOUS QUEUE RUNNER)
// =============================================================================


const int MAX_SEQUENCE_STEPS = 32;
SequenceStep sequenceQueue[MAX_SEQUENCE_STEPS];
uint8_t seqHead = 0;
uint8_t seqTail = 0;
uint8_t seqCount = 0;

enum SeqState : uint8_t {
  SEQ_STATE_IDLE = 0,
  SEQ_STATE_START_STEP,
  SEQ_STATE_EXECUTING,
  SEQ_STATE_BRAKING
};

SeqState seqState = SEQ_STATE_IDLE;
SequenceStep currentStep;
uint32_t stepStartLeftTicks  = 0;
uint32_t stepStartRightTicks = 0;
uint32_t stepTargetTicks     = 0;
unsigned long stepStartTimeMs = 0;
unsigned long stepBrakeStartMs = 0;

bool enqueueStep(StepType type, float param) {
  if (seqCount >= MAX_SEQUENCE_STEPS) return false;
  sequenceQueue[seqTail].type = type;
  sequenceQueue[seqTail].param = param;
  seqTail = (seqTail + 1) % MAX_SEQUENCE_STEPS;
  seqCount++;
  return true;
}

void clearSequenceQueue() {
  seqHead = 0;
  seqTail = 0;
  seqCount = 0;
  seqState = SEQ_STATE_IDLE;
}

void executeSequenceRunner() {
  if (seqState == SEQ_STATE_IDLE) {
    seqState = SEQ_STATE_START_STEP;
  }

  // 1. Initiate next step from queue
  if (seqState == SEQ_STATE_START_STEP) {
    if (seqCount == 0) {
      // Completed all motion steps
      seqState = SEQ_STATE_IDLE;
      currentMode = MODE_IDLE;
      motorsEnabled = false;
      stopMotors();
      sendBleMessage("SEQ:DONE\n");
      Serial.println(F("[SEQ] Execution Complete -> SEQ:DONE"));
      return;
    }

    currentStep = sequenceQueue[seqHead];
    seqHead = (seqHead + 1) % MAX_SEQUENCE_STEPS;
    seqCount--;

    stepStartLeftTicks  = encLeftTicks;
    stepStartRightTicks = encRightTicks;
    stepStartTimeMs     = millis();

    switch (currentStep.type) {
      case STEP_MOVE_FWD:
      case STEP_MOVE_REV: {
        float distMm = currentStep.param * 10.0f;
        stepTargetTicks = (uint32_t)max(1, (int)round(distMm / MM_PER_TICK));
        break;
      }
      case STEP_TURN_LEFT:
      case STEP_TURN_RIGHT: {
        // Differential Pivot Arc: s = (pi * W_track * deg) / 360
        float arcMm = (PI * WHEEL_TRACK_WIDTH_MM * currentStep.param) / 360.0f;
        stepTargetTicks = (uint32_t)max(1, (int)round(arcMm / MM_PER_TICK));
        break;
      }
      case STEP_PAUSE: {
        stepTargetTicks = (uint32_t)currentStep.param;
        break;
      }
      default:
        stepTargetTicks = 0;
        break;
    }

    seqState = SEQ_STATE_EXECUTING;
  }

  // 2. Active closed-loop step execution
  if (seqState == SEQ_STATE_EXECUTING) {
    uint32_t dL = encLeftTicks - stepStartLeftTicks;
    uint32_t dR = encRightTicks - stepStartRightTicks;
    uint32_t avgTicks = (dL + dR) / 2;

    switch (currentStep.type) {
      case STEP_MOVE_FWD: {
        // Differential tick trimming to drive straight
        int32_t diff = (int32_t)dL - (int32_t)dR;
        int trim = constrain((int)(diff * 2.5f), -25, 25);
        int spd = (avgTicks < 1) ? (minSpeed + 20) : baseSpeed;
        setMotors(spd - trim, spd + trim);

        if (avgTicks >= stepTargetTicks) {
          brakeMotors();
          stepBrakeStartMs = millis();
          seqState = SEQ_STATE_BRAKING;
        }
        break;
      }

      case STEP_MOVE_REV: {
        // Differential tick trimming in reverse
        int32_t diff = (int32_t)dL - (int32_t)dR;
        int trim = constrain((int)(diff * 2.5f), -25, 25);
        int spd = (avgTicks < 1) ? (minSpeed + 20) : baseSpeed;
        setMotors(-(spd - trim), -(spd + trim));

        if (avgTicks >= stepTargetTicks) {
          brakeMotors();
          stepBrakeStartMs = millis();
          seqState = SEQ_STATE_BRAKING;
        }
        break;
      }

      case STEP_TURN_LEFT: {
        // Differential pivot: Left Reverse, Right Forward
        int32_t diff = (int32_t)dL - (int32_t)dR;
        int trim = constrain((int)(diff * 6.0f), -30, 30);
        int turnSpeed = constrain(baseSpeed, 80, 160);
        setMotors(-(turnSpeed - trim), (turnSpeed + trim));

        if (avgTicks >= stepTargetTicks) {
          brakeMotors();
          stepBrakeStartMs = millis();
          seqState = SEQ_STATE_BRAKING;
        }
        break;
      }

      case STEP_TURN_RIGHT: {
        // Differential pivot: Left Forward, Right Reverse
        int32_t diff = (int32_t)dL - (int32_t)dR;
        int trim = constrain((int)(diff * 6.0f), -30, 30);
        int turnSpeed = constrain(baseSpeed, 80, 160);
        setMotors((turnSpeed - trim), -(turnSpeed + trim));

        if (avgTicks >= stepTargetTicks) {
          brakeMotors();
          stepBrakeStartMs = millis();
          seqState = SEQ_STATE_BRAKING;
        }
        break;
      }

      case STEP_PAUSE: {
        stopMotors();
        if (millis() - stepStartTimeMs >= (unsigned long)currentStep.param) {
          seqState = SEQ_STATE_START_STEP;
        }
        break;
      }

      default:
        seqState = SEQ_STATE_START_STEP;
        break;
    }
  }

  // 3. Active 50 ms braking before next step
  if (seqState == SEQ_STATE_BRAKING) {
    brakeMotors();
    if (millis() - stepBrakeStartMs >= 50) {
      seqState = SEQ_STATE_START_STEP;
    }
  }
}

// =============================================================================
// 6. BLE STACK (NORDIC UART SERVICE)
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
  uint8_t status_flags; // Bit 0: Enabled, Bit 1: Line Lost, Bit 2..7: Mode
};
#pragma pack(pop)

SemaphoreHandle_t bleMutex = nullptr;

class ServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override { 
    deviceConnected = true;
    // Set robust connection parameters:
    // Min Interval: 16 (20 ms), Max Interval: 24 (30 ms), Latency: 0, Timeout: 400 (4.0s)
    pServer->updateConnParams(pServer->getConnId(), 16, 24, 0, 400);
  }
  void onDisconnect(BLEServer* pServer) override { 
    deviceConnected = false; 
    stopMotors(); 
    motorsEnabled = false;
    currentMode = MODE_IDLE;
    pServer->getAdvertising()->start();
  }
};

// =============================================================================
// 7. STREAM FRAMING & BLE COMMAND DISPATCHER
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
        // Prevent buffer overrun on malformed unbounded stream
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
      stopMotors();
      sendBleMessage("ACK:RUN=0\n");
    } else {
      currentMode = MODE_LINE_FOLLOW_REACTIVE;
      resetPID();
      sendBleMessage("ACK:RUN=1\n");
    }
    return;
  }

  if (rx == "RUN=1" || rx == "ROBOT,START") { 
    currentMode = MODE_LINE_FOLLOW_REACTIVE;
    motorsEnabled = true; 
    resetPID();
    sendBleMessage("ACK:RUN=1\n");
    return; 
  }

  if (rx == "RUN=0" || rx == "ROBOT,STOP") { 
    currentMode = MODE_IDLE;
    motorsEnabled = false; 
    stopMotors(); 
    sendBleMessage("ACK:RUN=0\n");
    return; 
  }

  // --- SEQUENCE QUEUE COMMANDS ---
  if (rx == "SEQ,CLEAR") {
    clearSequenceQueue();
    sendBleMessage("ACK:SEQ_CLEAR\n");
    return;
  }

  if (rx == "SEQ,START") {
    if (seqCount > 0) {
      currentMode = MODE_SEQUENCE_RUN;
      seqState = SEQ_STATE_START_STEP;
      motorsEnabled = true;
      sendBleMessage("ACK:SEQ_START\n");
    } else {
      sendBleMessage("ERR:QUEUE_EMPTY\n");
    }
    return;
  }

  if (rx == "SEQ,STOP") {
    currentMode = MODE_IDLE;
    seqState = SEQ_STATE_IDLE;
    motorsEnabled = false;
    stopMotors();
    sendBleMessage("ACK:SEQ_STOP\n");
    return;
  }

  // --- SECTOR MAPPING & RACE RUNS ---
  if (rx == "MAP,START") {
    clearTrackMap();
    resetPID();
    currentMode = MODE_LINE_FOLLOW_MAP;
    motorsEnabled = true;
    sendBleMessage("ACK:MAP_START\n");
    return;
  }

  if (rx == "MAP,FINISH") {
    finalizeTrackMap();
    calculateSpeedProfiles();
    currentMode = MODE_IDLE;
    motorsEnabled = false;
    stopMotors();
    sendBleMessage("ACK:MAP_FINISH=" + String(mapSegmentCount) + "\n");
    return;
  }

  if (rx == "RACE,START") {
    if (mapSegmentCount > 0) {
      resetPID();
      currentMode = MODE_LINE_FOLLOW_RACE;
      raceSegIndex = 0;
      raceSegStartTick = (encLeftTicks + encRightTicks) / 2;
      motorsEnabled = true;
      sendBleMessage("ACK:RACE_START\n");
    } else {
      sendBleMessage("ERR:NO_MAP\n");
    }
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
  if (rx == "MIN?")       { sendBleMessage("ACK:MIN=" + String(minSpeed) + "\n"); return; }
  if (rx == "MAP_SPEED?" || rx == "MAP_SPD?") { sendBleMessage("ACK:MAP_SPEED=" + String(mapSpeed) + "\n"); return; }
  if (rx == "INV?")       { sendBleMessage("ACK:INV=" + String(invertSteering ? 1 : 0) + "\n"); return; }
  if (rx == "CONFIG?" || rx == "STATE?") {
    sendBleMessage("ACK:CONFIG=KP:" + String(Kp, 2) + ",KI:" + String(Ki, 2) + ",KD:" + String(Kd, 2) +
                   ",BASE:" + String(baseSpeed) + ",MAX:" + String(maxSpeed) + ",MIN:" + String(minSpeed) +
                   ",MAP_SPD:" + String(mapSpeed) + ",INV:" + String(invertSteering ? 1 : 0) + "\n");
    return;
  }

  // 3. Explicit Multi-Character Tokens (checked BEFORE single-letter aliases)
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
      if (val <= 255.0f && val > 0.0f) val *= 16.0f; // Scale 8-bit to 12-bit
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

  if (rx.startsWith("MAP_SPEED=") || rx.startsWith("MAP_SPD=")) {
    int eq = rx.indexOf('=');
    mapSpeed = constrain(rx.substring(eq + 1).toInt(), 30, 255);
    sendBleMessage("ACK:MAP_SPEED=" + String(mapSpeed) + "\n");
    return;
  }

  if (rx.startsWith("INV=")) {
    invertSteering = (rx.substring(4).toInt() != 0);
    sendBleMessage("ACK:INV=" + String(invertSteering ? 1 : 0) + "\n");
    return;
  }

  if (rx.startsWith("SEQ,ADD,")) {
    // Format: SEQ,ADD,<ACTION>,<PARAM>
    int firstComma  = rx.indexOf(',');
    int secondComma = rx.indexOf(',', firstComma + 1);
    int thirdComma  = rx.indexOf(',', secondComma + 1);

    if (secondComma != -1 && thirdComma != -1) {
      String action = rx.substring(secondComma + 1, thirdComma);
      action.toUpperCase();
      float param = rx.substring(thirdComma + 1).toFloat();
      bool success = false;

      if (action == "FWD") {
        success = enqueueStep(STEP_MOVE_FWD, param);
      } else if (action == "REV") {
        success = enqueueStep(STEP_MOVE_REV, param);
      } else if (action == "LEFT") {
        success = enqueueStep(STEP_TURN_LEFT, param);
      } else if (action == "RIGHT") {
        success = enqueueStep(STEP_TURN_RIGHT, param);
      } else if (action == "WAIT" || action == "PAUSE") {
        success = enqueueStep(STEP_PAUSE, param);
      }

      if (success) {
        sendBleMessage("ACK:SEQ_ADD=" + action + "," + String(param, 1) + "\n");
      } else {
        sendBleMessage("ERR:QUEUE_FULL\n");
      }
      return;
    }
    sendBleMessage("ERR:INVALID_PARAM=SEQ,ADD\n");
    return;
  }

  // 4. Guarded Single-Character Aliases (MUST be followed immediately by numeric digits/signs)
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
// 8. METRIC SENSOR ACQUISITION & CENTROID CALCULATION
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
// 9. CORE PID CONTROLLER WITH FILTERED DERIVATIVE
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
// 10. MOTOR CONTROL & ACTIVE DYNAMIC BRAKING
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

// High-Side Dynamic Clamping Brake (Clamps both terminals to VCC via high-side FETs)
void dynamicBrakeHighSide() {
  digitalWrite(LEFT_EN, HIGH); 
  digitalWrite(RIGHT_EN, HIGH);
  analogWrite(LEFT_RPWM, 255); 
  analogWrite(LEFT_LPWM, 255);
  analogWrite(RIGHT_RPWM, 255); 
  analogWrite(RIGHT_LPWM, 255);
}

// Active Reverse-Plug (Counter-Current) Braking: Applies reverse torque to stop momentum, then locks dynamic brake
void activePlugBrake(int plugPwm, uint32_t maxDurationMs) {
  digitalWrite(LEFT_EN, HIGH);
  digitalWrite(RIGHT_EN, HIGH);

  // Apply reverse polarity across H-bridge
  analogWrite(LEFT_RPWM, 0);
  analogWrite(LEFT_LPWM, constrain(plugPwm, 0, 255));
  analogWrite(RIGHT_RPWM, 0);
  analogWrite(RIGHT_LPWM, constrain(plugPwm, 0, 255));

  unsigned long start = millis();
  uint32_t lastTicks = encLeftTicks + encRightTicks;
  while ((millis() - start) < maxDurationMs) {
    delayMicroseconds(500);
    uint32_t currTicks = encLeftTicks + encRightTicks;
    if (currTicks == lastTicks && (millis() - start) >= 15) {
      break; // Motion halted
    }
    lastTicks = currTicks;
  }

  // Clamp to low-side dynamic brake to prevent rolling backward
  dynamicBrake();
}

void brakeMotors() {
  dynamicBrake();
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
// 11. TELEMETRY & COMPANION APP FEEDBACK
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
  // Store mode in bits 4..7 for diagnostics
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
// 12. FREERTOS CONTROL TASK & INITIALIZATION
// =============================================================================
TaskHandle_t controlTaskHandle = NULL;
unsigned long lastDebugMs = 0;

void vControlLoopTask(void *pvParameters) {
  TickType_t xLastWakeTime = xTaskGetTickCount();
  const TickType_t xFrequency = pdMS_TO_TICKS(3); // 3 ms period (~333.3 Hz)
  unsigned long lastTimeMicros = micros();

  for (;;) {
    vTaskDelayUntil(&xLastWakeTime, xFrequency);

    unsigned long nowMicros = micros();
    float dt = (nowMicros - lastTimeMicros) / 1000000.0f;
    if (dt <= 0.0f || dt > 0.05f) dt = 0.003f;
    lastTimeMicros = nowMicros;

    bool lineFound = readSensorArrayMetric();

    if (motorsEnabled) {
      switch (currentMode) {
        case MODE_LINE_FOLLOW_REACTIVE: {
          if (!lineFound) {
            handleLineLostRecovery();
          } else {
            lineLostStartTick = 0;
            float correction = computePID(currentErrorMm, dt);
            int leftSpeed  = baseSpeed + (int)correction;
            int rightSpeed = baseSpeed - (int)correction;
            setMotors(leftSpeed, rightSpeed);
          }
          break;
        }

        case MODE_LINE_FOLLOW_MAP: {
          executeMappingMode(lineFound, dt);
          break;
        }

        case MODE_LINE_FOLLOW_RACE: {
          executeRaceMode(lineFound, dt);
          break;
        }

        case MODE_SEQUENCE_RUN: {
          executeSequenceRunner();
          break;
        }

        case MODE_IDLE:
        default: {
          stopMotors();
          resetPID();
          break;
        }
      }
    } else {
      stopMotors();
      resetPID();
      lineLostStartTick = 0;
    }
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

  // BLE Stack (Runs on Core 0 with ESP32-S3 BT Controller)
  initBLE();

  // Pin Deterministic 333 Hz Real-Time Control Loop strictly to Core 1 (APP CPU)
  xTaskCreatePinnedToCore(
    vControlLoopTask,
    "ControlLoopTask",
    4096,
    NULL,
    10,               // High priority for microsecond-level determinism
    &controlTaskHandle,
    1                 // Core 1 (Leaving Core 0 dedicated to BLE radio & host stack)
  );

  Serial.println(F("[SYSTEM] ESP32-S3 Dual-Core Line Follower Ready: Core 0 [BLE], Core 1 [333Hz Control]."));
}

void loop() {
  // --- RATE-LIMITED BLE TELEMETRY (~22 Hz) ---
  if (deviceConnected) {
    sendTelemetry(currentErrorMm);
  }

  // --- DIAGNOSTIC LOGGING (10 Hz) ---
  unsigned long nowMs = millis();
  if (nowMs - lastDebugMs >= DEBUG_INTERVAL_MS) {
    lastDebugMs = nowMs;
    if (motorsEnabled) {
      Serial.printf("[RUN] Mode: %d | Err: %5.1fmm | L_Tick: %u | R_Tick: %u | Lost: %d | SeqRem: %d\n",
                    (int)currentMode, currentErrorMm, encLeftTicks, encRightTicks, isLineLost, seqCount);
    }
  }

  // Yield to FreeRTOS IDLE task to prevent CPU starvation and feed Task Watchdog (TWDT)
  vTaskDelay(pdMS_TO_TICKS(5));
}