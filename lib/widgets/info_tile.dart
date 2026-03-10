import 'package:flutter/material.dart';

/// A reusable widget for displaying information tiles.
class InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const InfoTile({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? Colors.green.shade50 : Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(10),
        border: highlight ? Border.all(color: Colors.green.shade300, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: highlight ? Colors.green.shade700 : null,
            ),
          ),
        ],
      ),
    );
  }
}
