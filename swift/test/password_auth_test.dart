import 'package:flutter_test/flutter_test.dart';

import 'package:r4830_controller/live/ble_codec.dart';
import 'package:r4830_controller/live/ble_controller.dart';

void main() {
  test('blank password auth chunks match observed OEM payload', () {
    final chunks = BleController.buildPasswordAuthChunks('', maxChunkBytes: 20);
    expect(chunks.length, 2);
    expect(bytesToHex(chunks[0]), '2302443431443843443938463030423230344539');
    expect(bytesToHex(chunks[1]), '38303039393845434638343237450045');
  });
}
