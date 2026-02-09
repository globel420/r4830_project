import 'package:flutter_test/flutter_test.dart';

import 'package:r4830_controller/live/ble_codec.dart';
import 'package:r4830_controller/live/ble_controller.dart';
import 'package:r4830_controller/live/charger_telemetry.dart';

void main() {
  test('extracts latest values from decoded RX logs', () {
    final logs = [
      BleLogEntry(
        timestamp: DateTime.parse('2026-02-07T12:00:00Z'),
        direction: 'RX',
        hex: '0621000016437a',
        decoded: {
          'frame_type': '0x06',
          'cmd_id': 0x21,
          'data32_le_f': 150.0,
          'data32_le_u': 1125515264,
        },
      ),
      BleLogEntry(
        timestamp: DateTime.parse('2026-02-07T12:00:01Z'),
        direction: 'RX',
        hex: '06220000003f61',
        decoded: {
          'frame_type': '0x06',
          'cmd_id': 0x22,
          'data32_le_f': 0.5,
          'data32_le_u': 1056964608,
        },
      ),
      BleLogEntry(
        timestamp: DateTime.parse('2026-02-07T12:00:02Z'),
        direction: 'RX',
        hex: '060c010000000d',
        decoded: {'frame_type': '0x06', 'cmd_id': 0x0c, 'data32_le_u': 1},
      ),
      BleLogEntry(
        timestamp: DateTime.parse('2026-02-07T12:00:03Z'),
        direction: 'RX',
        hex: '052a656e00fd',
        decoded: {
          'frame_type': '0x05',
          'cmd_id': 0x2a,
          'u8_02': 0x65,
          'u8_03': 0x6e,
        },
      ),
    ];

    final telemetry = ChargerTelemetryState.fromLogs(logs);

    expect(telemetry.stage2Voltage, 150.0);
    expect(telemetry.stage2Current, 0.5);
    expect(telemetry.outputEnabled, false);
    expect(telemetry.displayLanguage, 'English');
  });

  test('decodes traditional Chinese display language from frame05', () {
    final logs = [
      BleLogEntry(
        timestamp: DateTime.parse('2026-02-07T12:01:00Z'),
        direction: 'RX',
        hex: '052a7a740018',
        decoded: {
          'frame_type': '0x05',
          'cmd_id': 0x2a,
          'u8_02': 0x7a,
          'u8_03': 0x74,
        },
      ),
    ];

    final telemetry = ChargerTelemetryState.fromLogs(logs);
    expect(telemetry.displayLanguage, 'Chinese (Traditional)');
  });

  test('extracts telemetry from long OEM 3006/6905 frames', () {
    BleLogEntry rxEntry(DateTime ts, String hex) {
      final bytes = hexToBytes(hex)!;
      return BleLogEntry(
        timestamp: ts,
        direction: 'RX',
        hex: hex,
        decoded: decodePayload(bytes),
      );
    }

    final logs = [
      rxEntry(
        DateTime.parse('2026-02-07T12:00:03Z'),
        '0b017470735f322e312e34aa',
      ),
      rxEntry(
        DateTime.parse('2026-02-07T12:00:02Z'),
        '300600a0f5420000000000c26f4200808d410000a0414e5d604000000000000000000000000001d14800397cfbe03b01b0',
      ),
      rxEntry(
        DateTime.parse('2026-02-07T12:00:01Z'),
        '6905000015430000003f000022430000204100af304440860843400000803f0000803f0000324300009041009a99993e014b0150233743686172676546617374000000000000000000000000000100001643cdcc4c3f010308dc05c4097a682d484b000000000000004d',
      ),
    ];

    final telemetry = ChargerTelemetryState.fromLogs(logs);

    expect(telemetry.firmwareVersion, 'tps_2.1.4');
    expect(telemetry.inputVoltage, closeTo(122.8, 0.2));
    expect(telemetry.inputFrequencyHz, closeTo(59.9, 0.2));
    expect(telemetry.outputVoltage, closeTo(3.5, 0.05));
    expect(telemetry.outputCurrent, closeTo(0.0, 0.05));
    expect(telemetry.chargeStatRawA, 3735624);
    expect(telemetry.chargeStatRawB, 14744444);
    expect(telemetry.outputSetVoltage, closeTo(149.0, 0.1));
    expect(telemetry.outputSetCurrent, closeTo(0.5, 0.05));
    expect(telemetry.stage2Voltage, closeTo(150.0, 0.1));
    expect(telemetry.stage2Current, closeTo(0.8, 0.05));
    expect(telemetry.powerOffCurrent, closeTo(0.3, 0.05));
    expect(telemetry.powerLimitWatts, 1500);
    expect(telemetry.outputEnabled, true);
    expect(telemetry.manualControl, true);
    expect(telemetry.powerOnOutput, true);
    expect(telemetry.twoStageEnabled, true);
    expect(telemetry.selfStop, true);
    expect(telemetry.softStartSeconds, 8);
  });

  test('maps power-on output from 6905 byte 18 polarity', () {
    BleLogEntry entryFromBytes(DateTime ts, List<int> bytes) {
      return BleLogEntry(
        timestamp: ts,
        direction: 'RX',
        hex: bytesToHex(bytes),
        decoded: decodePayload(bytes),
      );
    }

    final base = hexToBytes(
      '6905000015430000003f000022430000204100af304440860843400000803f0000803f0000324300009041009a99993e014b0150233743686172676546617374000000000000000000000000000100001643cdcc4c3f010308dc05c4097a682d484b000000000000004d',
    )!;
    expect(base.length, 106);

    final openBytes = List<int>.from(base);
    openBytes[18] = 0;
    final closeBytes = List<int>.from(base);
    closeBytes[18] = 1;

    final openTelemetry = ChargerTelemetryState.fromLogs([
      entryFromBytes(DateTime.parse('2026-02-07T12:10:00Z'), openBytes),
    ]);
    final closeTelemetry = ChargerTelemetryState.fromLogs([
      entryFromBytes(DateTime.parse('2026-02-07T12:10:01Z'), closeBytes),
    ]);

    expect(openTelemetry.powerOnOutput, true);
    expect(closeTelemetry.powerOnOutput, false);
  });

  test('maps cmd 0x0b and 0x20 as power-on output and two-stage fallback', () {
    final logs = [
      BleLogEntry(
        timestamp: DateTime.parse('2026-02-07T12:20:00Z'),
        direction: 'RX',
        hex: '060b000000000b',
        decoded: {'frame_type': '0x06', 'cmd_id': 0x0b, 'data32_le_u': 0},
      ),
      BleLogEntry(
        timestamp: DateTime.parse('2026-02-07T12:20:01Z'),
        direction: 'RX',
        hex: '06200000000020',
        decoded: {'frame_type': '0x06', 'cmd_id': 0x20, 'data32_le_u': 0},
      ),
    ];

    final telemetry = ChargerTelemetryState.fromLogs(logs);
    expect(telemetry.powerOnOutput, true);
    expect(telemetry.twoStageEnabled, false);
  });

  test('maps cmd 0x27 as power limit watts', () {
    final logs = [
      BleLogEntry(
        timestamp: DateTime.parse('2026-02-07T12:30:00Z'),
        direction: 'RX',
        hex: '0627dc05000008',
        decoded: {'frame_type': '0x06', 'cmd_id': 0x27, 'data32_le_u': 1500},
      ),
    ];

    final telemetry = ChargerTelemetryState.fromLogs(logs);
    expect(telemetry.powerLimitWatts, 1500);
  });

  test('extracts charge statistics raw counters from 9-byte tail frames', () {
    final logs = [
      BleLogEntry(
        timestamp: DateTime.parse('2026-02-07T12:35:00Z'),
        direction: 'RX',
        hex: '0000000000000001b2',
        decoded: {
          'len': 9,
          'pkt_prefix': '0000',
          'u8_00': 0,
          'u8_01': 0,
          'u8_02': 0,
          'u8_03': 0,
          'u8_04': 0,
          'u8_05': 0,
          'u8_06': 0,
          'u8_07': 1,
          'u8_08': 0xb2,
        },
      ),
    ];

    final telemetry = ChargerTelemetryState.fromLogs(logs);
    expect(telemetry.chargeStatRawA, 0);
    expect(telemetry.chargeStatRawB, 0);
  });
}
