import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_constants.dart';
import '../models/robot_state.dart';
import '../models/sequence_step.dart';
import 'robot_service.dart';

export 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show BluetoothDevice, ScanResult, BluetoothAdapterState;

/// Internal queued command model for asynchronous BLE dispatch.
class _QueuedCommand {
  final String command;
  final Completer<bool> completer;
  final String? expectedAckPrefix;
  final Duration timeout;

  _QueuedCommand({
    required this.command,
    required this.completer,
    this.expectedAckPrefix,
    this.timeout = const Duration(milliseconds: 250),
  });
}

/// BLE (Nordic UART Service) implementation of [RobotService].
///
/// Features:
/// - Distinct 15-byte compact binary telemetry demultiplexing
/// - Stream framing and ASCII chunk reassembly on `\n` / `\r`
/// - Managed async command queue with ACK confirmation and rate throttling
/// - Automatic hardware state query & reconciliation upon connection
/// - Reactive telemetry stream and ValueNotifier
/// - Auto-reconnect and MTU negotiation handling
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

  // Managed Command Dispatcher Queue
  final List<_QueuedCommand> _commandQueue = [];
  bool _isDispatching = false;
  Completer<void>? _ackCompleter;
  String? _waitingAckPrefix;

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

  // Autonomous sequence completion stream
  final StreamController<void> _sequenceDoneController =
      StreamController<void>.broadcast();
  @override
  Stream<void> get onSequenceDone => _sequenceDoneController.stream;

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
  final Function(
    double kp,
    double ki,
    double kd,
    int baseSpeed,
    int maxSpeed,
    int minSpeed,
    bool invertSteering,
  )? onConfigReceived;
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
    this.onConfigReceived,
    this.onDisconnected,
  });

  // ---------------------------------------------------------------------------
  // BLE-specific API
  // ---------------------------------------------------------------------------

  /// Start scanning for BLE peripherals.
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

  /// Start scanning without filtering by service UUID.
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

      // Attempt MTU request
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

      // Automatically query hardware state to reconcile UI registers
      unawaited(queryHardwareState());

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

    // Drain queued commands with failure
    while (_commandQueue.isNotEmpty) {
      final cmd = _commandQueue.removeAt(0);
      if (!cmd.completer.isCompleted) {
        cmd.completer.complete(false);
      }
    }
    _isDispatching = false;
    _waitingAckPrefix = null;
    _ackCompleter = null;

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
    sendCommandAsync(command);
    return true;
  }

  @override
  Future<bool> sendCommandAsync(
    String command, {
    String? expectedAckPrefix,
    Duration timeout = const Duration(milliseconds: 250),
  }) {
    final completer = Completer<bool>();
    if (_rxChar == null) {
      completer.complete(false);
      return completer.future;
    }

    _commandQueue.add(_QueuedCommand(
      command: command,
      completer: completer,
      expectedAckPrefix: expectedAckPrefix,
      timeout: timeout,
    ));

    if (!_isDispatching) {
      _dispatchNext();
    }

    return completer.future;
  }

  Future<void> _dispatchNext() async {
    if (_isDispatching || _commandQueue.isEmpty) return;
    _isDispatching = true;

    while (_commandQueue.isNotEmpty) {
      if (_rxChar == null) {
        while (_commandQueue.isNotEmpty) {
          final cmd = _commandQueue.removeAt(0);
          if (!cmd.completer.isCompleted) cmd.completer.complete(false);
        }
        break;
      }

      final cmd = _commandQueue.removeAt(0);
      try {
        final trimmed = cmd.command.trim();
        final bytes = utf8.encode('$trimmed\n');
        debugPrint('📤 [BLE SEND] "$trimmed" (${bytes.length} bytes)');

        if (cmd.expectedAckPrefix != null) {
          _waitingAckPrefix = cmd.expectedAckPrefix;
          _ackCompleter = Completer<void>();
        }

        await _rxChar!.write(bytes, withoutResponse: true);

        if (cmd.expectedAckPrefix != null) {
          try {
            await _ackCompleter!.future.timeout(cmd.timeout);
          } catch (_) {
            debugPrint(
              '⚠️ [BLE TIMEOUT] Timed out waiting for ${cmd.expectedAckPrefix} (${cmd.timeout.inMilliseconds}ms)',
            );
          } finally {
            _waitingAckPrefix = null;
            _ackCompleter = null;
          }
        } else {
          // Safety throttle between unacknowledged packets
          await Future.delayed(const Duration(milliseconds: 30));
        }

        if (!cmd.completer.isCompleted) {
          cmd.completer.complete(true);
        }
      } catch (e) {
        debugPrint('❌ [BLE SEND] Error dispatching "${cmd.command}": $e');
        if (!cmd.completer.isCompleted) {
          cmd.completer.complete(false);
        }
      }

      // Inter-command spacing to prevent BLE radio saturation
      await Future.delayed(const Duration(milliseconds: 10));
    }

    _isDispatching = false;
  }

  @override
  Future<void> queryHardwareState() async {
    if (_rxChar == null) return;
    debugPrint('🔄 [BLE SYNC] Querying hardware state (THRESH?, MASK?, CONFIG?)...');
    await sendCommandAsync(AppConstants.cmdQueryThresholds, expectedAckPrefix: 'THRESHOLDS:');
    await sendCommandAsync(AppConstants.cmdQuerySensorMask, expectedAckPrefix: 'MASK:');
    await sendCommandAsync('CONFIG?', expectedAckPrefix: 'ACK:CONFIG');
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
    int mask = 0;
    for (int i = 0; i < AppConstants.sensorCount; i++) {
      if (_sensorEnabled[i]) mask |= (1 << i);
    }
    return sendSensorMask(mask);
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

  // ---------------------------------------------------------------------------
  // Autonomous Motion Queue & Sector Mapping
  // ---------------------------------------------------------------------------

  @override
  Future<void> sendSequence(List<SequenceStep> steps) async {
    if (_rxChar == null) {
      debugPrint('❌ [BLE SEQUENCE] Cannot send sequence: Not connected.');
      return;
    }
    debugPrint('🚀 [BLE SEQUENCE] Uploading ${steps.length} steps to robot...');

    // 1. Clear existing queue on ESP32, awaiting ACK:SEQ_CLEAR
    await sendCommandAsync(
      AppConstants.cmdSeqClear,
      expectedAckPrefix: 'ACK:SEQ_CLEAR',
    );

    // 2. Upload each step with verified acknowledgement
    for (int i = 0; i < steps.length; i++) {
      final cmd = steps[i].toBleCommand();
      await sendCommandAsync(
        cmd,
        expectedAckPrefix: 'ACK:SEQ_ADD',
      );
    }

    // 3. Initiate autonomous sequence execution, awaiting ACK:SEQ_START
    await sendCommandAsync(
      AppConstants.cmdSeqStart,
      expectedAckPrefix: 'ACK:SEQ_START',
    );
    debugPrint('✅ [BLE SEQUENCE] Sequence uploaded and started!');
  }

  @override
  bool stopSequence() {
    return sendCommand(AppConstants.cmdSeqStop);
  }

  @override
  bool startMapping() {
    return sendCommand(AppConstants.cmdMapStart);
  }

  @override
  bool finishMapping() {
    return sendCommand(AppConstants.cmdMapFinish);
  }

  @override
  bool startRace() {
    return sendCommand(AppConstants.cmdRaceStart);
  }

  @override
  bool sendMapSpeed(int speed) {
    final clamped = speed.clamp(0, 255);
    return sendCommand('${AppConstants.cmdMapSpeedPrefix}$clamped');
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await FlutterBluePlus.stopScan();
    await _telemetryController.close();
    await _sequenceDoneController.close();
    telemetryNotifier.dispose();
  }

  // ---------------------------------------------------------------------------
  // Incoming Data Handling (15-Byte Binary Telemetry vs. ASCII Stream)
  // ---------------------------------------------------------------------------

  @visibleForTesting
  void handleIncomingDataForTesting(List<int> data) => _handleIncomingData(data);

  void _handleIncomingData(List<int> data) {
    if (data.isEmpty) return;

    // 1. Strict Demultiplexing: 15-byte binary packet vs. ASCII text
    bool isBinaryTelemetry = false;
    if (data.length == 15) {
      final lastByte = data.last;
      // All firmware ASCII messages terminate with '\n' (10) or '\r' (13) and consist of printable characters
      final isDelimitedAscii = (lastByte == 10 || lastByte == 13) &&
          data.every((b) => (b >= 32 && b <= 126) || b == 10 || b == 13);
      if (!isDelimitedAscii) {
        isBinaryTelemetry = true;
      }
    }

    if (isBinaryTelemetry) {
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

    // 2. ASCII String Stream Framing (Chunked accumulator)
    final chunk = utf8.decode(data, allowMalformed: true);
    _incomingBuffer += chunk;

    while (_incomingBuffer.contains('\n') || _incomingBuffer.contains('\r')) {
      final nIdx = _incomingBuffer.indexOf('\n');
      final rIdx = _incomingBuffer.indexOf('\r');
      int splitIdx;
      if (nIdx != -1 && rIdx != -1) {
        splitIdx = nIdx < rIdx ? nIdx : rIdx;
      } else {
        splitIdx = nIdx != -1 ? nIdx : rIdx;
      }

      final line = _incomingBuffer.substring(0, splitIdx).trim();
      _incomingBuffer = _incomingBuffer.substring(splitIdx + 1);

      if (line.isNotEmpty) {
        _processLine(line);
      }
    }
  }

  void _processLine(String line) {
    debugPrint('📥 [BLE RECV] "$line"');

    // Notify waiting command dispatcher if matching ACK arrived
    if (_waitingAckPrefix != null && line.startsWith(_waitingAckPrefix!)) {
      if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
        _ackCompleter!.complete();
      }
    }

    // Hardware Error Handling: ERR:UNKNOWN_CMD=... or ERR:INVALID_PARAM
    if (line.startsWith('ERR:')) {
      debugPrint('⚠️ [BLE HARDWARE ERROR] $line');
      onDataReceived?.call(line);
      return;
    }

    // ACK:CONFIG=KP:2.50,KI:0.00,KD:0.08,BASE:70,MAX:120,MIN:30,INV:0
    if (line.startsWith('ACK:CONFIG=')) {
      final payload = line.substring('ACK:CONFIG='.length);
      final tokens = payload.split(',');
      double? hwKp, hwKi, hwKd;
      int? hwBase, hwMax, hwMin;
      bool? hwInv;

      for (final t in tokens) {
        final pair = t.split(':');
        if (pair.length == 2) {
          final k = pair[0].trim();
          final v = pair[1].trim();
          if (k == 'KP') {
            hwKp = double.tryParse(v);
          } else if (k == 'KI') {
            hwKi = double.tryParse(v);
          } else if (k == 'KD') {
            hwKd = double.tryParse(v);
          } else if (k == 'BASE') {
            hwBase = int.tryParse(v);
          } else if (k == 'MAX') {
            hwMax = int.tryParse(v);
          } else if (k == 'MIN') {
            hwMin = int.tryParse(v);
          } else if (k == 'INV') {
            hwInv = (v == '1');
          }
        }
      }

      if (hwKp != null &&
          hwKi != null &&
          hwKd != null &&
          hwBase != null &&
          hwMax != null &&
          hwMin != null &&
          hwInv != null) {
        onConfigReceived?.call(hwKp, hwKi, hwKd, hwBase, hwMax, hwMin, hwInv);
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

    // MASK:maskValue or ACK:MASK=maskValue
    if (line.startsWith(AppConstants.respSensorMask) ||
        line.startsWith('ACK:MASK=')) {
      final prefix = line.startsWith('ACK:MASK=')
          ? 'ACK:MASK='
          : AppConstants.respSensorMask;
      final payload = line.substring(prefix.length).trim();
      final mask = int.tryParse(payload);
      if (mask != null) {
        for (int i = 0; i < AppConstants.sensorCount; i++) {
          _sensorEnabled[i] = ((mask >> i) & 1) != 0;
        }
      }
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

    // Legacy SENSORS:val0,...,val11
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

    // SEQ:DONE (Autonomous motion queue finished)
    if (line == AppConstants.respSeqDone || line.startsWith('SEQ:DONE')) {
      debugPrint('🏁 [BLE SEQUENCE] Sequence execution complete (SEQ:DONE)');
      _sequenceDoneController.add(null);
      onDataReceived?.call(line);
      return;
    }

    // Generic messages
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
