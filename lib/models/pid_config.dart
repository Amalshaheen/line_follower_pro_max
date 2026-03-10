/// PID controller configuration for the line follower robot.
/// 
/// Hardware uses direct values: Kp=30.0, Ki=0.0, Kd=0.0 (defaults)
/// The app uses slider values (0-1) multiplied by scale to get effective values.
class PidConfig {
  double kp; // Effective Kp value sent to hardware
  double ki; // Effective Ki value sent to hardware
  double kd; // Effective Kd value sent to hardware
  double pScale;
  double iScale;
  double dScale;
  int maxSpeed;
  int baseSpeed;

  PidConfig({
    this.kp = 30.0,
    this.ki = 0.0,
    this.kd = 0.0,
    this.pScale = 10.0, // P scale: 10.0 for coarse, 1.0 for fine
    this.iScale = 1.0,
    this.dScale = 1.0,
    this.maxSpeed = 255,
    this.baseSpeed = 150,
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
    );
  }
}
