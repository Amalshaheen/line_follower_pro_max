import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:line_follower_pro_max/models/robot_state.dart';
import 'package:line_follower_pro_max/services/ble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BLE Stack Protocol & Demultiplexing Tests', () {
    test('Demultiplexer distinguishes 15-byte binary telemetry from 15-byte ASCII error', () {
      TelemetryData? receivedTelemetry;
      String? receivedData;

      final bleService = BleService(
        onTelemetryReceived: (t) => receivedTelemetry = t,
        onDataReceived: (d) => receivedData = d,
      );

      // 1. Create a true 15-byte binary telemetry packet
      final binaryBytes = Uint8List(15);
      for (int i = 0; i < 12; i++) {
        binaryBytes[i] = (i + 1) * 15;
      }
      final byteData = ByteData.sublistView(binaryBytes);
      byteData.setInt16(12, 1500, Endian.little); // +15.00 mm
      binaryBytes[14] = 0x01; // motors enabled, line detected

      // Send to internal handler via reflection/dynamic
      bleService.handleIncomingDataForTesting(binaryBytes);
      expect(receivedTelemetry, isNotNull);
      expect(receivedTelemetry!.errorMm, closeTo(15.00, 0.01));
      expect(receivedTelemetry!.motorsRunning, isTrue);
      expect(receivedData, isNull);

      // 2. Create a 15-byte ASCII error: "ERR:QUEUE_FULL\n" (exactly 15 bytes!)
      receivedTelemetry = null;
      receivedData = null;
      final ascii15Bytes = utf8.encode('ERR:QUEUE_FULL\n');
      expect(ascii15Bytes.length, 15);

      bleService.handleIncomingDataForTesting(ascii15Bytes);
      // Must NOT be misinterpreted as binary telemetry!
      expect(receivedTelemetry, isNull);
      expect(receivedData, equals('ERR:QUEUE_FULL'));
    });

    test('Stream framing assembles fragmented chunks and executes across newlines', () {
      final acks = <String, String>{};

      final bleService = BleService(
        onAckReceived: (cmd, val) => acks[cmd] = val,
      );

      // Deliver fragmented chunk 1: "ACK:BA"
      bleService.handleIncomingDataForTesting(utf8.encode('ACK:BA'));
      expect(acks.isEmpty, isTrue);

      // Deliver fragmented chunk 2: "SE=85\nACK:K"
      bleService.handleIncomingDataForTesting(utf8.encode('SE=85\nACK:K'));
      expect(acks.containsKey('BASE'), isTrue);
      expect(acks['BASE'], equals('85'));
      expect(acks.containsKey('KP'), isFalse);

      // Deliver fragmented chunk 3: "P=2.50\n"
      bleService.handleIncomingDataForTesting(utf8.encode('P=2.50\n'));
      expect(acks.containsKey('KP'), isTrue);
      expect(acks['KP'], equals('2.50'));
    });

    test('ACK:CONFIG correctly parses all hardware registers for initial reconciliation', () {
      double? kp, ki, kd;
      int? base, max, min;
      bool? inv;

      final bleService = BleService(
        onConfigReceived: (kP, kI, kD, b, m, mi, i) {
          kp = kP;
          ki = kI;
          kd = kD;
          base = b;
          max = m;
          min = mi;
          inv = i;
        },
      );

      final configPacket = utf8.encode(
        'ACK:CONFIG=KP:2.50,KI:0.00,KD:0.08,BASE:70,MAX:120,MIN:30,INV:0\n',
      );
      bleService.handleIncomingDataForTesting(configPacket);

      expect(kp, closeTo(2.50, 0.001));
      expect(ki, closeTo(0.00, 0.001));
      expect(kd, closeTo(0.08, 0.001));
      expect(base, equals(70));
      expect(max, equals(120));
      expect(min, equals(30));
      expect(inv, isFalse);
    });

    test('ACK:THR correctly updates single targeted sensor without modifying surrounding thresholds', () {
      List<int>? updatedThresholds;

      final bleService = BleService(
        onThresholdsReceived: (t) => updatedThresholds = t,
      );

      // Initialize all thresholds to 2000
      final all2000 = utf8.encode('THRESHOLDS:2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000\n');
      bleService.handleIncomingDataForTesting(all2000);
      expect(updatedThresholds, isNotNull);
      expect(updatedThresholds![2], equals(2000));

      // Send single sensor update for sensor index 2: 1850
      final thrSingle = utf8.encode('ACK:THR=2,1850\n');
      bleService.handleIncomingDataForTesting(thrSingle);

      expect(updatedThresholds![2], equals(1850));
      // Verify surrounding sensors remained untouched
      expect(updatedThresholds![0], equals(2000));
      expect(updatedThresholds![1], equals(2000));
      expect(updatedThresholds![3], equals(2000));
      expect(updatedThresholds![11], equals(2000));
    });

    test('ACK:CALIB correctly triggers onAckReceived for auto-calibration confirmation', () {
      String? ackCommand;
      String? ackValue;

      final bleService = BleService(
        onAckReceived: (cmd, val) {
          ackCommand = cmd;
          ackValue = val;
        },
      );

      final calibAck = utf8.encode('ACK:CALIB\n');
      bleService.handleIncomingDataForTesting(calibAck);

      expect(ackCommand, equals('CALIB'));
      expect(ackValue, equals(''));
    });
  });
}
