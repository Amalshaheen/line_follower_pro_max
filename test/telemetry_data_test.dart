import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_follower_pro_max/models/robot_state.dart';

void main() {
  group('TelemetryData Binary Parsing Tests', () {
    test('Correctly parses 15-byte packet with positive error in mm', () {
      final bytes = Uint8List(15);
      // 12 sensor values (0–255)
      for (int i = 0; i < 12; i++) {
        bytes[i] = (i + 1) * 20; // 20, 40, 60...
      }
      // Error * 100: +25.97 mm -> 2597 (0x0A25 in little-endian)
      final byteData = ByteData.sublistView(bytes);
      byteData.setInt16(12, 2597, Endian.little);

      // Flags: Bit 0 = motorsEnabled (1), Bit 1 = lineLost (0) -> 0x01
      bytes[14] = 0x01;

      final telemetry = TelemetryData.fromBinary(bytes);
      expect(telemetry, isNotNull);
      expect(telemetry!.sensors.length, 12);
      expect(telemetry.sensors[0], 20);
      expect(telemetry.sensors[11], 240);
      expect(telemetry.error, closeTo(25.97, 0.001));
      expect(telemetry.errorMm, closeTo(25.97, 0.001));
      expect(telemetry.motorsRunning, isTrue);
      expect(telemetry.lineDetected, isTrue);
    });

    test('Correctly parses negative error in mm and line lost flag (Bit 1 = 1)', () {
      final bytes = Uint8List(15);
      for (int i = 0; i < 12; i++) {
        bytes[i] = 10;
      }
      // Error * 100: -46.01 mm -> -4601
      final byteData = ByteData.sublistView(bytes);
      byteData.setInt16(12, -4601, Endian.little);

      // Flags: Bit 0 = 0 (stopped), Bit 1 = 1 (line lost) -> 0x02
      bytes[14] = 0x02;

      final telemetry = TelemetryData.fromBinary(bytes);
      expect(telemetry, isNotNull);
      expect(telemetry!.error, closeTo(-46.01, 0.001));
      expect(telemetry.errorMm, closeTo(-46.01, 0.001));
      expect(telemetry.motorsRunning, isFalse);
      expect(telemetry.lineDetected, isFalse);
    });

    test('Correctly flags line lost on error 99.90f (error_x100 = 9990)', () {
      final bytes = Uint8List(15);
      final byteData = ByteData.sublistView(bytes);
      byteData.setInt16(12, 9990, Endian.little);
      bytes[14] = 0x03; // Bit 0 = 1, Bit 1 = 1

      final telemetry = TelemetryData.fromBinary(bytes);
      expect(telemetry, isNotNull);
      expect(telemetry!.motorsRunning, isTrue);
      expect(telemetry.lineDetected, isFalse);
    });

    test('Returns null if packet has fewer than 15 bytes', () {
      final shortBytes = Uint8List(14);
      final telemetry = TelemetryData.fromBinary(shortBytes);
      expect(telemetry, isNull);
    });
  });
}
