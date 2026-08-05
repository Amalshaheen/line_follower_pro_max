import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_constants.dart';
import 'robot_service.dart';

export 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show BluetoothDevice, ScanResult, BluetoothAdapterState;

/// BLE (Nordic UART Service) implementation of [RobotService].
///
/// Scans for BLE peripherals and connects to one using the NUS service.
/// The hardware must speak the same app-level text protocol as the classic
/// Bluetooth version:
///
///   App → Bot : "KP=30.00\n", "RUN=1\n", "THRALL=2000\n", …
///   Bot → App : "SENSORS:0,0,…\n", "ACK:KP=30.00\n", …
class BleService implements RobotService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar; // bot → app (NOTIFY)
  BluetoothCharacteristic? _rxChar; // app → bot (WRITE)
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  String _incomingBuffer = '';
  List<int> _sensorThresholds = List<int>.filled(
    AppConstants.sensorCount,
    AppConstants.defaultThreshold,
  );

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------
  @override
  final Function(String line)? onDataReceived;
  @override
  final Function(List<int> rawValues, List<bool> onLine)? onSensorDataReceived;
  @override
  final Function(int runtimeMs)? onTrackFinished;
  @override
  final Function(String command, String value)? onAckReceived;
  @override
  final Function(List<int> thresholds)? onThresholdsReceived;
  @override
  final VoidCallback? onDisconnected;

  @override
  bool get isConnected => _device != null && _rxChar != null;

  BleService({
    this.onDataReceived,
    this.onSensorDataReceived,
    this.onTrackFinished,
    this.onAckReceived,
    this.onThresholdsReceived,
    this.onDisconnected,
  });

  // ---------------------------------------------------------------------------
  // BLE-specific API
  // ---------------------------------------------------------------------------

  /// Start scanning for BLE peripherals.
  ///
  /// Filters by the NUS service UUID so only compatible devices appear.
  /// Returns a stream of [ScanResult]s that the UI can display.
  Stream<List<ScanResult>> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    FlutterBluePlus.startScan(
      timeout: timeout,
      withServices: [Guid(AppConstants.bleServiceUuid)],
    );
    return FlutterBluePlus.scanResults;
  }

  /// Start scanning without filtering by service UUID — shows ALL nearby
  /// BLE devices. Useful when the device doesn't advertise the service UUID.
  Stream<List<ScanResult>> startScanAll({
    Duration timeout = const Duration(seconds: 10),
  }) {
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults;
  }

  /// Stop an ongoing scan.
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  /// Whether a scan is currently running.
  Stream<bool> get isScanningStream => FlutterBluePlus.isScanning;

  /// Current BLE adapter state.
  Stream<BluetoothAdapterState> get adapterStateStream =>
      FlutterBluePlus.adapterState;

  /// Connect to a BLE device discovered via scan.
  Future<bool> connect(BluetoothDevice device) async {
    if (isConnected) {
      await disconnect();
    }

    try {
      debugPrint('🔌 [BLE CONNECT] Connecting to ${device.platformName} …');
      // Pass mtu: null to skip automatic MTU negotiation, which can cause
      // AUTHENTICATION_FAILURE disconnects on some dual-mode ESP32 boards.
      await device.connect(
        timeout: const Duration(seconds: 15),
        mtu: null,
      );
      // Discover services
      final services = await device.discoverServices();
      debugPrint('🔍 [BLE CONNECT] Found ${services.length} services');
      for (final s in services) {
        debugPrint('   Service UUID: ${s.serviceUuid}');
      }

      // Find NUS service — compare normalised UUIDs (strip dashes, lowercase)
      final targetUuid = AppConstants.bleServiceUuid
          .replaceAll('-', '').toLowerCase();

      BluetoothService? nus;
      for (final s in services) {
        final sUuid = s.serviceUuid.str128
            .replaceAll('-', '').toLowerCase();
        if (sUuid == targetUuid) {
          nus = s;
          break;
        }
      }

      if (nus == null) {
        debugPrint('❌ [BLE CONNECT] NUS service not found. Check that the '
            'hardware is advertising the correct service UUID.');
        await device.disconnect();
        return false;
      }

      // Find TX (notify) and RX (write) characteristics
      final txUuid = AppConstants.bleTxCharUuid
          .replaceAll('-', '').toLowerCase();
      final rxUuid = AppConstants.bleRxCharUuid
          .replaceAll('-', '').toLowerCase();

      for (final c in nus.characteristics) {
        final uuid = c.characteristicUuid.str128
            .replaceAll('-', '').toLowerCase();
        debugPrint('   Characteristic: $uuid');
        if (uuid == txUuid) {
          _txChar = c;
        } else if (uuid == rxUuid) {
          _rxChar = c;
        }
      }

      if (_txChar == null || _rxChar == null) {
        debugPrint('❌ [BLE CONNECT] NUS characteristics not found. '
            'TX=$_txChar, RX=$_rxChar');
        await device.disconnect();
        return false;
      }

      // Subscribe to notifications from the bot
      await _txChar!.setNotifyValue(true);
      await _notifySubscription?.cancel();
      _notifySubscription = _txChar!.onValueReceived.listen(
        _handleIncomingData,
        onError: (Object e) {
          debugPrint('❌ [BLE NOTIFY] Error: $e');
          _handleDisconnected();
        },
      );

      // Monitor connection state
      await _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnected();
        }
      });

      _device = device;
      debugPrint('✅ [BLE CONNECT] Connected to ${device.platformName}');
      return true;
    } catch (e) {
      debugPrint('❌ [BLE CONNECT] Error: $e');
      _device = null;
      _rxChar = null;
      _txChar = null;
      return false;
    }
  }

  /// Disconnect from the BLE device.
  Future<void> disconnect() async {
    debugPrint('🔌 [BLE DISCONNECT] Disconnecting …');
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _rxChar = null;
    _txChar = null;
    _incomingBuffer = '';
    debugPrint('✅ [BLE DISCONNECT] Disconnected');
  }

  // ---------------------------------------------------------------------------
  // RobotService implementation
  // ---------------------------------------------------------------------------

  @override
  Future<bool> initializePermissions() async {
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      return statuses.values.every((s) => s.isGranted);
    } catch (e) {
      debugPrint('BLE permission error: $e');
      return false;
    }
  }

  @override
  bool sendCommand(String command) {
    if (_rxChar == null) {
      debugPrint('❌ [BLE SEND] Not connected. Command: $command');
      return false;
    }
    try {
      final bytes = utf8.encode('$command\n');
      debugPrint('📤 [BLE SEND] "$command"  (${bytes.length} bytes)');
      // withoutResponse=true for higher throughput on BLE UART
      _rxChar!.write(bytes, withoutResponse: true);
      return true;
    } catch (e) {
      debugPrint('❌ [BLE SEND] Error: $e');
      return false;
    }
  }

  @override
  bool sendThresholdForAllSensors(int threshold) {
    return sendCommand('${AppConstants.cmdThresholdAllPrefix}$threshold');
  }

  @override
  bool sendThresholdForSensor({required int index, required int threshold}) {
    if (index < 0 || index >= AppConstants.sensorCount) {
      debugPrint('❌ [THRESHOLD] Invalid sensor index: $index');
      return false;
    }
    return sendCommand(
      '${AppConstants.cmdThresholdSinglePrefix}$index,$threshold',
    );
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await FlutterBluePlus.stopScan();
  }

  // ---------------------------------------------------------------------------
  // Incoming data handling — identical protocol to BluetoothService
  // ---------------------------------------------------------------------------

  void _handleIncomingData(List<int> data) {
    final chunk = utf8.decode(data, allowMalformed: true);
    debugPrint('📥 [BLE RECEIVE] "${chunk.trim()}" (${data.length} bytes)');

    _incomingBuffer += chunk;

    while (_incomingBuffer.contains('\n')) {
      final idx = _incomingBuffer.indexOf('\n');
      final line = _incomingBuffer.substring(0, idx).trim();
      _incomingBuffer = _incomingBuffer.substring(idx + 1);

      if (line.isNotEmpty) {
        debugPrint('📨 [BLE RECEIVE] Complete message: "$line"');
        _processLine(line);
      }
    }
  }

  void _processLine(String line) {
    // SENSORS:val0,val1,...,val11
    if (line.startsWith(AppConstants.respSensors)) {
      final payload = line.substring(AppConstants.respSensors.length);
      final parts = payload.split(',');

      if (parts.length == AppConstants.sensorCount) {
        final rawValues = parts.map((v) => int.tryParse(v.trim()) ?? 0).toList();
        final thresholds = _sensorThresholds.length == AppConstants.sensorCount
            ? _sensorThresholds
            : List<int>.filled(AppConstants.sensorCount, AppConstants.defaultThreshold);
        final onLine = List<bool>.generate(
          AppConstants.sensorCount,
          (i) => rawValues[i] > thresholds[i],
        );
        onSensorDataReceived?.call(rawValues, onLine);
      } else {
        debugPrint(
          '⚠️ [BLE SENSORS] Expected ${AppConstants.sensorCount} values, got ${parts.length}',
        );
      }
      return;
    }

    // THRESHOLDS:val0,...,val11
    if (line.startsWith(AppConstants.respThresholds)) {
      final payload = line.substring(AppConstants.respThresholds.length);
      final parts = payload.split(',');
      if (parts.length == AppConstants.sensorCount) {
        _sensorThresholds = parts
            .map((v) => int.tryParse(v.trim()) ?? 0)
            .toList(growable: false);
        onThresholdsReceived?.call(List<int>.from(_sensorThresholds));
      }
      return;
    }

    // TRACK_FINISHED
    if (line == AppConstants.respTrackFinished) {
      debugPrint('🏁 [BLE TRACK] Track finished!');
      onTrackFinished?.call(0);
      return;
    }

    // TIME=123456
    if (line.startsWith(AppConstants.respTimePrefix)) {
      final timeStr = line.substring(AppConstants.respTimePrefix.length);
      final runtime = int.tryParse(timeStr) ?? 0;
      onTrackFinished?.call(runtime);
      return;
    }

    // ACK:COMMAND=VALUE
    if (line.startsWith(AppConstants.respAck)) {
      final ackContent = line.substring(AppConstants.respAck.length);
      final eqIndex = ackContent.indexOf('=');
      if (eqIndex > 0) {
        final command = ackContent.substring(0, eqIndex);
        final value = ackContent.substring(eqIndex + 1);
        if (command == 'THRALL') {
          final threshold = int.tryParse(value);
          if (threshold != null) {
            _sensorThresholds = List<int>.filled(
              AppConstants.sensorCount,
              threshold,
            );
            onThresholdsReceived?.call(List<int>.from(_sensorThresholds));
          }
        } else if (command == 'THR') {
          final parts = value.split(',');
          if (parts.length == 2) {
            final index = int.tryParse(parts[0].trim());
            final threshold = int.tryParse(parts[1].trim());
            if (index != null &&
                threshold != null &&
                index >= 0 &&
                index < AppConstants.sensorCount) {
              _sensorThresholds[index] = threshold;
              onThresholdsReceived?.call(List<int>.from(_sensorThresholds));
            }
          }
        }
        onAckReceived?.call(command, value);
      } else {
        onAckReceived?.call(ackContent, '');
      }
      return;
    }

    // Generic message
    onDataReceived?.call(line);
  }

  void _handleDisconnected() {
    debugPrint('⚠️ [BLE DISCONNECT] Disconnected unexpectedly!');
    _device = null;
    _rxChar = null;
    _txChar = null;
    _incomingBuffer = '';
    onDisconnected?.call();
  }
}
