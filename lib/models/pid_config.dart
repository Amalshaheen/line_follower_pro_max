import '../constants/app_constants.dart';

/// PID controller configuration for the line follower robot.
/// 
/// Hardware defaults in line_follower_hardware.ino:
/// Kp=2.5 (PWM per mm error), Ki=0.0, Kd=0.08 (PWM per mm/s),
/// BaseSpeed=70, MaxSpeed=120, MinSpeed=30, InvertSteering=false.
class PidConfig {
  double kp; // Effective Kp value sent to hardware
  double ki; // Effective Ki value sent to hardware
  double kd; // Effective Kd value sent to hardware
  double pScale;
  double iScale;
  double dScale;
  int maxSpeed;
  int baseSpeed;
  int minSpeed;
  bool invertSteering;

  PidConfig({
    this.kp = AppConstants.defaultKp,
    this.ki = AppConstants.defaultKi,
    this.kd = AppConstants.defaultKd,
    this.pScale = AppConstants.defaultPScale,
    this.iScale = AppConstants.defaultIScale,
    this.dScale = AppConstants.defaultDScale,
    this.maxSpeed = AppConstants.defaultMaxSpeed,
    this.baseSpeed = AppConstants.defaultBaseSpeed,
    this.minSpeed = AppConstants.defaultMinSpeed,
    this.invertSteering = AppConstants.defaultInvertSteering,
  });

  /// Get slider value (0-1) from effective value based on scale.
  /// Scale determines the range: e.g., scale=10 means slider covers 0-100
  double getSliderValue(double effectiveValue, double scale) {
    if (scale == 0) return 0;
    final maxValue = scale * 10; // slider 0-1 maps to 0-(scale*10)
    return (effectiveValue / maxValue).clamp(0.0, 1.0);
  }

  /// Get effective value from slider value (0-1) based on scale.
  double getEffectiveValue(double sliderValue, double scale) {
    return sliderValue * scale * 10;
  }

  /// Create a copy of this config with optional modifications.
  PidConfig copyWith({
    double? kp,
    double? ki,
    double? kd,
    double? pScale,
    double? iScale,
    double? dScale,
    int? maxSpeed,
    int? baseSpeed,
    int? minSpeed,
    bool? invertSteering,
  }) {
    return PidConfig(
      kp: kp ?? this.kp,
      ki: ki ?? this.ki,
      kd: kd ?? this.kd,
      pScale: pScale ?? this.pScale,
      iScale: iScale ?? this.iScale,
      dScale: dScale ?? this.dScale,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      baseSpeed: baseSpeed ?? this.baseSpeed,
      minSpeed: minSpeed ?? this.minSpeed,
      invertSteering: invertSteering ?? this.invertSteering,
    );
  }
}
