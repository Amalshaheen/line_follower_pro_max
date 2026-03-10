import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../widgets/index.dart';
import '../constants/app_constants.dart';
import '../models/pid_run_history.dart';
import '../services/bluetooth_service.dart';
import '../services/history_service.dart';
import 'bluetooth_settings_page.dart';

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
  late List<bool> sensorOnLine = List<bool>.filled(AppConstants.sensorCount, false);
  late List<int> sensorRawValues = List<int>.filled(AppConstants.sensorCount, 0);
  
  // PID values - these are the effective values sent to hardware
  double kp = AppConstants.defaultKp;
  double ki = AppConstants.defaultKi;
  double kd = AppConstants.defaultKd;
  double pScale = AppConstants.defaultPScale;
  double iScale = AppConstants.defaultIScale;
  double dScale = AppConstants.defaultDScale;

  late TextEditingController pController = TextEditingController(text: AppConstants.defaultKp.toStringAsFixed(2));
  late TextEditingController iController = TextEditingController(text: AppConstants.defaultKi.toStringAsFixed(2));
  late TextEditingController dController = TextEditingController(text: AppConstants.defaultKd.toStringAsFixed(2));
  late TextEditingController maxSpeedController = TextEditingController(text: '255');
  late TextEditingController baseSpeedController = TextEditingController(text: '150');

  // History service and run history
  final HistoryService _historyService = HistoryService();
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
    _loadHistory();
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
    pController.dispose();
    iController.dispose();
    dController.dispose();
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
        debugPrint('✅ [DASHBOARD] onSensorDataReceived called with ${onLine.length} sensors');
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
            btStatus = 'Connected to ${selectedDevice!.name ?? selectedDevice!.address}';
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
          btStatus = 'Connected to ${selectedDevice!.name ?? selectedDevice!.address}';
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

  double _effectivePidValue(double sliderValue, double scale) {
    return sliderValue * 10 * scale;
  }

  double _getBaseValue(double currentValue, double scale) {
    // Calculate base value (fixed part) based on current scale precision
    final increment = 10 * scale;
    return (currentValue / increment).floor() * increment;
  }

  double _getSliderPosition(double currentValue, double scale) {
    // Calculate slider position to adjust only at current scale level
    final baseValue = _getBaseValue(currentValue, scale);
    final increment = 10 * scale;
    return ((currentValue - baseValue) / increment).clamp(0.0, 1.0);
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
      pController.text = run.kp.toStringAsFixed(2);
      iController.text = run.ki.toStringAsFixed(2);
      dController.text = run.kd.toStringAsFixed(2);
      maxSpeedController.text = run.maxSpeed.toString();
      baseSpeedController.text = run.baseSpeed.toString();
    });
    
    // Send all values to hardware
    bluetoothService.sendCommand('${AppConstants.cmdKpPrefix}${run.kp.toStringAsFixed(2)}');
    bluetoothService.sendCommand('${AppConstants.cmdKiPrefix}${run.ki.toStringAsFixed(2)}');
    bluetoothService.sendCommand('${AppConstants.cmdKdPrefix}${run.kd.toStringAsFixed(2)}');
    bluetoothService.sendCommand('${AppConstants.cmdMaxSpeedPrefix}${run.maxSpeed}');
    bluetoothService.sendCommand('${AppConstants.cmdBaseSpeedPrefix}${run.baseSpeed}');
    
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
    final command = newRunning ? AppConstants.cmdRunStart : AppConstants.cmdRunStop;
    bluetoothService.sendCommand(command);
  }

  // Calibration methods
  void _handleCalibrateBlack() {
    debugPrint('📏 [APP] Starting BLACK calibration');
    bluetoothService.sendCommand(AppConstants.cmdCalibrateBlack);
  }

  void _handleCalibrateWhite() {
    debugPrint('📏 [APP] Starting WHITE calibration');
    bluetoothService.sendCommand(AppConstants.cmdCalibrateWhite);
  }

  void _handlePChanged(double value) {
    setState(() {
      final baseValue = _getBaseValue(double.tryParse(pController.text) ?? kp, pScale);
      final newEffectiveValue = baseValue + _effectivePidValue(value, pScale);
      kp = newEffectiveValue;
      pController.text = newEffectiveValue.toStringAsFixed(2);
    });
  }

  void _handlePChangeEnd(double value) {
    final effectiveKp = double.tryParse(pController.text) ?? kp;
    final command = '${AppConstants.cmdKpPrefix}${effectiveKp.toStringAsFixed(2)}';
    debugPrint('📊 [APP] Kp value changed to ${effectiveKp.toStringAsFixed(2)}, sending: $command');
    bluetoothService.sendCommand(command);
  }

  void _handlePSubmitted(String input) {
    final newKp = double.tryParse(input) ?? kp;
    setState(() {
      kp = newKp;
      pController.text = newKp.toStringAsFixed(2);
    });
    final command = '${AppConstants.cmdKpPrefix}${newKp.toStringAsFixed(2)}';
    debugPrint('📊 [APP] Kp value submitted as ${newKp.toStringAsFixed(2)}, sending: $command');
    bluetoothService.sendCommand(command);
  }

  void _handlePScaleChanged(double newScale) {
    setState(() {
      pScale = newScale;
    });
  }

  void _handleIChanged(double value) {
    setState(() {
      final baseValue = _getBaseValue(double.tryParse(iController.text) ?? ki, iScale);
      final newEffectiveValue = baseValue + _effectivePidValue(value, iScale);
      ki = newEffectiveValue;
      iController.text = newEffectiveValue.toStringAsFixed(2);
    });
  }

  void _handleIChangeEnd(double value) {
    final effectiveKi = double.tryParse(iController.text) ?? ki;
    final command = '${AppConstants.cmdKiPrefix}${effectiveKi.toStringAsFixed(2)}';
    debugPrint('📊 [APP] Ki value changed to ${effectiveKi.toStringAsFixed(2)}, sending: $command');
    bluetoothService.sendCommand(command);
  }

  void _handleISubmitted(String input) {
    final newKi = double.tryParse(input) ?? ki;
    setState(() {
      ki = newKi;
      iController.text = newKi.toStringAsFixed(2);
    });
    final command = '${AppConstants.cmdKiPrefix}${newKi.toStringAsFixed(2)}';
    debugPrint('📊 [APP] Ki value submitted as ${newKi.toStringAsFixed(2)}, sending: $command');
    bluetoothService.sendCommand(command);
  }

  void _handleIScaleChanged(double newScale) {
    setState(() {
      iScale = newScale;
    });
  }

  void _handleDChanged(double value) {
    setState(() {
      final baseValue = _getBaseValue(double.tryParse(dController.text) ?? kd, dScale);
      final newEffectiveValue = baseValue + _effectivePidValue(value, dScale);
      kd = newEffectiveValue;
      dController.text = newEffectiveValue.toStringAsFixed(2);
    });
  }

  void _handleDChangeEnd(double value) {
    final effectiveKd = double.tryParse(dController.text) ?? kd;
    final command = '${AppConstants.cmdKdPrefix}${effectiveKd.toStringAsFixed(2)}';
    debugPrint('📊 [APP] Kd value changed to ${effectiveKd.toStringAsFixed(2)}, sending: $command');
    bluetoothService.sendCommand(command);
  }

  void _handleDSubmitted(String input) {
    final newKd = double.tryParse(input) ?? kd;
    setState(() {
      kd = newKd;
      dController.text = newKd.toStringAsFixed(2);
    });
    final command = '${AppConstants.cmdKdPrefix}${newKd.toStringAsFixed(2)}';
    debugPrint('📊 [APP] Kd value submitted as ${newKd.toStringAsFixed(2)}, sending: $command');
    bluetoothService.sendCommand(command);
  }

  void _handleDScaleChanged(double newScale) {
    setState(() {
      dScale = newScale;
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🏗️ [DASHBOARD] Building... current sensorOnLine: length=${sensorOnLine.length}, values=${sensorOnLine.map((s) => s ? 'ON' : 'OFF').join(',')}');
    
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
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SensorsCard(sensorOnLine: sensorOnLine),
              const SizedBox(height: 12),
              ControlSummaryCard(
                isRunning: isRunning,
                trackFinished: trackFinished,
                runtime: runtime,
                onStartStop: _handleStartStop,
                onCalibrateBlack: _handleCalibrateBlack,
                onCalibrateWhite: _handleCalibrateWhite,
              ),
              const SizedBox(height: 12),
              PidCard(
                pValue: _getSliderPosition(kp, pScale),
                iValue: _getSliderPosition(ki, iScale),
                dValue: _getSliderPosition(kd, dScale),
                pScale: pScale,
                iScale: iScale,
                dScale: dScale,
                pController: pController,
                iController: iController,
                dController: dController,

                onPChanged: _handlePChanged,
                onIChanged: _handleIChanged,
                onDChanged: _handleDChanged,
                onPChangeEnd: _handlePChangeEnd,
                onIChangeEnd: _handleIChangeEnd,
                onDChangeEnd: _handleDChangeEnd,
                onPSubmitted: _handlePSubmitted,
                onISubmitted: _handleISubmitted,
                onDSubmitted: _handleDSubmitted,
                onPScaleChanged: _handlePScaleChanged,
                onIScaleChanged: _handleIScaleChanged,
                onDScaleChanged: _handleDScaleChanged,
              ),
              const SizedBox(height: 12),
              SpeedCard(
                maxSpeedController: maxSpeedController,
                baseSpeedController: baseSpeedController,
                onMaxSpeedSend: () {
                  final maxSpeed = maxSpeedController.text;
                  debugPrint('⚡ [APP] Max Speed button pressed, value: $maxSpeed');
                  final command = '${AppConstants.cmdMaxSpeedPrefix}$maxSpeed';
                  bluetoothService.sendCommand(command);
                },
                onBaseSpeedSend: () {
                  final baseSpeed = baseSpeedController.text;
                  debugPrint('⚡ [APP] Base Speed button pressed, value: $baseSpeed');
                  final command = '${AppConstants.cmdBaseSpeedPrefix}$baseSpeed';
                  bluetoothService.sendCommand(command);
                },
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
