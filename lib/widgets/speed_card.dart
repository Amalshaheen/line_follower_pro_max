import 'package:flutter/material.dart';
import 'speed_field_row.dart';
import '../constants/app_constants.dart';

/// Card widget for speed control settings.
class SpeedCard extends StatelessWidget {
  final TextEditingController maxSpeedController;
  final TextEditingController baseSpeedController;
  final TextEditingController? thresholdAllController;
  final String? thresholdInfoText;
  final VoidCallback onMaxSpeedSend;
  final VoidCallback onBaseSpeedSend;
  final VoidCallback? onThresholdAllSend;
  final VoidCallback? onResetDefaults;

  const SpeedCard({
    super.key,
    required this.maxSpeedController,
    required this.baseSpeedController,
    this.thresholdAllController,
    this.thresholdInfoText,
    required this.onMaxSpeedSend,
    required this.onBaseSpeedSend,
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
                  label: Text(
                    thresholdAllController != null
                        ? 'Reset Speed/Threshold'
                        : 'Reset Speed',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
