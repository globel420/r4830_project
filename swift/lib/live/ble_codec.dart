import 'dart:convert';
import 'dart:typed_data';

String bytesToHex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

List<int>? hexToBytes(String input) {
  final sanitized = input.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
  if (sanitized.isEmpty || sanitized.length.isOdd) return null;
  final result = <int>[];
  for (var i = 0; i < sanitized.length; i += 2) {
    final byte = int.tryParse(sanitized.substring(i, i + 2), radix: 16);
    if (byte == null) return null;
    result.add(byte);
  }
  return result;
}

List<int> buildFrame06(int cmdId, int data32) {
  final bytes = <int>[0x06, cmdId & 0xFF];
  final data = ByteData(4)..setUint32(0, data32, Endian.little);
  for (var i = 0; i < 4; i++) {
    bytes.add(data.getUint8(i));
  }
  final checksum = bytes
      .sublist(1, 6)
      .fold<int>(0, (sum, b) => (sum + b) & 0xFF);
  bytes.add(checksum);
  return bytes;
}

List<int> buildFrame06FromBytes(int cmdId, List<int> data32LeBytes) {
  if (data32LeBytes.length != 4) {
    throw ArgumentError('data32LeBytes must be 4 bytes');
  }
  final bytes = <int>[0x06, cmdId & 0xFF, ...data32LeBytes];
  final checksum = bytes
      .sublist(1, 6)
      .fold<int>(0, (sum, b) => (sum + b) & 0xFF);
  bytes.add(checksum);
  return bytes;
}

List<int> buildFrame05(int cmdId, int data24) {
  final bytes = <int>[0x05, cmdId & 0xFF];
  final d0 = data24 & 0xFF;
  final d1 = (data24 >> 8) & 0xFF;
  final d2 = (data24 >> 16) & 0xFF;
  bytes.addAll([d0, d1, d2]);
  final checksum = bytes
      .sublist(1, 5)
      .fold<int>(0, (sum, b) => (sum + b) & 0xFF);
  bytes.add(checksum);
  return bytes;
}

List<int> buildFrame05FromBytes(int cmdId, List<int> data24LeBytes) {
  if (data24LeBytes.length != 3) {
    throw ArgumentError('data24LeBytes must be 3 bytes');
  }
  final bytes = <int>[0x05, cmdId & 0xFF, ...data24LeBytes];
  final checksum = bytes
      .sublist(1, 5)
      .fold<int>(0, (sum, b) => (sum + b) & 0xFF);
  bytes.add(checksum);
  return bytes;
}

Map<String, dynamic> decodePayload(List<int> bytes) {
  final map = <String, dynamic>{};
  final len = bytes.length;
  map['len'] = len;
  map['hex'] = bytesToHex(bytes);
  if (len >= 2) {
    map['pkt_prefix'] = bytesToHex(bytes.sublist(0, 2));
  }

  for (var i = 0; i < len; i++) {
    map['u8_${i.toString().padLeft(2, '0')}'] = bytes[i];
  }

  if (len >= 4) {
    final byteData = ByteData(len);
    for (var i = 0; i < len; i++) {
      byteData.setUint8(i, bytes[i]);
    }
    for (var off = 0; off <= len - 4; off++) {
      final value = byteData.getFloat32(off, Endian.little);
      map['f32le_off_${off.toString().padLeft(2, '0')}'] = value.isFinite
          ? value
          : value.isNaN
          ? 'NaN'
          : 'Inf';
    }
  }

  if (len == 7 && bytes[0] == 0x06) {
    final cmdId = bytes[1];
    final data = ByteData(4);
    for (var i = 0; i < 4; i++) {
      data.setUint8(i, bytes[2 + i]);
    }
    final data32 = data.getUint32(0, Endian.little);
    final data32Signed = data.getInt32(0, Endian.little);
    final data32Float = data.getFloat32(0, Endian.little);
    final checksum = bytes[6];
    final calc = bytes.sublist(1, 6).fold<int>(0, (sum, b) => (sum + b) & 0xFF);

    map['frame_type'] = '0x06';
    map['cmd_id'] = cmdId;
    map['data32_le_u'] = data32;
    map['data32_le_i'] = data32Signed;
    map['data32_le_f'] = data32Float.isFinite
        ? data32Float
        : data32Float.isNaN
        ? 'NaN'
        : 'Inf';
    map['checksum'] = checksum;
    map['checksum_ok'] = checksum == calc;
    if (data32 == 0 || data32 == 1) {
      map['data32_bool_candidate'] = data32 == 1;
    }
  }

  if (len == 6 && bytes[0] == 0x05) {
    final cmdId = bytes[1];
    final data24 = bytes[2] | (bytes[3] << 8) | (bytes[4] << 16);
    final checksum = bytes[5];
    final calc = bytes.sublist(1, 5).fold<int>(0, (sum, b) => (sum + b) & 0xFF);
    map['frame_type'] = '0x05';
    map['cmd_id'] = cmdId;
    map['data24_le_u'] = data24;
    map['checksum'] = checksum;
    map['checksum_ok'] = checksum == calc;
  }

  if (len == 4 && bytes[0] == 0x03) {
    final cmdId = bytes[1];
    final ackStatus = bytes[2];
    final checksum = bytes[3];
    final calc = (cmdId + ackStatus) & 0xFF;
    map['frame_type'] = '0x03_ack';
    map['cmd_id'] = cmdId;
    map['ack_status'] = ackStatus;
    map['ack_ok'] = ackStatus == 1;
    map['checksum'] = checksum;
    map['checksum_ok'] = checksum == calc;
  }

  return map;
}

String prettyJson(Map<String, dynamic> value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}
