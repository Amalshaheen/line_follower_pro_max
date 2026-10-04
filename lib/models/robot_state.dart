import 'dart:typed_data';

/// Represents a 15-byte compact binary telemetry packet from the robot over BLE.
///
/// Layout:
/// - Bytes 0–11: 12 individual 8-bit analog IR values (0–255).
/// - Bytes 12–13: Signed 16-bit integer representing `errorMm * 100` (little-endian).
///                In normal operation: -52.52 mm to +52.52 mm.
///                When line lost: 99.90 mm (9990).
/// - Byte 14: Status flags (Bit 0 = motors running, Bit 1 = line lost).
class TelemetryData {
  final List<int> sensors; // 12 values: 0-255
  final double error; // Line error in mm (-52.52 to +52.52 mm, or 99.90 when lost)
  final bool motorsRunning;
  final bool lineDetected;
  final int rawFlags;
  final DateTime timestamp;

  /// Semantic accessor for error in millimeters
  double get errorMm => error;

  const TelemetryData({
    required this.sensors,
    required this.error,
    required this.motorsRunning,
    required this.lineDetected,
    this.rawFlags = 0,
    required this.timestamp,
  });

  /// Parse a 15-byte raw binary packet from the TX characteristic.
  static TelemetryData? fromBinary(List<int> bytes) {
    if (bytes.length < 15) return null;
    final sensors = bytes.sublist(0, 12);
    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
    final errorX100 = byteData.getInt16(12, Endian.little);
    final flags = bytes[14];
    final motorsRunning = (flags & (1 << 0)) != 0;
    final lineLost = (flags & (1 << 1)) != 0 || errorX100 >= 9900;
    final lineDetected = !lineLost;

    return TelemetryData(
      sensors: List<int>.unmodifiable(sensors),
      error: errorX100 / 100.0,
      motorsRunning: motorsRunning,
      lineDetected: lineDetected,
      rawFlags: flags,
      timestamp: DateTime.now(),
    );
  }
}

/// Represents the runtime state of the line follower robot.
class RobotState {
  final bool isRunning;
  final bool trackFinished;
  final int runtime; // Runtime in milliseconds
  final List<int> sensorRawValues; // Raw analog values from sensors (0-255 or 0-4095)
  final List<bool> sensorOnLine; // Processed boolean values
  final double lineError; // Current line tracking error in millimeters (-52.52 to +52.52 mm)
  final bool lineDetected;
  final String latestMessage;
  final TelemetryData? latestTelemetry;

  const RobotState({
    this.isRunning = false,
    this.trackFinished = false,
    this.runtime = 0,
    this.sensorRawValues = const [],
    this.sensorOnLine = const [],
    this.lineError = 0.0,
    this.lineDetected = true,
    this.latestMessage = '--',
    this.latestTelemetry,
  });

  /// Format runtime as mm:ss.ms
  String get formattedRuntime {
    if (runtime == 0) return '--:--';
    final minutes = (runtime ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((runtime ~/ 1000) % 60).toString().padLeft(2, '0');
    final milliseconds = ((runtime % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds.$milliseconds';
  }

  /// Create a copy of this state with optional modifications.
  RobotState copyWith({
    bool? isRunning,
    bool? trackFinished,
    int? runtime,
    List<int>? sensorRawValues,
    List<bool>? sensorOnLine,
    double? lineError,
    bool? lineDetected,
    String? latestMessage,
    TelemetryData? latestTelemetry,
  }) {
    return RobotState(
      isRunning: isRunning ?? this.isRunning,
      trackFinished: trackFinished ?? this.trackFinished,
      runtime: runtime ?? this.runtime,
      sensorRawValues: sensorRawValues ?? this.sensorRawValues,
      sensorOnLine: sensorOnLine ?? this.sensorOnLine,
      lineError: lineError ?? this.lineError,
      lineDetected: lineDetected ?? this.lineDetected,
      latestMessage: latestMessage ?? this.latestMessage,
      latestTelemetry: latestTelemetry ?? this.latestTelemetry,
    );
  }
}

/// Represents the connection status of the Bluetooth device.
enum BluetoothConnectionStatus {
  disconnected,
  connecting,
  connected,
  connectionFailed,
}

/// Represents the Bluetooth connection state.
class BluetoothState {
  final BluetoothConnectionStatus status;
  final String statusMessage;
  final String? selectedDeviceAddress;
  final String? selectedDeviceName;

  const BluetoothState({
    this.status = BluetoothConnectionStatus.disconnected,
    this.statusMessage = 'Disconnected',
    this.selectedDeviceAddress,
    this.selectedDeviceName,
  });

  bool get isConnected => status == BluetoothConnectionStatus.connected;
  bool get isConnecting => status == BluetoothConnectionStatus.connecting;

  /// Create a copy of this state with optional modifications.
  BluetoothState copyWith({
    BluetoothConnectionStatus? status,
    String? statusMessage,
    String? selectedDeviceAddress,
    String? selectedDeviceName,
  }) {
    return BluetoothState(
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      selectedDeviceAddress: selectedDeviceAddress ?? this.selectedDeviceAddress,
      selectedDeviceName: selectedDeviceName ?? this.selectedDeviceName,
    );
  }
}
