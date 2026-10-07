#include <iostream>
#include <cassert>
#include <string>
#include <vector>
#include <cmath>
#include <cstring>
#include <cstdint>

struct String : public std::string {
  String() : std::string() {}
  String(const char* s) : std::string(s ? s : "") {}
  String(const std::string& s) : std::string(s) {}
  String(int v) : std::string(std::to_string(v)) {}
  String(unsigned int v) : std::string(std::to_string(v)) {}
  String(long v) : std::string(std::to_string(v)) {}
  String(unsigned long v) : std::string(std::to_string(v)) {}
  String(float v, int p = 2) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%.*f", p, v);
    *this = buf;
  }
  String(double v, int p = 2) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%.*f", p, v);
    *this = buf;
  }
  void trim() {
    while (!empty() && (front() == ' ' || front() == '\t' || front() == '\r' || front() == '\n')) erase(begin());
    while (!empty() && (back() == ' ' || back() == '\t' || back() == '\r' || back() == '\n')) pop_back();
  }
  bool endsWith(const char* s) const {
    size_t slen = strlen(s);
    if (length() < slen) return false;
    return compare(length() - slen, slen, s) == 0;
  }
  void remove(size_t index) {
    if (index < length()) erase(index);
  }
  bool equalsIgnoreCase(const char* s) const {
    if (length() != strlen(s)) return false;
    for (size_t i = 0; i < length(); i++) {
      if (tolower((unsigned char)(*this)[i]) != tolower((unsigned char)s[i])) return false;
    }
    return true;
  }
  bool startsWith(const char* s) const {
    size_t slen = strlen(s);
    if (length() < slen) return false;
    return compare(0, slen, s) == 0;
  }
  int indexOf(char c, size_t from = 0) const {
    auto pos = find(c, from);
    return (pos == std::string::npos) ? -1 : (int)pos;
  }
  String substring(size_t from, size_t to = std::string::npos) const {
    if (from >= length()) return String();
    size_t count = (to == std::string::npos) ? std::string::npos : (to - from);
    return String(substr(from, count));
  }
  int toInt() const {
    try { return std::stoi(*this); } catch (...) { return 0; }
  }
  float toFloat() const {
    try { return std::stof(*this); } catch (...) { return 0.0f; }
  }
  void toUpperCase() {
    for (auto &c : *this) c = toupper((unsigned char)c);
  }
};

template<typename T>
T constrain(T x, T a, T b) { return (x < a) ? a : (x > b) ? b : x; }

// Test capture for BLE TX messages
std::vector<std::string> capturedMessages;
void sendBleMessage(const String& msg) {
  capturedMessages.push_back(msg);
}

// Firmware variables
int sensorThresholds[12];
uint16_t sensorMask = 0x0FFF;
float defaultThreshold = 2000.0f;
bool motorsEnabled = false;
float Kp = 2.5f, Ki = 0.0f, Kd = 0.08f;
int baseSpeed = 70, maxSpeed = 120, minSpeed = 30;
bool invertSteering = false;
int mapSegmentCount = 0;

enum RobotMode : uint8_t {
  MODE_IDLE = 0,
  MODE_LINE_FOLLOW_REACTIVE,
  MODE_LINE_FOLLOW_MAP,
  MODE_LINE_FOLLOW_RACE,
  MODE_SEQUENCE_RUN
} currentMode = MODE_IDLE;

enum StepType : uint8_t {
  STEP_NONE = 0, STEP_MOVE_FWD, STEP_MOVE_REV, STEP_TURN_LEFT, STEP_TURN_RIGHT, STEP_PAUSE
};
struct SequenceStep { StepType type; float param; } sequenceQueue[32];
uint8_t seqHead = 0, seqTail = 0, seqCount = 0;
enum SeqState : uint8_t { SEQ_STATE_IDLE = 0, SEQ_STATE_START_STEP, SEQ_STATE_EXECUTING, SEQ_STATE_BRAKING } seqState = SEQ_STATE_IDLE;

bool enqueueStep(StepType type, float param) {
  if (seqCount >= 32) return false;
  sequenceQueue[seqTail].type = type;
  sequenceQueue[seqTail].param = param;
  seqTail = (seqTail + 1) % 32;
  seqCount++;
  return true;
}
void clearSequenceQueue() { seqHead = seqTail = seqCount = 0; seqState = SEQ_STATE_IDLE; }
void stopMotors() {}
void resetPID() {}
void clearTrackMap() {}
void finalizeTrackMap() {}
void calculateSpeedProfiles() {}
uint32_t encLeftTicks = 0, encRightTicks = 0, raceSegIndex = 0, raceSegStartTick = 0;

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

// Stream framing logic from firmware
const size_t RX_STREAM_BUFFER_SIZE = 256;
char rxStreamBuffer[RX_STREAM_BUFFER_SIZE];
size_t rxStreamBufferLen = 0;

static inline bool isNumericStart(char c) {
  return (c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.';
}

void handleCommand(String rx);

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
  if (rx == "MIN?")  { sendBleMessage("ACK:MIN=" + String(minSpeed) + "\n"); return; }
  if (rx == "INV?")  { sendBleMessage("ACK:INV=" + String(invertSteering ? 1 : 0) + "\n"); return; }
  if (rx == "CONFIG?" || rx == "STATE?") {
    sendBleMessage("ACK:CONFIG=KP:" + String(Kp, 2) + ",KI:" + String(Ki, 2) + ",KD:" + String(Kd, 2) +
                   ",BASE:" + String(baseSpeed) + ",MAX:" + String(maxSpeed) + ",MIN:" + String(minSpeed) +
                   ",INV:" + String(invertSteering ? 1 : 0) + "\n");
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

int main() {
  for (int i = 0; i < 12; i++) sensorThresholds[i] = 2000;

  std::cout << "--- Running Firmware Unit Tests ---" << std::endl;

  // Test 1: THR=2,1850 updates ONLY sensor 2
  capturedMessages.clear();
  handleCommand("THR=2,1850");
  assert(sensorThresholds[2] == 1850);
  assert(sensorThresholds[0] == 2000);
  assert(sensorThresholds[1] == 2000);
  assert(sensorThresholds[3] == 2000);
  assert(capturedMessages.size() == 2);
  assert(capturedMessages[0] == "ACK:THR=2,1850\n");
  assert(capturedMessages[1].rfind("THRESHOLDS:2000,2000,1850,2000", 0) == 0);
  std::cout << "[PASS] Test 1: THR=2,1850 updates only sensor 2" << std::endl;

  // Test 2: THRALL=2100 updates all 12 sensors
  capturedMessages.clear();
  handleCommand("THRALL=2100");
  for (int i = 0; i < 12; i++) assert(sensorThresholds[i] == 2100);
  assert(capturedMessages[0] == "ACK:THRALL=2100\n");
  std::cout << "[PASS] Test 2: THRALL=2100 updates all 12 sensors" << std::endl;

  // Test 3: T2000 updates all 12 sensors
  capturedMessages.clear();
  handleCommand("T2000");
  for (int i = 0; i < 12; i++) assert(sensorThresholds[i] == 2000);
  assert(capturedMessages[0] == "ACK:THRALL=2000\n");
  std::cout << "[PASS] Test 3: T2000 updates all 12 sensors" << std::endl;

  // Test 4: TIME? does NOT trigger T
  capturedMessages.clear();
  handleCommand("TIME?");
  assert(capturedMessages.size() == 1);
  assert(capturedMessages[0] == "ERR:UNKNOWN_CMD=TIME?\n");
  std::cout << "[PASS] Test 4: TIME? does NOT trigger T" << std::endl;

  // Test 5: SEQ,ADD,FWD,10 does NOT trigger S
  capturedMessages.clear();
  clearSequenceQueue();
  handleCommand("SEQ,ADD,FWD,10");
  assert(seqCount == 1);
  assert(sequenceQueue[0].type == STEP_MOVE_FWD);
  assert(std::fabs(sequenceQueue[0].param - 10.0f) < 0.001f);
  assert(capturedMessages.size() == 1);
  assert(capturedMessages[0] == "ACK:SEQ_ADD=FWD,10.0\n");
  std::cout << "[PASS] Test 5: SEQ,ADD,FWD,10 correctly queued without triggering S" << std::endl;

  // Test 6: S toggles run/stop
  capturedMessages.clear();
  motorsEnabled = false;
  handleCommand("S");
  assert(motorsEnabled == true);
  assert(capturedMessages[0] == "ACK:RUN=1\n");
  capturedMessages.clear();
  handleCommand("S");
  assert(motorsEnabled == false);
  assert(capturedMessages[0] == "ACK:RUN=0\n");
  std::cout << "[PASS] Test 6: S toggles run/stop" << std::endl;

  // Test 7: SENS? and MASK? do NOT trigger S
  capturedMessages.clear();
  handleCommand("SENS?");
  assert(motorsEnabled == false);
  assert(capturedMessages[0] == "MASK:4095\n");
  std::cout << "[PASS] Test 7: SENS? queries mask without triggering S" << std::endl;

  // Test 8: Stream framing with multiple concatenated commands
  capturedMessages.clear();
  const char* stream1 = "KP=3.14\nKD=0.09\n";
  processRxStream((const uint8_t*)stream1, strlen(stream1));
  assert(std::fabs(Kp - 3.14f) < 0.01f);
  assert(std::fabs(Kd - 0.09f) < 0.01f);
  assert(capturedMessages.size() == 2);
  assert(capturedMessages[0] == "ACK:KP=3.14\n");
  assert(capturedMessages[1] == "ACK:KD=0.09\n");
  std::cout << "[PASS] Test 8: Multiple commands in single stream buffer parsed correctly" << std::endl;

  // Test 9: Stream framing across chunked packets
  capturedMessages.clear();
  const char* chunk1 = "BASE=";
  const char* chunk2 = "85\n";
  processRxStream((const uint8_t*)chunk1, strlen(chunk1));
  assert(capturedMessages.empty());
  processRxStream((const uint8_t*)chunk2, strlen(chunk2));
  assert(baseSpeed == 85);
  assert(capturedMessages.size() == 1);
  assert(capturedMessages[0] == "ACK:BASE=85\n");
  std::cout << "[PASS] Test 9: Fragmented stream chunks accumulated and processed on delimiter" << std::endl;

  // Test 10: CONFIG? query
  capturedMessages.clear();
  handleCommand("CONFIG?");
  assert(capturedMessages.size() == 1);
  assert(capturedMessages[0].rfind("ACK:CONFIG=KP:", 0) == 0);
  std::cout << "[PASS] Test 10: CONFIG? query responded with all parameters" << std::endl;

  std::cout << "ALL 10 TESTS PASSED SUCCESSFULLY!" << std::endl;
  return 0;
}
