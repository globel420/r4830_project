import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:r4830_controller/domain/replay_controller.dart';

void main() {
  group('ReplayController', () {
    late ReplayController controller;
    late File tempFile;

    setUp(() async {
      controller = ReplayController();
      tempFile = File('${Directory.systemTemp.path}/test.jsonl');
      await tempFile.writeAsString(
        '{"ts": 1000, "type": "ATT_WRITE_CMD", "handle": 6, "value": "01", "flags": 0, "dir": "W", "cid": 4, "pb": 0, "bc": 0, "att_opcode": 0, "value_hex": "01", "raw_hex": "01"}\n'
        '{"ts": 2000, "type": "ATT_HANDLE_VALUE_NTF", "handle": 3, "value": "02", "flags": 0, "dir": "R", "cid": 4, "pb": 0, "bc": 0, "att_opcode": 0, "value_hex": "02", "raw_hex": "02"}\n'
        'invalid_line\n'
        '{"ts": 3000, "type": "ATT_WRITE_CMD", "handle": 6, "value": "03", "flags": 0, "dir": "W", "cid": 4, "pb": 0, "bc": 0, "att_opcode": 0, "value_hex": "03", "raw_hex": "03"}\n',      );
    });

    tearDown(() async {
      await tempFile.delete();
    });

    test('loadCapture should load events correctly', () async {
      await controller.loadCapture(tempFile.path);

      expect(controller.events.length, 3);
      expect(controller.totalLines, 4);
      expect(controller.invalidLines, 1);
      expect(controller.firstTs, 1000);
    });

    test('playback controls should work correctly', () async {
      await controller.loadCapture(tempFile.path);

      expect(controller.isPlaying, false);
      expect(controller.currentIndex, -1);

      controller.play();
      expect(controller.isPlaying, true);
      expect(controller.currentIndex, 0);

      controller.pause();
      expect(controller.isPlaying, false);

      controller.play();
      expect(controller.isPlaying, true);

      controller.stop();
      expect(controller.isPlaying, false);

      controller.reset();
      expect(controller.currentIndex, -1);
    });

    test('step should advance the index', () async {
      await controller.loadCapture(tempFile.path);

      expect(controller.currentIndex, -1);
      controller.step();
      expect(controller.currentIndex, 0);
      controller.step();
      expect(controller.currentIndex, 1);
    });

    test('setSpeed should update the speed', () {
      expect(controller.speed, 1.0);
      controller.setSpeed(2.0);
      expect(controller.speed, 2.0);
    });

    test('filtering should work correctly', () async {
      await controller.loadCapture(tempFile.path);
      controller.play();
      await Future.delayed(const Duration(milliseconds: 10)); // allow time for play to start
      controller.step();
      controller.step();


      final commands = controller.filteredEvents(telemetry: false);
      final telemetry = controller.filteredEvents(telemetry: true);

      expect(commands.length, 2);
      expect(telemetry.length, 1);

      expect(controller.playedCount(telemetry: false), 2);
      expect(controller.playedCount(telemetry: true), 1);
    });
  });
}
