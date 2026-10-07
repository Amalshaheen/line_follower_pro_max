import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../models/sequence_step.dart';
import '../services/robot_service.dart';

/// Interactive visual motion queue builder and executor for autonomous robot sequences.
class SequenceEditorScreen extends StatefulWidget {
  final RobotService? robotService;
  final bool isConnected;

  const SequenceEditorScreen({
    super.key,
    required this.robotService,
    this.isConnected = false,
  });

  @override
  State<SequenceEditorScreen> createState() => _SequenceEditorScreenState();
}

class _SequenceEditorScreenState extends State<SequenceEditorScreen> {
  List<SequenceStep> _steps = [];
  bool _isUploading = false;
  bool _isExecuting = false;
  int? _activeStepIndex;
  StreamSubscription<void>? _sequenceDoneSub;
  Timer? _stepSimulationTimer;

  @override
  void initState() {
    super.initState();
    // Default starter sequence: Square test routine
    _steps = List.from(SequencePreset.defaultPresets.first.steps);
    _setupSubscriptions();
  }

  @override
  void didUpdateWidget(covariant SequenceEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.robotService != widget.robotService) {
      _sequenceDoneSub?.cancel();
      _setupSubscriptions();
    }
    if (!widget.isConnected && (_isExecuting || _isUploading)) {
      _resetExecutionState();
    }
  }

  void _setupSubscriptions() {
    _sequenceDoneSub = widget.robotService?.onSequenceDone.listen((_) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _resetExecutionState();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
          content: Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'Autonomous Sequence Completed! (SEQ:DONE)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _resetExecutionState() {
    _stepSimulationTimer?.cancel();
    if (mounted) {
      setState(() {
        _isUploading = false;
        _isExecuting = false;
        _activeStepIndex = null;
      });
    }
  }

  @override
  void dispose() {
    _sequenceDoneSub?.cancel();
    _stepSimulationTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Action Handlers
  // ---------------------------------------------------------------------------

  void _addStep(StepType type, double defaultValue) {
    HapticFeedback.lightImpact();
    setState(() {
      _steps.add(SequenceStep.create(type: type, value: defaultValue));
    });
  }

  void _deleteStep(int index) {
    HapticFeedback.mediumImpact();
    setState(() {
      _steps.removeAt(index);
    });
  }

  void _updateStepValue(int index, double delta) {
    HapticFeedback.selectionClick();
    setState(() {
      final current = _steps[index];
      _steps[index] = current.copyWith(value: current.value + delta);
    });
  }

  void _setStepExactValue(int index, double exactVal) {
    HapticFeedback.lightImpact();
    setState(() {
      _steps[index] = _steps[index].copyWith(value: exactVal);
    });
  }

  void _reorderSteps(int oldIndex, int newIndex) {
    HapticFeedback.lightImpact();
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final step = _steps.removeAt(oldIndex);
      _steps.insert(newIndex, step);
    });
  }

  void _clearAllSteps() {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text(
          'Clear Motion Queue?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to remove all steps from the sequence?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _steps.clear());
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _loadPreset(SequencePreset preset) {
    HapticFeedback.mediumImpact();
    setState(() {
      _steps = List.from(preset.steps);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1500),
        backgroundColor: const Color(0xFF282E3E),
        content: Text('Loaded preset: ${preset.name}'),
      ),
    );
  }

  Future<void> _runSequence() async {
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one motion step.')),
      );
      return;
    }

    if (!widget.isConnected || widget.robotService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Robot disconnected! Connect BLE first to run sequence.'),
        ),
      );
      return;
    }

    HapticFeedback.heavyImpact();

    setState(() {
      _isUploading = true;
      _isExecuting = true;
      _activeStepIndex = 0;
    });

    try {
      await widget.robotService!.sendSequence(_steps);
      if (!mounted) return;
      setState(() {
        _isUploading = false;
      });

      // Local progress tracker for step progression visual indicator
      _stepSimulationTimer?.cancel();
      _startStepTrackingTimer();
    } catch (e) {
      if (!mounted) return;
      _resetExecutionState();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to transmit sequence: $e')),
      );
    }
  }

  void _startStepTrackingTimer() {
    int current = 0;
    _stepSimulationTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (!_isExecuting || !mounted) {
        timer.cancel();
        return;
      }
      if (current < _steps.length - 1) {
        current++;
        setState(() {
          _activeStepIndex = current;
        });
      }
    });
  }

  void _emergencyStop() {
    HapticFeedback.heavyImpact();
    widget.robotService?.stopSequence();
    widget.robotService?.sendCommand(AppConstants.cmdRunStop);
    _resetExecutionState();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'EMERGENCY STOP SENT - SEQUENCE ABORTED',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build Methods
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF13161F) : const Color(0xFFF4F6FB),
      body: SafeArea(
        child: Column(
          children: [
            // Status & Quick Presets Header
            _buildHeaderBar(),

            // Disconnection Warning Banner if offline
            if (!widget.isConnected) _buildOfflineBanner(),

            // Sequence Step List Timeline
            Expanded(
              child: _steps.isEmpty
                  ? _buildEmptyState()
                  : _buildReorderableStepList(),
            ),

            // Bottom Command & Control Dock
            _buildBottomControlDock(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1E222D),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2E3446), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.account_tree_rounded,
              color: Color(0xFF10B981),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Motion Sequence Queue',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF374151),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_steps.length} / 32 steps',
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  _isExecuting
                      ? (_isUploading ? 'Uploading to ESP32...' : 'Executing sequence on robot...')
                      : 'Closed-loop Hall encoder odometry',
                  style: TextStyle(
                    color: _isExecuting ? const Color(0xFF38BDF8) : const Color(0xFF9CA3AF),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Presets Menu
          PopupMenuButton<SequencePreset>(
            icon: const Icon(Icons.playlist_play_rounded, color: Colors.white70),
            tooltip: 'Load Motion Preset',
            color: const Color(0xFF282E3E),
            onSelected: _loadPreset,
            itemBuilder: (context) => SequencePreset.defaultPresets.map((preset) {
              return PopupMenuItem<SequencePreset>(
                value: preset,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      preset.description,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          // Clear Button
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
            tooltip: 'Clear Queue',
            onPressed: _steps.isEmpty || _isExecuting ? null : _clearAllSteps,
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.amber.shade900.withValues(alpha: 0.9),
      child: const Row(
        children: [
          Icon(Icons.bluetooth_disabled_rounded, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'BLE Disconnected. Reconnect to send motion sequences to ESP32.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.alt_route_rounded,
              size: 64,
              color: Colors.grey.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Motion Steps in Queue',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add steps below or choose a preset routine from the top right menu.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add First Step'),
              onPressed: () => _showAddStepSheet(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReorderableStepList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: _steps.length,
      // ignore: deprecated_member_use
      onReorder: _reorderSteps,
      proxyDecorator: (child, index, animation) {
        return Material(
          color: Colors.transparent,
          elevation: 6,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final step = _steps[index];
        final isActive = _isExecuting && _activeStepIndex == index;
        return _buildStepCard(step, index, isActive);
      },
    );
  }

  Widget _buildStepCard(SequenceStep step, int index, bool isActive) {
    return Container(
      key: ValueKey(step.id),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF2A344D) : const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? const Color(0xFF38BDF8)
              : const Color(0xFF2E3446),
          width: isActive ? 2 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.25),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Column(
        children: [
          // Step Header Row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              children: [
                // Step Number Badge
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF38BDF8)
                        : const Color(0xFF282E3E),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Action Icon
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: step.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(step.icon, color: step.color, size: 20),
                ),
                const SizedBox(width: 10),

                // Action Title & Short Label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        step.toBleCommand(),
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Formatted Value Display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF13161F),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: step.color.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    step.formattedValue,
                    style: TextStyle(
                      color: step.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),

                // Delete Step Button
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: Colors.white38,
                  hoverColor: Colors.red.withValues(alpha: 0.1),
                  splashRadius: 18,
                  onPressed: _isExecuting ? null : () => _deleteStep(index),
                ),

                // Drag Handle
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: Colors.white24,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Value Tuner Controls Row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: _buildStepTuner(step, index),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTuner(SequenceStep step, int index) {
    if (step.type == StepType.forward || step.type == StepType.reverse) {
      // Distance Adjustment (+/- 5cm, +/- 10cm)
      return Row(
        children: [
          _buildTunerChip('-10', () => _updateStepValue(index, -10)),
          const SizedBox(width: 6),
          _buildTunerChip('-5', () => _updateStepValue(index, -5)),
          const Spacer(),
          _buildTunerChip('+5 cm', () => _updateStepValue(index, 5), isHighlight: true),
          const SizedBox(width: 6),
          _buildTunerChip('+10 cm', () => _updateStepValue(index, 10)),
          const SizedBox(width: 6),
          _buildTunerChip('+25 cm', () => _updateStepValue(index, 25)),
        ],
      );
    } else if (step.type == StepType.turnLeft || step.type == StepType.turnRight) {
      // Angle Adjustment (45°, 90°, 180°, +/-15°)
      return Row(
        children: [
          _buildTunerChip('45°', () => _setStepExactValue(index, 45)),
          const SizedBox(width: 6),
          _buildTunerChip('90°', () => _setStepExactValue(index, 90), isHighlight: true),
          const SizedBox(width: 6),
          _buildTunerChip('180°', () => _setStepExactValue(index, 180)),
          const Spacer(),
          _buildTunerChip('-15°', () => _updateStepValue(index, -15)),
          const SizedBox(width: 6),
          _buildTunerChip('+15°', () => _updateStepValue(index, 15)),
        ],
      );
    } else {
      // Wait / Pause Adjustment (250ms, 500ms, 1000ms, +/-100ms)
      return Row(
        children: [
          _buildTunerChip('250ms', () => _setStepExactValue(index, 250)),
          const SizedBox(width: 6),
          _buildTunerChip('500ms', () => _setStepExactValue(index, 500), isHighlight: true),
          const SizedBox(width: 6),
          _buildTunerChip('1000ms', () => _setStepExactValue(index, 1000)),
          const Spacer(),
          _buildTunerChip('-100ms', () => _updateStepValue(index, -100)),
          const SizedBox(width: 6),
          _buildTunerChip('+100ms', () => _updateStepValue(index, 100)),
        ],
      );
    }
  }

  Widget _buildTunerChip(String label, VoidCallback onTap, {bool isHighlight = false}) {
    return InkWell(
      onTap: _isExecuting ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isHighlight
              ? const Color(0xFF374151)
              : const Color(0xFF282E3E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isHighlight ? const Color(0xFF4B5563) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isHighlight ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom Action Bar & Modal Sheet
  // ---------------------------------------------------------------------------

  Widget _buildBottomControlDock() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E222D),
        border: Border(
          top: BorderSide(color: Color(0xFF2E3446), width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick Add Buttons Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickAddButton(
                  icon: Icons.arrow_upward_rounded,
                  label: '+ FWD 10cm',
                  color: const Color(0xFF10B981),
                  onTap: () => _addStep(StepType.forward, 10),
                ),
                const SizedBox(width: 8),
                _buildQuickAddButton(
                  icon: Icons.arrow_downward_rounded,
                  label: '+ REV 10cm',
                  color: const Color(0xFFF59E0B),
                  onTap: () => _addStep(StepType.reverse, 10),
                ),
                const SizedBox(width: 8),
                _buildQuickAddButton(
                  icon: Icons.turn_left_rounded,
                  label: '+ LEFT 90°',
                  color: const Color(0xFF3B82F6),
                  onTap: () => _addStep(StepType.turnLeft, 90),
                ),
                const SizedBox(width: 8),
                _buildQuickAddButton(
                  icon: Icons.turn_right_rounded,
                  label: '+ RIGHT 90°',
                  color: const Color(0xFF8B5CF6),
                  onTap: () => _addStep(StepType.turnRight, 90),
                ),
                const SizedBox(width: 8),
                _buildQuickAddButton(
                  icon: Icons.timer_outlined,
                  label: '+ WAIT 500ms',
                  color: const Color(0xFF06B6D4),
                  onTap: () => _addStep(StepType.wait, 500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Main Action Execution Buttons
          Row(
            children: [
              // Add Custom Step Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF4B5563)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: const Text('Add Step'),
                onPressed: _isExecuting ? null : _showAddStepSheet,
              ),
              const SizedBox(width: 10),

              // Run Sequence Button
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF374151),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isUploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 22),
                  label: Text(
                    _isUploading
                        ? 'UPLOADING...'
                        : (_isExecuting ? 'EXECUTING...' : 'RUN SEQUENCE'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: _isExecuting || _steps.isEmpty ? null : _runSequence,
                ),
              ),

              // Emergency Stop Button
              if (_isExecuting) ...[
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 20),
                  label: const Text(
                    'STOP',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _emergencyStop,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAddButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isExecuting ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddStepSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E222D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Movement Action',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose an action to add to the robot autonomous motion queue',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              _buildModalActionTile(
                icon: Icons.arrow_upward_rounded,
                title: 'Move Forward',
                subtitle: 'Straight trajectory with encoder tick-trimming',
                color: const Color(0xFF10B981),
                onTap: () {
                  Navigator.pop(ctx);
                  _addStep(StepType.forward, 20.0);
                },
              ),
              _buildModalActionTile(
                icon: Icons.arrow_downward_rounded,
                title: 'Move Backward',
                subtitle: 'Straight reverse trajectory with anti-drift trimming',
                color: const Color(0xFFF59E0B),
                onTap: () {
                  Navigator.pop(ctx);
                  _addStep(StepType.reverse, 20.0);
                },
              ),
              _buildModalActionTile(
                icon: Icons.turn_left_rounded,
                title: 'Turn Left',
                subtitle: 'In-place differential pivot rotation',
                color: const Color(0xFF3B82F6),
                onTap: () {
                  Navigator.pop(ctx);
                  _addStep(StepType.turnLeft, 90.0);
                },
              ),
              _buildModalActionTile(
                icon: Icons.turn_right_rounded,
                title: 'Turn Right',
                subtitle: 'In-place differential pivot rotation',
                color: const Color(0xFF8B5CF6),
                onTap: () {
                  Navigator.pop(ctx);
                  _addStep(StepType.turnRight, 90.0);
                },
              ),
              _buildModalActionTile(
                icon: Icons.timer_outlined,
                title: 'Pause / Wait',
                subtitle: 'Halt motors with active BTS7960 braking',
                color: const Color(0xFF06B6D4),
                onTap: () {
                  Navigator.pop(ctx);
                  _addStep(StepType.wait, 500.0);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white30),
      onTap: onTap,
    );
  }
}
