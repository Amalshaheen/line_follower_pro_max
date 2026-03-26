import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../widgets/index.dart';
import '../constants/app_constants.dart';
import '../models/pid_run_history.dart';
import '../services/bluetooth_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
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
  int runtime = 0; // Runtime in milliseconds
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

  // PID values - these are the effective values sent to hardware
  double kp = AppConstants.defaultKp;
  double ki = AppConstants.defaultKi;
  double kd = AppConstants.defaultKd;

  late TextEditingController maxSpeedController = TextEditingController(
    text: AppConstants.defaultMaxSpeed.toString(),
  );
  late TextEditingController baseSpeedController = TextEditingController(
    text: AppConstants.defaultBaseSpeed.toString(),
  );
  late List<int> sensorThresholds = List<int>.filled(
    AppConstants.sensorCount,
    AppConstants.defaultThreshold,
  );

  // History service and run history
  final HistoryService _historyService = HistoryService();
  final SettingsService _settingsService = SettingsService();
  AppSettings _defaultSettings = AppSettings.defaults();
  List<PidRunHistory> history = [];

  // Bluetooth related variables
  late BluetoothService bluetoothService;
  bool isConnected = false;
  bool isConnecting = false;
  String btStatus = 'Disconnected';
  List<BluetoothDevice> bondedDevices = [];
  BluetoothDevice? selectedDevice;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
    _loadDefaultSettings(applyToCurrentControls: true);
    _loadHistory();
  }

  Future<void> _loadDefaultSettings({
    required bool applyToCurrentControls,
  }) async {
    final loaded = await _settingsService.getSettings();
    final savedSensorThresholds = await _settingsService.getSensorThresholds();
    if (!mounted) {
      return;
    }
    setState(() {
      _defaultSettings = loaded;
      if (applyToCurrentControls) {
        kp = loaded.kp;
        ki = loaded.ki;
        kd = loaded.kd;
        maxSpeedController.text = loaded.maxSpeed.toString();
        baseSpeedController.text = loaded.baseSpeed.toString();
        sensorThresholds =
            savedSensorThresholds ??
            List<int>.filled(AppConstants.sensorCount, loaded.threshold);
      }
    });
  }

  Future<void> _loadHistory() async {
    final loadedHistory = await _historyService.getHistory();
    if (mounted) {
      setState(() {
        history = loadedHistory;
      });
    }
  }

  @override
  void dispose() {
    maxSpeedController.dispose();
    baseSpeedController.dispose();
    bluetoothService.dispose();
    super.dispose();
  }

  Future<void> _initBluetooth() async {
    bluetoothService = BluetoothService(
      onDataReceived: (line) {
        if (mounted) {
          debugPrint('📨 [DASHBOARD] Message received: $line');
          setState(() {
            // Handle status messages from hardware
            if (line == 'Robot Started') {
              isRunning = true;
              trackFinished = false;
              runtime = 0;
            } else if (line == 'Robot Stopped') {
              isRunning = false;
            }
          });
        }
      },
      onSensorDataReceived: (rawValues, onLine) {
        debugPrint(
          '✅ [DASHBOARD] onSensorDataReceived called with ${onLine.length} sensors',
        );
        if (mounted && onLine.length == AppConstants.sensorCount) {
          debugPrint('   ✓ Check passed! Updating UI...');
          setState(() {
            sensorOnLine = onLine;
            sensorRawValues = rawValues;
          });
          // Debug output
          final sensorStates = onLine.map((s) => s ? '🟢' : '⚫').join(' ');
          debugPrint('📊 [APP] Sensor states updated: [$sensorStates]');
        }
      },
      onTrackFinished: (runtimeMs) {
        if (mounted) {
          setState(() {
            trackFinished = true;
            isRunning = false;
            if (runtimeMs > 0) {
              runtime = runtimeMs;
            }
          });
          debugPrint('🏁 [DASHBOARD] Track finished! Runtime: ${runtime}ms');
          // Request the runtime if we got 0
          if (runtime == 0) {
            bluetoothService.sendCommand(AppConstants.cmdQueryTime);
          } else {
            // Save the successful run to history
            _saveRunToHistory(runtimeMs);
          }
        }
      },
      onAckReceived: (command, value) {
        debugPrint('✅ [DASHBOARD] ACK received: $command=$value');
        // Can be used to confirm settings were applied
      },
      onThresholdsReceived: (thresholds) {
        if (mounted && thresholds.length == AppConstants.sensorCount) {
          setState(() {
            sensorThresholds = thresholds;
          });
          debugPrint(
            '🎚️ [DASHBOARD] Thresholds synced: ${thresholds.join(', ')}',
          );
        }
      },
      onDisconnected: () {
        if (mounted) {
          setState(() {
            isConnected = false;
            btStatus = 'Disconnected';
          });
        }
      },
    );

    final permissionsGranted = await bluetoothService.initializePermissions();
    if (permissionsGranted) {
      await _loadBondedDevices();
      // Check if already connected
      _updateConnectionStatus();
    }
  }

  void _updateConnectionStatus() {
    if (bluetoothService.isConnected) {
      if (mounted) {
        setState(() {
          isConnected = true;
          if (selectedDevice != null) {
            btStatus =
                'Connected to ${selectedDevice!.name ?? selectedDevice!.address}';
          } else {
            btStatus = 'Connected';
          }
        });
      }
    }
  }

  Future<void> _loadBondedDevices() async {
    final devices = await bluetoothService.getBondedDevices();
    if (mounted) {
      setState(() {
        bondedDevices = devices;
      });
    }
  }

  Future<void> _connectToDevice() async {
    if (selectedDevice == null) return;

    setState(() => isConnecting = true);

    final success = await bluetoothService.connect(selectedDevice!);

    if (mounted) {
      setState(() {
        isConnecting = false;
        if (success) {
          isConnected = true;
          btStatus =
              'Connected to ${selectedDevice!.name ?? selectedDevice!.address}';
          bluetoothService.sendCommand(AppConstants.cmdQueryThresholds);
        } else {
          btStatus = 'Failed to connect';
        }
      });

      // Show feedback to user and close the settings page if connection was successful
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected successfully'),
            duration: Duration(milliseconds: 800),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> _disconnectDevice() async {
    await bluetoothService.disconnect();
    if (mounted) {
      setState(() {
        isConnected = false;
        btStatus = 'Disconnected';
      });
    }
  }

  void _navigateToBluetoothSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BluetoothSettingsPage(
          bondedDevices: bondedDevices,
          selectedDevice: selectedDevice,
          isConnected: isConnected,
          isConnecting: isConnecting,
          btStatus: btStatus,
          onDeviceSelected: (device) {
            setState(() => selectedDevice = device);
          },
          onConnect: _connectToDevice,
          onDisconnect: _disconnectDevice,
          onRefresh: _loadBondedDevices,
        ),
      ),
    ).then((_) {
      // Update connection status when returning from settings
      _updateConnectionStatus();
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
        _loadDefaultSettings(applyToCurrentControls: false);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Defaults saved. Use reset buttons to apply.'),
          ),
        );
      }
    });
  }

  // History management methods
  Future<void> _saveRunToHistory(int runtimeMs) async {
    final run = PidRunHistory.create(
      runtimeMs: runtimeMs,
      kp: kp,
      ki: ki,
      kd: kd,
      maxSpeed: int.tryParse(maxSpeedController.text) ?? 255,
      baseSpeed: int.tryParse(baseSpeedController.text) ?? 150,
    );
    await _historyService.addRun(run);
    await _loadHistory();
    debugPrint('📝 [DASHBOARD] Run saved to history: $run');
  }

  void _restoreConfig(PidRunHistory run) {
    setState(() {
      kp = run.kp;
      ki = run.ki;
      kd = run.kd;
      maxSpeedController.text = run.maxSpeed.toString();
      baseSpeedController.text = run.baseSpeed.toString();
    });

    // Send all values to hardware
    bluetoothService.sendCommand(
      '${AppConstants.cmdKpPrefix}${run.kp.toStringAsFixed(2)}',
    );
    bluetoothService.sendCommand(
      '${AppConstants.cmdKiPrefix}${run.ki.toStringAsFixed(2)}',
    );
    bluetoothService.sendCommand(
      '${AppConstants.cmdKdPrefix}${run.kd.toStringAsFixed(2)}',
    );
    bluetoothService.sendCommand(
      '${AppConstants.cmdMaxSpeedPrefix}${run.maxSpeed}',
    );
    bluetoothService.sendCommand(
      '${AppConstants.cmdBaseSpeedPrefix}${run.baseSpeed}',
    );

    debugPrint('🔄 [DASHBOARD] Configuration restored: ${run.pidSummary}');

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

  void _handleStartStop() {
    final newRunning = !isRunning;
    setState(() {
      isRunning = newRunning;
      if (newRunning) {
        trackFinished = false;
        runtime = 0;
      }
    });
    debugPrint('▶️  [APP] Robot ${newRunning ? 'STARTED' : 'STOPPED'}');
    final command = newRunning
        ? AppConstants.cmdRunStart
        : AppConstants.cmdRunStop;
    bluetoothService.sendCommand(command);
  }

  void _handlePChanged(double value) {
    setState(() {
      kp = value;
    });
  }

  void _handleIChanged(double value) {
    setState(() {
      ki = value;
    });
  }

  void _handleDChanged(double value) {
    setState(() {
      kd = value;
    });
  }

  void _handleCalibrationModeChanged(bool enabled) {
    setState(() => isCalibrationMode = enabled);
    if (enabled) {
      bluetoothService.sendCommand(AppConstants.cmdQueryThresholds);
    }
  }

  void _handleSensorThresholdPreview(int index, int value) {
    if (index < 0 || index >= sensorThresholds.length) {
      return;
    }
    setState(() {
      sensorThresholds[index] = value;
    });
  }

  void _handleSensorThresholdCommit(int index, int value) {
    _handleSensorThresholdPreview(index, value);
    bluetoothService.sendThresholdForSensor(index: index, threshold: value);
  }

  Future<void> _handleSaveCalibration() async {
    await _settingsService.saveSensorThresholds(sensorThresholds);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 900),
        content: Text('Calibration values saved'),
      ),
    );
  }

  void _handlePidSend() {
    bluetoothService.sendCommand(
      '${AppConstants.cmdKpPrefix}${kp.toStringAsFixed(2)}',
    );
    bluetoothService.sendCommand(
      '${AppConstants.cmdKiPrefix}${ki.toStringAsFixed(2)}',
    );
    bluetoothService.sendCommand(
      '${AppConstants.cmdKdPrefix}${kd.toStringAsFixed(2)}',
    );

    debugPrint(
      '📤 [APP] PID sent: Kp=${kp.toStringAsFixed(2)}, Ki=${ki.toStringAsFixed(2)}, Kd=${kd.toStringAsFixed(2)}',
    );

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

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '🏗️ [DASHBOARD] Building... current sensorOnLine: length=${sensorOnLine.length}, values=${sensorOnLine.map((s) => s ? 'ON' : 'OFF').join(',')}',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appTitle),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.bluetooth),
                onPressed: _navigateToBluetoothSettings,
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
                onShowAnalogChanged: (value) {
                  setState(() => showAnalogSensors = value);
                },
                onCalibrationModeChanged: _handleCalibrationModeChanged,
                onSensorThresholdPreview: _handleSensorThresholdPreview,
                onSensorThresholdCommit: _handleSensorThresholdCommit,
                onSaveCalibration: _handleSaveCalibration,
              ),
              const SizedBox(height: 12),
              ControlSummaryCard(
                isRunning: isRunning,
                trackFinished: trackFinished,
                runtime: runtime,
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
                  debugPrint(
                    '⚡ [APP] Max Speed button pressed, value: $maxSpeed',
                  );
                  final command = '${AppConstants.cmdMaxSpeedPrefix}$maxSpeed';
                  bluetoothService.sendCommand(command);
                },
                onBaseSpeedSend: () {
                  final baseSpeed = baseSpeedController.text;
                  debugPrint(
                    '⚡ [APP] Base Speed button pressed, value: $baseSpeed',
                  );
                  final command =
                      '${AppConstants.cmdBaseSpeedPrefix}$baseSpeed';
                  bluetoothService.sendCommand(command);
                },
                onResetDefaults: _handleResetSpeedThresholdDefaults,
              ),
              const SizedBox(height: 12),
              HistoryCard(
                history: history,
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
