import 'dart:async';
import 'package:flutter/material.dart';
import '../models/robot_state.dart';

/// Enumerates the two supported connection transport types.
enum ConnectionMode { classic, ble }

/// Abstract base class that both [BluetoothService] (classic SPP) and
/// [BleService] (BLE / Nordic UART Service) implement.
///
/// All application logic should depend on this interface so that switching
/// between transport types requires no changes to the dashboard or widgets.
abstract class RobotService {
  // ---------------------------------------------------------------------------
  // Callbacks
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

  /// Called when the connection drops unexpectedly.
  VoidCallback? get onDisconnected;

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

  /// Send a raw command string to the robot.
  ///
  /// Supports concise tuning commands (`P1.25`, `M255`, `S`) and compound
  /// protocol commands (`KP=30.00`, `RUN=1`, `THRALL=2000`).
  bool sendCommand(String command);

  /// Convenience: set a single global threshold for all sensors.
  bool sendThresholdForAllSensors(int threshold);

  /// Convenience: set the threshold for a single sensor by [index].
  bool sendThresholdForSensor({required int index, required int threshold});
}
