import 'package:flutter_test/flutter_test.dart';

import 'package:r4830_controller/live/ble_codec.dart';

void main() {
  test('buildFrame06FromBytes computes checksum', () {
    final bytes = buildFrame06FromBytes(0x0c, [0x01, 0x00, 0x00, 0x00]);
    expect(bytesToHex(bytes), '060c010000000d');
  });

  test('buildFrame05FromBytes computes checksum', () {
    final bytes = buildFrame05FromBytes(0x2a, [0x65, 0x6e, 0x00]);
    expect(bytesToHex(bytes), '052a656e00fd');
  });

  test('decodePayload extracts frame06 fields', () {
    final bytes = hexToBytes('060c010000000d')!;
    final decoded = decodePayload(bytes);
    expect(decoded['frame_type'], '0x06');
    expect(decoded['cmd_id'], 0x0c);
    expect(decoded['checksum_ok'], true);
    expect(decoded['data32_le_u'], 1);
  });

  test('decodePayload extracts ack frame fields', () {
    final bytes = hexToBytes('03210122')!;
    final decoded = decodePayload(bytes);
    expect(decoded['frame_type'], '0x03_ack');
    expect(decoded['cmd_id'], 0x21);
    expect(decoded['ack_status'], 1);
    expect(decoded['ack_ok'], true);
    expect(decoded['checksum_ok'], true);
  });
}
