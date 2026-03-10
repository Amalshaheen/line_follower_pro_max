# Project Structure

This refactored project follows a modular architecture for better maintainability and scalability.

## Directory Structure

```
lib/
├── main.dart                    # Application entry point (clean and minimal)
├── constants/
│   └── app_constants.dart       # All app-wide constants and configuration
├── models/
│   ├── pid_config.dart          # PID controller configuration model
│   ├── robot_state.dart         # Robot and Bluetooth state models
│   └── index.dart               # Model exports
├── services/
│   ├── bluetooth_service.dart   # Bluetooth communication logic
│   └── index.dart               # Service exports
├── screens/
│   ├── dashboard_page.dart      # Main control dashboard
│   ├── bluetooth_settings_page.dart # Bluetooth device management
│   └── index.dart               # Screen exports
├── widgets/
│   ├── info_tile.dart           # Info display widget
│   ├── sensor_bar.dart          # Sensor visualization widget
│   ├── small_control_field.dart # Small input field with send button
│   ├── speed_field_row.dart     # Speed control field
│   ├── pid_slider_row.dart      # PID slider with scale selector
│   ├── sensors_card.dart        # Sensors card widget
│   ├── control_summary_card.dart # Control status card
│   ├── pid_card.dart            # PID configuration card
│   ├── speed_card.dart          # Speed control card
│   ├── history_card.dart        # Message history card
│   └── index.dart               # Widget exports
└── utils/                       # (Placeholder for utilities)
```

## Key Improvements

### 1. **Separation of Concerns**
   - **Models**: Data structures and state management
   - **Services**: Business logic (Bluetooth communication)
   - **Screens**: UI screens and pages
   - **Widgets**: Reusable UI components
   - **Constants**: Centralized configuration and strings

### 2. **Modularity**
   - Each file has a single responsibility
   - Easy to locate and modify specific features
   - Simplified testing and debugging

### 3. **Reusability**
   - Extracted widgets can be used across multiple screens
   - Constants avoid magic strings and numbers
   - State models can be extended for future needs

### 4. **Maintainability**
   - Reduced main.dart from 990 lines to ~30 lines
   - Clear file organization makes navigation intuitive
   - Easy to onboard new team members

### 5. **Scalability**
   - Ready for state management (Provider, Riverpod, etc.)
   - Easy to add more screens and features
   - Service-based architecture for dependency injection

## Next Steps for Enhancement

1. **State Management**: Integrate Provider or Riverpod for better state management
2. **Bluetooth Integration**: Complete the integration of BluetoothService in DashboardPage
3. **Error Handling**: Add comprehensive error handling and user feedback
4. **Testing**: Add unit tests for services and widgets
5. **Localization**: Add multi-language support if needed

## How to Use

### Import Models
```dart
import 'models/index.dart';
// Then use: PidConfig, RobotState, BluetoothState
```

### Import Services
```dart
import 'services/index.dart';
// Then use: BluetoothService
```

### Import Widgets
```dart
import 'widgets/index.dart';
// Then use: SensorsCard, PidCard, SpeedCard, etc.
```

### Import Constants
```dart
import 'constants/app_constants.dart';
// Then use: AppConstants.defaultPValue, AppConstants.appTitle, etc.
```
