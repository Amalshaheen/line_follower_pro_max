import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Digit-wise editor for PID values with fixed 2 decimal places.
class PidDigitEditorRow extends StatefulWidget {
  final String title;
  final double value;
  final ValueChanged<double> onChanged;
  final Color? accentColor;

  const PidDigitEditorRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.accentColor,
  });

  @override
  State<PidDigitEditorRow> createState() => _PidDigitEditorRowState();
}

class _PidDigitEditorRowState extends State<PidDigitEditorRow> {
  late final TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(
      text: _clampAndRound(widget.value).toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant PidDigitEditorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _valueController.text = _clampAndRound(widget.value).toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  double _maxValue() {
    final intMax = math.pow(10, 3).toDouble() - 1;
    return intMax + 0.99;
  }

  double _clampAndRound(double candidate) {
    final clamped = candidate.clamp(0.0, _maxValue());
    return ((clamped * 100).round()) / 100;
  }

  void _applyStep(double step) {
    widget.onChanged(_clampAndRound(widget.value + step));
  }

  void _commitManualValue() {
    final parsed = double.tryParse(_valueController.text.trim());
    if (parsed == null) {
      _valueController.text = _clampAndRound(widget.value).toStringAsFixed(2);
      return;
    }
    widget.onChanged(_clampAndRound(parsed));
  }

  @override
  Widget build(BuildContext context) {
    final normalized = _clampAndRound(widget.value);
    final parts = normalized.toStringAsFixed(2).split('.');
    final intPart = parts[0].padLeft(3, '0');
    final decPart = parts[1];
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;

    final intSteps = List<double>.generate(
      3,
      (index) => math.pow(10, 3 - index - 1).toDouble(),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, color: accent),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 3,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    _DigitStepCell(
                      digit: intPart[i],
                      accentColor: accent,
                      onIncrement: () => _applyStep(intSteps[i]),
                      onDecrement: () => _applyStep(-intSteps[i]),
                    ),
                  const _DotCell(),
                  _DigitStepCell(
                    digit: decPart[0],
                    accentColor: accent,
                    onIncrement: () => _applyStep(0.1),
                    onDecrement: () => _applyStep(-0.1),
                  ),
                  _DigitStepCell(
                    digit: decPart[1],
                    accentColor: accent,
                    onIncrement: () => _applyStep(0.01),
                    onDecrement: () => _applyStep(-0.01),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 88,
              child: TextField(
                controller: _valueController,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                onSubmitted: (_) => _commitManualValue(),
                onEditingComplete: _commitManualValue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DigitStepCell extends StatelessWidget {
  final String digit;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final Color accentColor;

  const _DigitStepCell({
    required this.digit,
    required this.onIncrement,
    required this.onDecrement,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RepeatArrowButton(
            icon: Icons.keyboard_arrow_up,
            onPressed: onIncrement,
            semanticLabel: 'Increase digit',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              digit,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          _RepeatArrowButton(
            icon: Icons.keyboard_arrow_down,
            onPressed: onDecrement,
            semanticLabel: 'Decrease digit',
          ),
        ],
      ),
    );
  }
}

class _RepeatArrowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;

  const _RepeatArrowButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
  });

  @override
  State<_RepeatArrowButton> createState() => _RepeatArrowButtonState();
}

class _RepeatArrowButtonState extends State<_RepeatArrowButton> {
  Timer? _startDelayTimer;
  Timer? _repeatTimer;

  void _startRepeat() {
    _cancelRepeat();
    _startDelayTimer = Timer(const Duration(milliseconds: 300), () {
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 70), (_) {
        widget.onPressed();
      });
    });
  }

  void _cancelRepeat() {
    _startDelayTimer?.cancel();
    _repeatTimer?.cancel();
    _startDelayTimer = null;
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _cancelRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: (_) => _startRepeat(),
        onTapUp: (_) => _cancelRepeat(),
        onTapCancel: _cancelRepeat,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
          child: Icon(widget.icon, size: 40),
        ),
      ),
    );
  }
}

class _DotCell extends StatelessWidget {
  const _DotCell();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 10,
      child: Center(
        child: Text(
          '.',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
