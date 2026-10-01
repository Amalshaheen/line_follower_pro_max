import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:line_follower_pro_max/constants/app_constants.dart';
import 'package:line_follower_pro_max/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppSettings Tests', () {
    test('Defaults match AppConstants', () {
      final defaults = AppSettings.defaults();
      expect(defaults.kp, AppConstants.defaultKp);
      expect(defaults.ki, AppConstants.defaultKi);
      expect(defaults.kd, AppConstants.defaultKd);
      expect(defaults.maxSpeed, AppConstants.defaultMaxSpeed);
      expect(defaults.baseSpeed, AppConstants.defaultBaseSpeed);
      expect(defaults.threshold, AppConstants.defaultThreshold);
      expect(defaults.deviceName, AppConstants.defaultDeviceName);
    });

    test('copyWith updates specific properties', () {
      final defaults = AppSettings.defaults();
      final updated = defaults.copyWith(
        kp: 42.0,
        deviceName: 'RoboRacer',
      );
      expect(updated.kp, 42.0);
      expect(updated.deviceName, 'RoboRacer');
      expect(updated.ki, defaults.ki);
      expect(updated.maxSpeed, defaults.maxSpeed);
    });
  });

  group('SettingsService Onboarding Tests', () {
    test('isOnboardingComplete defaults to false', () async {
      final service = SettingsService();
      final complete = await service.isOnboardingComplete();
      expect(complete, isFalse);
    });

    test('setOnboardingComplete sets flag to true and persists', () async {
      final service = SettingsService();
      await service.setOnboardingComplete(true);
      final complete = await service.isOnboardingComplete();
      expect(complete, isTrue);
    });

    test('saveSettings and getSettings persist custom values', () async {
      final service = SettingsService();
      const custom = AppSettings(
        kp: 40.0,
        ki: 0.1,
        kd: 1.5,
        maxSpeed: 220,
        baseSpeed: 130,
        threshold: 2500,
        deviceName: 'CustomBot_BLE',
      );
      await service.saveSettings(custom);
      final loaded = await service.getSettings();

      expect(loaded.kp, 40.0);
      expect(loaded.ki, 0.1);
      expect(loaded.kd, 1.5);
      expect(loaded.maxSpeed, 220);
      expect(loaded.baseSpeed, 130);
      expect(loaded.threshold, 2500);
      expect(loaded.deviceName, 'CustomBot_BLE');
    });
  });
}
