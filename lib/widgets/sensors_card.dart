import 'package:flutter/material.dart';
import '../widgets/sensor_bar.dart';
import '../constants/app_constants.dart';

/// Card widget displaying sensor status with optional analog values.
class SensorsCard extends StatelessWidget {
  final List<bool> sensorOnLine;
  final List<int> sensorRawValues;
  final bool showAnalog;
  final ValueChanged<bool>? onShowAnalogChanged;

  const SensorsCard({
    super.key,
    required this.sensorOnLine,
    this.sensorRawValues = const [],
    this.showAnalog = false,
    this.onShowAnalogChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppConstants.sensorsLabel,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Analog',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Switch(
                      value: showAnalog,
                      onChanged: onShowAnalogChanged,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            SensorBar(
              sensorOnLine: sensorOnLine,
              sensorRawValues: sensorRawValues,
              showAnalog: showAnalog,
            ),
          ],
        ),
      ),
    );
  }
}
