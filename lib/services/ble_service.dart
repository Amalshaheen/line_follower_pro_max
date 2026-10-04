import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_constants.dart';
import '../models/robot_state.dart';
import 'robot_service.dart';

export 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show BluetoothDevice, ScanResult, BluetoothAdapterState;

/// BLE (Nordic UART Service) implementation of [RobotService].
///
/// Features:
/// - 15-byte compact binary telemetry parsing (12 sensors, error, flags)
/// - Fallback ASCII parsing for text responses (ACK, THRESHOLDS, TIME, etc.)
/// - Reactive telemetry stream and ValueNotifier
/// - Reliable connection, MTU configuration, and auto-reconnect handling
/// - Non-blocking command dispatch via writeWithoutResponse
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
  List<bool> _sensorEnabled = List<bool>.filled(
    AppConstants.sensorCount,
    true,
  );

  // Auto-reconnect configuration
  bool autoReconnectEnabled = true;
  bool _isManualDisconnect = false;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;

  // Reactive state management
  final ValueNotifier<TelemetryData?> telemetryNotifier =
      ValueNotifier<TelemetryData?>(null);
  final StreamController<TelemetryData> _telemetryController =
      StreamController<TelemetryData>.broadcast();
  Stream<TelemetryData> get telemetryStream => _telemetryController.stream;

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------
  @override
  final Function(String line)? onDataReceived;
  @override
  final Function(List<int> rawValues, List<bool> onLine)? onSensorDataReceived;
  @override
  final Function(TelemetryData telemetry)? onTelemetryReceived;
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
    this.onTelemetryReceived,
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
  /// Filters by NUS service UUID and known device names.
  Stream<List<ScanResult>> startScan({
    Duration timeout = const Duration(seconds: 10),
    String? deviceNameFilter,
  }) {
    FlutterBluePlus.startScan(
      timeout: timeout,
      withServices: [Guid(AppConstants.bleServiceUuid)],
    );
    return FlutterBluePlus.scanResults;
  }

  /// Start scanning without filtering by service UUID — shows ALL nearby
  /// BLE devices. Useful if the peripheral doesn't advertise service UUID.
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
    _isManualDisconnect = false;
    _reconnectAttempts = 0;

    if (isConnected) {
      await disconnect();
    }

    try {
      debugPrint('🔌 [BLE CONNECT] Connecting to ${device.platformName} (${device.remoteId}) …');
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
        mtu: null,
      );

      // Attempt MTU request (gracefully ignored on iOS or if unsupported)
      try {
        await device.requestMtu(256).timeout(const Duration(milliseconds: 1500));
      } catch (e) {
        debugPrint('ℹ️ [BLE MTU] Default MTU preserved: $e');
      }

      // Discover services
      final services = await device.discoverServices();
      debugPrint('🔍 [BLE CONNECT] Found ${services.length} services');

      // Find NUS service
      final targetUuid = AppConstants.bleServiceUuid
          .replaceAll('-', '')
          .toLowerCase();

      BluetoothService? nus;
      for (final s in services) {
        final sUuid = s.serviceUuid.str128.replaceAll('-', '').toLowerCase();
        if (sUuid == targetUuid) {
          nus = s;
          break;
        }
      }

      if (nus == null) {
        debugPrint('❌ [BLE CONNECT] NUS service not found on device.');
        await device.disconnect();
        return false;
      }

      // Find TX (notify) and RX (write) characteristics
      final txUuid = AppConstants.bleTxCharUuid.replaceAll('-', '').toLowerCase();
      final rxUuid = AppConstants.bleRxCharUuid.replaceAll('-', '').toLowerCase();

      for (final c in nus.characteristics) {
        final uuid = c.characteristicUuid.str128.replaceAll('-', '').toLowerCase();
        if (uuid == txUuid) {
          _txChar = c;
        } else if (uuid == rxUuid) {
          _rxChar = c;
        }
      }

      if (_txChar == null || _rxChar == null) {
        debugPrint('❌ [BLE CONNECT] NUS characteristics missing: TX=$_txChar, RX=$_rxChar');
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
    _isManualDisconnect = true;
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
      final trimmed = command.trim();
      final bytes = utf8.encode('$trimmed\n');
      debugPrint('📤 [BLE SEND] "$trimmed" (${bytes.length} bytes)');
      // withoutResponse=true avoids UI thread stalls
      _rxChar!.write(bytes, withoutResponse: true);
      return true;
    } catch (e) {
      debugPrint('❌ [BLE SEND] Error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Fast Concise Commands (Phone -> ESP32)
  // ---------------------------------------------------------------------------

  bool sendFastKp(double kp) => sendCommand('P${kp.toStringAsFixed(2)}');
  bool sendFastKi(double ki) => sendCommand('I${ki.toStringAsFixed(2)}');
  bool sendFastKd(double kd) => sendCommand('D${kd.toStringAsFixed(2)}');
  bool sendFastMaxSpeed(int speed) => sendCommand('M$speed');
  bool sendFastBaseSpeed(int speed) => sendCommand('B$speed');
  bool sendFastThreshold(int threshold) => sendCommand('T$threshold');
  bool sendToggleRun() => sendCommand('S');

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
  bool sendSensorEnable({required int index, required bool enabled}) {
    if (index < 0 || index >= AppConstants.sensorCount) {
      debugPrint('❌ [SENSOR_ENABLE] Invalid sensor index: $index');
      return false;
    }
    _sensorEnabled[index] = enabled;
    return sendCommand(
      '${AppConstants.cmdSensorSinglePrefix}$index,${enabled ? 1 : 0}',
    );
  }

  @override
  bool sendSensorMask(int mask) {
    for (int i = 0; i < AppConstants.sensorCount; i++) {
      _sensorEnabled[i] = ((mask >> i) & 1) != 0;
    }
    return sendCommand('${AppConstants.cmdSensorMaskPrefix}$mask');
  }

  @override
  void setSensorEnabledList(List<bool> enabled) {
    _sensorEnabled = List<bool>.generate(
      AppConstants.sensorCount,
      (i) => i < enabled.length ? enabled[i] : true,
    );
  }

  @override
  bool sendMinSpeed(int minSpeed) {
    final clamped = minSpeed.clamp(0, 255);
    return sendCommand('${AppConstants.cmdMinSpeedPrefix}$clamped');
  }

  @override
  bool sendInvertSteering(bool invert) {
    return sendCommand('${AppConstants.cmdInvertSteeringPrefix}${invert ? 1 : 0}');
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await FlutterBluePlus.stopScan();
    await _telemetryController.close();
    telemetryNotifier.dispose();
  }

  // ---------------------------------------------------------------------------
  // Incoming Data Handling (15-Byte Binary Telemetry or ASCII Stream)
  // ---------------------------------------------------------------------------

  void _handleIncomingData(List<int> data) {
    // 1. Binary Packet (15 Bytes)
    if (data.length == 15) {
      final telemetry = TelemetryData.fromBinary(data);
      if (telemetry != null) {
        telemetryNotifier.value = telemetry;
        if (!_telemetryController.isClosed) {
          _telemetryController.add(telemetry);
        }

        // Compute boolean line detection per sensor
        final onLine = List<bool>.generate(
          AppConstants.sensorCount,
          (i) {
            if (!_sensorEnabled[i]) return false;
            final raw = telemetry.sensors[i];
            // Normalize threshold: 12-bit (0-4095) downscaled to 8-bit (>> 4)
            final thresh = _sensorThresholds[i] > 255
                ? (_sensorThresholds[i] >> 4)
                : _sensorThresholds[i];
            return raw > thresh;
          },
        );

        onTelemetryReceived?.call(telemetry);
        onSensorDataReceived?.call(telemetry.sensors, onLine);
        return;
      }
    }

    // 2. ASCII String Stream (ACKs, thresholds, status)
    final chunk = utf8.decode(data, allowMalformed: true);
    _incomingBuffer += chunk;

    while (_incomingBuffer.contains('\n')) {
      final idx = _incomingBuffer.indexOf('\n');
      final line = _incomingBuffer.substring(0, idx).trim();
      _incomingBuffer = _incomingBuffer.substring(idx + 1);

      if (line.isNotEmpty) {
        _processLine(line);
      }
    }
  }

  void _processLine(String line) {
    // Legacy ASCII SENSORS:val0,val1,...,val11
    if (line.startsWith(AppConstants.respSensors)) {
      final payload = line.substring(AppConstants.respSensors.length);
      final parts = payload.split(',');

      if (parts.length == AppConstants.sensorCount) {
        final rawValues = parts.map((v) => int.tryParse(v.trim()) ?? 0).toList();
        final onLine = List<bool>.generate(
          AppConstants.sensorCount,
          (i) {
            if (!_sensorEnabled[i]) return false;
            final thresh = _sensorThresholds[i];
            return rawValues[i] > thresh;
          },
        );
        onSensorDataReceived?.call(rawValues, onLine);
      }
      return;
    }

    // MASK:maskValue
    if (line.startsWith(AppConstants.respSensorMask)) {
      final payload = line.substring(AppConstants.respSensorMask.length).trim();
      final mask = int.tryParse(payload);
      if (mask != null) {
        for (int i = 0; i < AppConstants.sensorCount; i++) {
          _sensorEnabled[i] = ((mask >> i) & 1) != 0;
        }
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

    // Generic messages (e.g., "Robot Started", "Robot Stopped")
    onDataReceived?.call(line);
  }

  void _handleDisconnected() {
    debugPrint('⚠️ [BLE DISCONNECT] Device disconnected.');
    final disconnectedDev = _device;
    _device = null;
    _rxChar = null;
    _txChar = null;
    _incomingBuffer = '';
    onDisconnected?.call();

    // Auto-reconnect handling if not manually initiated
    if (!_isManualDisconnect &&
        autoReconnectEnabled &&
        disconnectedDev != null &&
        _reconnectAttempts < maxReconnectAttempts) {
      _reconnectAttempts++;
      final delaySec = _reconnectAttempts * 2;
      debugPrint(
        '🔄 [BLE RECONNECT] Attempt $_reconnectAttempts/$maxReconnectAttempts in ${delaySec}s …',
      );
      Future.delayed(Duration(seconds: delaySec), () {
        if (_device == null && !_isManualDisconnect) {
          connect(disconnectedDev);
        }
      });
    }
  }
}
