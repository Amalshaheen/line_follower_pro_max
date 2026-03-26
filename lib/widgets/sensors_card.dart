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
  final void Function(int value)? onAllSensorThresholdCommit;
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
    this.onAllSensorThresholdCommit,
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
                        onAllSensorThresholdCommit: onAllSensorThresholdCommit,
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

class _CalibrationPanel extends StatefulWidget {
  final List<int> sensorRawValues;
  final List<int> sensorThresholds;
  final void Function(int index, int value)? onSensorThresholdPreview;
  final void Function(int index, int value)? onSensorThresholdCommit;
  final void Function(int value)? onAllSensorThresholdCommit;
  final VoidCallback? onSaveCalibration;

  const _CalibrationPanel({
    required this.sensorRawValues,
    required this.sensorThresholds,
    this.onSensorThresholdPreview,
    this.onSensorThresholdCommit,
    this.onAllSensorThresholdCommit,
    this.onSaveCalibration,
  });

  @override
  State<_CalibrationPanel> createState() => _CalibrationPanelState();
}

class _CalibrationPanelState extends State<_CalibrationPanel> {
  late final TextEditingController _allThresholdController;

  @override
  void initState() {
    super.initState();
    _allThresholdController = TextEditingController(
      text: widget.sensorThresholds.isNotEmpty
          ? widget.sensorThresholds.first.toString()
          : AppConstants.defaultThreshold.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _CalibrationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sensorThresholds != widget.sensorThresholds &&
        widget.sensorThresholds.isNotEmpty) {
      _allThresholdController.text = widget.sensorThresholds.first.toString();
    }
  }

  @override
  void dispose() {
    _allThresholdController.dispose();
    super.dispose();
  }

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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _allThresholdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'All thresholds',
                  ),
                  onSubmitted: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed != null) {
                      widget.onAllSensorThresholdCommit?.call(parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final parsed = int.tryParse(
                    _allThresholdController.text.trim(),
                  );
                  if (parsed != null) {
                    widget.onAllSensorThresholdCommit?.call(parsed);
                  }
                },
                child: const Text('Set All'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: widget.onSaveCalibration,
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
                final threshold = index < widget.sensorThresholds.length
                    ? widget.sensorThresholds[index]
                    : AppConstants.defaultThreshold;
                final rawValue = index < widget.sensorRawValues.length
                    ? widget.sensorRawValues[index]
                    : 0;

                return _SensorThresholdSlider(
                  sensorIndex: index,
                  threshold: threshold,
                  rawValue: rawValue,
                  onPreview: widget.onSensorThresholdPreview,
                  onCommit: widget.onSensorThresholdCommit,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorThresholdSlider extends StatefulWidget {
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
  State<_SensorThresholdSlider> createState() => _SensorThresholdSliderState();
}

class _SensorThresholdSliderState extends State<_SensorThresholdSlider> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.threshold.toString());
  }

  @override
  void didUpdateWidget(covariant _SensorThresholdSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threshold != widget.threshold) {
      _controller.text = widget.threshold.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOnLine = widget.rawValue > widget.threshold;

    return Container(
      width: 64,
      padding: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Column(
          children: [
            Text(
              'S${widget.sensorIndex}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(trackHeight: 10),
                  child: Slider(
                    min: 0,
                    max: 4100,
                    divisions: 41,
                    value: widget.threshold.clamp(0, 4095).toDouble(),
                    onChanged: (value) {
                      widget.onPreview?.call(widget.sensorIndex, value.round());
                    },
                    onChangeEnd: (value) {
                      widget.onCommit?.call(widget.sensorIndex, value.round());
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: TextField(
                controller: _controller,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                ),
                style: Theme.of(context).textTheme.labelSmall,
                onSubmitted: (value) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed != null) {
                    widget.onCommit?.call(widget.sensorIndex, parsed);
                  }
                },
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 12,
              width: double.infinity,
              child: ColoredBox(color: isOnLine ? Colors.black : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
