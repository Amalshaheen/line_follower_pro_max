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
  bool autoStopOnFinish = true;
  bool lineLostRecoveryEnabled = true;
  DateTime? _currentRunStartedAt;
  bool _currentRunSaved = false;

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
  late TextEditingController allThresholdController = TextEditingController(
    text: AppConstants.defaultThreshold.toString(),
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
        allThresholdController.text = loaded.threshold.toString();
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
    allThresholdController.dispose();
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
              _currentRunStartedAt = DateTime.now();
              _currentRunSaved = false;
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
            if (autoStopOnFinish) {
              isRunning = false;
            }
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
            if (!_currentRunSaved) {
              _currentRunSaved = true;
              _saveRunToHistory(runtimeMs);
            }
          }
        }
      },
      onAckReceived: (command, value) {
        debugPrint('✅ [DASHBOARD] ACK received: $command=$value');
        if (!mounted) {
          return;
        }
        if (command == 'BASE') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(milliseconds: 900),
              content: Text('Base speed confirmed: $value'),
            ),
          );
        }
      },
      onThresholdsReceived: (thresholds) {
        if (mounted && thresholds.length == AppConstants.sensorCount) {
          final average =
              thresholds.reduce((a, b) => a + b) ~/ thresholds.length;
          setState(() {
            sensorThresholds = thresholds;
            allThresholdController.text = average.toString();
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
          bluetoothService.sendCommand(
            '${AppConstants.cmdAutoStopPrefix}${autoStopOnFinish ? 1 : 0}',
          );
          bluetoothService.sendCommand(
            '${AppConstants.cmdLineLostRecoveryPrefix}${lineLostRecoveryEnabled ? 1 : 0}',
          );
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

  Future<bool?> _showSaveRunDialog({required int runtimeMs}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save This Run?'),
        content: Text('Runtime: ${(runtimeMs / 1000).toStringAsFixed(2)}s'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  int _currentElapsedRuntimeMs() {
    final startedAt = _currentRunStartedAt;
    if (startedAt == null) {
      return runtime;
    }
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
      debugPrint('▶️  [APP] Robot STARTED');
      bluetoothService.sendCommand(AppConstants.cmdRunStart);
      return;
    }

    final elapsed = _currentElapsedRuntimeMs();
    final shouldAskSave = elapsed > 0 && !_currentRunSaved;

    setState(() {
      isRunning = false;
      runtime = elapsed;
    });
    debugPrint('⏹️  [APP] Robot STOPPED');
    bluetoothService.sendCommand(AppConstants.cmdRunStop);

    if (!shouldAskSave || !mounted) {
      return;
    }

    final shouldSave = await _showSaveRunDialog(runtimeMs: elapsed);
    if (!mounted) {
      return;
    }

    if (shouldSave == true) {
      _currentRunSaved = true;
      await _saveRunToHistory(elapsed);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Run saved to history')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Run discarded')));
    }
  }

  void _handleAutoStopChanged(bool enabled) {
    setState(() => autoStopOnFinish = enabled);
    bluetoothService.sendCommand(
      '${AppConstants.cmdAutoStopPrefix}${enabled ? 1 : 0}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        content: Text(
          enabled
              ? 'Auto-stop on finish enabled'
              : 'Auto-stop on finish disabled',
        ),
      ),
    );
  }

  void _handleLineLostRecoveryChanged(bool enabled) {
    setState(() => lineLostRecoveryEnabled = enabled);
    bluetoothService.sendCommand(
      '${AppConstants.cmdLineLostRecoveryPrefix}${enabled ? 1 : 0}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        content: Text(
          enabled
              ? 'Line-lost recovery enabled'
              : 'Line-lost recovery disabled',
        ),
      ),
    );
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

  void _handleAllSensorThresholdCommit(int value) {
    final normalized = value.clamp(0, 4095);
    setState(() {
      sensorThresholds = List<int>.filled(AppConstants.sensorCount, normalized);
      allThresholdController.text = normalized.toString();
    });
    bluetoothService.sendThresholdForAllSensors(normalized);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        content: Text('All thresholds set to $normalized'),
      ),
    );
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
                onStartStop: () {
                  _handleStartStop();
                },
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
