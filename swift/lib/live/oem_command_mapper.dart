import 'dart:typed_data';

import 'ble_codec.dart';

enum CommandConfidence { verified, candidate }

class CommandMappingResult {
  CommandMappingResult({
    required this.payloadHex,
    required this.confidence,
    required this.label,
  });

  final String payloadHex;
  final CommandConfidence confidence;
  final String label;

  bool get isCandidate => confidence == CommandConfidence.candidate;
}

class OemCommandMapper {
  @Deprecated(
    'Use outputOpen/outputClose to match observed firmware semantics.',
  )
  static CommandMappingResult outputEnable(bool enabled) {
    return _frame06Bool(
      cmdId: 0x0c,
      enabled: enabled,
      confidence: CommandConfidence.verified,
      label: enabled
          ? 'current_path_enable_legacy'
          : 'current_path_disable_legacy',
    );
  }

  static CommandMappingResult outputOpen() {
    // Live captures on this firmware: 0x0c value 0 turns output ON/open.
    return _frame06Int(
      cmdId: 0x0c,
      value: 0,
      confidence: CommandConfidence.verified,
      label: 'current_output_open',
    );
  }

  static CommandMappingResult outputClose() {
    // Live captures on this firmware: 0x0c value 1 turns output OFF/close.
    return _frame06Int(
      cmdId: 0x0c,
      value: 1,
      confidence: CommandConfidence.verified,
      label: 'current_output_close',
    );
  }

  static CommandMappingResult manualControl(bool enabled) {
    return _frame06Bool(
      cmdId: 0x23,
      enabled: enabled,
      confidence: CommandConfidence.verified,
      label: enabled ? 'manual_output_open' : 'manual_output_close',
    );
  }

  static CommandMappingResult powerOnOutput(bool enabled) {
    // OEM diffs show power-on output semantics are inverted at protocol level:
    // Open => 0, Close => 1 (where enabled=true means Open in UI).
    return _frame06Bool(
      cmdId: 0x0b,
      enabled: !enabled,
      confidence: CommandConfidence.candidate,
      label: enabled
          ? 'power_on_output_enable_candidate'
          : 'power_on_output_disable_candidate',
    );
  }

  static CommandMappingResult selfStop(bool enabled) {
    return _frame06Bool(
      cmdId: 0x14,
      enabled: enabled,
      confidence: CommandConfidence.verified,
      label: enabled ? 'self_stop_enable' : 'self_stop_disable',
    );
  }

  static CommandMappingResult twoStageSwitch(bool enabled) {
    return _frame06Bool(
      cmdId: 0x20,
      enabled: enabled,
      confidence: CommandConfidence.verified,
      label: enabled ? 'two_stage_enable' : 'two_stage_disable',
    );
  }

  static CommandMappingResult powerOffCurrent(double amps) {
    return _frame06Float(
      cmdId: 0x15,
      value: amps,
      confidence: CommandConfidence.verified,
      label: 'power_off_current',
    );
  }

  static CommandMappingResult secondStageVoltage(double volts) {
    return _frame06Float(
      cmdId: 0x21,
      value: volts,
      confidence: CommandConfidence.verified,
      label: 'second_stage_voltage',
    );
  }

  static CommandMappingResult secondStageCurrent(double amps) {
    return _frame06Float(
      cmdId: 0x22,
      value: amps,
      confidence: CommandConfidence.verified,
      label: 'second_stage_current',
    );
  }

  static CommandMappingResult softStartSeconds(int seconds) {
    return _frame06Int(
      cmdId: 0x26,
      value: seconds,
      confidence: CommandConfidence.verified,
      label: 'soft_start_time',
    );
  }

  static CommandMappingResult chargingStatisticsZero() {
    return _frame06Int(
      cmdId: 0x13,
      value: 0,
      confidence: CommandConfidence.candidate,
      label: 'charging_statistics_zero_candidate',
    );
  }

  static CommandMappingResult outputVoltageSetpoint(double volts) {
    return _frame06Float(
      cmdId: 0x07,
      value: volts,
      confidence: CommandConfidence.verified,
      label: 'output_voltage_setpoint',
    );
  }

  static CommandMappingResult outputCurrentSetpoint(double amps) {
    return _frame06Float(
      cmdId: 0x08,
      value: amps,
      confidence: CommandConfidence.verified,
      label: 'output_current_setpoint',
    );
  }

  static CommandMappingResult powerLimitWatts(int watts) {
    return _frame06Int(
      cmdId: 0x27,
      value: watts,
      confidence: CommandConfidence.verified,
      label: 'power_limit_watts',
    );
  }

  static CommandMappingResult displayLanguage(String value) {
    final normalized = value.toLowerCase().trim();
    if (normalized == 'chinese (traditional)' ||
        normalized == 'traditional chinese' ||
        normalized == 'chinese traditional') {
      final bytes = buildFrame05FromBytes(0x2a, const [0x7a, 0x74, 0x00]);
      return CommandMappingResult(
        payloadHex: bytesToHex(bytes),
        confidence: CommandConfidence.candidate,
        label: 'display_language_chinese_traditional_candidate',
      );
    }
    if (normalized == 'chinese' ||
        normalized == 'chinese (simplified)' ||
        normalized == 'simplified chinese' ||
        normalized == 'chinese simplified') {
      final bytes = buildFrame05FromBytes(0x2a, const [0x7a, 0x68, 0x00]);
      return CommandMappingResult(
        payloadHex: bytesToHex(bytes),
        confidence: CommandConfidence.candidate,
        label: 'display_language_chinese_simplified_candidate',
      );
    }
    final bytes = buildFrame05FromBytes(0x2a, const [0x65, 0x6e, 0x00]);
    return CommandMappingResult(
      payloadHex: bytesToHex(bytes),
      confidence: CommandConfidence.candidate,
      label: 'display_language_english_candidate',
    );
  }

  static CommandMappingResult multiMotorMode(String value) {
    final normalized = value.toLowerCase().trim();
    final enabled = normalized == 'equal distribution';
    return _frame06Bool(
      cmdId: 0x2f,
      enabled: enabled,
      confidence: CommandConfidence.candidate,
      label: enabled
          ? 'equal_distribution_enable_candidate'
          : 'intelligent_control_candidate',
    );
  }

  static CommandMappingResult renameCharger(String value) {
    return _frameAscii(
      cmdId: 0x1e,
      value: value,
      maxLen: 16,
      confidence: CommandConfidence.candidate,
      label: 'rename_charger_candidate',
    );
  }

  static CommandMappingResult setBlePassword(String value) {
    return _frameAscii(
      cmdId: 0x1b,
      value: value,
      maxLen: 16,
      confidence: CommandConfidence.candidate,
      label: 'set_ble_password_candidate',
    );
  }

  static CommandMappingResult _frame06Bool({
    required int cmdId,
    required bool enabled,
    required CommandConfidence confidence,
    required String label,
  }) {
    return _frame06Int(
      cmdId: cmdId,
      value: enabled ? 1 : 0,
      confidence: confidence,
      label: label,
    );
  }

  static CommandMappingResult _frame06Float({
    required int cmdId,
    required double value,
    required CommandConfidence confidence,
    required String label,
  }) {
    final data = ByteData(4)..setFloat32(0, value, Endian.little);
    final bits = data.getUint32(0, Endian.little);
    final bytes = buildFrame06(cmdId, bits);
    return CommandMappingResult(
      payloadHex: bytesToHex(bytes),
      confidence: confidence,
      label: label,
    );
  }

  static CommandMappingResult _frame06Int({
    required int cmdId,
    required int value,
    required CommandConfidence confidence,
    required String label,
  }) {
    final bytes = buildFrame06(cmdId, value);
    return CommandMappingResult(
      payloadHex: bytesToHex(bytes),
      confidence: confidence,
      label: label,
    );
  }

  static CommandMappingResult _frameAscii({
    required int cmdId,
    required String value,
    required int maxLen,
    required CommandConfidence confidence,
    required String label,
  }) {
    final sanitized = _asciiOnly(value).trim();
    final clipped = sanitized.length > maxLen
        ? sanitized.substring(0, maxLen)
        : sanitized;
    final dataBytes = <int>[...clipped.codeUnits, 0x00];
    final checksum =
        (cmdId + dataBytes.fold<int>(0, (sum, b) => sum + b)) & 0xFF;
    final frame = <int>[dataBytes.length + 1, cmdId, ...dataBytes, checksum];
    return CommandMappingResult(
      payloadHex: bytesToHex(frame),
      confidence: confidence,
      label: label,
    );
  }

  static String _asciiOnly(String raw) {
    final out = StringBuffer();
    for (final code in raw.codeUnits) {
      if (code >= 0x20 && code <= 0x7e) {
        out.writeCharCode(code);
      }
    }
    return out.toString();
  }
}
