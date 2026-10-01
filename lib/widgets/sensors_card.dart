import 'package:flutter/material.dart';
import '../widgets/sensor_bar.dart';
import '../constants/app_constants.dart';

/// Card widget displaying sensor status with optional analog values.
class SensorsCard extends StatelessWidget {
  final List<bool> sensorOnLine;
  final List<int> sensorRawValues;
  final List<bool>? sensorEnabled;
  final bool showAnalog;
  final bool isCalibrationMode;
  final List<int> sensorThresholds;
  final double? lineError;
  final bool lineDetected;
  final ValueChanged<bool>? onShowAnalogChanged;
  final ValueChanged<bool>? onCalibrationModeChanged;
  final void Function(int index, int value)? onSensorThresholdPreview;
  final void Function(int index, int value)? onSensorThresholdCommit;
  final void Function(int value)? onAllSensorThresholdCommit;
  final void Function(int index, bool enabled)? onSensorEnableChanged;
  final void Function(bool enabled)? onAllSensorsEnableChanged;
  final VoidCallback? onSaveCalibration;

  const SensorsCard({
    super.key,
    required this.sensorOnLine,
    this.sensorRawValues = const [],
    this.sensorEnabled,
    this.showAnalog = false,
    this.isCalibrationMode = false,
    this.sensorThresholds = const [],
    this.lineError,
    this.lineDetected = true,
    this.onShowAnalogChanged,
    this.onCalibrationModeChanged,
    this.onSensorThresholdPreview,
    this.onSensorThresholdCommit,
    this.onAllSensorThresholdCommit,
    this.onSensorEnableChanged,
    this.onAllSensorsEnableChanged,
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
              sensorEnabled: sensorEnabled,
              showAnalog: showAnalog,
              lineError: lineError,
              lineDetected: lineDetected,
              onSensorTap: (index) {
                final isCurrentlyEnabled = sensorEnabled == null ||
                    index >= sensorEnabled!.length ||
                    sensorEnabled![index];
                onSensorEnableChanged?.call(index, !isCurrentlyEnabled);
              },
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
                        sensorEnabled: sensorEnabled,
                        onSensorThresholdPreview: onSensorThresholdPreview,
                        onSensorThresholdCommit: onSensorThresholdCommit,
                        onAllSensorThresholdCommit: onAllSensorThresholdCommit,
                        onSensorEnableChanged: onSensorEnableChanged,
                        onAllSensorsEnableChanged: onAllSensorsEnableChanged,
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
  final List<bool>? sensorEnabled;
  final void Function(int index, int value)? onSensorThresholdPreview;
  final void Function(int index, int value)? onSensorThresholdCommit;
  final void Function(int value)? onAllSensorThresholdCommit;
  final void Function(int index, bool enabled)? onSensorEnableChanged;
  final void Function(bool enabled)? onAllSensorsEnableChanged;
  final VoidCallback? onSaveCalibration;

  const _CalibrationPanel({
    required this.sensorRawValues,
    required this.sensorThresholds,
    this.sensorEnabled,
    this.onSensorThresholdPreview,
    this.onSensorThresholdCommit,
    this.onAllSensorThresholdCommit,
    this.onSensorEnableChanged,
    this.onAllSensorsEnableChanged,
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
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => widget.onAllSensorsEnableChanged?.call(true),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                label: const Text('All On'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => widget.onAllSensorsEnableChanged?.call(false),
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('All Off'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: widget.onSaveCalibration,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save Calibration'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 92,
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
                final isEnabled = widget.sensorEnabled == null ||
                    index >= widget.sensorEnabled!.length ||
                    widget.sensorEnabled![index];

                return _SensorThresholdEditor(
                  sensorIndex: index,
                  threshold: threshold,
                  rawValue: rawValue,
                  isEnabled: isEnabled,
                  onEnableChanged: (en) =>
                      widget.onSensorEnableChanged?.call(index, en),
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

class _SensorThresholdEditor extends StatefulWidget {
  final int sensorIndex;
  final int threshold;
  final int rawValue;
  final bool isEnabled;
  final ValueChanged<bool>? onEnableChanged;
  final void Function(int index, int value)? onPreview;
  final void Function(int index, int value)? onCommit;

  const _SensorThresholdEditor({
    required this.sensorIndex,
    required this.threshold,
    required this.rawValue,
    this.isEnabled = true,
    this.onEnableChanged,
    this.onPreview,
    this.onCommit,
  });

  @override
  State<_SensorThresholdEditor> createState() => _SensorThresholdEditorState();
}

class _SensorThresholdEditorState extends State<_SensorThresholdEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.threshold.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitCurrentValue();
    }
  }

  void _commitCurrentValue() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed != null && parsed != widget.threshold) {
      widget.onCommit?.call(widget.sensorIndex, parsed);
    }
  }

  @override
  void didUpdateWidget(covariant _SensorThresholdEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threshold != widget.threshold) {
      final currentParsed = int.tryParse(_controller.text.trim());
      if (currentParsed != widget.threshold && !_focusNode.hasFocus) {
        _controller.text = widget.threshold.toString();
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rawVal = widget.rawValue <= 255
        ? (widget.rawValue * 4095 ~/ 255).clamp(0, 4095)
        : widget.rawValue.clamp(0, 4095);
    final isOnLine = widget.isEnabled && (rawVal > widget.threshold);

    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: BoxDecoration(
        color: widget.isEnabled
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.isEnabled
              ? Theme.of(context).dividerColor
              : Theme.of(context).dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'S${widget.sensorIndex}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: widget.isEnabled ? null : Colors.grey,
                ),
              ),
              InkWell(
                onTap: () => widget.onEnableChanged?.call(!widget.isEnabled),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: Icon(
                    widget.isEnabled
                        ? Icons.power_settings_new_rounded
                        : Icons.power_off_rounded,
                    size: 15,
                    color: widget.isEnabled ? Colors.teal : Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            enabled: widget.isEnabled,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 5,
              ),
              fillColor: widget.isEnabled ? null : Colors.grey.shade100,
              filled: !widget.isEnabled,
            ),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: widget.isEnabled ? null : Colors.grey.shade500,
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value.trim());
              if (parsed != null) {
                widget.onPreview?.call(widget.sensorIndex, parsed);
              }
            },
            onSubmitted: (_) => _commitCurrentValue(),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 6,
              width: double.infinity,
              child: ColoredBox(
                color: !widget.isEnabled
                    ? Colors.grey.shade300
                    : (isOnLine ? Colors.teal : Colors.grey.shade300),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
