import 'dart:convert';

class AttEvent {
  AttEvent({
    required this.index,
    required this.ts,
    required this.flags,
    required this.dir,
    required this.cid,
    required this.pb,
    required this.bc,
    required this.attOpcode,
    required this.type,
    required this.handle,
    required this.valueHex,
    required this.rawHex,
    required this.raw,
  });

  final int index;
  final int ts;
  final int flags;
  final String dir;
  final int cid;
  final int pb;
  final int bc;
  final int attOpcode;
  final String type;
  final int? handle;
  final String valueHex;
  final String rawHex;
  final Map<String, dynamic> raw;

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String? _asString(dynamic v) {
    if (v is String) return v;
    return null;
  }

  static AttEvent? fromJson(Map<String, dynamic> json, int index) {
    final ts = _asInt(json['ts']);
    final flags = _asInt(json['flags']);
    final dir = _asString(json['dir']);
    final cid = _asInt(json['cid']);
    final pb = _asInt(json['pb']);
    final bc = _asInt(json['bc']);
    final attOpcode = _asInt(json['att_opcode']);
    final type = _asString(json['type']);
    final valueHex = _asString(json['value_hex']);
    final rawHex = _asString(json['raw_hex']);

    final dynamic handleValue = json['handle'];
    int? handle;
    if (handleValue != null) {
      handle = _asInt(handleValue);
      if (handle == null) {
        return null;
      }
    }

    if ([
      ts,
      flags,
      dir,
      cid,
      pb,
      bc,
      attOpcode,
      type,
      valueHex,
      rawHex,
    ].any((value) => value == null)) {
      return null;
    }

    return AttEvent(
      index: index,
      ts: ts!,
      flags: flags!,
      dir: dir!,
      cid: cid!,
      pb: pb!,
      bc: bc!,
      attOpcode: attOpcode!,
      type: type!,
      handle: handle,
      valueHex: valueHex!,
      rawHex: rawHex!,
      raw: json,
    );
  }

  String prettyJson() {
    return const JsonEncoder.withIndent('  ').convert(raw);
  }
}
