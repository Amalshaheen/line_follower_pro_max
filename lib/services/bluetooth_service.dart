import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_constants.dart';

/// Service for managing Bluetooth communication with the line follower robot.
class BluetoothService {
  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _inputSubscription;
  String _incomingBuffer = '';

  // Callbacks for handling incoming data and connection changes
  final Function(String line)? onDataReceived;
  final Function(List<int> rawValues, List<bool> onLine)? onSensorDataReceived;
  final Function(int runtimeMs)? onTrackFinished;
  final Function(String command, String value)? onAckReceived;
  final VoidCallback? onDisconnected;

  bool get isConnected => _connection != null;

  BluetoothService({
    this.onDataReceived,
    this.onSensorDataReceived,
    this.onTrackFinished,
    this.onAckReceived,
    this.onDisconnected,
  });

  /// Initialize Bluetooth permissions.
  Future<bool> initializePermissions() async {
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      return statuses.values.every((status) => status.isGranted);
    } catch (e) {
      debugPrint('Permission initialization error: $e');
      return false;
    }
  }

  /// Get a list of bonded Bluetooth devices.
  Future<List<BluetoothDevice>> getBondedDevices() async {
    try {
      return await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      debugPrint('Error getting bonded devices: $e');
      return [];
    }
  }

  /// Connect to a specific Bluetooth device.
  Future<bool> connect(BluetoothDevice device) async {
    if (_connection != null) {
      await disconnect();
    }

    try {
      debugPrint('🔌 [BT CONNECT] Attempting to connect to ${device.name} (${device.address})');
      
      final connection = await BluetoothConnection.toAddress(device.address);
      
      if (connection.isConnected) {
        _connection = connection;

        await _inputSubscription?.cancel();
        
        if (connection.input != null) {
          _inputSubscription = connection.input!.listen(
            _handleIncomingData,
            onDone: _handleDisconnected,
            onError: (Object error) {
              debugPrint('❌ [BT CONNECT] Bluetooth input error: $error');
              _handleDisconnected();
            },
          );
        }

        debugPrint('✅ [BT CONNECT] Successfully connected to ${device.address}');
        return true;
      } else {
        debugPrint('❌ [BT CONNECT] Connection established but isConnected is false');
        await connection.close();
        return false;
      }
    } catch (e) {
      debugPrint('❌ [BT CONNECT] Connection error: $e');
      _connection = null;
      return false;
    }
  }

  /// Disconnect from the Bluetooth device.
  Future<void> disconnect() async {
    debugPrint('🔌 [BT DISCONNECT] Disconnecting from Bluetooth device...');
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    await _connection?.close();
    _connection = null;
    debugPrint('✅ [BT DISCONNECT] Successfully disconnected');
  }

  /// Send a command to the connected device.
  bool sendCommand(String command) {
    if (_connection == null) {
      debugPrint('❌ [BT SEND] FAILED - Not connected. Command: $command');
      return false;
    }

    try {
      final commandWithNewline = '$command\n';
      final encodedCommand = utf8.encode(commandWithNewline);
      
      debugPrint('📤 [BT SEND] Sending command: "$command"');
      debugPrint('   └─ Length: ${encodedCommand.length} bytes');
      
      _connection!.output.add(encodedCommand);
      
      debugPrint('✅ [BT SEND] Command sent successfully!');
      return true;
    } catch (e) {
      debugPrint('❌ [BT SEND] Error sending command "$command": $e');
      return false;
    }
  }

  /// Handle incoming data from the Bluetooth device.
  void _handleIncomingData(Uint8List data) {
    final chunk = utf8.decode(data, allowMalformed: true);
    debugPrint('📥 [BT RECEIVE] Raw data: "$chunk" (${data.length} bytes)');
    
    _incomingBuffer += chunk;

    while (_incomingBuffer.contains('\n')) {
      final index = _incomingBuffer.indexOf('\n');
      final line = _incomingBuffer.substring(0, index).trim();
      _incomingBuffer = _incomingBuffer.substring(index + 1);

      if (line.isNotEmpty) {
        debugPrint('📨 [BT RECEIVE] Complete message: "$line"');
        _processLine(line);
      }
    }
  }

  /// Process a complete line of incoming data.
  void _processLine(String line) {
    debugPrint('📨 [BT PROCESS] Processing line: "$line" (length: ${line.length})');
    
    // Check for sensor data (format: SENSORS:val0,val1,...,val11)
    if (line.startsWith(AppConstants.respSensors)) {
      final payload = line.substring(AppConstants.respSensors.length);
      final parts = payload.split(',');
      
      debugPrint('📥 [SENSORS] Raw payload: "$payload" (${parts.length} values)');
      
      if (parts.length == AppConstants.sensorCount) {
        // Parse raw analog values
        final rawValues = parts.map((v) => int.tryParse(v.trim()) ?? 0).toList();
        
        // For now, determine on/off using a simple threshold (midpoint of typical range)
        // The hardware handles thresholding internally for PID, but we need to display
        // This threshold can be adjusted or made configurable
        const displayThreshold = 2000; // Midpoint of 0-4095 ADC range
        final onLine = rawValues.map((v) => v > displayThreshold).toList();
        
        // Debug output for sensor changes
        final sensorStates = onLine.map((s) => s ? '🟢' : '⚫').join(' ');
        debugPrint('🔍 [SENSORS] Sensor states: [$sensorStates]');
        debugPrint('   └─ Raw values: ${rawValues.join(', ')}');
        
        onSensorDataReceived?.call(rawValues, onLine);
      } else {
        debugPrint('⚠️ [SENSORS] Expected ${AppConstants.sensorCount} values, got ${parts.length}');
      }
      return;
    }
    
    // Check for track finished
    if (line == AppConstants.respTrackFinished) {
      debugPrint('🏁 [TRACK] Track finished!');
      onTrackFinished?.call(0); // Runtime will come from TIME= response
      return;
    }
    
    // Check for time response (format: TIME=123456)
    if (line.startsWith(AppConstants.respTimePrefix)) {
      final timeStr = line.substring(AppConstants.respTimePrefix.length);
      final runtime = int.tryParse(timeStr) ?? 0;
      debugPrint('⏱️ [TIME] Runtime: ${runtime}ms');
      onTrackFinished?.call(runtime);
      return;
    }
    
    // Check for ACK response (format: ACK:COMMAND=VALUE)
    if (line.startsWith(AppConstants.respAck)) {
      final ackContent = line.substring(AppConstants.respAck.length);
      debugPrint('✅ [ACK] Received: $ackContent');
      // Parse command and value from ACK (e.g., "KP=30.0")
      final eqIndex = ackContent.indexOf('=');
      if (eqIndex > 0) {
        final command = ackContent.substring(0, eqIndex);
        final value = ackContent.substring(eqIndex + 1);
        onAckReceived?.call(command, value);
      } else {
        onAckReceived?.call(ackContent, '');
      }
      return;
    }

    // Otherwise, treat it as a regular message
    onDataReceived?.call(line);
  }

  /// Handle disconnection from the Bluetooth device.
  void _handleDisconnected() {
    debugPrint('⚠️  [BT DISCONNECT] Bluetooth disconnected unexpectedly!');
    _connection = null;
    _incomingBuffer = '';
    onDisconnected?.call();
  }

  /// Clean up resources.
  Future<void> dispose() async {
    await disconnect();
  }
}
