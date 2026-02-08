import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'ble_codec.dart';

enum PayloadType { shortFrame, frame06, frame05, raw }

class PayloadEntry {
  PayloadEntry({
    required this.id,
    required this.type,
    this.hex,
    this.cmdId,
    this.data32,
    this.data32HexLe,
    this.data24,
    this.data24HexLe,
    this.count,
    this.notes,
  });

  final String id;
  final PayloadType type;
  final String? hex;
  final int? cmdId;
  final int? data32;
  final String? data32HexLe;
  final int? data24;
  final String? data24HexLe;
  final int? count;
  final String? notes;

  List<int>? buildBytes() {
    switch (type) {
      case PayloadType.shortFrame:
      case PayloadType.raw:
        return hex == null ? null : hexToBytes(hex!);
      case PayloadType.frame06:
        if (cmdId == null) return null;
        if (data32HexLe != null) {
          final bytes = hexToBytes(data32HexLe!);
          if (bytes == null) return null;
          return buildFrame06FromBytes(cmdId!, bytes);
        }
        if (data32 == null) return null;
        return buildFrame06(cmdId!, data32!);
      case PayloadType.frame05:
        if (cmdId == null) return null;
        if (data24HexLe != null) {
          final bytes = hexToBytes(data24HexLe!);
          if (bytes == null) return null;
          return buildFrame05FromBytes(cmdId!, bytes);
        }
        if (data24 == null) return null;
        return buildFrame05(cmdId!, data24!);
    }
  }

  String displayLabel() {
    final c = count == null ? '' : ' (${count}x)';
    switch (type) {
      case PayloadType.shortFrame:
        return 'short ${hex ?? id}$c';
      case PayloadType.raw:
        return hex ?? id;
      case PayloadType.frame06:
        final data = data32HexLe != null
            ? 'le ${data32HexLe!}'
            : data32 == null
                ? ''
                : '0x${data32!.toRadixString(16).padLeft(8, '0')}';
        return '0x06 cmd 0x${cmdId!.toRadixString(16).padLeft(2, '0')} data32 $data$c';
      case PayloadType.frame05:
        final data = data24HexLe != null
            ? 'le ${data24HexLe!}'
            : data24 == null
                ? ''
                : '0x${data24!.toRadixString(16).padLeft(6, '0')}';
        return '0x05 cmd 0x${cmdId!.toRadixString(16).padLeft(2, '0')} data24 $data$c';
    }
  }
}

class PayloadRegistry {
  PayloadRegistry({
    required this.shortFrames,
    required this.frame06,
    required this.frame05,
    required this.raw,
  });

  final List<PayloadEntry> shortFrames;
  final List<PayloadEntry> frame06;
  final List<PayloadEntry> frame05;
  final List<PayloadEntry> raw;

  static Future<PayloadRegistry> load() async {
    final jsonString = await rootBundle.loadString('assets/payload_registry.json');
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;

    int? parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) {
        final v = value.toLowerCase();
        if (v.startsWith('0x')) {
          return int.tryParse(v.substring(2), radix: 16);
        }
        return int.tryParse(v);
      }
      return null;
    }

    List<PayloadEntry> parseList(String key, PayloadType type) {
      final list = (decoded[key] as List<dynamic>? ?? []);
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        return PayloadEntry(
          id: map['id'] as String? ?? '${type.name}_${map['hex'] ?? map['cmd_id']}',
          type: type,
          hex: map['hex'] as String?,
          cmdId: parseInt(map['cmd_id']),
          data32: parseInt(map['data32']),
          data32HexLe: map['data32_hex_le'] as String?,
          data24: parseInt(map['data24']),
          data24HexLe: map['data24_hex_le'] as String?,
          count: parseInt(map['count']),
          notes: map['notes'] as String?,
        );
      }).toList();
    }

    return PayloadRegistry(
      shortFrames: parseList('short_frames', PayloadType.shortFrame),
      frame06: parseList('frame06', PayloadType.frame06),
      frame05: parseList('frame05', PayloadType.frame05),
      raw: parseList('raw', PayloadType.raw),
    );
  }
}
