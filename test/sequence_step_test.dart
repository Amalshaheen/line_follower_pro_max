import 'package:flutter_test/flutter_test.dart';
import 'package:line_follower_pro_max/models/sequence_step.dart';

void main() {
  group('SequenceStep Model Tests', () {
    test('Correctly formats BLE command strings for all action types', () {
      final fwd = SequenceStep.create(type: StepType.forward, value: 25.0);
      expect(fwd.toBleCommand(), 'SEQ,ADD,FWD,25.0');
      expect(fwd.formattedValue, '25 cm');

      final rev = SequenceStep.create(type: StepType.reverse, value: 15.5);
      expect(rev.toBleCommand(), 'SEQ,ADD,REV,15.5');
      expect(rev.formattedValue, '15.5 cm');

      final left = SequenceStep.create(type: StepType.turnLeft, value: 90.0);
      expect(left.toBleCommand(), 'SEQ,ADD,LEFT,90.0');
      expect(left.formattedValue, '90 °');

      final right = SequenceStep.create(type: StepType.turnRight, value: 180.0);
      expect(right.toBleCommand(), 'SEQ,ADD,RIGHT,180.0');
      expect(right.formattedValue, '180 °');

      final wait = SequenceStep.create(type: StepType.wait, value: 500.0);
      expect(wait.toBleCommand(), 'SEQ,ADD,WAIT,500');
      expect(wait.formattedValue, '500 ms');
    });

    test('Clamps out-of-range values according to kinematic safety limits', () {
      // Forward clamp: [1.0, 500.0]
      final tooSmallFwd = SequenceStep.create(type: StepType.forward, value: -10);
      expect(tooSmallFwd.value, 1.0);

      final tooLargeFwd = SequenceStep.create(type: StepType.forward, value: 1000);
      expect(tooLargeFwd.value, 500.0);

      // Turns clamp: [5.0, 720.0]
      final tooSmallTurn = SequenceStep.create(type: StepType.turnLeft, value: 1);
      expect(tooSmallTurn.value, 5.0);

      final tooLargeTurn = SequenceStep.create(type: StepType.turnRight, value: 999);
      expect(tooLargeTurn.value, 720.0);

      // Wait clamp: [50.0, 10000.0]
      final tooSmallWait = SequenceStep.create(type: StepType.wait, value: 10);
      expect(tooSmallWait.value, 50.0);

      final tooLargeWait = SequenceStep.create(type: StepType.wait, value: 50000);
      expect(tooLargeWait.value, 10000.0);
    });

    test('copyWith updates value and type while clamping safely', () {
      final step = SequenceStep.create(type: StepType.forward, value: 20);
      final updated = step.copyWith(value: 35);
      expect(updated.value, 35.0);
      expect(updated.id, step.id);
      expect(updated.type, StepType.forward);

      final changedType = step.copyWith(type: StepType.turnRight, value: 90);
      expect(changedType.type, StepType.turnRight);
      expect(changedType.value, 90.0);
      expect(changedType.toBleCommand(), 'SEQ,ADD,RIGHT,90.0');
    });

    test('Default presets contain valid, non-empty motion queues', () {
      final presets = SequencePreset.defaultPresets;
      expect(presets, isNotEmpty);
      for (final p in presets) {
        expect(p.name, isNotEmpty);
        expect(p.steps, isNotEmpty);
        for (final s in p.steps) {
          expect(s.value, greaterThan(0));
          expect(s.toBleCommand(), startsWith('SEQ,ADD,'));
        }
      }
    });
  });
}
