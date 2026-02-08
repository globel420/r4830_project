import 'package:flutter_test/flutter_test.dart';

import 'package:r4830_controller/live/ble_codec.dart';
import 'package:r4830_controller/live/ble_controller.dart';

void main() {
  test(
    'waitForCommandAck returns acknowledged when ack frame is present',
    () async {
      final controller = BleController(bindPlatformStreams: false);
      controller.addLogBytes('RX', hexToBytes('03210122')!);

      final state = await controller.waitForCommandAck(
        cmdId: 0x21,
        timeout: const Duration(milliseconds: 30),
      );
      expect(state, CommandAckState.acknowledged);
      controller.dispose();
    },
  );

  test('waitForCommandAck returns rejected when ack_status is 0', () async {
    final controller = BleController(bindPlatformStreams: false);
    controller.addLogBytes('RX', hexToBytes('03210021')!);

    final state = await controller.waitForCommandAck(
      cmdId: 0x21,
      timeout: const Duration(milliseconds: 30),
    );
    expect(state, CommandAckState.rejected);
    controller.dispose();
  });

  test('waitForCommandAck returns timeout when no ack arrives', () async {
    final controller = BleController(bindPlatformStreams: false);

    final state = await controller.waitForCommandAck(
      cmdId: 0x21,
      timeout: const Duration(milliseconds: 30),
    );
    expect(state, CommandAckState.timeout);
    controller.dispose();
  });
}
