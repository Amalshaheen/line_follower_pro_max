/// Application-wide constants for the Line Follower Control app.
class AppConstants {
  // Device names and identifiers
  static const String defaultDeviceName = 'ESP32_PID_Pro';

  // Default PID configuration values (matching hardware defaults)
  static const double defaultKp = 30.0;
  static const double defaultKi = 0.0;
  static const double defaultKd = 0.0;
  static const double defaultPScale = 10.0;
  static const double defaultIScale = 1.0;
  static const double defaultDScale = 1.0;

  // Default speed values
  static const int defaultMaxSpeed = 255;
  static const int defaultBaseSpeed = 150;

  // PID scale options
  static const List<double> pidScaleOptions = [10.0, 1.0, 0.1, 0.01];

  // Number of sensors
  static const int sensorCount = 12;

  // Message history limit
  static const int maxHistoryItems = 20;

  // Bluetooth commands (matching hardware protocol)
  static const String cmdRunStart = 'RUN=1';
  static const String cmdRunStop = 'RUN=0';
  static const String cmdKpPrefix = 'KP=';
  static const String cmdKiPrefix = 'KI=';
  static const String cmdKdPrefix = 'KD=';
  static const String cmdMaxSpeedPrefix = 'MAX=';
  static const String cmdBaseSpeedPrefix = 'BASE=';
  static const String cmdCalibrateBlack = 'CAL=BLACK';
  static const String cmdCalibrateWhite = 'CAL=WHITE';
  static const String cmdQueryTime = 'TIME?';

  // Response prefixes from hardware
  static const String respSensors = 'SENSORS:';
  static const String respAck = 'ACK:';
  static const String respTrackFinished = 'TRACK_FINISHED';
  static const String respTimePrefix = 'TIME=';

  // UI strings
  static const String appTitle = 'Line Follower Control';
  static const String bluetoothSettingsTitle = 'Bluetooth Settings';
  static const String sensorsLabel = 'Sensors';
  static const String pidLabel = 'PID';
  static const String speedLabel = 'Speed';
  static const String pidHistoryLabel = 'PID history';

  // Button labels
  static const String startButtonLabel = 'Start';
  static const String stopButtonLabel = 'Stop';
  static const String connectButtonLabel = 'Connect';
  static const String disconnectButtonLabel = 'Disconnect';
  static const String refreshButtonLabel = 'Refresh';
  static const String sendButtonLabel = 'Send';

  // Error messages
  static const String failedToLoadDevicesError = 'Failed to load paired devices';
  static const String connectionFailedError = 'Connection failed';
  static const String disconnectedStatusMessage = 'Disconnected';
  static const String connectedStatusMessagePrefix = 'Connected to ';
  static const String connectingStatusMessagePrefix = 'Connecting to ';

  // Speed labels
  static const String maxSpeedLabel = 'Max speed';
  static const String baseSpeedLabel = 'Base speed';

  // Calibration labels
  static const String calibrateBlackLabel = 'Calibrate Black';
  static const String calibrateWhiteLabel = 'Calibrate White';
}
