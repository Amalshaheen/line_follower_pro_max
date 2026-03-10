import 'package:flutter/material.dart';

/// A reusable widget for speed control fields.
class SpeedFieldRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onSend;

  const SpeedFieldRow({
    super.key,
    required this.label,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text('$label:')),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: onSend, child: const Text('Send')),
      ],
    );
  }
}
