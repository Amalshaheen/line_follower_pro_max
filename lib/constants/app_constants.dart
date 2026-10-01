/// Application-wide constants for the Line Follower Control app.
class AppConstants {
  // ---------------------------------------------------------------------------
  // Device defaults
  // ---------------------------------------------------------------------------

  /// Default device name shown in settings (BLE).
  /// Users can change this to match their robot's advertised name.
  static const String defaultDeviceName = 'LFR_V5_Tuner';

  // ---------------------------------------------------------------------------
  // BLE — Nordic UART Service (NUS) UUIDs
  // ---------------------------------------------------------------------------

  /// NUS Service UUID
  static const String bleServiceUuid =
      '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';

  /// NUS RX characteristic UUID (app → bot WRITE)
  static const String bleRxCharUuid =
      '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

  /// NUS TX characteristic UUID (bot → app NOTIFY)
  static const String bleTxCharUuid =
      '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

  // ---------------------------------------------------------------------------
  // Default PID configuration values (matching hardware defaults)
  // ---------------------------------------------------------------------------
  static const double defaultKp = 30.0;
  static const double defaultKi = 0.0;
  static const double defaultKd = 0.0;
  static const double defaultPScale = 10.0;
  static const double defaultIScale = 1.0;
  static const double defaultDScale = 1.0;

  // Default speed values
  static const int defaultMaxSpeed = 255;
  static const int defaultBaseSpeed = 150;
  static const int defaultThreshold = 2000;

  // PID scale options
  static const List<double> pidScaleOptions = [10.0, 1.0, 0.1, 0.01];

  // Number of sensors
  static const int sensorCount = 12;

  // Message history limit
  static const int maxHistoryItems = 20;

  // ---------------------------------------------------------------------------
  // Hardware protocol commands (app → bot)
  // Communication over BLE Nordic UART Service.
  // ---------------------------------------------------------------------------
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
  static const String cmdQueryThresholds = 'THRESH?';
  static const String cmdThresholdAllPrefix = 'THRALL=';
  static const String cmdThresholdSinglePrefix = 'THR=';
  static const String cmdAutoStopPrefix = 'AUTOSTOP=';
  static const String cmdLineLostRecoveryPrefix = 'LINELOST=';
  static const String cmdSensorSinglePrefix = 'SENS=';
  static const String cmdSensorMaskPrefix = 'MASK=';
  static const String cmdQuerySensorMask = 'MASK?';

  // ---------------------------------------------------------------------------
  // Response prefixes from hardware (bot → app)
  // Communication over BLE Nordic UART Service.
  // ---------------------------------------------------------------------------
  static const String respSensors = 'SENSORS:';
  static const String respAck = 'ACK:';
  static const String respTrackFinished = 'TRACK_FINISHED';
  static const String respTimePrefix = 'TIME=';
  static const String respThresholds = 'THRESHOLDS:';
  static const String respSensorMask = 'MASK:';

  // ---------------------------------------------------------------------------
  // UI strings
  // ---------------------------------------------------------------------------
  static const String appTitle = 'LineRobo Companion Pro';
  static const String bluetoothSettingsTitle = 'Connection Settings';
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
  static const String scanButtonLabel = 'Scan';

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
  static const String thresholdAllLabel = 'All sensor threshold';
}
