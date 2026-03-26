import 'package:flutter/material.dart';
import '../widgets/sensor_bar.dart';
import '../constants/app_constants.dart';

/// Card widget displaying sensor status with optional analog values.
class SensorsCard extends StatelessWidget {
  final List<bool> sensorOnLine;
  final List<int> sensorRawValues;
  final bool showAnalog;
  final bool isCalibrationMode;
  final List<int> sensorThresholds;
  final ValueChanged<bool>? onShowAnalogChanged;
  final ValueChanged<bool>? onCalibrationModeChanged;
  final void Function(int index, int value)? onSensorThresholdPreview;
  final void Function(int index, int value)? onSensorThresholdCommit;
  final VoidCallback? onSaveCalibration;

  const SensorsCard({
    super.key,
    required this.sensorOnLine,
    this.sensorRawValues = const [],
    this.showAnalog = false,
    this.isCalibrationMode = false,
    this.sensorThresholds = const [],
    this.onShowAnalogChanged,
    this.onCalibrationModeChanged,
    this.onSensorThresholdPreview,
    this.onSensorThresholdCommit,
    this.onSaveCalibration,
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onCalibrationModeChanged == null
                          ? null
                          : () => onCalibrationModeChanged!.call(
                              !isCalibrationMode,
                            ),
                      icon: Icon(
                        isCalibrationMode
                            ? Icons.check_circle_outline_rounded
                            : Icons.tune_rounded,
                        size: 18,
                      ),
                      label: Text(isCalibrationMode ? 'Done' : 'Calibration'),
                    ),
                    const SizedBox(width: 8),
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
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: isCalibrationMode
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _CalibrationPanel(
                        sensorRawValues: sensorRawValues,
                        sensorThresholds: sensorThresholds,
                        onSensorThresholdPreview: onSensorThresholdPreview,
                        onSensorThresholdCommit: onSensorThresholdCommit,
                        onSaveCalibration: onSaveCalibration,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalibrationPanel extends StatelessWidget {
  final List<int> sensorRawValues;
  final List<int> sensorThresholds;
  final void Function(int index, int value)? onSensorThresholdPreview;
  final void Function(int index, int value)? onSensorThresholdCommit;
  final VoidCallback? onSaveCalibration;

  const _CalibrationPanel({
    required this.sensorRawValues,
    required this.sensorThresholds,
    this.onSensorThresholdPreview,
    this.onSensorThresholdCommit,
    this.onSaveCalibration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calibration mode: drag each slider up/down, release to send to hardware',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onSaveCalibration,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Calibration'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 230,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: AppConstants.sensorCount,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final threshold = index < sensorThresholds.length
                    ? sensorThresholds[index]
                    : AppConstants.defaultThreshold;
                final rawValue = index < sensorRawValues.length
                    ? sensorRawValues[index]
                    : 0;

                return _SensorThresholdSlider(
                  sensorIndex: index,
                  threshold: threshold,
                  rawValue: rawValue,
                  onPreview: onSensorThresholdPreview,
                  onCommit: onSensorThresholdCommit,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorThresholdSlider extends StatelessWidget {
  final int sensorIndex;
  final int threshold;
  final int rawValue;
  final void Function(int index, int value)? onPreview;
  final void Function(int index, int value)? onCommit;

  const _SensorThresholdSlider({
    required this.sensorIndex,
    required this.threshold,
    required this.rawValue,
    this.onPreview,
    this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    final isOnLine = rawValue > threshold;

    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Text('S$sensorIndex', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 6),
                child: Slider(
                  min: 0,
                  max: 4095,
                  divisions: 4095,
                  value: threshold.clamp(0, 4095).toDouble(),
                  onChanged: (value) {
                    onPreview?.call(sensorIndex, value.round());
                  },
                  onChangeEnd: (value) {
                    onCommit?.call(sensorIndex, value.round());
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('T:$threshold', style: Theme.of(context).textTheme.labelSmall),
          Text('R:$rawValue', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Icon(
            isOnLine ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: isOnLine ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }
}
