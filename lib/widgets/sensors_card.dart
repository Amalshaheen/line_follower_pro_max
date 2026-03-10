import 'package:flutter/material.dart';
import '../widgets/sensor_bar.dart';
import '../constants/app_constants.dart';

/// Card widget displaying sensor status.
class SensorsCard extends StatelessWidget {
  final List<bool> sensorOnLine;

  const SensorsCard({
    super.key,
    required this.sensorOnLine,
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
              AppConstants.sensorsLabel,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            SensorBar(sensorOnLine: sensorOnLine),
          ],
        ),
      ),
    );
  }
}
