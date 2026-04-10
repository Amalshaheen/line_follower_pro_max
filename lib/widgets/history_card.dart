import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/pid_run_history.dart';

/// Card widget displaying PID run history with restore functionality.
class HistoryCard extends StatelessWidget {
  final List<PidRunHistory> history;
  final RunCaptureType? selectedFilter;
  final ValueChanged<RunCaptureType?>? onFilterChanged;
  final void Function(PidRunHistory)? onRestoreConfig;
  final void Function(String)? onDeleteRun;
  final VoidCallback? onClearAll;

  const HistoryCard({
    super.key,
    required this.history,
    this.selectedFilter,
    this.onFilterChanged,
    this.onRestoreConfig,
    this.onDeleteRun,
    this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppConstants.pidHistoryLabel,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (history.isNotEmpty && onClearAll != null)
                  TextButton.icon(
                    onPressed: () => _confirmClearAll(context),
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: DropdownButton<RunCaptureType?>(
                value: selectedFilter,
                hint: const Text('Filter runs'),
                items: const [
                  DropdownMenuItem<RunCaptureType?>(
                    value: null,
                    child: Text('All runtimes'),
                  ),
                  DropdownMenuItem<RunCaptureType?>(
                    value: RunCaptureType.pathFinished,
                    child: Text('Path Finished runtime'),
                  ),
                  DropdownMenuItem<RunCaptureType?>(
                    value: RunCaptureType.startStop,
                    child: Text('Start/Stop runtime'),
                  ),
                ],
                onChanged: onFilterChanged,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No completed runs yet',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Successful runs will appear here',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: history.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final run = history[index];
                        return Dismissible(
                          key: Key(run.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            color: Colors.red,
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => onDeleteRun?.call(run.id),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            dense: true,
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  run.formattedRuntime,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                ),
                              ),
                            ),
                            title: Text(
                              run.pidSummary,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              '${run.captureTypeLabel} • Speed: ${run.baseSpeed}/${run.maxSpeed} • ${run.formattedTimestamp}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.restore, size: 20),
                              tooltip: 'Restore this configuration',
                              onPressed: () => _confirmRestore(context, run),
                            ),
                            onTap: () => _confirmRestore(context, run),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRestore(BuildContext context, PidRunHistory run) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Apply this configuration?'),
            const SizedBox(height: 12),
            _buildConfigDetail(context, 'Kp', run.kp.toStringAsFixed(2)),
            _buildConfigDetail(context, 'Ki', run.ki.toStringAsFixed(2)),
            _buildConfigDetail(context, 'Kd', run.kd.toStringAsFixed(2)),
            _buildConfigDetail(context, 'Base Speed', run.baseSpeed.toString()),
            _buildConfigDetail(context, 'Max Speed', run.maxSpeed.toString()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onRestoreConfig?.call(run);
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigDetail(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Are you sure you want to delete all run history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () {
              Navigator.pop(context);
              onClearAll?.call();
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
