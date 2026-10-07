import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/robot_service.dart';

/// Interactive control card for Sector Mapping & Predictive Race Mode.
class MappingControlsCard extends StatefulWidget {
  final RobotService? robotService;
  final bool isConnected;

  const MappingControlsCard({
    super.key,
    required this.robotService,
    required this.isConnected,
  });

  @override
  State<MappingControlsCard> createState() => _MappingControlsCardState();
}

enum MappingRunState {
  idle,
  mapping,
  mapRecorded,
  racing,
}

class _MappingControlsCardState extends State<MappingControlsCard> {
  MappingRunState _currentState = MappingRunState.idle;
  int _mappingSpeed = 55;

  void _handleMappingSpeedChanged(double value) {
    final speed = value.round();
    setState(() => _mappingSpeed = speed);
    if (widget.isConnected) {
      widget.robotService?.sendMapSpeed(speed);
    }
  }

  void _handleStartMapping() {
    if (!widget.isConnected) {
      _showDisconnectedSnackBar();
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() => _currentState = MappingRunState.mapping);
    widget.robotService?.startMapping();
    _showFeedbackSnackBar(
      'Track Mapping Started. Robot is recording straight & turn sectors...',
      const Color(0xFF3B82F6),
    );
  }

  void _handleFinishMapping() {
    if (!widget.isConnected) {
      _showDisconnectedSnackBar();
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _currentState = MappingRunState.mapRecorded);
    widget.robotService?.finishMapping();
    _showFeedbackSnackBar(
      'Track Mapping Finished! Velocity profiles & pre-brake points calculated.',
      const Color(0xFF10B981),
    );
  }

  void _handleStartRace() {
    if (!widget.isConnected) {
      _showDisconnectedSnackBar();
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() => _currentState = MappingRunState.racing);
    widget.robotService?.startRace();
    _showFeedbackSnackBar(
      'RACE STARTED! Autonomous acceleration on straights & pre-braking before turns.',
      const Color(0xFF8B5CF6),
    );
  }

  void _handleStopAll() {
    HapticFeedback.mediumImpact();
    setState(() => _currentState = MappingRunState.idle);
    widget.robotService?.sendCommand('RUN=0');
    _showFeedbackSnackBar('All motors and mapping runs stopped.', Colors.redAccent);
  }

  void _showDisconnectedSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text('Robot is not connected over BLE.'),
      ),
    );
  }

  void _showFeedbackSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        duration: const Duration(milliseconds: 2200),
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Title & Status Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.speed_rounded,
                    color: Color(0xFF8B5CF6),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sector Mapping & Race Mode',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Pre-braking corner optimization',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(),
              ],
            ),
            const SizedBox(height: 14),

            // Mode Explanation Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E222D).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getStateDescription(),
                      style: const TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Mapping Run Speed Configuration Slider
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tune_rounded, size: 16, color: Color(0xFF3B82F6)),
                          SizedBox(width: 6),
                          Text(
                            'Mapping Run Speed',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E222D),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'PWM $_mappingSpeed',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: _mappingSpeed.toDouble(),
                      min: 30,
                      max: 180,
                      divisions: 30,
                      activeColor: const Color(0xFF3B82F6),
                      inactiveColor: Colors.grey.withValues(alpha: 0.3),
                      onChanged: _currentState == MappingRunState.mapping
                          ? null
                          : _handleMappingSpeedChanged,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Action Buttons Row
            Row(
              children: [
                // 1. Start Mapping Button
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text(
                      'Record Map',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: _currentState == MappingRunState.mapping
                        ? null
                        : _handleStartMapping,
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Finish Mapping Button
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text(
                      'Finish Map',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: _currentState == MappingRunState.mapping
                        ? _handleFinishMapping
                        : null,
                  ),
                ),
                const SizedBox(width: 8),

                // 3. Race Run Button
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.sports_score_rounded, size: 18),
                    label: const Text(
                      'RACE',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: _currentState == MappingRunState.racing
                        ? null
                        : _handleStartRace,
                  ),
                ),
              ],
            ),

            if (_currentState != MappingRunState.idle) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text(
                    'HALT / IDLE',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: _handleStopAll,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    Color color;
    String label;

    switch (_currentState) {
      case MappingRunState.idle:
        color = Colors.grey;
        label = 'IDLE';
        break;
      case MappingRunState.mapping:
        color = const Color(0xFF3B82F6);
        label = 'MAPPING...';
        break;
      case MappingRunState.mapRecorded:
        color = const Color(0xFF10B981);
        label = 'MAP READY';
        break;
      case MappingRunState.racing:
        color = const Color(0xFF8B5CF6);
        label = 'RACING';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getStateDescription() {
    switch (_currentState) {
      case MappingRunState.idle:
        return 'Ready. Tap "Record Map" for calibration lap or "RACE" to execute pre-braked raceline.';
      case MappingRunState.mapping:
        return 'Mapping lap active. Bot is logging straights, corners, and length in encoder ticks.';
      case MappingRunState.mapRecorded:
        return 'Track map compiled! Robot will pre-brake ~94 mm before entering corners.';
      case MappingRunState.racing:
        return 'Predictive race lap active! Straightaway acceleration and curve pre-braking engaged.';
    }
  }
}
