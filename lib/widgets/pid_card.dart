import 'package:flutter/material.dart';
import 'pid_digit_editor_row.dart';
import '../constants/app_constants.dart';

/// Card widget for PID controller configuration.
class PidCard extends StatelessWidget {
  final double pValue;
  final double iValue;
  final double dValue;
  final ValueChanged<double> onPChanged;
  final ValueChanged<double> onIChanged;
  final ValueChanged<double> onDChanged;
  final VoidCallback onSendAll;
  final VoidCallback onResetDefaults;

  const PidCard({
    super.key,
    required this.pValue,
    required this.iValue,
    required this.dValue,
    required this.onPChanged,
    required this.onIChanged,
    required this.onDChanged,
    required this.onSendAll,
    required this.onResetDefaults,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppConstants.pidLabel,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap arrows for small steps, hold for fast changes, or type on the right.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            PidDigitEditorRow(
              title: 'P',
              value: pValue,
              onChanged: onPChanged,
              accentColor: colorScheme.primary,
            ),
            PidDigitEditorRow(
              title: 'I',
              value: iValue,
              onChanged: onIChanged,
              accentColor: colorScheme.tertiary,
            ),
            PidDigitEditorRow(
              title: 'D',
              value: dValue,
              onChanged: onDChanged,
              accentColor: colorScheme.secondary,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onResetDefaults,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reset PID'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onSendAll,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Send PID'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
