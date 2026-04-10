import 'dart:convert';

enum RunCaptureType { pathFinished, startStop }

/// Represents a single successful PID run with its configuration and result.
class PidRunHistory {
  final String id;
  final DateTime timestamp;
  final int runtimeMs;
  final RunCaptureType captureType;
  final double kp;
  final double ki;
  final double kd;
  final int maxSpeed;
  final int baseSpeed;

  PidRunHistory({
    required this.id,
    required this.timestamp,
    required this.runtimeMs,
    required this.captureType,
    required this.kp,
    required this.ki,
    required this.kd,
    required this.maxSpeed,
    required this.baseSpeed,
  });

  /// Create a new run history entry with auto-generated ID.
  factory PidRunHistory.create({
    required int runtimeMs,
    required RunCaptureType captureType,
    required double kp,
    required double ki,
    required double kd,
    required int maxSpeed,
    required int baseSpeed,
  }) {
    return PidRunHistory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      runtimeMs: runtimeMs,
      captureType: captureType,
      kp: kp,
      ki: ki,
      kd: kd,
      maxSpeed: maxSpeed,
      baseSpeed: baseSpeed,
    );
  }

  /// Format runtime as human-readable string (e.g., "12.34s").
  String get formattedRuntime {
    final seconds = runtimeMs / 1000;
    return '${seconds.toStringAsFixed(2)}s';
  }

  /// Format timestamp as human-readable string.
  String get formattedTimestamp {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  /// Short summary of PID values.
  String get pidSummary {
    return 'P=${kp.toStringAsFixed(1)} I=${ki.toStringAsFixed(1)} D=${kd.toStringAsFixed(1)}';
  }

  String get captureTypeLabel {
    return captureType == RunCaptureType.pathFinished
        ? 'Path Finished'
        : 'Start/Stop';
  }

  static RunCaptureType parseCaptureType(String? raw) {
    switch (raw) {
      case 'start_stop':
        return RunCaptureType.startStop;
      case 'path_finished':
      default:
        return RunCaptureType.pathFinished;
    }
  }

  static String encodeCaptureType(RunCaptureType value) {
    return value == RunCaptureType.pathFinished
        ? 'path_finished'
        : 'start_stop';
  }

  /// Convert to JSON map for storage.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'runtimeMs': runtimeMs,
      'captureType': encodeCaptureType(captureType),
      'kp': kp,
      'ki': ki,
      'kd': kd,
      'maxSpeed': maxSpeed,
      'baseSpeed': baseSpeed,
    };
  }

  /// Create from JSON map.
  factory PidRunHistory.fromJson(Map<String, dynamic> json) {
    return PidRunHistory(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      runtimeMs: json['runtimeMs'] as int,
      captureType: parseCaptureType(json['captureType'] as String?),
      kp: (json['kp'] as num).toDouble(),
      ki: (json['ki'] as num).toDouble(),
      kd: (json['kd'] as num).toDouble(),
      maxSpeed: json['maxSpeed'] as int,
      baseSpeed: json['baseSpeed'] as int,
    );
  }

  /// Encode a list of histories to JSON string.
  static String encodeList(List<PidRunHistory> histories) {
    return jsonEncode(histories.map((h) => h.toJson()).toList());
  }

  /// Decode a JSON string to list of histories.
  static List<PidRunHistory> decodeList(String jsonString) {
    if (jsonString.isEmpty) return [];
    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => PidRunHistory.fromJson(json)).toList();
  }

  @override
  String toString() {
    return 'PidRunHistory(id: $id, runtime: $formattedRuntime, type: $captureTypeLabel, $pidSummary)';
  }
}
