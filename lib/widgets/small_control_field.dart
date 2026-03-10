import 'package:flutter/material.dart';

/// A reusable widget for small control fields with a send button.
class SmallControlField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onSend;

  const SmallControlField({
    super.key,
    required this.label,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton(onPressed: onSend, child: const Text('Send')),
      ],
    );
  }
}
