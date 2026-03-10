import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// A reusable widget for PID slider row with scale selector and text input.
class PidSliderRow extends StatelessWidget {
  final String title;
  final double value;
  final double scale;
  final TextEditingController controller;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<double> onScaleChanged;

  const PidSliderRow({
    super.key,
    required this.title,
    required this.value,
    required this.scale,
    required this.controller,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onSubmitted,
    required this.onScaleChanged,
  });

  void _changeScale(int direction) {
    final currentIndex = AppConstants.pidScaleOptions.indexOf(scale);
    final newIndex = (currentIndex + direction).clamp(0, AppConstants.pidScaleOptions.length - 1);
    if (newIndex != currentIndex) {
      onScaleChanged(AppConstants.pidScaleOptions[newIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 20, child: Text(title)),
          Expanded(
            child: Slider(
              value: value,
              min: 0,
              max: 1,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => _changeScale(1),
                  child: const Icon(Icons.remove, size: 14),
                ),
                const SizedBox(width: 4),
                Text(
                  scale == scale.toInt() ? '${scale.toInt()}x' : '${scale}x',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _changeScale(-1),
                  child: const Icon(Icons.add, size: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 76,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              onSubmitted: onSubmitted,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
