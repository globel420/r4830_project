import 'package:flutter_test/flutter_test.dart';

import 'package:r4830_controller/live/oem_command_mapper.dart';

void main() {
  test('manual control mappings match observed payloads', () {
    final open = OemCommandMapper.manualControl(true);
    final close = OemCommandMapper.manualControl(false);
    expect(open.payloadHex, '06230100000024');
    expect(close.payloadHex, '06230000000023');
    expect(open.confidence, CommandConfidence.verified);
  });

  test('output open/close mapping matches observed payload', () {
    final open = OemCommandMapper.outputOpen();
    final close = OemCommandMapper.outputClose();
    expect(open.payloadHex, '060c000000000c');
    expect(close.payloadHex, '060c010000000d');
    expect(open.confidence, CommandConfidence.verified);
  });

  test(
    'power-on output / self-stop / two-stage mappings are encoded correctly',
    () {
      final powerOn = OemCommandMapper.powerOnOutput(true);
      final selfStop = OemCommandMapper.selfStop(false);
      expect(powerOn.payloadHex, '060b000000000b');
      expect(selfStop.payloadHex, '06140000000014');
      final twoStage = OemCommandMapper.twoStageSwitch(true);
      expect(twoStage.payloadHex, '06200100000021');
      expect(powerOn.confidence, CommandConfidence.candidate);
      expect(selfStop.confidence, CommandConfidence.verified);
      expect(twoStage.confidence, CommandConfidence.verified);
    },
  );

  test('second-stage voltage and current frames are encoded correctly', () {
    final voltage = OemCommandMapper.secondStageVoltage(150.0);
    final current = OemCommandMapper.secondStageCurrent(0.5);
    expect(voltage.payloadHex, '0621000016437a');
    expect(current.payloadHex, '06220000003f61');
  });

  test('power-off current and soft start mappings are encoded correctly', () {
    final powerOff = OemCommandMapper.powerOffCurrent(0.3);
    final softStart = OemCommandMapper.softStartSeconds(8);
    expect(powerOff.payloadHex, '06159a99993e1f');
    expect(softStart.payloadHex, '0626080000002e');
  });

  test('charging statistics zero mapping is encoded correctly', () {
    final zero = OemCommandMapper.chargingStatisticsZero();
    expect(zero.payloadHex, '06130000000013');
    expect(zero.confidence, CommandConfidence.candidate);
  });

  test('power limit mapping is encoded correctly', () {
    final limit = OemCommandMapper.powerLimitWatts(1500);
    expect(limit.payloadHex, '0627dc05000008');
    expect(limit.confidence, CommandConfidence.verified);
  });

  test('display language maps to expected frame05 payloads', () {
    final english = OemCommandMapper.displayLanguage('English');
    final chinese = OemCommandMapper.displayLanguage('Chinese');
    expect(english.payloadHex, '052a656e00fd');
    expect(chinese.payloadHex, '052a7a68000c');
    expect(english.confidence, CommandConfidence.candidate);
  });

  test('safety mappings encode charger name and BLE password', () {
    final rename = OemCommandMapper.renameCharger('ChargeFast');
    final password = OemCommandMapper.setBlePassword('123456');
    expect(rename.payloadHex, '0c1e4368617267654661737400f6');
    expect(password.payloadHex, '081b3132333435360050');
    expect(rename.confidence, CommandConfidence.candidate);
    expect(password.confidence, CommandConfidence.candidate);
  });
}
