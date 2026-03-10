import 'package:flutter/material.dart';
import 'pid_slider_row.dart';
import '../constants/app_constants.dart';

/// Card widget for PID controller configuration.
class PidCard extends StatelessWidget {
  final double pValue;
  final double iValue;
  final double dValue;
  final double pScale;
  final double iScale;
  final double dScale;
  final TextEditingController pController;
  final TextEditingController iController;
  final TextEditingController dController;
  final ValueChanged<double> onPChanged;
  final ValueChanged<double> onIChanged;
  final ValueChanged<double> onDChanged;
  final ValueChanged<double> onPChangeEnd;
  final ValueChanged<double> onIChangeEnd;
  final ValueChanged<double> onDChangeEnd;
  final ValueChanged<String> onPSubmitted;
  final ValueChanged<String> onISubmitted;
  final ValueChanged<String> onDSubmitted;
  final ValueChanged<double> onPScaleChanged;
  final ValueChanged<double> onIScaleChanged;
  final ValueChanged<double> onDScaleChanged;

  const PidCard({
    super.key,
    required this.pValue,
    required this.iValue,
    required this.dValue,
    required this.pScale,
    required this.iScale,
    required this.dScale,
    required this.pController,
    required this.iController,
    required this.dController,
    required this.onPChanged,
    required this.onIChanged,
    required this.onDChanged,
    required this.onPChangeEnd,
    required this.onIChangeEnd,
    required this.onDChangeEnd,
    required this.onPSubmitted,
    required this.onISubmitted,
    required this.onDSubmitted,
    required this.onPScaleChanged,
    required this.onIScaleChanged,
    required this.onDScaleChanged,
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
              AppConstants.pidLabel,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            PidSliderRow(
              title: 'P',
              value: pValue,
              scale: pScale,
              controller: pController,
              onChanged: onPChanged,
              onSubmitted: onPSubmitted,
              onScaleChanged: onPScaleChanged,
              onChangeEnd: onPChangeEnd,
            ),
            PidSliderRow(
              title: 'I',
              value: iValue,
              scale: iScale,
              controller: iController,
              onChanged: onIChanged,
              onSubmitted: onISubmitted,
              onScaleChanged: onIScaleChanged,
              onChangeEnd: onIChangeEnd,
            ),
            PidSliderRow(
              title: 'D',
              value: dValue,
              scale: dScale,
              controller: dController,
              onChanged: onDChanged,
              onSubmitted: onDSubmitted,
              onScaleChanged: onDScaleChanged,
              onChangeEnd: onDChangeEnd,
            ),
          ],
        ),
      ),
    );
  }
}
