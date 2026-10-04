import 'package:flutter/material.dart';
import 'speed_field_row.dart';
import '../constants/app_constants.dart';

/// Card widget for speed and motor polarity settings.
class SpeedCard extends StatelessWidget {
  final TextEditingController maxSpeedController;
  final TextEditingController baseSpeedController;
  final TextEditingController? minSpeedController;
  final TextEditingController? thresholdAllController;
  final String? thresholdInfoText;
  final bool? invertSteering;
  final ValueChanged<bool>? onInvertSteeringChanged;
  final VoidCallback onMaxSpeedSend;
  final VoidCallback onBaseSpeedSend;
  final VoidCallback? onMinSpeedSend;
  final VoidCallback? onThresholdAllSend;
  final VoidCallback? onResetDefaults;

  const SpeedCard({
    super.key,
    required this.maxSpeedController,
    required this.baseSpeedController,
    this.minSpeedController,
    this.thresholdAllController,
    this.thresholdInfoText,
    this.invertSteering,
    this.onInvertSteeringChanged,
    required this.onMaxSpeedSend,
    required this.onBaseSpeedSend,
    this.onMinSpeedSend,
    this.onThresholdAllSend,
    this.onResetDefaults,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppConstants.speedLabel,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SpeedFieldRow(
              label: AppConstants.maxSpeedLabel,
              controller: maxSpeedController,
              onSend: onMaxSpeedSend,
            ),
            const SizedBox(height: 8),
            SpeedFieldRow(
              label: AppConstants.baseSpeedLabel,
              controller: baseSpeedController,
              onSend: onBaseSpeedSend,
            ),
            if (minSpeedController != null && onMinSpeedSend != null) ...[
              const SizedBox(height: 8),
              SpeedFieldRow(
                label: AppConstants.minSpeedLabel,
                controller: minSpeedController!,
                onSend: onMinSpeedSend!,
              ),
              const SizedBox(height: 2),
              Text(
                'Deadband compensation to overcome BTS7960 motor stiction (0-255 PWM).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
            if (invertSteering != null && onInvertSteeringChanged != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppConstants.invertSteeringLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Text(
                            invertSteering! ? 'Inverted (Reverse steering)' : 'Normal polarity',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: invertSteering!,
                      onChanged: onInvertSteeringChanged,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ),
            ],
            if (thresholdAllController != null &&
                onThresholdAllSend != null) ...[
              const SizedBox(height: 8),
              SpeedFieldRow(
                label: AppConstants.thresholdAllLabel,
                controller: thresholdAllController!,
                onSend: onThresholdAllSend!,
              ),
              if (thresholdInfoText != null) ...[
                const SizedBox(height: 4),
                Text(
                  thresholdInfoText!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
            if (onResetDefaults != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onResetDefaults,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reset Speed Defaults'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
