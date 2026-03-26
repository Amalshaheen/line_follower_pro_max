import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

class AppSettings {
  final double kp;
  final double ki;
  final double kd;
  final int maxSpeed;
  final int baseSpeed;
  final int threshold;

  const AppSettings({
    required this.kp,
    required this.ki,
    required this.kd,
    required this.maxSpeed,
    required this.baseSpeed,
    required this.threshold,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      kp: AppConstants.defaultKp,
      ki: AppConstants.defaultKi,
      kd: AppConstants.defaultKd,
      maxSpeed: AppConstants.defaultMaxSpeed,
      baseSpeed: AppConstants.defaultBaseSpeed,
      threshold: AppConstants.defaultThreshold,
    );
  }

  AppSettings copyWith({
    double? kp,
    double? ki,
    double? kd,
    int? maxSpeed,
    int? baseSpeed,
    int? threshold,
  }) {
    return AppSettings(
      kp: kp ?? this.kp,
      ki: ki ?? this.ki,
      kd: kd ?? this.kd,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      baseSpeed: baseSpeed ?? this.baseSpeed,
      threshold: threshold ?? this.threshold,
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

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
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
      threshold: _prefs?.getInt(_thresholdKey) ?? defaults.threshold,
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
  }
}
