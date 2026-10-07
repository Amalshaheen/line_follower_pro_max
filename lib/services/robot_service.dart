import 'dart:async';
import 'package:flutter/material.dart';
import '../models/robot_state.dart';
import '../models/sequence_step.dart';

/// Abstract base class for the robot communication service ([BleService]).
///
/// Application logic depends on this interface for telemetry, command handling,
/// and sensor state management.
abstract class RobotService {
  // ---------------------------------------------------------------------------
  // Callbacks & Event Streams
  // ---------------------------------------------------------------------------

  /// Called when a raw text line is received that isn't handled by a more
  /// specific callback (e.g. status messages like "Robot Started").
  Function(String line)? get onDataReceived;

  /// Called when parsed sensor data arrives.
  /// [rawValues] — 12 analog readings (0–255 or 0–4095).
  /// [onLine]    — 12 boolean flags (true = sensor sees the line).
  Function(List<int> rawValues, List<bool> onLine)? get onSensorDataReceived;

  /// Called when high-speed 15-byte binary telemetry arrives over BLE.
  Function(TelemetryData telemetry)? get onTelemetryReceived;

  /// Called when the track-finished event arrives, with [runtimeMs] ≥ 0.
  Function(int runtimeMs)? get onTrackFinished;

  /// Called when an ACK is received from the hardware.
  /// [command] — the command key (e.g. "KP"), [value] — the echoed value.
  Function(String command, String value)? get onAckReceived;

  /// Called when updated threshold values are received from the hardware.
  Function(List<int> thresholds)? get onThresholdsReceived;

  /// Called when complete hardware state is reconciled via `CONFIG?`.
  Function(
    double kp,
    double ki,
    double kd,
    int baseSpeed,
    int maxSpeed,
    int minSpeed,
    bool invertSteering,
  )? get onConfigReceived;

  /// Called when the connection drops unexpectedly.
  VoidCallback? get onDisconnected;

  /// Stream firing when the hardware completes an autonomous motion sequence (`SEQ:DONE`).
  Stream<void> get onSequenceDone;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  bool get isConnected;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Request all required OS permissions. Returns true if all are granted.
  Future<bool> initializePermissions();

  /// Release all resources.
  Future<void> dispose();

  // ---------------------------------------------------------------------------
  // Communication
  // ---------------------------------------------------------------------------

  /// Send a raw command string to the robot (enqueued).
  ///
  /// Supports concise tuning commands (`P1.25`, `M255`, `S`) and compound
  /// protocol commands (`KP=30.00`, `RUN=1`, `THRALL=2000`).
  bool sendCommand(String command);

  /// Send a command asynchronously, waiting for an optional ACK prefix or safety throttle.
  Future<bool> sendCommandAsync(
    String command, {
    String? expectedAckPrefix,
    Duration timeout,
  });

  /// Automatically queries all hardware registers (`THRESH?`, `MASK?`, `CONFIG?`)
  /// to synchronize UI state with robot firmware.
  Future<void> queryHardwareState();

  /// Convenience: set a single global threshold for all sensors.
  bool sendThresholdForAllSensors(int threshold);

  /// Convenience: set the threshold for a single sensor by [index].
  bool sendThresholdForSensor({required int index, required int threshold});

  /// Enable or disable an individual sensor by [index].
  bool sendSensorEnable({required int index, required bool enabled});

  /// Enable or disable sensors via a bitmask (bit i = 1 means sensor i enabled).
  bool sendSensorMask(int mask);

  /// Synchronize the local list of enabled sensors.
  void setSensorEnabledList(List<bool> enabled);

  /// Set deadband compensation speed (0-255) to overcome BTS7960 stiction.
  bool sendMinSpeed(int minSpeed);

  /// Invert steering polarity for reversed sensor array or motor wiring.
  bool sendInvertSteering(bool invert);

  // ---------------------------------------------------------------------------
  // Autonomous Motion Queue & Sector Mapping
  // ---------------------------------------------------------------------------

  /// Uploads and initiates a sequential list of motion commands with safe throttling.
  Future<void> sendSequence(List<SequenceStep> steps);

  /// Immediately aborts execution of the current motion sequence.
  bool stopSequence();

  /// Starts line-following in sector/segment mapping mode (`MAP,START`).
  bool startMapping();

  /// Concludes mapping mode and computes velocity profiles (`MAP,FINISH`).
  bool finishMapping();

  /// Initiates predictive race mode using recorded track map (`RACE,START`).
  bool startRace();

  /// Sets independent sector mapping speed (`MAP_SPEED=<val>`).
  bool sendMapSpeed(int speed);
}
