# Hardware Fix - Command Protocol Update

## Problem
The Flutter app and ESP32 hardware were using **different command protocols**, causing:
- Start/Stop button in app not working
- PID values not updating on hardware
- Speed values not updating on hardware
- Sensor data visible in console but app not responsive

## Root Cause
**App sends:**
- `ROBOT,START` / `ROBOT,STOP` for start/stop
- `P,5.00,0.00` for combined P and I values
- `S,M,255` for max speed
- `S,B,150` for base speed

**Old hardware expected:**
- No start/stop command (only physical button)
- `p5.0` for Kp (separate commands)
- `i0.0` for Ki
- `m255` for max speed
- `s150` for base speed

## Solution
Updated `hardware_updated.ino` to support **both** protocols:

### New Commands (App Protocol)
1. **Start/Stop Robot:**
   - `ROBOT,START` - Starts the robot via Bluetooth
   - `ROBOT,STOP` - Stops the robot and kills motors

2. **PID Update:**
   - `P,{p_value},{i_value}` - Updates both Kp and Ki at once
   - Example: `P,5.00,0.00`

3. **Speed Update:**
   - `S,M,{value}` - Updates max speed
   - `S,B,{value}` - Updates base speed
   - Example: `S,M,255` or `S,B,150`

### Legacy Commands (Still Supported)
- `p{value}` - Set Kp
- `i{value}` - Set Ki
- `d{value}` - Set Kd
- `t{value}` - Set threshold
- `s{value}` - Set base speed
- `m{value}` - Set max speed
- `dm{value}` - Set mux delay

## Changes Made

### 1. Added ROBOT Command Handler
```cpp
if (btData.startsWith("ROBOT,")) {
    String action = btData.substring(6);
    if (action == "START") {
        isRunning = true;
        // Confirm to both Serial and Bluetooth
    } 
    else if (action == "STOP") {
        isRunning = false;
        setMotors(0, 0);
    }
}
```

### 2. Added Compound PID Parser
```cpp
if (btData.startsWith("P,")) {
    // Parse P,{p},{i} format
    // Update Kp and Ki
}
```

### 3. Added Compound Speed Parser
```cpp
if (btData.startsWith("S,")) {
    // Parse S,M,{value} or S,B,{value}
    // Update maxSpeed or baseSpeed
}
```

### 4. Enhanced Debugging
- Added emoji indicators for different command types
- Echo commands to both Serial Monitor and Bluetooth
- Clear success/failure messages

## Instructions

1. **Upload the new firmware:**
   - Open `hardware_updated.ino` in Arduino IDE
   - Upload to your ESP32

2. **Test with app:**
   - Connect via Bluetooth in the Flutter app
   - Click START button - robot should start moving
   - Adjust PID sliders - values should update
   - Click STOP button - robot should stop

3. **Monitor in Serial Monitor:**
   - You'll see all received commands with emojis:
   - 📥 for incoming commands
   - ✅ for START
   - ⏹️ for STOP
   - 🎯 for PID updates
   - ⚡ for max speed
   - 🏃 for base speed

## Expected Behavior Now

✅ **Start/Stop button in app** - Controls robot via Bluetooth
✅ **PID sliders** - Update Kp and Ki on hardware
✅ **Speed inputs** - Update max and base speed
✅ **Sensor visualization** - Still works (was already working)
✅ **Physical button** - Still works for start/stop toggle
✅ **Legacy commands** - Still supported for manual testing

## Testing Commands Manually

You can test via Serial Bluetooth Terminal app:
- `ROBOT,START` - Start robot
- `ROBOT,STOP` - Stop robot
- `P,5.00,0.50` - Set Kp=5.0, Ki=0.5
- `S,M,200` - Set max speed to 200
- `S,B,120` - Set base speed to 120

Or use legacy format:
- `p5.0` - Set Kp
- `i0.5` - Set Ki
- `s120` - Set base speed
