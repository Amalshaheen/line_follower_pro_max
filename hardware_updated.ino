#include "BluetoothSerial.h"

// --- Initialize Bluetooth ---
BluetoothSerial SerialBT;

// --- Motor Pins (TB6612FNG) ---
const int AIN1 = 13;
const int AIN2 = 14;
const int PWMA = 26;

const int BIN1 = 12;
const int BIN2 = 27;
const int PWMB = 25;
const int STBY = 33;

// --- Interface Pins ---
const int START_BUTTON = 21;
const int BLACK_BUTTON = 4; 
const int WHITE_BUTTON = 15; 
const int ONBOARD_LED = 2;

// --- Multiplexer Pins ---
const int MUX_SIG = 34;
const int S0 = 16;
const int S1 = 5;
const int S2 = 18;
const int S3 = 19;
const int NUM_SENSORS = 12;

// --- Line Detection Settings (Now Dynamic) ---
int threshold = 600;       // Removed 'const' so it can be changed via BT
int lastPosition = 5500;   // Default center position (11 sensors * 1000 / 2)

// --- PID Variables ---
float Kp = 5.0;  // Proportional multiplier
float Ki = 0.0;  // Integral multiplier
float Kd = 0.0;  // Derivative multiplier

int P, I, D;
int lastError = 0;

// --- Speed & Delay Settings (Now Dynamic) ---
int baseSpeed = 150; // Removed 'const' 
int maxSpeed = 255;  // Removed 'const' 
int muxDelay = 80;   // Dynamic delay for delayMicroseconds

bool isRunning = false;

void setup() {
  Serial.begin(115200);
  
  // Start Bluetooth Serial
  SerialBT.begin("ESP32_LineFollower"); // This is the name you will see on your phone!
  Serial.println("Bluetooth Started! Ready to pair.");

  // Initialize MUX pins
  pinMode(S0, OUTPUT);
  pinMode(S1, OUTPUT);
  pinMode(S2, OUTPUT);
  pinMode(S3, OUTPUT);
  pinMode(MUX_SIG, INPUT);
  
  // ESP32 ADC Setup
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // Initialize Motor Pins
  pinMode(AIN1, OUTPUT);
  pinMode(AIN2, OUTPUT);
  pinMode(PWMA, OUTPUT);
  pinMode(BIN1, OUTPUT);
  pinMode(BIN2, OUTPUT);
  pinMode(PWMB, OUTPUT);
  pinMode(STBY, OUTPUT);
  
  // Initialize Interface Pins
  pinMode(START_BUTTON, INPUT_PULLUP);
  pinMode(BLACK_BUTTON, INPUT_PULLUP);
  pinMode(WHITE_BUTTON, INPUT_PULLUP);
  pinMode(ONBOARD_LED, OUTPUT);

  // Enable the motor driver
  digitalWrite(STBY, HIGH); 
  
  // Wait for initial start button press OR Bluetooth start command
  Serial.println("Waiting for start button or Bluetooth START command...");
  while (!isRunning && digitalRead(START_BUTTON) == HIGH) {
    checkBluetooth();   // Listen for BT commands while waiting
    printVisualizer();  // Print sensor blocks continuously while waiting
    delay(10); 
  }
  
  if (digitalRead(START_BUTTON) == LOW) {
    isRunning = true;
  }
  
  if (isRunning) {
    delay(1000); // 1-second delay before moving
  }
}


void loop() {
  // Always check for incoming Bluetooth commands
  checkBluetooth();

  // Always print the visualizer blocks (timer-managed inside the function)
  printVisualizer();

  // --- 1. Check for Start/Stop Toggle ---
  if (digitalRead(START_BUTTON) == LOW) {
    isRunning = !isRunning; 
    
    if (!isRunning) {
      setMotors(0, 0);
    }
    delay(500); // Debounce delay
  }

  // --- 2. Run PID only if active ---
  if (isRunning) {
    int position = getLinePosition();
    int error = 5500 - position; 

    P = error;
    I = I + error;
    D = error - lastError;
    lastError = error;

    int motorSpeedAdjustment = (P * Kp) + (I * Ki) + (D * Kd);

    int leftSpeed = baseSpeed - motorSpeedAdjustment;
    int rightSpeed = baseSpeed + motorSpeedAdjustment;

    if (leftSpeed > maxSpeed) leftSpeed = maxSpeed;
    if (rightSpeed > maxSpeed) rightSpeed = maxSpeed;
    if (leftSpeed < -maxSpeed) leftSpeed = -maxSpeed;
    if (rightSpeed < -maxSpeed) rightSpeed = -maxSpeed;

    setMotors(leftSpeed, rightSpeed);
  }
}

// ====================================================================
// FUNCTIONS
// ====================================================================

// --- Visualizer Function (Prints to PC and Phone) ---
void printVisualizer() {
  static unsigned long lastPrintTime = 0;
  
  // Only print every 50ms so we don't slow down the PID loop!
  if (millis() - lastPrintTime > 50) {
    lastPrintTime = millis();
    
    String visualLine = "[";
    
    for (int i = 0; i < NUM_SENSORS; i++) {
      int value = readMux(i); 
      
      // If the sensor sees the line, send '_'. Otherwise, send a space.
      // This format is parsed by the Flutter app to display sensor state
      if (value > threshold) { 
        visualLine += "_";  x
      } 
      else {
        visualLine += " "; 
      }
    }
    
    visualLine += "]";
    
    // Print the clean block line to PC Serial Monitor
    Serial.println(visualLine);

    // Print the clean block line to Phone Bluetooth Monitor
    SerialBT.println(visualLine);
  }
}

// --- Function to Check and Parse Bluetooth Commands ---
void checkBluetooth() {
  if (SerialBT.available()) {
    String btData = SerialBT.readStringUntil('\n'); 
    btData.trim(); 

    if (btData.length() > 0) {
      Serial.print("📥 Received: "); 
      Serial.println(btData);

      // --- NEW: Handle App's Comma-Separated Commands ---
      
      // ROBOT,START or ROBOT,STOP
      if (btData.startsWith("ROBOT,")) {
        String action = btData.substring(6); // Get part after "ROBOT,"
        action.trim();
        
        if (action == "START") {
          isRunning = true;
          SerialBT.println("✅ Robot STARTED");
          Serial.println("✅ Robot STARTED");
        } 
        else if (action == "STOP") {
          isRunning = false;
          setMotors(0, 0); // Stop motors immediately
          SerialBT.println("⏹️ Robot STOPPED");
          Serial.println("⏹️ Robot STOPPED");
        }
        return;
      }
      
      // P,{p_value},{i_value} - Combined PID command from app
      if (btData.startsWith("P,")) {
        int firstComma = btData.indexOf(',');
        int secondComma = btData.indexOf(',', firstComma + 1);
        
        if (secondComma > 0) {
          String pStr = btData.substring(firstComma + 1, secondComma);
          String iStr = btData.substring(secondComma + 1);
          
          Kp = pStr.toFloat();
          Ki = iStr.toFloat();
          
          SerialBT.print("🎯 PID Updated -> Kp: ");
          SerialBT.print(Kp);
          SerialBT.print(", Ki: ");
          SerialBT.println(Ki);
          
          Serial.print("🎯 PID Updated -> Kp: ");
          Serial.print(Kp);
          Serial.print(", Ki: ");
          Serial.println(Ki);
        }
        return;
      }
      
      // S,M,{value} or S,B,{value} - Speed commands from app
      if (btData.startsWith("S,")) {
        int firstComma = btData.indexOf(',');
        int secondComma = btData.indexOf(',', firstComma + 1);
        
        if (secondComma > 0) {
          String speedType = btData.substring(firstComma + 1, secondComma);
          String valueStr = btData.substring(secondComma + 1);
          
          speedType.trim();
          
          if (speedType == "M") { // Max speed
            maxSpeed = valueStr.toInt();
            SerialBT.print("⚡ Max Speed updated to: ");
            SerialBT.println(maxSpeed);
            Serial.print("⚡ Max Speed updated to: ");
            Serial.println(maxSpeed);
          } 
          else if (speedType == "B") { // Base speed
            baseSpeed = valueStr.toInt();
            SerialBT.print("🏃 Base Speed updated to: ");
            SerialBT.println(baseSpeed);
            Serial.print("🏃 Base Speed updated to: ");
            Serial.println(baseSpeed);
          }
        }
        return;
      }

      // --- LEGACY: Keep backward compatibility with old single-char commands ---
      
      if (btData.startsWith("dm")) {
        muxDelay = btData.substring(2).toInt();
        SerialBT.print("⏱️ Mux Delay updated to: "); SerialBT.println(muxDelay);
        Serial.print("⏱️ Mux Delay updated to: "); Serial.println(muxDelay);
      } 
      else {
        char cmd = btData.charAt(0);                
        float value = btData.substring(1).toFloat(); 
        
        switch (cmd) {
          case 'p': 
            Kp = value; 
            SerialBT.print("Kp updated to: "); SerialBT.println(Kp);
            Serial.print("Kp updated to: "); Serial.println(Kp);
            break;
          case 'i': 
            Ki = value; 
            SerialBT.print("Ki updated to: "); SerialBT.println(Ki);
            Serial.print("Ki updated to: "); Serial.println(Ki);
            break;
          case 'd': 
            Kd = value; 
            SerialBT.print("Kd updated to: "); SerialBT.println(Kd);
            Serial.print("Kd updated to: "); Serial.println(Kd);
            break;
          case 't': 
            threshold = (int)value; 
            SerialBT.print("Threshold updated to: "); SerialBT.println(threshold);
            Serial.print("Threshold updated to: "); Serial.println(threshold);
            break;
          case 's': 
            baseSpeed = (int)value; 
            SerialBT.print("Base Speed updated to: "); SerialBT.println(baseSpeed);
            Serial.print("Base Speed updated to: "); Serial.println(baseSpeed);
            break;
          case 'm': 
            maxSpeed = (int)value; 
            SerialBT.print("Max Speed updated to: "); SerialBT.println(maxSpeed);
            Serial.print("Max Speed updated to: "); Serial.println(maxSpeed);
            break;
          default: 
            SerialBT.println("❌ Unknown command!"); 
            Serial.println("❌ Unknown command!");
            break;
        }
      }
    }
  }
}

// --- Reads sensors and calculates weighted average position ---
int getLinePosition() {
  long weightedSum = 0;
  long sum = 0;
  bool onLine = false;

  for (int i = 0; i < NUM_SENSORS; i++) {
    int value = readMux(i);
    
    if (value > threshold) {
      onLine = true;
      weightedSum += (long)value * (i * 1000); 
      sum += value;
    }
  }

  if (!onLine) {
    if (lastPosition < 5500) return 0;       
    else return 11000;                       
  }

  lastPosition = weightedSum / sum;
  return lastPosition;
}

// --- Reads a specific channel on the 74HC4067 MUX ---
int readMux(int channel) {
  digitalWrite(S0, bitRead(channel, 0));
  digitalWrite(S1, bitRead(channel, 1));
  digitalWrite(S2, bitRead(channel, 2));
  digitalWrite(S3, bitRead(channel, 3));
  delayMicroseconds(muxDelay); 
  return analogRead(MUX_SIG);
}

// --- Controls TB6612FNG Motors ---
void setMotors(int leftSpeed, int rightSpeed) {
  // Left Motor (A)
  if (leftSpeed >= 0) {
    digitalWrite(AIN1, HIGH);
    digitalWrite(AIN2, LOW);
  } else {
    digitalWrite(AIN1, LOW);
    digitalWrite(AIN2, HIGH);
    leftSpeed = -leftSpeed; 
  }
  analogWrite(PWMA, leftSpeed);

  // Right Motor (B)
  if (rightSpeed >= 0) {
    digitalWrite(BIN1, HIGH);
    digitalWrite(BIN2, LOW);
  } else {
    digitalWrite(BIN1, LOW);
    digitalWrite(BIN2, HIGH);
    rightSpeed = -rightSpeed; 
  }
  analogWrite(PWMB, rightSpeed);
}
