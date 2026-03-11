import 'package:flutter/material.dart';

/// A reusable widget for sensor display showing on/off state or analog values.
class SensorBar extends StatelessWidget {
  final List<bool> sensorOnLine;
  final List<int> sensorRawValues;
  final bool showAnalog;

  const SensorBar({
    super.key,
    required this.sensorOnLine,
    this.sensorRawValues = const [],
    this.showAnalog = false,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('🎨 [SENSOR_BAR] Building with ${sensorOnLine.length} sensors');
    if (sensorOnLine.isNotEmpty) {
      debugPrint('   └─ Values: ${sensorOnLine.map((s) => s ? 'ON(🟢)' : 'OFF(⚫)').join(' ')}');
    }
    
    if (sensorOnLine.isEmpty) {
      return Container(
        height: showAnalog ? 60 : 18,
        color: Colors.grey[300],
        child: const Center(child: Text('No sensor data')),
      );
    }

    if (showAnalog) {
      return _buildAnalogView(context);
    }
    return _buildBinaryView(context);
  }

  Widget _buildBinaryView(BuildContext context) {
    return Container(
      height: 24,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: List.generate(
          sensorOnLine.length,
          (index) {
            final isOn = sensorOnLine[index];
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(
                  right: index == sensorOnLine.length - 1 ? 0 : 1,
                  top: 2,
                  bottom: 2,
                  left: index == 0 ? 2 : 1,
                ),
                decoration: BoxDecoration(
                  color: isOn ? Colors.black87 : Colors.white,
                  border: Border.all(
                    color: isOn ? Colors.black45 : Colors.grey[300] ?? Colors.grey,
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAnalogView(BuildContext context) {
    // Find max value for scaling (use 1023 as typical ADC max, or actual max)
    const maxValue = 1023;
    
    return Container(
      height: 80,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          sensorOnLine.length,
          (index) {
            final rawValue = index < sensorRawValues.length 
                ? sensorRawValues[index] 
                : 0;
            final normalizedHeight = (rawValue / maxValue).clamp(0.0, 1.0);
            final isOn = sensorOnLine[index];
            
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? 0 : 1,
                  right: index == sensorOnLine.length - 1 ? 0 : 1,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      rawValue.toString(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: normalizedHeight.clamp(0.05, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isOn 
                                  ? Colors.green.shade600 
                                  : Colors.grey.shade400,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
