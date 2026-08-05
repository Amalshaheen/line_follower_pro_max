import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'robot_service.dart';

class AppSettings {
  final double kp;
  final double ki;
  final double kd;
  final int maxSpeed;
  final int baseSpeed;
  final int threshold;

  /// Which connection transport to use when connecting to the robot.
  final ConnectionMode connectionMode;

  /// The device name (or name prefix) to scan/filter for.
  final String deviceName;

  const AppSettings({
    required this.kp,
    required this.ki,
    required this.kd,
    required this.maxSpeed,
    required this.baseSpeed,
    required this.threshold,
    this.connectionMode = ConnectionMode.classic,
    this.deviceName = AppConstants.defaultDeviceName,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      kp: AppConstants.defaultKp,
      ki: AppConstants.defaultKi,
      kd: AppConstants.defaultKd,
      maxSpeed: AppConstants.defaultMaxSpeed,
      baseSpeed: AppConstants.defaultBaseSpeed,
      threshold: AppConstants.defaultThreshold,
      connectionMode: ConnectionMode.classic,
      deviceName: AppConstants.defaultDeviceName,
    );
  }

  AppSettings copyWith({
    double? kp,
    double? ki,
    double? kd,
    int? maxSpeed,
    int? baseSpeed,
    int? threshold,
    ConnectionMode? connectionMode,
    String? deviceName,
  }) {
    return AppSettings(
      kp: kp ?? this.kp,
      ki: ki ?? this.ki,
      kd: kd ?? this.kd,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      baseSpeed: baseSpeed ?? this.baseSpeed,
      threshold: threshold ?? this.threshold,
      connectionMode: connectionMode ?? this.connectionMode,
      deviceName: deviceName ?? this.deviceName,
    );
  }
}

class SettingsService {
  static const String _kpKey = 'settings.default.kp';
  static const String _kiKey = 'settings.default.ki';
  static const String _kdKey = 'settings.default.kd';
  static const String _maxSpeedKey = 'settings.default.maxSpeed';
  static const String _baseSpeedKey = 'settings.default.baseSpeed';
  static const String _thresholdKey = 'settings.default.threshold';
  static const String _sensorThresholdsKey = 'settings.calibration.thresholds';
  static const String _connectionModeKey = 'settings.connection.mode';
  static const String _deviceNameKey = 'settings.connection.deviceName';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<AppSettings> getSettings() async {
    await init();
    final defaults = AppSettings.defaults();

    final modeStr = _prefs?.getString(_connectionModeKey);
    final mode = modeStr == 'ble' ? ConnectionMode.ble : ConnectionMode.classic;

    return AppSettings(
      kp: _prefs?.getDouble(_kpKey) ?? defaults.kp,
      ki: _prefs?.getDouble(_kiKey) ?? defaults.ki,
      kd: _prefs?.getDouble(_kdKey) ?? defaults.kd,
      maxSpeed: _prefs?.getInt(_maxSpeedKey) ?? defaults.maxSpeed,
      baseSpeed: _prefs?.getInt(_baseSpeedKey) ?? defaults.baseSpeed,
      threshold: _prefs?.getInt(_thresholdKey) ?? defaults.threshold,
      connectionMode: mode,
      deviceName: _prefs?.getString(_deviceNameKey) ?? defaults.deviceName,
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    await init();
    await _prefs?.setDouble(_kpKey, settings.kp);
    await _prefs?.setDouble(_kiKey, settings.ki);
    await _prefs?.setDouble(_kdKey, settings.kd);
    await _prefs?.setInt(_maxSpeedKey, settings.maxSpeed);
    await _prefs?.setInt(_baseSpeedKey, settings.baseSpeed);
    await _prefs?.setInt(_thresholdKey, settings.threshold);
    await _prefs?.setString(
      _connectionModeKey,
      settings.connectionMode == ConnectionMode.ble ? 'ble' : 'classic',
    );
    await _prefs?.setString(_deviceNameKey, settings.deviceName);
  }

  Future<void> saveSensorThresholds(List<int> thresholds) async {
    await init();
    final normalized = List<int>.generate(AppConstants.sensorCount, (index) {
      final value = index < thresholds.length
          ? thresholds[index]
          : AppConstants.defaultThreshold;
      return value.clamp(0, 4095);
    }, growable: false);
    final serialized = normalized.join(',');
    await _prefs?.setString(_sensorThresholdsKey, serialized);
  }

  Future<List<int>?> getSensorThresholds() async {
    await init();
    final raw = _prefs?.getString(_sensorThresholdsKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final parts = raw.split(',');
    if (parts.length != AppConstants.sensorCount) {
      return null;
    }

    return parts
        .map(
          (v) => (int.tryParse(v.trim()) ?? AppConstants.defaultThreshold)
              .clamp(0, 4095),
        )
        .toList(growable: false);
  }

  Future<void> resetToFactoryDefaults() async {
    await init();
    await _prefs?.remove(_kpKey);
    await _prefs?.remove(_kiKey);
    await _prefs?.remove(_kdKey);
    await _prefs?.remove(_maxSpeedKey);
    await _prefs?.remove(_baseSpeedKey);
    await _prefs?.remove(_thresholdKey);
    await _prefs?.remove(_sensorThresholdsKey);
    // Note: connection mode and device name are intentionally NOT reset
    // as they are physical setup choices, not PID defaults.
  }
}
