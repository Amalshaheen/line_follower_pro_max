import 'package:flutter/material.dart';
import 'constants/app_constants.dart';
import 'screens/index.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settingsService = SettingsService();
  final onboardingComplete = await settingsService.isOnboardingComplete();
  runApp(MainApp(onboardingComplete: onboardingComplete));
}

/// Main application widget.
class MainApp extends StatelessWidget {
  final bool onboardingComplete;

  const MainApp({super.key, this.onboardingComplete = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6FB),
      ),
      home: onboardingComplete ? const DashboardPage() : const OnboardingPage(),
    );
  }
}
