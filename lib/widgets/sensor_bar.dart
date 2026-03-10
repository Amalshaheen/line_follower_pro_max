import 'package:flutter/material.dart';

/// A reusable widget for sensor display showing on/off state.
class SensorBar extends StatelessWidget {
  final List<bool> sensorOnLine;

  const SensorBar({
    super.key,
    required this.sensorOnLine,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('🎨 [SENSOR_BAR] Building with ${sensorOnLine.length} sensors');
    if (sensorOnLine.isNotEmpty) {
      debugPrint('   └─ Values: ${sensorOnLine.map((s) => s ? 'ON(🟢)' : 'OFF(⚫)').join(' ')}');
    }
    
    if (sensorOnLine.isEmpty) {
      return Container(
        height: 18,
        color: Colors.grey[300],
        child: const Center(child: Text('No sensor data')),
      );
    }
    
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
}
