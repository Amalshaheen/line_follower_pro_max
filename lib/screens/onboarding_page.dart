import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/settings_service.dart';
import 'dashboard_page.dart';

/// Onboarding wizard screen to introduce the app and configure initial default values.
class OnboardingPage extends StatefulWidget {
  /// When [isEditing] is true, the user is modifying defaults from the Settings screen.
  final bool isEditing;

  const OnboardingPage({super.key, this.isEditing = false});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  final SettingsService _settingsService = SettingsService();
  final _formKey = GlobalKey<FormState>();

  int _currentPage = 0;
  static const int _pageCount = 4;

  // Controllers for default values
  late final TextEditingController _deviceNameController;
  late final TextEditingController _kpController;
  late final TextEditingController _kiController;
  late final TextEditingController _kdController;
  late final TextEditingController _maxSpeedController;
  late final TextEditingController _baseSpeedController;
  late final TextEditingController _minSpeedController;
  late final TextEditingController _thresholdController;
  late bool _invertSteering;

  @override
  void initState() {
    super.initState();
    _deviceNameController = TextEditingController(
      text: AppConstants.defaultDeviceName,
    );
    _kpController = TextEditingController(
      text: AppConstants.defaultKp.toStringAsFixed(2),
    );
    _kiController = TextEditingController(
      text: AppConstants.defaultKi.toStringAsFixed(2),
    );
    _kdController = TextEditingController(
      text: AppConstants.defaultKd.toStringAsFixed(2),
    );
    _maxSpeedController = TextEditingController(
      text: AppConstants.defaultMaxSpeed.toString(),
    );
    _baseSpeedController = TextEditingController(
      text: AppConstants.defaultBaseSpeed.toString(),
    );
    _minSpeedController = TextEditingController(
      text: AppConstants.defaultMinSpeed.toString(),
    );
    _invertSteering = AppConstants.defaultInvertSteering;
    _thresholdController = TextEditingController(
      text: AppConstants.defaultThreshold.toString(),
    );

    _loadExistingDefaultsIfAvailable();
  }

  Future<void> _loadExistingDefaultsIfAvailable() async {
    final settings = await _settingsService.getSettings();
    if (!mounted) return;
    setState(() {
      _deviceNameController.text = settings.deviceName;
      _kpController.text = settings.kp.toStringAsFixed(2);
      _kiController.text = settings.ki.toStringAsFixed(2);
      _kdController.text = settings.kd.toStringAsFixed(2);
      _maxSpeedController.text = settings.maxSpeed.toString();
      _baseSpeedController.text = settings.baseSpeed.toString();
      _minSpeedController.text = settings.minSpeed.toString();
      _invertSteering = settings.invertSteering;
      _thresholdController.text = settings.threshold.toString();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _deviceNameController.dispose();
    _kpController.dispose();
    _kiController.dispose();
    _kdController.dispose();
    _maxSpeedController.dispose();
    _baseSpeedController.dispose();
    _minSpeedController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pageCount - 1) {
      if (_currentPage > 0 && !_formKey.currentState!.validate()) {
        return;
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishSetup();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finishSetup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final settings = AppSettings(
      kp: double.tryParse(_kpController.text.trim()) ?? AppConstants.defaultKp,
      ki: double.tryParse(_kiController.text.trim()) ?? AppConstants.defaultKi,
      kd: double.tryParse(_kdController.text.trim()) ?? AppConstants.defaultKd,
      maxSpeed: int.tryParse(_maxSpeedController.text.trim()) ??
          AppConstants.defaultMaxSpeed,
      baseSpeed: int.tryParse(_baseSpeedController.text.trim()) ??
          AppConstants.defaultBaseSpeed,
      minSpeed: int.tryParse(_minSpeedController.text.trim()) ??
          AppConstants.defaultMinSpeed,
      invertSteering: _invertSteering,
      threshold: int.tryParse(_thresholdController.text.trim()) ??
          AppConstants.defaultThreshold,
      deviceName: _deviceNameController.text.trim().isEmpty
          ? AppConstants.defaultDeviceName
          : _deviceNameController.text.trim(),
    );

    await _settingsService.saveSettings(settings);
    await _settingsService.setOnboardingComplete(true);

    if (!mounted) return;

    if (widget.isEditing) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const DashboardPage()),
      );
    }
  }

  Future<void> _skipWithDefaults() async {
    final defaults = AppSettings.defaults();
    await _settingsService.saveSettings(defaults);
    await _settingsService.setOnboardingComplete(true);

    if (!mounted) return;

    if (widget.isEditing) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const DashboardPage()),
      );
    }
  }

  String? _validateDouble(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    if (double.tryParse(value.trim()) == null) return 'Enter a valid number';
    return null;
  }

  String? _validateInt(String? value, {int min = 0, int max = 4095}) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Enter a whole number';
    if (parsed < min || parsed > max) return 'Must be between $min and $max';
    return null;
  }

  void _applyPidPreset(double kp, double ki, double kd) {
    setState(() {
      _kpController.text = kp.toStringAsFixed(2);
      _kiController.text = ki.toStringAsFixed(2);
      _kdController.text = kd.toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Setup Wizard' : 'Welcome Setup'),
        leading: widget.isEditing
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: [
          if (!widget.isEditing && _currentPage == 0)
            TextButton(
              onPressed: _skipWithDefaults,
              child: const Text('Skip with Defaults'),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Progress Bar
              LinearProgressIndicator(
                value: (_currentPage + 1) / _pageCount,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  children: [
                    _buildWelcomeStep(context),
                    _buildDeviceNameStep(context),
                    _buildPidStep(context),
                    _buildSpeedAndThresholdStep(context),
                  ],
                ),
              ),
              _buildBottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1: Welcome & Highlights
  // ---------------------------------------------------------------------------

  Widget _buildWelcomeStep(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.precision_manufacturing_rounded,
              size: 48,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'LineRobo Companion ',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: 'Pro',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFD4AF37),
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Let’s set up your robot defaults so you’re ready to tune, calibrate, and race right away.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        _buildHighlightCard(
          icon: Icons.bluetooth_searching,
          title: 'High-Speed BLE Telemetry',
          description:
              'Real-time binary telemetry packets for 12 analog IR sensors and error line tracking.',
        ),
        const SizedBox(height: 12),
        _buildHighlightCard(
          icon: Icons.tune_rounded,
          title: 'Instant Wireless PID Tuning',
          description:
              'Adjust Kp, Ki, and Kd on the fly with responsive sliders, buttons, and telemetry history.',
        ),
        const SizedBox(height: 12),
        _buildHighlightCard(
          icon: Icons.timer_outlined,
          title: 'Lap Timing & Sensor Masking',
          description:
              'Auto-stop on finish markers, individual sensor toggles, and lap time benchmarks.',
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildHighlightCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2: Robot Identity (BLE Device Name)
  // ---------------------------------------------------------------------------

  Widget _buildDeviceNameStep(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        _buildStepHeader(
          icon: Icons.bluetooth_searching,
          stepNumber: '1',
          title: 'Robot BLE Identity',
          subtitle:
              'Set your robot’s advertised Bluetooth Low Energy name or prefix. The app uses this to highlight and quickly connect to your robot.',
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _deviceNameController,
          decoration: const InputDecoration(
            labelText: 'Robot BLE Name',
            hintText: 'e.g. LFR_V5_Tuner',
            prefixIcon: Icon(Icons.smart_toy_outlined),
            border: OutlineInputBorder(),
            helperText: 'Case-insensitive prefix used during BLE scanning',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter a device name';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        Text(
          'Quick Presets:',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPresetChip('LFR_V5_Tuner', () {
              setState(() => _deviceNameController.text = 'LFR_V5_Tuner');
            }),
            _buildPresetChip('LineRobo', () {
              setState(() => _deviceNameController.text = 'LineRobo');
            }),
            _buildPresetChip('ESP32_LFR', () {
              setState(() => _deviceNameController.text = 'ESP32_LFR');
            }),
            _buildPresetChip('CustomBot', () {
              setState(() => _deviceNameController.text = 'CustomBot');
            }),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 3: PID Control Defaults
  // ---------------------------------------------------------------------------

  Widget _buildPidStep(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        _buildStepHeader(
          icon: Icons.tune_rounded,
          stepNumber: '2',
          title: 'Default PID Parameters',
          subtitle:
              'These values will be loaded whenever the app starts or when resetting tuning sliders to defaults.',
        ),
        const SizedBox(height: 16),
        Text(
          'Choose a Starting Tuning Preset:',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.balance, size: 16),
              label: const Text('Balanced (Default)'),
              onPressed: () => _applyPidPreset(2.5, 0.0, 0.08),
            ),
            ActionChip(
              avatar: const Icon(Icons.flash_on, size: 16),
              label: const Text('Aggressive / High Kp'),
              onPressed: () => _applyPidPreset(3.5, 0.02, 0.12),
            ),
            ActionChip(
              avatar: const Icon(Icons.waves, size: 16),
              label: const Text('Smooth / Safe'),
              onPressed: () => _applyPidPreset(1.8, 0.0, 0.05),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _kpController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Default Kp',
                  border: OutlineInputBorder(),
                  helperText: 'Proportional',
                ),
                validator: _validateDouble,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _kiController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Default Ki',
                  border: OutlineInputBorder(),
                  helperText: 'Integral',
                ),
                validator: _validateDouble,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _kdController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Default Kd',
                  border: OutlineInputBorder(),
                  helperText: 'Derivative',
                ),
                validator: _validateDouble,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 4: Speed and Sensor Threshold
  // ---------------------------------------------------------------------------

  Widget _buildSpeedAndThresholdStep(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        _buildStepHeader(
          icon: Icons.speed_rounded,
          stepNumber: '3',
          title: 'Speed & Threshold Defaults',
          subtitle:
              'Configure baseline motor PWM speeds (0–255) and the analog optical cutoff threshold for line detection (0–4095).',
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _maxSpeedController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Default Max Speed (PWM)',
            helperText: 'Maximum motor output PWM (0–255)',
            prefixIcon: Icon(Icons.rocket_launch_outlined),
            border: OutlineInputBorder(),
          ),
          validator: (v) => _validateInt(v, min: 0, max: 255),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _baseSpeedController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Default Base Speed (PWM)',
            helperText: 'Nominal cruise speed on straight track (0–255)',
            prefixIcon: Icon(Icons.play_arrow_outlined),
            border: OutlineInputBorder(),
          ),
          validator: (v) => _validateInt(v, min: 0, max: 255),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _minSpeedController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Default Min Speed / Deadband (PWM)',
            helperText: 'Stiction compensation for BTS7960 (0–255, default: 30)',
            prefixIcon: Icon(Icons.speed_outlined),
            border: OutlineInputBorder(),
          ),
          validator: (v) => _validateInt(v, min: 0, max: 255),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Invert Steering Polarity'),
          subtitle: Text(
            _invertSteering
                ? 'Inverted (Reversed motor/sensor polarity)'
                : 'Normal steering polarity',
          ),
          value: _invertSteering,
          onChanged: (val) => setState(() => _invertSteering = val),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _thresholdController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Default Sensor Threshold',
            helperText: 'Analog reading cutoff (0–4095, typically ~2000)',
            prefixIcon: Icon(Icons.sensors_outlined),
            border: OutlineInputBorder(),
          ),
          validator: (v) => _validateInt(v, min: 0, max: 4095),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared Components
  // ---------------------------------------------------------------------------

  Widget _buildStepHeader({
    required IconData icon,
    required String stepNumber,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Step $stepNumber of 3',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(icon, size: 28, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final isLastPage = _currentPage == _pageCount - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          if (_currentPage > 0)
            OutlinedButton(
              onPressed: _previousPage,
              child: const Text('Back'),
            )
          else
            const SizedBox(width: 72),
          const Spacer(),
          // Dots indicator
          Row(
            children: List.generate(
              _pageCount,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == index ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: _currentPage == index
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _nextPage,
            icon: Icon(
              isLastPage ? Icons.check_circle_outline : Icons.arrow_forward,
              size: 18,
            ),
            label: Text(
              isLastPage
                  ? (widget.isEditing ? 'Save' : 'Finish')
                  : (_currentPage == 0 ? 'Get Started' : 'Next'),
            ),
          ),
        ],
      ),
    );
  }
}
