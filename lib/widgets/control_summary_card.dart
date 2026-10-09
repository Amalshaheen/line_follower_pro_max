import 'package:flutter/material.dart';
import 'info_tile.dart';
import '../constants/app_constants.dart';

/// Primary Action Card for robot control: Start/Emergency Stop toggle, run duration timer,
/// and Calibrate Sensors trigger.
class ControlSummaryCard extends StatelessWidget {
  final bool isRunning;
  final bool trackFinished;
  final int runtime; // Runtime in milliseconds
  final VoidCallback onStartStop;
  final VoidCallback? onCalibrate;
  final bool isConnected;

  const ControlSummaryCard({
    super.key,
    required this.isRunning,
    this.trackFinished = false,
    this.runtime = 0,
    required this.onStartStop,
    this.onCalibrate,
    this.isConnected = true,
  });

  /// Format runtime as mm:ss.ms
  String _formatRuntime(int runtimeMs) {
    if (runtimeMs == 0) return '--:--';
    final minutes = (runtimeMs ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((runtimeMs ~/ 1000) % 60).toString().padLeft(2, '0');
    final milliseconds = ((runtimeMs % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds.$milliseconds';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Main Start/Stop and Runtime Row
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: isRunning ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: onStartStop,
                      icon: Icon(
                        isRunning
                            ? Icons.stop_circle_rounded
                            : Icons.play_arrow_rounded,
                        size: 26,
                      ),
                      label: Text(
                        isRunning
                            ? 'EMERGENCY STOP'
                            : AppConstants.startButtonLabel,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: InfoTile(
                      label: 'Run time',
                      value: _formatRuntime(runtime),
                      highlight: isRunning,
                    ),
                  ),
                ],
              ),
            ),
            if (onCalibrate != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                    ),
                  ),
                  onPressed: isConnected ? onCalibrate : null,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
                  label: const Text(
                    'Calibrate Sensors (Baseline)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
