import 'package:flutter/material.dart';
import 'info_tile.dart';
import '../constants/app_constants.dart';

/// Card widget for control summary showing start/stop and runtime info.
class ControlSummaryCard extends StatelessWidget {
  final bool isRunning;
  final bool trackFinished;
  final int runtime; // Runtime in milliseconds
  final VoidCallback onStartStop;

  const ControlSummaryCard({
    super.key,
    required this.isRunning,
    this.trackFinished = false,
    this.runtime = 0,
    required this.onStartStop,
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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Main controls row
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: isRunning ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: onStartStop,
                      icon: Icon(
                        isRunning
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        isRunning
                            ? AppConstants.stopButtonLabel
                            : AppConstants.startButtonLabel,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        InfoTile(
                          label: 'Lap time',
                          value: _formatRuntime(runtime),
                          highlight: trackFinished,
                        ),
                        if (trackFinished)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Track Finished!',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
