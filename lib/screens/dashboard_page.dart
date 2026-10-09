import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/index.dart';
import '../constants/app_constants.dart';
import '../models/index.dart';
import '../services/index.dart';
import 'bluetooth_settings_page.dart';
import 'settings_page.dart';

/// Main streamlined dashboard screen for pure optical line-following,
/// real-time telemetry, and PID/drive parameter tuning.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool isRunning = false;
  int runtime = 0;
  late List<bool> sensorOnLine = List<bool>.filled(
    AppConstants.sensorCount,
    false,
  );
  late List<int> sensorRawValues = List<int>.filled(
    AppConstants.sensorCount,
    0,
  );
  bool showAnalogSensors = true;
  bool isCalibrationMode = true;
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
  late TextEditingController minSpeedController = TextEditingController(
    text: AppConstants.defaultMinSpeed.toString(),
  );
  bool invertSteering = AppConstants.defaultInvertSteering;
  late TextEditingController allThresholdController = TextEditingController(
    text: AppConstants.defaultThreshold.toString(),
  );
  late List<int> sensorThresholds = List<int>.filled(
    AppConstants.sensorCount,
    AppConstants.defaultThreshold,
  );
  late List<bool> sensorEnabled = List<bool>.filled(
    AppConstants.sensorCount,
    true,
  );

  // History / settings
  final HistoryService _historyService = HistoryService();
  final SettingsService _settingsService = SettingsService();
  AppSettings _defaultSettings = AppSettings.defaults();

  // Connection state
  BleService? _bleService;
  RobotService? get _activeService => _bleService;

  String _deviceName = AppConstants.defaultDeviceName;
  bool isConnected = false;
  bool isConnecting = false;
  String btStatus = 'Disconnected';

  // BLE Scan
  List<ScanResult> scanResults = [];
  ScanResult? selectedScanResult;
  bool isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  @override
  void initState() {
    super.initState();
    _initFromSettings();
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> _initFromSettings() async {
    final settings = await _settingsService.getSettings();
    final savedSensorThresholds = await _settingsService.getSensorThresholds();
    final savedSensorEnabled = await _settingsService.getSensorEnabled();
    if (!mounted) return;

    setState(() {
      _defaultSettings = settings;
      _deviceName = settings.deviceName;

      kp = settings.kp;
      ki = settings.ki;
      kd = settings.kd;
      maxSpeedController.text = settings.maxSpeed.toString();
      baseSpeedController.text = settings.baseSpeed.toString();
      minSpeedController.text = settings.minSpeed.toString();
      invertSteering = settings.invertSteering;
      sensorThresholds = savedSensorThresholds ??
          List<int>.filled(AppConstants.sensorCount, settings.threshold);
      sensorEnabled = savedSensorEnabled ??
          List<bool>.filled(AppConstants.sensorCount, true);
      allThresholdController.text = settings.threshold.toString();
    });

    await _initServices();
  }

  Future<void> _initServices() async {
    _bleService = BleService(
      onDataReceived: _onDataReceived,
      onSensorDataReceived: _onSensorDataReceived,
      onTelemetryReceived: _onTelemetryReceived,
      onAckReceived: _onAckReceived,
      onThresholdsReceived: _onThresholdsReceived,
      onConfigReceived: _onConfigReceived,
      onDisconnected: _onDisconnected,
    );

    _bleService!.setSensorEnabledList(sensorEnabled);
    await _bleService!.initializePermissions();
  }

  // ---------------------------------------------------------------------------
  // Service Callbacks
  // ---------------------------------------------------------------------------

  void _onDataReceived(String line) {
    if (!mounted) return;
    setState(() {
      if (line == 'Robot Started') {
        isRunning = true;
        runtime = 0;
        _currentRunStartedAt = DateTime.now();
        _currentRunSaved = false;
      } else if (line == 'Robot Stopped') {
        isRunning = false;
      }
    });
  }

  List<int> _scaleTo12Bit(List<int> values) {
    if (values.isEmpty) return values;
    final maxVal = values.fold<int>(0, (m, v) => v > m ? v : m);
    if (maxVal <= 255) {
      return values.map((v) => (v * 4095 ~/ 255).clamp(0, 4095)).toList();
    }
    return values.map((v) => v.clamp(0, 4095)).toList();
  }

  void _onSensorDataReceived(List<int> rawValues, List<bool> onLine) {
    if (!mounted || onLine.length != AppConstants.sensorCount) return;
    setState(() {
      sensorOnLine = onLine;
      sensorRawValues = _scaleTo12Bit(rawValues);
    });
  }

  void _onTelemetryReceived(TelemetryData telemetry) {
    if (!mounted) return;
    setState(() {
      lineError = telemetry.error;
      lineDetected = telemetry.lineDetected;
      isRunning = telemetry.motorsRunning;
      sensorRawValues = _scaleTo12Bit(telemetry.sensors);
    });
  }

  void _onAckReceived(String command, String value) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    if (command == 'BASE') {
      final spd = int.tryParse(value);
      if (spd != null) baseSpeedController.text = value;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1000),
          content: Text('Base speed confirmed: $value'),
        ),
      );
    } else if (command == 'MAX') {
      final spd = int.tryParse(value);
      if (spd != null) maxSpeedController.text = value;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1000),
          content: Text('Max speed confirmed: $value'),
        ),
      );
    } else if (command == 'MIN') {
      final spd = int.tryParse(value);
      if (spd != null) minSpeedController.text = value;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1000),
          content: Text('Min speed confirmed: $value'),
        ),
      );
    } else if (command == 'KP') {
      final parsed = double.tryParse(value);
      if (parsed != null) setState(() => kp = parsed);
    } else if (command == 'KI') {
      final parsed = double.tryParse(value);
      if (parsed != null) setState(() => ki = parsed);
    } else if (command == 'KD') {
      final parsed = double.tryParse(value);
      if (parsed != null) setState(() => kd = parsed);
    } else if (command == 'INV') {
      setState(() => invertSteering = (value == '1'));
    } else if (command == 'CALIB') {
      messenger.showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 1500),
          backgroundColor: Color(0xFF10B981),
          content: Text('✅ Optical sensors calibrated successfully!'),
        ),
      );
    } else if (command == 'RUN') {
      setState(() => isRunning = (value == '1'));
    }
  }

  void _onConfigReceived(
    double hwKp,
    double hwKi,
    double hwKd,
    int hwBase,
    int hwMax,
    int hwMin,
    bool hwInv,
  ) {
    if (!mounted) return;
    setState(() {
      kp = hwKp;
      ki = hwKi;
      kd = hwKd;
      baseSpeedController.text = hwBase.toString();
      maxSpeedController.text = hwMax.toString();
      minSpeedController.text = hwMin.toString();
      invertSteering = hwInv;
    });
    debugPrint(
      '✅ [SYNC] Hardware config reconciled: P=$hwKp, I=$hwKi, D=$hwKd, Base=$hwBase, Max=$hwMax, Min=$hwMin, Inv=$hwInv',
    );
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
      isRunning = false;
    });
  }

  // ---------------------------------------------------------------------------
  // BLE Management
  // ---------------------------------------------------------------------------

  void _handleDeviceNameChanged(String name) {
    if (name.isEmpty) return;
    setState(() => _deviceName = name);
    _settingsService.saveSettings(
      _defaultSettings.copyWith(
        deviceName: name,
      ),
    );
  }

  void _startBleScan() {
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

    final success = await _bleService!.connect(selectedScanResult!.device);

    if (mounted) {
      setState(() {
        isConnecting = false;
        if (success) {
          isConnected = true;
          final name = selectedScanResult!.device.platformName.isNotEmpty
              ? selectedScanResult!.device.platformName
              : selectedScanResult!.device.remoteId.str;
          btStatus = 'Connected to $name';
          _postConnect();
        } else {
          btStatus = 'BLE connection failed';
        }
      });
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected to robot over BLE'),
            duration: Duration(milliseconds: 800),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.of(context).pop();
      }
    }
    return success;
  }

  void _postConnect() {
    _activeService?.queryHardwareState();
    final minSpeed =
        int.tryParse(minSpeedController.text) ?? AppConstants.defaultMinSpeed;
    _activeService?.sendMinSpeed(minSpeed);
    _activeService?.sendInvertSteering(invertSteering);
  }

  Future<bool> _connectToDevice() async => await _connectBle();

  Future<void> _disconnectDevice() async {
    await _bleService?.disconnect();
    if (mounted) {
      setState(() {
        isConnected = false;
        btStatus = 'Disconnected';
        isRunning = false;
      });
    }
  }

  void _navigateToBluetoothSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BluetoothSettingsPage(
          scanResults: scanResults,
          selectedScanResult: selectedScanResult,
          isScanning: isScanning,
          bleAdapterStateStream: _bleService?.adapterStateStream,
          isConnected: isConnected,
          isConnecting: isConnecting,
          btStatus: btStatus,
          deviceName: _deviceName,
          onDeviceNameChanged: _handleDeviceNameChanged,
          onBleDeviceSelected: (result) {
            setState(() => selectedScanResult = result);
          },
          onConnect: _connectToDevice,
          onDisconnect: _disconnectDevice,
          onStartBleScan: _startBleScan,
        ),
      ),
    ).then((_) {
      if (_activeService?.isConnected == true && mounted) {
        setState(() => isConnected = true);
      }
    });
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
      }
    });
  }

  Future<void> _loadDefaultSettings() async {
    final loaded = await _settingsService.getSettings();
    if (!mounted) return;
    setState(() {
      _defaultSettings = loaded;
      _deviceName = loaded.deviceName;
    });
  }

  // ---------------------------------------------------------------------------
  // Robot Control Actions
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
    final run = PidRunHistory.create(
      runtimeMs: elapsed,
      captureType: RunCaptureType.startStop,
      kp: kp,
      ki: ki,
      kd: kd,
      maxSpeed: int.tryParse(maxSpeedController.text) ?? AppConstants.defaultMaxSpeed,
      baseSpeed: int.tryParse(baseSpeedController.text) ?? AppConstants.defaultBaseSpeed,
      minSpeed: int.tryParse(minSpeedController.text) ?? AppConstants.defaultMinSpeed,
    );
    await _historyService.addRun(run);
  }

  void _handleAutoCalibrate() {
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to robot over BLE to calibrate')),
      );
      return;
    }
    _activeService?.triggerAutoCalibration();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Triggering optical auto-calibration routine...'),
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tuning & Calibration Handlers
  // ---------------------------------------------------------------------------

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

  void _sendPidValuesQuietly() {
    _activeService?.sendCommand('${AppConstants.cmdKpPrefix}${kp.toStringAsFixed(2)}');
    _activeService?.sendCommand('${AppConstants.cmdKiPrefix}${ki.toStringAsFixed(2)}');
    _activeService?.sendCommand('${AppConstants.cmdKdPrefix}${kd.toStringAsFixed(2)}');
  }

  void _handlePidSend() {
    _sendPidValuesQuietly();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        content: Text(
          'PID Sent: P ${kp.toStringAsFixed(2)} | I ${ki.toStringAsFixed(2)} | D ${kd.toStringAsFixed(2)}',
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
    _sendPidValuesQuietly();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 800),
        content: Text('PID gains reset to default'),
      ),
    );
  }

  void _handleSensorEnableChanged(int index, bool enabled) {
    if (index < 0 || index >= sensorEnabled.length) return;
    setState(() => sensorEnabled[index] = enabled);
    _activeService?.sendSensorEnable(index: index, enabled: enabled);
    _settingsService.saveSensorEnabled(sensorEnabled);
  }

  void _handleAllSensorsEnableChanged(bool enabled) {
    setState(() {
      sensorEnabled = List<bool>.filled(AppConstants.sensorCount, enabled);
    });
    final mask = enabled ? ((1 << AppConstants.sensorCount) - 1) : 0;
    _activeService?.sendSensorMask(mask);
    _settingsService.saveSensorEnabled(sensorEnabled);
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
  }

  Future<void> _handleSaveCalibration() async {
    await _settingsService.saveSensorThresholds(sensorThresholds);
    await _settingsService.saveSensorEnabled(sensorEnabled);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 900),
        content: Text('Sensor calibration & thresholds saved'),
      ),
    );
  }

  void _handleInvertSteeringChanged(bool inverted) {
    setState(() => invertSteering = inverted);
    _activeService?.sendInvertSteering(inverted);
    _settingsService.saveSettings(
      _defaultSettings.copyWith(invertSteering: inverted),
    );
  }

  void _handleResetSpeedDefaults() {
    setState(() {
      maxSpeedController.text = _defaultSettings.maxSpeed.toString();
      baseSpeedController.text = _defaultSettings.baseSpeed.toString();
      minSpeedController.text = _defaultSettings.minSpeed.toString();
      invertSteering = _defaultSettings.invertSteering;
    });
    _activeService?.sendCommand('${AppConstants.cmdMaxSpeedPrefix}${_defaultSettings.maxSpeed}');
    _activeService?.sendCommand('${AppConstants.cmdBaseSpeedPrefix}${_defaultSettings.baseSpeed}');
    _activeService?.sendMinSpeed(_defaultSettings.minSpeed);
    _activeService?.sendInvertSteering(_defaultSettings.invertSteering);
  }

  @override
  void dispose() {
    maxSpeedController.dispose();
    baseSpeedController.dispose();
    minSpeedController.dispose();
    allThresholdController.dispose();
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
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
              const TextSpan(text: 'LineRobo '),
              TextSpan(
                text: 'Championship',
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
                icon: const Icon(Icons.bluetooth_searching),
                onPressed: _navigateToBluetoothSettings,
                tooltip: 'BLE Connection',
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
            tooltip: 'App Defaults',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Live 12-Channel Optical Telemetry & Metric Center Needle
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Optical Telemetry',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Analog',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Switch(
                                value: showAnalogSensors,
                                onChanged: (value) => setState(() => showAnalogSensors = value),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SensorBar(
                        sensorOnLine: sensorOnLine,
                        sensorRawValues: sensorRawValues,
                        sensorEnabled: sensorEnabled,
                        showAnalog: showAnalogSensors,
                        lineError: lineError,
                        lineDetected: lineDetected,
                        onSensorTap: (index) {
                          final cur = sensorEnabled[index];
                          _handleSensorEnableChanged(index, !cur);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 2. Primary Action Card: Start / Emergency Stop, run duration timer, and Calibrate Sensors
              ControlSummaryCard(
                isRunning: isRunning,
                runtime: runtime,
                isConnected: isConnected,
                onStartStop: _handleStartStop,
                onCalibrate: _handleAutoCalibrate,
              ),
              const SizedBox(height: 12),

              // 3. PID Tuning Card: Real-time sliders for Kp, Ki, Kd with scale multipliers
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

              // 4. Speed & Drive Card: Base Speed, Max Speed, Min Speed, and Steering Inversion toggle
              SpeedCard(
                maxSpeedController: maxSpeedController,
                baseSpeedController: baseSpeedController,
                minSpeedController: minSpeedController,
                invertSteering: invertSteering,
                onInvertSteeringChanged: _handleInvertSteeringChanged,
                onMaxSpeedSend: () {
                  final spd = maxSpeedController.text.trim();
                  _activeService?.sendCommand('${AppConstants.cmdMaxSpeedPrefix}$spd');
                },
                onBaseSpeedSend: () {
                  final spd = baseSpeedController.text.trim();
                  _activeService?.sendCommand('${AppConstants.cmdBaseSpeedPrefix}$spd');
                },
                onMinSpeedSend: () {
                  final minSpeed = int.tryParse(minSpeedController.text.trim()) ?? AppConstants.defaultMinSpeed;
                  _activeService?.sendMinSpeed(minSpeed);
                },
                onResetDefaults: _handleResetSpeedDefaults,
              ),
              const SizedBox(height: 12),

              // 5. Individual & Global Sensor Threshold Calibration Card
              SensorsCard(
                sensorOnLine: sensorOnLine,
                sensorRawValues: sensorRawValues,
                sensorEnabled: sensorEnabled,
                showAnalog: showAnalogSensors,
                isCalibrationMode: isCalibrationMode,
                sensorThresholds: sensorThresholds,
                lineError: lineError,
                lineDetected: lineDetected,
                onShowAnalogChanged: (value) => setState(() => showAnalogSensors = value),
                onCalibrationModeChanged: (value) => setState(() => isCalibrationMode = value),
                onSensorThresholdPreview: _handleSensorThresholdPreview,
                onSensorThresholdCommit: _handleSensorThresholdCommit,
                onAllSensorThresholdCommit: _handleAllSensorThresholdCommit,
                onSensorEnableChanged: _handleSensorEnableChanged,
                onAllSensorsEnableChanged: _handleAllSensorsEnableChanged,
                onSaveCalibration: _handleSaveCalibration,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
