import 'package:flutter/material.dart';

import '../services/settings_service.dart';

class SettingsPage extends StatefulWidget {
  final AppSettings initialSettings;

  const SettingsPage({super.key, required this.initialSettings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _kpController;
  late final TextEditingController _kiController;
  late final TextEditingController _kdController;
  late final TextEditingController _maxSpeedController;
  late final TextEditingController _baseSpeedController;
  late final TextEditingController _thresholdController;

  @override
  void initState() {
    super.initState();
    _kpController = TextEditingController(
      text: widget.initialSettings.kp.toStringAsFixed(2),
    );
    _kiController = TextEditingController(
      text: widget.initialSettings.ki.toStringAsFixed(2),
    );
    _kdController = TextEditingController(
      text: widget.initialSettings.kd.toStringAsFixed(2),
    );
    _maxSpeedController = TextEditingController(
      text: widget.initialSettings.maxSpeed.toString(),
    );
    _baseSpeedController = TextEditingController(
      text: widget.initialSettings.baseSpeed.toString(),
    );
    _thresholdController = TextEditingController(
      text: widget.initialSettings.threshold.toString(),
    );
  }

  @override
  void dispose() {
    _kpController.dispose();
    _kiController.dispose();
    _kdController.dispose();
    _maxSpeedController.dispose();
    _baseSpeedController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  String? _validateDouble(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    if (double.tryParse(value.trim()) == null) {
      return 'Invalid number';
    }
    return null;
  }

  String? _validateInt(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    if (int.tryParse(value.trim()) == null) {
      return 'Invalid number';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final settings = AppSettings(
      kp: double.parse(_kpController.text.trim()),
      ki: double.parse(_kiController.text.trim()),
      kd: double.parse(_kdController.text.trim()),
      maxSpeed: int.parse(_maxSpeedController.text.trim()),
      baseSpeed: int.parse(_baseSpeedController.text.trim()),
      threshold: int.parse(_thresholdController.text.trim()),
    );

    await _settingsService.saveSettings(settings);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _resetToFactoryDefaults() async {
    await _settingsService.resetToFactoryDefaults();
    final defaults = AppSettings.defaults();

    setState(() {
      _kpController.text = defaults.kp.toStringAsFixed(2);
      _kiController.text = defaults.ki.toStringAsFixed(2);
      _kdController.text = defaults.kd.toStringAsFixed(2);
      _maxSpeedController.text = defaults.maxSpeed.toString();
      _baseSpeedController.text = defaults.baseSpeed.toString();
      _thresholdController.text = defaults.threshold.toString();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factory defaults restored')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Defaults Settings')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Default PID',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _kpController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Kp',
                  border: OutlineInputBorder(),
                ),
                validator: _validateDouble,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _kiController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Ki',
                  border: OutlineInputBorder(),
                ),
                validator: _validateDouble,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _kdController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Kd',
                  border: OutlineInputBorder(),
                ),
                validator: _validateDouble,
              ),
              const SizedBox(height: 18),
              Text(
                'Default Speed and Threshold',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _maxSpeedController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max speed',
                  border: OutlineInputBorder(),
                ),
                validator: _validateInt,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _baseSpeedController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Base speed',
                  border: OutlineInputBorder(),
                ),
                validator: _validateInt,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _thresholdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'All sensor threshold',
                  border: OutlineInputBorder(),
                ),
                validator: _validateInt,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save Defaults'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _resetToFactoryDefaults,
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Reset to Factory Defaults'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
