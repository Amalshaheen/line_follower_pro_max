import 'package:flutter/material.dart';

/// Available movement and pause actions in the autonomous motion queue.
enum StepType {
  forward,
  reverse,
  turnLeft,
  turnRight,
  wait,
}

/// A discrete motion or delay step in the autonomous execution queue.
class SequenceStep {
  /// Unique identifier for list reordering and animation keys.
  final String id;

  /// The category of motion or delay.
  final StepType type;

  /// The parameter value:
  /// - [StepType.forward], [StepType.reverse]: distance in centimeters (cm)
  /// - [StepType.turnLeft], [StepType.turnRight]: angle in degrees (°)
  /// - [StepType.wait]: duration in milliseconds (ms)
  final double value;

  const SequenceStep({
    required this.id,
    required this.type,
    required this.value,
  });

  /// Factory constructor with automated value clamping according to physical robot kinematics.
  factory SequenceStep.create({
    String? id,
    required StepType type,
    required double value,
  }) {
    final clampedValue = _clampValue(type, value);
    final stepId = id ?? '${DateTime.now().microsecondsSinceEpoch}_${type.name}';
    return SequenceStep(
      id: stepId,
      type: type,
      value: clampedValue,
    );
  }

  /// Clamps the value according to the type's physical limits.
  static double _clampValue(StepType type, double val) {
    switch (type) {
      case StepType.forward:
      case StepType.reverse:
        return val.clamp(1.0, 500.0); // 1 cm to 5 meters
      case StepType.turnLeft:
      case StepType.turnRight:
        return val.clamp(5.0, 720.0); // 5° to 720° (2 full revolutions)
      case StepType.wait:
        return val.clamp(50.0, 10000.0); // 50 ms to 10 seconds
    }
  }

  /// Friendly display title for UI cards.
  String get title {
    switch (type) {
      case StepType.forward:
        return 'Move Forward';
      case StepType.reverse:
        return 'Move Backward';
      case StepType.turnLeft:
        return 'Pivot Left';
      case StepType.turnRight:
        return 'Pivot Right';
      case StepType.wait:
        return 'Pause / Wait';
    }
  }

  /// Short display label.
  String get shortLabel {
    switch (type) {
      case StepType.forward:
        return 'FWD';
      case StepType.reverse:
        return 'REV';
      case StepType.turnLeft:
        return 'LEFT';
      case StepType.turnRight:
        return 'RIGHT';
      case StepType.wait:
        return 'WAIT';
    }
  }

  /// Unit string.
  String get unit {
    switch (type) {
      case StepType.forward:
      case StepType.reverse:
        return 'cm';
      case StepType.turnLeft:
      case StepType.turnRight:
        return '°';
      case StepType.wait:
        return 'ms';
    }
  }

  /// Formatted string showing value and unit (e.g., "25.0 cm", "90.0°", "500 ms").
  String get formattedValue {
    if (type == StepType.wait) {
      return '${value.toInt()} $unit';
    }
    return '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)} $unit';
  }

  /// Standard Material icon representing the motion type.
  IconData get icon {
    switch (type) {
      case StepType.forward:
        return Icons.arrow_upward_rounded;
      case StepType.reverse:
        return Icons.arrow_downward_rounded;
      case StepType.turnLeft:
        return Icons.turn_left_rounded;
      case StepType.turnRight:
        return Icons.turn_right_rounded;
      case StepType.wait:
        return Icons.timer_outlined;
    }
  }

  /// Distinctive accent color for the action type.
  Color get color {
    switch (type) {
      case StepType.forward:
        return const Color(0xFF10B981); // Emerald Green
      case StepType.reverse:
        return const Color(0xFFF59E0B); // Amber / Orange
      case StepType.turnLeft:
        return const Color(0xFF3B82F6); // Cyan / Blue
      case StepType.turnRight:
        return const Color(0xFF8B5CF6); // Purple / Violet
      case StepType.wait:
        return const Color(0xFF06B6D4); // Light Teal
    }
  }

  /// Generates the Nordic UART Service (NUS) command matching ESP32 firmware protocol.
  String toBleCommand() {
    switch (type) {
      case StepType.forward:
        return 'SEQ,ADD,FWD,${value.toStringAsFixed(1)}';
      case StepType.reverse:
        return 'SEQ,ADD,REV,${value.toStringAsFixed(1)}';
      case StepType.turnLeft:
        return 'SEQ,ADD,LEFT,${value.toStringAsFixed(1)}';
      case StepType.turnRight:
        return 'SEQ,ADD,RIGHT,${value.toStringAsFixed(1)}';
      case StepType.wait:
        return 'SEQ,ADD,WAIT,${value.toInt()}';
    }
  }

  /// Copy with updated parameters.
  SequenceStep copyWith({
    String? id,
    StepType? type,
    double? value,
  }) {
    final nextType = type ?? this.type;
    final nextVal = value != null ? _clampValue(nextType, value) : this.value;
    return SequenceStep(
      id: id ?? this.id,
      type: nextType,
      value: nextVal,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SequenceStep &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          value == other.value;

  @override
  int get hashCode => id.hashCode ^ type.hashCode ^ value.hashCode;
}

/// Predefined movement sequence templates for quick testing.
class SequencePreset {
  final String name;
  final String description;
  final List<SequenceStep> steps;

  const SequencePreset({
    required this.name,
    required this.description,
    required this.steps,
  });

  /// Set of common test routines.
  static List<SequencePreset> get defaultPresets => [
    SequencePreset(
      name: 'Square Path (20 cm)',
      description: '4 x [Forward 20cm -> Right 90°]',
      steps: [
        SequenceStep.create(type: StepType.forward, value: 20),
        SequenceStep.create(type: StepType.turnRight, value: 90),
        SequenceStep.create(type: StepType.forward, value: 20),
        SequenceStep.create(type: StepType.turnRight, value: 90),
        SequenceStep.create(type: StepType.forward, value: 20),
        SequenceStep.create(type: StepType.turnRight, value: 90),
        SequenceStep.create(type: StepType.forward, value: 20),
        SequenceStep.create(type: StepType.turnRight, value: 90),
      ],
    ),
    SequencePreset(
      name: 'Slalom Agility Test',
      description: 'S-curve maneuvers with pauses',
      steps: [
        SequenceStep.create(type: StepType.forward, value: 15),
        SequenceStep.create(type: StepType.turnLeft, value: 45),
        SequenceStep.create(type: StepType.forward, value: 20),
        SequenceStep.create(type: StepType.turnRight, value: 90),
        SequenceStep.create(type: StepType.forward, value: 20),
        SequenceStep.create(type: StepType.turnLeft, value: 45),
        SequenceStep.create(type: StepType.forward, value: 15),
      ],
    ),
    SequencePreset(
      name: 'Out & Back (180° Turn)',
      description: 'Straight 30cm -> 180° Pivot -> Return',
      steps: [
        SequenceStep.create(type: StepType.forward, value: 30),
        SequenceStep.create(type: StepType.wait, value: 300),
        SequenceStep.create(type: StepType.turnRight, value: 180),
        SequenceStep.create(type: StepType.wait, value: 300),
        SequenceStep.create(type: StepType.forward, value: 30),
      ],
    ),
    SequencePreset(
      name: 'Calibration Pivot Test',
      description: 'Sequential 90° pivots to verify wheel calibration',
      steps: [
        SequenceStep.create(type: StepType.turnRight, value: 90),
        SequenceStep.create(type: StepType.wait, value: 500),
        SequenceStep.create(type: StepType.turnRight, value: 90),
        SequenceStep.create(type: StepType.wait, value: 500),
        SequenceStep.create(type: StepType.turnRight, value: 90),
        SequenceStep.create(type: StepType.wait, value: 500),
        SequenceStep.create(type: StepType.turnRight, value: 90),
      ],
    ),
  ];
}
