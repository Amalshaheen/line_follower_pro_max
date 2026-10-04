import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

class AppSettings {
  final double kp;
  final double ki;
  final double kd;
  final int maxSpeed;
  final int baseSpeed;
  final int minSpeed;
  final bool invertSteering;
  final int threshold;

  /// The device name (or name prefix) to scan/filter for over BLE.
  final String deviceName;

  const AppSettings({
    required this.kp,
    required this.ki,
    required this.kd,
    required this.maxSpeed,
    required this.baseSpeed,
    this.minSpeed = AppConstants.defaultMinSpeed,
    this.invertSteering = AppConstants.defaultInvertSteering,
    required this.threshold,
    this.deviceName = AppConstants.defaultDeviceName,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      kp: AppConstants.defaultKp,
      ki: AppConstants.defaultKi,
      kd: AppConstants.defaultKd,
      maxSpeed: AppConstants.defaultMaxSpeed,
      baseSpeed: AppConstants.defaultBaseSpeed,
      minSpeed: AppConstants.defaultMinSpeed,
      invertSteering: AppConstants.defaultInvertSteering,
      threshold: AppConstants.defaultThreshold,
      deviceName: AppConstants.defaultDeviceName,
    );
  }

  AppSettings copyWith({
    double? kp,
    double? ki,
    double? kd,
    int? maxSpeed,
    int? baseSpeed,
    int? minSpeed,
    bool? invertSteering,
    int? threshold,
    String? deviceName,
  }) {
    return AppSettings(
      kp: kp ?? this.kp,
      ki: ki ?? this.ki,
      kd: kd ?? this.kd,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      baseSpeed: baseSpeed ?? this.baseSpeed,
      minSpeed: minSpeed ?? this.minSpeed,
      invertSteering: invertSteering ?? this.invertSteering,
      threshold: threshold ?? this.threshold,
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
  static const String _minSpeedKey = 'settings.default.minSpeed';
  static const String _invertSteeringKey = 'settings.default.invertSteering';
  static const String _thresholdKey = 'settings.default.threshold';
  static const String _sensorThresholdsKey = 'settings.calibration.thresholds';
  static const String _sensorEnabledKey = 'settings.calibration.enabled';
  static const String _deviceNameKey = 'settings.connection.deviceName';
  static const String _onboardingCompleteKey = 'app.onboarding.complete';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<bool> isOnboardingComplete() async {
    await init();
    return _prefs?.getBool(_onboardingCompleteKey) ?? false;
  }

  Future<void> setOnboardingComplete(bool complete) async {
    await init();
    await _prefs?.setBool(_onboardingCompleteKey, complete);
  }

  Future<AppSettings> getSettings() async {
    await init();
    final defaults = AppSettings.defaults();

    return AppSettings(
      kp: _prefs?.getDouble(_kpKey) ?? defaults.kp,
      ki: _prefs?.getDouble(_kiKey) ?? defaults.ki,
      kd: _prefs?.getDouble(_kdKey) ?? defaults.kd,
      maxSpeed: _prefs?.getInt(_maxSpeedKey) ?? defaults.maxSpeed,
      baseSpeed: _prefs?.getInt(_baseSpeedKey) ?? defaults.baseSpeed,
      minSpeed: _prefs?.getInt(_minSpeedKey) ?? defaults.minSpeed,
      invertSteering: _prefs?.getBool(_invertSteeringKey) ?? defaults.invertSteering,
      threshold: _prefs?.getInt(_thresholdKey) ?? defaults.threshold,
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
    await _prefs?.setInt(_minSpeedKey, settings.minSpeed);
    await _prefs?.setBool(_invertSteeringKey, settings.invertSteering);
    await _prefs?.setInt(_thresholdKey, settings.threshold);
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

  Future<void> saveSensorEnabled(List<bool> enabled) async {
    await init();
    final normalized = List<bool>.generate(
      AppConstants.sensorCount,
      (index) => index < enabled.length ? enabled[index] : true,
      growable: false,
    );
    final serialized = normalized.map((b) => b ? '1' : '0').join(',');
    await _prefs?.setString(_sensorEnabledKey, serialized);
  }

  Future<List<bool>?> getSensorEnabled() async {
    await init();
    final raw = _prefs?.getString(_sensorEnabledKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final parts = raw.split(',');
    if (parts.length != AppConstants.sensorCount) {
      return null;
    }

    return parts
        .map((v) => v.trim() == '1' || v.trim().toLowerCase() == 'true')
        .toList(growable: false);
  }

  Future<void> resetToFactoryDefaults() async {
    await init();
    await _prefs?.remove(_kpKey);
    await _prefs?.remove(_kiKey);
    await _prefs?.remove(_kdKey);
    await _prefs?.remove(_maxSpeedKey);
    await _prefs?.remove(_baseSpeedKey);
    await _prefs?.remove(_minSpeedKey);
    await _prefs?.remove(_invertSteeringKey);
    await _prefs?.remove(_thresholdKey);
    await _prefs?.remove(_sensorThresholdsKey);
    await _prefs?.remove(_sensorEnabledKey);
    // Note: device name is intentionally NOT reset as it is a physical
    // setup choice, not a PID default.
  }
}
