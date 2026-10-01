import 'package:flutter/material.dart';

/// A modern, interactive 12-channel sensor visualizer displaying real-time
/// 8-bit normalized analog reflectance (0–255) and line tracking error.
class SensorBar extends StatelessWidget {
  final List<bool> sensorOnLine;
  final List<int> sensorRawValues;
  final List<bool>? sensorEnabled;
  final bool showAnalog;
  final double? lineError; // Line error (-5.5 to +5.5)
  final bool lineDetected;
  final void Function(int index)? onSensorTap;

  const SensorBar({
    super.key,
    required this.sensorOnLine,
    this.sensorRawValues = const [],
    this.sensorEnabled,
    this.showAnalog = true,
    this.lineError,
    this.lineDetected = true,
    this.onSensorTap,
  });

  @override
  Widget build(BuildContext context) {
    if (sensorOnLine.isEmpty && sensorRawValues.isEmpty) {
      return Container(
        height: showAnalog ? 90 : 28,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Center(
          child: Text(
            'Waiting for sensor stream …',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      );
    }

    final count = sensorOnLine.isNotEmpty
        ? sensorOnLine.length
        : sensorRawValues.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showAnalog)
          _buildAnalogVisualizer(context, count)
        else
          _buildBinaryVisualizer(context, count),

        // Line Position & Error Indicator Bar
        if (lineError != null) ...[
          const SizedBox(height: 6),
          _buildErrorIndicator(context),
        ],
      ],
    );
  }

  Widget _buildBinaryVisualizer(BuildContext context, int count) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: List.generate(count, (index) {
          final isEnabled = sensorEnabled == null ||
              index >= sensorEnabled!.length ||
              sensorEnabled![index];
          final isOn = isEnabled &&
              (index < sensorOnLine.length ? sensorOnLine[index] : false);
          return Expanded(
            child: Tooltip(
              message: isEnabled
                  ? 'Sensor ${index + 1}: ${isOn ? "LINE" : "Off-line"}'
                  : 'Sensor ${index + 1}: OFF (Disabled)',
              child: GestureDetector(
                onTap: () => onSensorTap?.call(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: !isEnabled
                        ? Colors.grey.shade300.withValues(alpha: 0.6)
                        : (isOn ? Colors.teal.shade500 : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(3),
                    border: isOn
                        ? null
                        : Border.all(
                            color: !isEnabled
                                ? Colors.grey.shade400
                                : Colors.grey.shade300,
                            width: 0.5,
                          ),
                    boxShadow: isOn
                        ? [
                            BoxShadow(
                              color: Colors.teal.withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            )
                          ]
                        : null,
                  ),
                  child: !isEnabled
                      ? Center(
                          child: Icon(
                            Icons.power_settings_new_rounded,
                            size: 11,
                            color: Colors.grey.shade500,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildAnalogVisualizer(BuildContext context, int count) {
    // Detect if values are 8-bit (max <= 255) to scale up to 12-bit (0-4095)
    final maxValInSet = sensorRawValues.fold<int>(
      0,
      (max, val) => val > max ? val : max,
    );
    const maxScale = 4095.0;

    return Container(
      height: 108,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(count, (index) {
          final isEnabled = sensorEnabled == null ||
              index >= sensorEnabled!.length ||
              sensorEnabled![index];
          final rawValue =
              index < sensorRawValues.length ? sensorRawValues[index] : 0;
          final isOn = isEnabled &&
              (index < sensorOnLine.length ? sensorOnLine[index] : false);

          // Scale up to 0–4095 range
          final displayValue = (rawValue <= 255 && maxValInSet <= 255)
              ? (rawValue * 4095 ~/ 255).clamp(0, 4095)
              : rawValue.clamp(0, 4095);

          final fillFraction = isEnabled
              ? (displayValue / maxScale).clamp(0.04, 1.0)
              : 0.0;

          return Expanded(
            child: Tooltip(
              message: isEnabled
                  ? 'Sensor ${index + 1}: $displayValue / 4095\n'
                      'State: ${isOn ? "LINE (Active)" : "Off-line"}'
                  : 'Sensor ${index + 1}: OFF (Disabled - Tap to toggle)',
              child: InkWell(
                onTap: () => onSensorTap?.call(index),
                borderRadius: BorderRadius.circular(4),
                child: Opacity(
                  opacity: isEnabled ? 1.0 : 0.45,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Sensor reading readout (0-4095) or OFF
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isEnabled ? '$displayValue' : 'OFF',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: !isEnabled
                                  ? Colors.red.shade400
                                  : (isOn
                                      ? Colors.teal.shade800
                                      : Colors.grey.shade700),
                            ),
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(height: 3),

                      // Vertical analog level bar with background track
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: Colors.grey.shade200,
                              width: 0.5,
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: fillFraction,
                              widthFactor: 1.0,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 60),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2.5),
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: isOn
                                        ? [
                                            Colors.teal.shade700,
                                            Colors.teal.shade400,
                                          ]
                                        : [
                                            Colors.grey.shade400,
                                            Colors.grey.shade300,
                                          ],
                                  ),
                                  boxShadow: isOn
                                      ? [
                                          BoxShadow(
                                            color: Colors.teal.withValues(alpha: 0.35),
                                            blurRadius: 3,
                                            spreadRadius: 0.5,
                                          )
                                        ]
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),

                      // Sensor index label
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ));
        }),
      ),
    );
  }

  Widget _buildErrorIndicator(BuildContext context) {
    final err = lineError ?? 0.0;
    // Map error from -5.5 .. +5.5 to 0.0 .. 1.0 (0.5 is centered)
    final clampedNorm = ((err + 5.5) / 11.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Line: ${lineDetected ? "DETECTED" : "LOST"}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: lineDetected ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
              Text(
                'Error: ${err.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: err.abs() < 0.5 ? Colors.teal.shade700 : Colors.deepOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final indicatorX = (width - 12) * clampedNorm;

              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Center reference line
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // Center tick mark
                  Positioned(
                    left: (width / 2) - 1,
                    child: Container(
                      width: 2,
                      height: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  // Moving position pointer
                  Positioned(
                    left: indicatorX,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: lineDetected ? Colors.teal : Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
