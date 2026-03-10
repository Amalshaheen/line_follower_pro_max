/// Represents the runtime state of the line follower robot.
class RobotState {
  final bool isRunning;
  final bool trackFinished;
  final int runtime; // Runtime in milliseconds
  final List<int> sensorRawValues; // Raw analog values from sensors (0-4095)
  final List<bool> sensorOnLine; // Processed boolean values
  final String latestMessage;

  const RobotState({
    this.isRunning = false,
    this.trackFinished = false,
    this.runtime = 0,
    this.sensorRawValues = const [],
    this.sensorOnLine = const [],
    this.latestMessage = '--',
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
    String? latestMessage,
  }) {
    return RobotState(
      isRunning: isRunning ?? this.isRunning,
      trackFinished: trackFinished ?? this.trackFinished,
      runtime: runtime ?? this.runtime,
      sensorRawValues: sensorRawValues ?? this.sensorRawValues,
      sensorOnLine: sensorOnLine ?? this.sensorOnLine,
      latestMessage: latestMessage ?? this.latestMessage,
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
