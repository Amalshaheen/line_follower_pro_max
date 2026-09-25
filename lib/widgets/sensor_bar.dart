import 'package:flutter/material.dart';

/// A modern, interactive 12-channel sensor visualizer displaying real-time
/// 8-bit normalized analog reflectance (0–255) and line tracking error.
class SensorBar extends StatelessWidget {
  final List<bool> sensorOnLine;
  final List<int> sensorRawValues;
  final bool showAnalog;
  final double? lineError; // Line error (-5.5 to +5.5)
  final bool lineDetected;
  final void Function(int index)? onSensorTap;

  const SensorBar({
    super.key,
    required this.sensorOnLine,
    this.sensorRawValues = const [],
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
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black26),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: List.generate(count, (index) {
          final isOn = index < sensorOnLine.length ? sensorOnLine[index] : false;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSensorTap?.call(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: isOn ? Colors.tealAccent.shade400 : Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: isOn
                      ? [
                          BoxShadow(
                            color: Colors.tealAccent.withValues(alpha: 0.4),
                            blurRadius: 4,
                            spreadRadius: 1,
                          )
                        ]
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
    // Detect if values are 8-bit (max <= 255) or legacy 12-bit (max > 255)
    final maxValInSet = sensorRawValues.fold<int>(
      0,
      (max, val) => val > max ? val : max,
    );
    final maxScale = maxValInSet > 255 ? 4095.0 : 255.0;

    return Container(
      height: 105,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade800),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(count, (index) {
          final rawValue =
              index < sensorRawValues.length ? sensorRawValues[index] : 0;
          final isOn =
              index < sensorOnLine.length ? sensorOnLine[index] : false;
          final fillFraction = (rawValue / maxScale).clamp(0.04, 1.0);

          return Expanded(
            child: Tooltip(
              message: 'Sensor ${index + 1}: $rawValue / ${maxScale.toInt()}\n'
                  'State: ${isOn ? "LINE (Active)" : "Off-line"}',
              child: InkWell(
                onTap: () => onSensorTap?.call(index),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Sensor reading readout
                      Text(
                        '$rawValue',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isOn
                              ? Colors.tealAccent.shade400
                              : Colors.grey.shade400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),

                      // Vertical analog level bar
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: fillFraction,
                            widthFactor: 0.9,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 60),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: isOn
                                      ? [
                                          Colors.teal.shade700,
                                          Colors.tealAccent.shade400,
                                        ]
                                      : [
                                          Colors.blueGrey.shade800,
                                          Colors.blueGrey.shade600,
                                        ],
                                ),
                                boxShadow: isOn
                                    ? [
                                        BoxShadow(
                                          color: Colors.tealAccent.withValues(alpha: 0.35),
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
                      const SizedBox(height: 3),

                      // Sensor index label
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
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
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
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
