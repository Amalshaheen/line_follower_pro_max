import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/index.dart';
import '../constants/app_constants.dart';
import '../models/index.dart';
import '../services/index.dart';
import 'bluetooth_settings_page.dart';
import 'settings_page.dart';

/// Main dashboard screen for controlling the line follower robot.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool isRunning = false;
  bool trackFinished = false;
  int runtime = 0;
  late List<bool> sensorOnLine = List<bool>.filled(
    AppConstants.sensorCount,
    false,
  );
  late List<int> sensorRawValues = List<int>.filled(
    AppConstants.sensorCount,
    0,
  );
  bool showAnalogSensors = false;
  bool isCalibrationMode = false;
  bool autoStopOnFinish = true;
  bool lineLostRecoveryEnabled = true;
  double lineError = 0.0;
  bool lineDetected = true;
  DateTime? _currentRunStartedAt;
  bool _currentRunSaved = false;

  // PID values — effective values sent to hardware
  double kp = AppConstants.defaultKp;
  double ki = AppConstants.defaultKi;
  double kd = AppConstants.defaultKd;

  late TextEditingController maxSpeedController = TextEditingController(
    text: AppConstants.defaultMaxSpeed.toString(),
  );
  late TextEditingController baseSpeedController = TextEditingController(
    text: AppConstants.defaultBaseSpeed.toString(),
  );
  late TextEditingController allThresholdController = TextEditingController(
    text: AppConstants.defaultThreshold.toString(),
  );
  late List<int> sensorThresholds = List<int>.filled(
    AppConstants.sensorCount,
    AppConstants.defaultThreshold,
  );

  // History / settings
  final HistoryService _historyService = HistoryService();
  final SettingsService _settingsService = SettingsService();
  AppSettings _defaultSettings = AppSettings.defaults();
  List<PidRunHistory> history = [];
  RunCaptureType? _historyFilter;

  // ── Connection state ───────────────────────────────────────────────────────
  /// The active service (either classic BT or BLE).
  RobotService? _activeService;

  ConnectionMode _connectionMode = ConnectionMode.classic;
  String _deviceName = AppConstants.defaultDeviceName;
  bool isConnected = false;
  bool isConnecting = false;
  String btStatus = 'Disconnected';

  // Classic BT
  BluetoothService? _classicService;
  List<BluetoothDevice> bondedDevices = [];
  BluetoothDevice? selectedClassicDevice;

  // BLE
  BleService? _bleService;
  List<ScanResult> scanResults = [];
  ScanResult? selectedScanResult;
  bool isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  @override
  void initState() {
    super.initState();
    _initFromSettings();
    _loadHistory();
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> _initFromSettings() async {
    final settings = await _settingsService.getSettings();
    final savedSensorThresholds = await _settingsService.getSensorThresholds();
    if (!mounted) return;

    setState(() {
      _defaultSettings = settings;
      _connectionMode = settings.connectionMode;
      _deviceName = settings.deviceName;

      kp = settings.kp;
      ki = settings.ki;
      kd = settings.kd;
      maxSpeedController.text = settings.maxSpeed.toString();
      baseSpeedController.text = settings.baseSpeed.toString();
      sensorThresholds = savedSensorThresholds ??
          List<int>.filled(AppConstants.sensorCount, settings.threshold);
      allThresholdController.text = settings.threshold.toString();
    });

    await _initServices();
  }

  Future<void> _initServices() async {
    // Build both services so we can switch without reinitialising permissions.
    _classicService = BluetoothService(
      onDataReceived: _onDataReceived,
      onSensorDataReceived: _onSensorDataReceived,
      onTelemetryReceived: _onTelemetryReceived,
      onTrackFinished: _onTrackFinished,
      onAckReceived: _onAckReceived,
      onThresholdsReceived: _onThresholdsReceived,
      onDisconnected: _onDisconnected,
    );

    _bleService = BleService(
      onDataReceived: _onDataReceived,
      onSensorDataReceived: _onSensorDataReceived,
      onTelemetryReceived: _onTelemetryReceived,
      onTrackFinished: _onTrackFinished,
      onAckReceived: _onAckReceived,
      onThresholdsReceived: _onThresholdsReceived,
      onDisconnected: _onDisconnected,
    );

    _activeService = _connectionMode == ConnectionMode.ble
        ? _bleService
        : _classicService;

    // Request permissions for BOTH transports upfront so the user isn't
    // interrupted later when they switch modes.
    await _classicService!.initializePermissions();
    await _bleService!.initializePermissions();

    if (_connectionMode == ConnectionMode.classic) {
      await _loadBondedDevices();
    }
  }

  // ---------------------------------------------------------------------------
  // Shared service callbacks
  // ---------------------------------------------------------------------------

  void _onDataReceived(String line) {
    if (!mounted) return;
    setState(() {
      if (line == 'Robot Started') {
        isRunning = true;
        trackFinished = false;
        runtime = 0;
        _currentRunStartedAt = DateTime.now();
        _currentRunSaved = false;
      } else if (line == 'Robot Stopped') {
        isRunning = false;
      }
    });
  }

  void _onSensorDataReceived(List<int> rawValues, List<bool> onLine) {
    if (!mounted || onLine.length != AppConstants.sensorCount) return;
    setState(() {
      sensorOnLine = onLine;
      sensorRawValues = rawValues;
    });
  }

  void _onTelemetryReceived(TelemetryData telemetry) {
    if (!mounted) return;
    setState(() {
      lineError = telemetry.error;
      lineDetected = telemetry.lineDetected;
      isRunning = telemetry.motorsRunning;
      sensorRawValues = telemetry.sensors;
    });
  }

  void _onTrackFinished(int runtimeMs) {
    if (!mounted) return;
    setState(() {
      trackFinished = true;
      if (autoStopOnFinish) isRunning = false;
      if (runtimeMs > 0) runtime = runtimeMs;
    });
    if (runtime == 0) {
      _activeService?.sendCommand(AppConstants.cmdQueryTime);
    } else if (!_currentRunSaved) {
      _currentRunSaved = true;
      _saveRunToHistory(runtimeMs, captureType: RunCaptureType.pathFinished);
    }
  }

  void _onAckReceived(String command, String value) {
    if (!mounted) return;
    if (command == 'BASE') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 900),
          content: Text('Base speed confirmed: $value'),
        ),
      );
    }
  }

  void _onThresholdsReceived(List<int> thresholds) {
    if (!mounted || thresholds.length != AppConstants.sensorCount) return;
    final average = thresholds.reduce((a, b) => a + b) ~/ thresholds.length;
    setState(() {
      sensorThresholds = thresholds;
      allThresholdController.text = average.toString();
    });
  }

  void _onDisconnected() {
    if (!mounted) return;
    setState(() {
      isConnected = false;
      btStatus = 'Disconnected';
    });
  }

  // ---------------------------------------------------------------------------
  // Mode switching
  // ---------------------------------------------------------------------------

  void _handleModeChanged(ConnectionMode mode) {
    if (mode == _connectionMode) return;
    setState(() {
      _connectionMode = mode;
      _activeService = mode == ConnectionMode.ble ? _bleService : _classicService;
      scanResults = [];
      selectedScanResult = null;
    });
    // Persist the new mode choice
    _settingsService.saveSettings(
      _defaultSettings.copyWith(connectionMode: mode, deviceName: _deviceName),
    );
    if (mode == ConnectionMode.classic) {
      _loadBondedDevices();
    }
    // BLE permissions are already requested at init — no extra call needed
  }

  void _handleDeviceNameChanged(String name) {
    if (name.isEmpty) return;
    setState(() => _deviceName = name);
    _settingsService.saveSettings(
      _defaultSettings.copyWith(
        connectionMode: _connectionMode,
        deviceName: name,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Classic BT helpers
  // ---------------------------------------------------------------------------

  Future<List<BluetoothDevice>> _loadBondedDevices() async {
    final devices = await _classicService!.getBondedDevices();
    if (mounted) {
      setState(() => bondedDevices = devices);
    }
    return devices;
  }

  Future<bool> _connectClassic() async {
    if (selectedClassicDevice == null) return false;
    setState(() => isConnecting = true);

    final success = await _classicService!.connect(selectedClassicDevice!);

    if (mounted) {
      setState(() {
        isConnecting = false;
        if (success) {
          isConnected = true;
          btStatus =
              'Connected to ${selectedClassicDevice!.name ?? selectedClassicDevice!.address}';
          _postConnect();
        } else {
          btStatus = 'Failed to connect';
        }
      });
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected successfully'),
            duration: Duration(milliseconds: 800),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.of(context).pop();
      }
    }
    return success;
  }

  // ---------------------------------------------------------------------------
  // BLE helpers
  // ---------------------------------------------------------------------------

  void _startBleScan() {
    // Ensure BLE adapter is on before scanning
    final stream = _bleService!.startScanAll(
      timeout: const Duration(seconds: 10),
    );
    setState(() {
      scanResults = [];
      isScanning = true;
    });

    _scanSubscription?.cancel();
    _scanSubscription = stream.listen(
      (results) {
        if (mounted) setState(() => scanResults = results);
      },
      onError: (Object e) {
        debugPrint('❌ [BLE SCAN] Error: $e');
        if (mounted) setState(() => isScanning = false);
      },
    );

    _isScanningSubscription?.cancel();
    _isScanningSubscription = _bleService!.isScanningStream.listen((scanning) {
      if (mounted) setState(() => isScanning = scanning);
    });
  }

  Future<bool> _connectBle() async {
    if (selectedScanResult == null) return false;
    setState(() => isConnecting = true);
    await _bleService!.stopScan();

    final success =
        await _bleService!.connect(selectedScanResult!.device);

    if (mounted) {
      setState(() {
        isConnecting = false;
        if (success) {
          isConnected = true;
          final name = selectedScanResult!.device.platformName.isNotEmpty
              ? selectedScanResult!.device.platformName
              : selectedScanResult!.device.remoteId.str;
          btStatus = 'Connected to $name (BLE)';
          _postConnect();
        } else {
          btStatus = 'BLE connection failed';
        }
      });
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('BLE connected successfully'),
            duration: Duration(milliseconds: 800),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.of(context).pop();
      }
    }
    return success;
  }

  // ---------------------------------------------------------------------------
  // Shared connect/disconnect
  // ---------------------------------------------------------------------------

  void _postConnect() {
    _activeService?.sendCommand(AppConstants.cmdQueryThresholds);
    _activeService?.sendCommand(
      '${AppConstants.cmdAutoStopPrefix}${autoStopOnFinish ? 1 : 0}',
    );
    _activeService?.sendCommand(
      '${AppConstants.cmdLineLostRecoveryPrefix}${lineLostRecoveryEnabled ? 1 : 0}',
    );
  }

  Future<bool> _connectToDevice() async {
    if (_connectionMode == ConnectionMode.ble) {
      return await _connectBle();
    } else {
      return await _connectClassic();
    }
  }

  Future<void> _disconnectDevice() async {
    if (_connectionMode == ConnectionMode.ble) {
      await _bleService?.disconnect();
    } else {
      await _classicService?.disconnect();
    }
    if (mounted) {
      setState(() {
        isConnected = false;
        btStatus = 'Disconnected';
        isRunning = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _navigateToBluetoothSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BluetoothSettingsPage(
          bondedDevices: bondedDevices,
          selectedClassicDevice: selectedClassicDevice,
          scanResults: scanResults,
          selectedScanResult: selectedScanResult,
          isScanning: isScanning,
          bleAdapterStateStream: _bleService?.adapterStateStream,
          connectionMode: _connectionMode,
          isConnected: isConnected,
          isConnecting: isConnecting,
          btStatus: btStatus,
          deviceName: _deviceName,
          onModeChanged: (mode) {
            _handleModeChanged(mode);
            setState(() {});
          },
          onDeviceNameChanged: _handleDeviceNameChanged,
          onClassicDeviceSelected: (device) {
            setState(() => selectedClassicDevice = device);
          },
          onBleDeviceSelected: (result) {
            setState(() => selectedScanResult = result);
          },
          onConnect: _connectToDevice,
          onDisconnect: _disconnectDevice,
          onRefreshClassic: _loadBondedDevices,
          onStartBleScan: _startBleScan,
        ),
      ),
    ).then((_) => _updateConnectionStatus());
  }

  void _navigateToSettingsPage() {
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(initialSettings: _defaultSettings),
      ),
    ).then((changed) {
      if (changed == true) {
        _loadDefaultSettings();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Defaults saved. Use reset buttons to apply.'),
          ),
        );
      }
    });
  }

  void _updateConnectionStatus() {
    if (_activeService?.isConnected == true && mounted) {
      setState(() => isConnected = true);
    }
  }

  // ---------------------------------------------------------------------------
  // Settings & history
  // ---------------------------------------------------------------------------

  Future<void> _loadDefaultSettings() async {
    final loaded = await _settingsService.getSettings();
    if (!mounted) return;
    final modeChanged = loaded.connectionMode != _connectionMode;
    setState(() {
      _defaultSettings = loaded;
      // Sync connection mode and device name so UI reflects saved settings
      _connectionMode = loaded.connectionMode;
      _deviceName = loaded.deviceName;
      _activeService = _connectionMode == ConnectionMode.ble
          ? _bleService
          : _classicService;
    });
    if (modeChanged && _connectionMode == ConnectionMode.classic) {
      _loadBondedDevices();
    }
  }

  Future<void> _loadHistory() async {
    final loadedHistory = await _historyService.getHistory();
    if (mounted) setState(() => history = loadedHistory);
  }

  List<PidRunHistory> get _filteredHistory {
    final filter = _historyFilter;
    if (filter == null) return history;
    return history.where((run) => run.captureType == filter).toList();
  }

  void _handleHistoryFilterChanged(RunCaptureType? filter) {
    setState(() => _historyFilter = filter);
  }

  Future<void> _saveRunToHistory(
    int runtimeMs, {
    required RunCaptureType captureType,
  }) async {
    final run = PidRunHistory.create(
      runtimeMs: runtimeMs,
      captureType: captureType,
      kp: kp,
      ki: ki,
      kd: kd,
      maxSpeed: int.tryParse(maxSpeedController.text) ?? 255,
      baseSpeed: int.tryParse(baseSpeedController.text) ?? 150,
    );
    await _historyService.addRun(run);
    await _loadHistory();
  }

  void _restoreConfig(PidRunHistory run) {
    setState(() {
      kp = run.kp;
      ki = run.ki;
      kd = run.kd;
      maxSpeedController.text = run.maxSpeed.toString();
      baseSpeedController.text = run.baseSpeed.toString();
    });
    _activeService?.sendCommand('${AppConstants.cmdKpPrefix}${run.kp.toStringAsFixed(2)}');
    _activeService?.sendCommand('${AppConstants.cmdKiPrefix}${run.ki.toStringAsFixed(2)}');
    _activeService?.sendCommand('${AppConstants.cmdKdPrefix}${run.kd.toStringAsFixed(2)}');
    _activeService?.sendCommand('${AppConstants.cmdMaxSpeedPrefix}${run.maxSpeed}');
    _activeService?.sendCommand('${AppConstants.cmdBaseSpeedPrefix}${run.baseSpeed}');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Configuration restored: ${run.pidSummary}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteRun(String id) async {
    await _historyService.removeRun(id);
    await _loadHistory();
  }

  Future<void> _clearAllHistory() async {
    await _historyService.clearHistory();
    await _loadHistory();
  }

  // ---------------------------------------------------------------------------
  // Robot control
  // ---------------------------------------------------------------------------

  int _currentElapsedRuntimeMs() {
    final startedAt = _currentRunStartedAt;
    if (startedAt == null) return runtime;
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    return elapsed > 0 ? elapsed : runtime;
  }

  Future<void> _handleStartStop() async {
    if (!isRunning) {
      setState(() {
        isRunning = true;
        trackFinished = false;
        runtime = 0;
      });
      _currentRunStartedAt = DateTime.now();
      _currentRunSaved = false;
      _activeService?.sendCommand(AppConstants.cmdRunStart);
      return;
    }

    final elapsed = _currentElapsedRuntimeMs();
    final shouldAutoSave = elapsed > 0 && !_currentRunSaved;

    setState(() {
      isRunning = false;
      runtime = elapsed;
    });
    _activeService?.sendCommand(AppConstants.cmdRunStop);

    if (!shouldAutoSave) return;

    _currentRunSaved = true;
    await _saveRunToHistory(elapsed, captureType: RunCaptureType.startStop);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Run saved automatically')));
  }

  void _handleAutoStopChanged(bool enabled) {
    setState(() => autoStopOnFinish = enabled);
    _activeService?.sendCommand(
      '${AppConstants.cmdAutoStopPrefix}${enabled ? 1 : 0}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        content: Text(
          enabled ? 'Auto-stop on finish enabled' : 'Auto-stop on finish disabled',
        ),
      ),
    );
  }

  void _handleLineLostRecoveryChanged(bool enabled) {
    setState(() => lineLostRecoveryEnabled = enabled);
    _activeService?.sendCommand(
      '${AppConstants.cmdLineLostRecoveryPrefix}${enabled ? 1 : 0}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        content: Text(
          enabled ? 'Line-lost recovery enabled' : 'Line-lost recovery disabled',
        ),
      ),
    );
  }

  void _handlePChanged(double value) {
    setState(() => kp = value);
    _sendPidValuesQuietly();
  }

  void _handleIChanged(double value) {
    setState(() => ki = value);
    _sendPidValuesQuietly();
  }

  void _handleDChanged(double value) {
    setState(() => kd = value);
    _sendPidValuesQuietly();
  }

  void _handleCalibrationModeChanged(bool enabled) {
    setState(() => isCalibrationMode = enabled);
    if (enabled) {
      _activeService?.sendCommand(AppConstants.cmdQueryThresholds);
    }
  }

  void _handleSensorThresholdPreview(int index, int value) {
    if (index < 0 || index >= sensorThresholds.length) return;
    setState(() => sensorThresholds[index] = value);
  }

  void _handleSensorThresholdCommit(int index, int value) {
    _handleSensorThresholdPreview(index, value);
    _activeService?.sendThresholdForSensor(index: index, threshold: value);
  }

  void _handleAllSensorThresholdCommit(int value) {
    final normalized = value.clamp(0, 4095);
    setState(() {
      sensorThresholds = List<int>.filled(AppConstants.sensorCount, normalized);
      allThresholdController.text = normalized.toString();
    });
    _activeService?.sendThresholdForAllSensors(normalized);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        content: Text('All thresholds set to $normalized'),
      ),
    );
  }

  Future<void> _handleSaveCalibration() async {
    await _settingsService.saveSensorThresholds(sensorThresholds);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 900),
        content: Text('Calibration values saved'),
      ),
    );
  }

  void _sendPidValuesQuietly() {
    _activeService?.sendCommand('${AppConstants.cmdKpPrefix}${kp.toStringAsFixed(2)}');
    _activeService?.sendCommand('${AppConstants.cmdKiPrefix}${ki.toStringAsFixed(2)}');
    _activeService?.sendCommand('${AppConstants.cmdKdPrefix}${kd.toStringAsFixed(2)}');
  }

  void _handlePidSend() {
    _activeService?.sendCommand('${AppConstants.cmdKpPrefix}${kp.toStringAsFixed(2)}');
    _activeService?.sendCommand('${AppConstants.cmdKiPrefix}${ki.toStringAsFixed(2)}');
    _activeService?.sendCommand('${AppConstants.cmdKdPrefix}${kd.toStringAsFixed(2)}');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        content: Text(
          'PID sent: P ${kp.toStringAsFixed(2)} | I ${ki.toStringAsFixed(2)} | D ${kd.toStringAsFixed(2)}',
        ),
      ),
    );
  }

  void _handleResetPidDefaults() {
    setState(() {
      kp = _defaultSettings.kp;
      ki = _defaultSettings.ki;
      kd = _defaultSettings.kd;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 800),
        content: Text('PID reset to saved defaults'),
      ),
    );
  }

  void _handleResetSpeedThresholdDefaults() {
    setState(() {
      maxSpeedController.text = _defaultSettings.maxSpeed.toString();
      baseSpeedController.text = _defaultSettings.baseSpeed.toString();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 800),
        content: Text('Speed reset to saved defaults'),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    maxSpeedController.dispose();
    baseSpeedController.dispose();
    allThresholdController.dispose();
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _classicService?.dispose();
    _bleService?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'LineRobo Companion '),
              TextSpan(
                text: 'Pro',
                style: const TextStyle(
                  color: Color(0xFFD4AF37),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  _connectionMode == ConnectionMode.ble
                      ? Icons.bluetooth_searching
                      : Icons.bluetooth,
                ),
                onPressed: _navigateToBluetoothSettings,
                tooltip: _connectionMode == ConnectionMode.ble
                    ? 'BLE Connection'
                    : 'Bluetooth Connection',
              ),
              if (isConnected)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: _navigateToSettingsPage,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SensorsCard(
                sensorOnLine: sensorOnLine,
                sensorRawValues: sensorRawValues,
                showAnalog: showAnalogSensors,
                isCalibrationMode: isCalibrationMode,
                sensorThresholds: sensorThresholds,
                lineError: lineError,
                lineDetected: lineDetected,
                onShowAnalogChanged: (value) {
                  setState(() => showAnalogSensors = value);
                },
                onCalibrationModeChanged: _handleCalibrationModeChanged,
                onSensorThresholdPreview: _handleSensorThresholdPreview,
                onSensorThresholdCommit: _handleSensorThresholdCommit,
                onAllSensorThresholdCommit: _handleAllSensorThresholdCommit,
                onSaveCalibration: _handleSaveCalibration,
              ),
              const SizedBox(height: 12),
              ControlSummaryCard(
                isRunning: isRunning,
                trackFinished: trackFinished,
                runtime: runtime,
                autoStopOnFinish: autoStopOnFinish,
                lineLostRecoveryEnabled: lineLostRecoveryEnabled,
                onAutoStopChanged: _handleAutoStopChanged,
                onLineLostRecoveryChanged: _handleLineLostRecoveryChanged,
                onStartStop: _handleStartStop,
              ),
              const SizedBox(height: 12),
              PidCard(
                pValue: kp,
                iValue: ki,
                dValue: kd,
                onPChanged: _handlePChanged,
                onIChanged: _handleIChanged,
                onDChanged: _handleDChanged,
                onSendAll: _handlePidSend,
                onResetDefaults: _handleResetPidDefaults,
              ),
              const SizedBox(height: 12),
              SpeedCard(
                maxSpeedController: maxSpeedController,
                baseSpeedController: baseSpeedController,
                onMaxSpeedSend: () {
                  final maxSpeed = maxSpeedController.text;
                  _activeService?.sendCommand(
                    '${AppConstants.cmdMaxSpeedPrefix}$maxSpeed',
                  );
                },
                onBaseSpeedSend: () {
                  final baseSpeed = baseSpeedController.text;
                  _activeService?.sendCommand(
                    '${AppConstants.cmdBaseSpeedPrefix}$baseSpeed',
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(milliseconds: 900),
                      content: Text('Base speed set to $baseSpeed'),
                    ),
                  );
                },
                onResetDefaults: _handleResetSpeedThresholdDefaults,
              ),
              const SizedBox(height: 12),
              HistoryCard(
                history: _filteredHistory,
                selectedFilter: _historyFilter,
                onFilterChanged: _handleHistoryFilterChanged,
                onRestoreConfig: _restoreConfig,
                onDeleteRun: _deleteRun,
                onClearAll: _clearAllHistory,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
