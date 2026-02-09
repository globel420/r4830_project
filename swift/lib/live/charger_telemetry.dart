import 'ble_controller.dart';

class ChargerTelemetryState {
  ChargerTelemetryState({
    this.firmwareVersion,
    this.outputSetVoltage,
    this.outputSetCurrent,
    this.inputVoltage,
    this.inputCurrent,
    this.outputVoltage,
    this.outputCurrent,
    this.inputFrequencyHz,
    this.temperatureC,
    this.temperature2C,
    this.throttlingPercent,
    this.inputPowerW,
    this.outputPowerW,
    this.efficiencyPercent,
    this.stage2Voltage,
    this.stage2Current,
    this.powerOffCurrent,
    this.powerLimitWatts,
    this.softStartSeconds,
    this.outputEnabled,
    this.manualControl,
    this.twoStageEnabled,
    this.powerOnOutput,
    this.selfStop,
    this.equalDistributionMode,
    this.displayLanguage,
    this.lastRxAt,
  });

  final String? firmwareVersion;
  final double? outputSetVoltage;
  final double? outputSetCurrent;
  final double? inputVoltage;
  final double? inputCurrent;
  final double? outputVoltage;
  final double? outputCurrent;
  final double? inputFrequencyHz;
  final double? temperatureC;
  final double? temperature2C;
  final double? throttlingPercent;
  final double? inputPowerW;
  final double? outputPowerW;
  final double? efficiencyPercent;

  final double? stage2Voltage;
  final double? stage2Current;
  final double? powerOffCurrent;
  final int? powerLimitWatts;
  final int? softStartSeconds;

  final bool? outputEnabled;
  final bool? manualControl;
  final bool? twoStageEnabled;
  final bool? powerOnOutput;
  final bool? selfStop;
  final bool? equalDistributionMode;
  final String? displayLanguage;

  final DateTime? lastRxAt;

  static ChargerTelemetryState fromLogs(List<BleLogEntry> rxLogs) {
    if (rxLogs.isEmpty) {
      return ChargerTelemetryState();
    }

    String? firmwareVersion;
    double? outputSetVoltage;
    double? outputSetCurrent;
    double? outputVoltage;
    double? outputCurrent;
    double? inputVoltage;
    double? inputCurrent;
    double? inputFrequencyHz;
    double? temperatureC;
    double? temperature2C;
    double? throttlingPercent;
    double? inputPowerW;
    double? outputPowerW;
    double? efficiencyPercent;

    double? stage2Voltage;
    double? stage2Current;
    double? powerOffCurrent;
    int? powerLimitWatts;
    int? softStartSeconds;

    bool? outputEnabled;
    bool? manualControl;
    bool? twoStageEnabled;
    bool? powerOnOutput;
    bool? selfStop;
    bool? equalDistributionMode;
    String? displayLanguage;
    bool? outputEnabledFrom6905;
    bool? outputEnabledFrom3006;
    bool? outputEnabledFrom06;

    final seenCmd = <int>{};
    for (final entry in rxLogs) {
      final decoded = entry.decoded;
      final prefix = decoded['pkt_prefix']?.toString().toLowerCase();
      final frameType = decoded['frame_type'];

      if (prefix == '0b01' && firmwareVersion == null) {
        final parsed = _parseAscii(decoded, start: 2, maxBytes: 24);
        if (parsed != null && parsed.isNotEmpty) {
          firmwareVersion = parsed;
        }
      }

      if (prefix == '3006') {
        inputVoltage ??= _bounded(_f32At(decoded, 2), min: 0, max: 300);
        inputCurrent ??= _bounded(_f32At(decoded, 6), min: 0, max: 200);
        inputFrequencyHz ??= _bounded(_f32At(decoded, 10), min: 0, max: 500);
        temperatureC ??= _bounded(_f32At(decoded, 14), min: -40, max: 200);
        temperature2C ??= _bounded(_f32At(decoded, 18), min: -40, max: 200);
        // OEM display feed:
        // off_22 ~= output voltage, off_26 ~= output current, off_10 ~= frequency.
        outputVoltage ??= _bounded(_f32At(decoded, 22), min: 0, max: 300);
        outputCurrent ??= _bounded(_f32At(decoded, 26), min: 0, max: 200);
        inputPowerW ??= _bounded(_f32At(decoded, 30), min: 0, max: 50000);
        efficiencyPercent ??= _bounded(_f32At(decoded, 34), min: 0, max: 100);
        throttlingPercent ??= _bounded(_f32At(decoded, 34), min: 0, max: 100);
        final outputFlag = _u8At(decoded, 38);
        if (outputFlag != null && (outputFlag == 0 || outputFlag == 1)) {
          outputEnabledFrom3006 ??= outputFlag == 1;
        }
      }

      if (prefix == '6905') {
        outputSetVoltage ??= _bounded(_f32At(decoded, 2), min: 0, max: 300);
        outputSetCurrent ??= _bounded(_f32At(decoded, 6), min: 0, max: 200);
        final powerOnRaw = _u8At(decoded, 18);
        if (powerOnOutput == null &&
            powerOnRaw != null &&
            (powerOnRaw == 0 || powerOnRaw == 1)) {
          // Confirmed by two-run OEM diffs:
          // 6905[18] flips with Power-on output save, where 0=>Open and 1=>Close.
          powerOnOutput = powerOnRaw == 0;
        }
        powerOffCurrent ??= _bounded(_f32At(decoded, 44), min: 0, max: 200);
        final outputFlag = _u8At(decoded, 77);
        if (outputFlag != null && (outputFlag == 0 || outputFlag == 1)) {
          outputEnabledFrom6905 ??= outputFlag == 1;
        }
        stage2Voltage ??= _bounded(_f32At(decoded, 78), min: 0, max: 300);
        stage2Current ??= _bounded(_f32At(decoded, 82), min: 0, max: 200);
        final manualFlag = _u8At(decoded, 86);
        if (manualControl == null &&
            manualFlag != null &&
            (manualFlag == 0 || manualFlag == 1)) {
          manualControl = manualFlag == 1;
        }
        final settingsBits = _u8At(decoded, 87);
        if (settingsBits != null) {
          selfStop ??= (settingsBits & 0x02) != 0;
          // OEM baseline shows Two-stage as Open while bit2 is 0,
          // so this flag appears inverted in the packed settings byte.
          twoStageEnabled ??= (settingsBits & 0x04) == 0;
        }
        final softStart = _u8At(decoded, 88);
        if (softStartSeconds == null &&
            softStart != null &&
            softStart >= 0 &&
            softStart <= 120) {
          softStartSeconds = softStart;
        }
        if (powerLimitWatts == null) {
          final low = _u8At(decoded, 89);
          final high = _u8At(decoded, 90);
          if (low != null && high != null) {
            final watts = low | (high << 8);
            if (watts >= 100 && watts <= 50000) {
              powerLimitWatts = watts;
            }
          }
        }
        if (displayLanguage == null) {
          final lang0 = _u8At(decoded, 93);
          final lang1 = _u8At(decoded, 94);
          displayLanguage = _languageFromCode(lang0, lang1) ?? displayLanguage;
        }
      }

      if (frameType == '0x05') {
        final cmd = _asInt(decoded['cmd_id']);
        if (cmd == 0x2a && displayLanguage == null) {
          final b2 = _asInt(decoded['u8_02']);
          final b3 = _asInt(decoded['u8_03']);
          displayLanguage = _languageFromCode(b2, b3) ?? displayLanguage;
        }
      }

      if (frameType != '0x06') {
        continue;
      }
      final cmd = _asInt(decoded['cmd_id']);
      if (cmd == null) continue;
      if (seenCmd.contains(cmd)) continue;
      seenCmd.add(cmd);

      final valueU = _asInt(decoded['data32_le_u']);
      final valueF = _asDouble(decoded['data32_le_f']);

      switch (cmd) {
        case 0x07:
          outputSetVoltage = valueF;
          outputVoltage ??= valueF;
        case 0x08:
          outputSetCurrent = valueF;
          outputCurrent ??= valueF;
        case 0x0c:
          // Live-capture mapping on this firmware: 0 => Open/On, 1 => Close/Off.
          outputEnabledFrom06 ??= valueU == 0;
        case 0x0b:
          // Candidate write mapping from capture diffs:
          // 0x0b is used by Power-on output save.
          // Semantics are inverted in protocol payload: 0=>Open, 1=>Close.
          powerOnOutput ??= valueU == 0;
        case 0x14:
          selfStop = valueU == 1;
        case 0x15:
          powerOffCurrent = valueF;
        case 0x20:
          // Candidate write mapping from capture diffs:
          // 0x20 is used by Two-stage switch save.
          twoStageEnabled ??= valueU == 1;
        case 0x21:
          stage2Voltage = valueF;
        case 0x22:
          stage2Current = valueF;
        case 0x23:
          manualControl = valueU == 1;
        case 0x26:
          softStartSeconds = valueU;
        case 0x27:
          powerLimitWatts = valueU;
        case 0x2f:
          equalDistributionMode = valueU == 1;
      }
    }
    outputEnabled =
        outputEnabledFrom6905 ??
        outputEnabledFrom3006 ??
        outputEnabledFrom06 ??
        outputEnabled;

    final computedOutputPower =
        outputPowerW ??
        ((outputVoltage != null && outputCurrent != null)
            ? outputVoltage * outputCurrent
            : null);

    return ChargerTelemetryState(
      firmwareVersion: firmwareVersion,
      outputSetVoltage: outputSetVoltage,
      outputSetCurrent: outputSetCurrent,
      inputVoltage: inputVoltage,
      inputCurrent: inputCurrent,
      outputVoltage: outputVoltage,
      outputCurrent: outputCurrent,
      inputFrequencyHz: inputFrequencyHz,
      temperatureC: temperatureC,
      temperature2C: temperature2C,
      throttlingPercent: throttlingPercent,
      inputPowerW: inputPowerW,
      outputPowerW: computedOutputPower,
      stage2Voltage: stage2Voltage,
      stage2Current: stage2Current,
      powerOffCurrent: powerOffCurrent,
      powerLimitWatts: powerLimitWatts,
      softStartSeconds: softStartSeconds,
      outputEnabled: outputEnabled,
      manualControl: manualControl,
      twoStageEnabled: twoStageEnabled,
      powerOnOutput: powerOnOutput,
      selfStop: selfStop,
      equalDistributionMode: equalDistributionMode,
      displayLanguage: displayLanguage,
      lastRxAt: rxLogs.first.timestamp,
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  static int? _u8At(Map<String, dynamic> decoded, int index) {
    final key = 'u8_${index.toString().padLeft(2, '0')}';
    return _asInt(decoded[key]);
  }

  static double? _f32At(Map<String, dynamic> decoded, int offset) {
    final key = 'f32le_off_${offset.toString().padLeft(2, '0')}';
    return _asDouble(decoded[key]);
  }

  static double? _bounded(
    double? value, {
    required double min,
    required double max,
  }) {
    if (value == null) return null;
    if (!value.isFinite) return null;
    if (value < min || value > max) return null;
    return value;
  }

  static String? _parseAscii(
    Map<String, dynamic> decoded, {
    required int start,
    required int maxBytes,
  }) {
    final bytes = <int>[];
    for (var i = 0; i < maxBytes; i++) {
      final value = _u8At(decoded, start + i);
      if (value == null) break;
      if (value == 0) break;
      if (value < 0x20 || value > 0x7e) break;
      bytes.add(value);
    }
    if (bytes.isEmpty) return null;
    return String.fromCharCodes(bytes);
  }

  static String? _languageFromCode(int? b0, int? b1) {
    if (b0 == 0x65 && b1 == 0x6e) return 'English';
    if (b0 == 0x7a && b1 == 0x68) return 'Chinese (Simplified)';
    if (b0 == 0x7a && b1 == 0x74) return 'Chinese (Traditional)';
    return null;
  }
}
