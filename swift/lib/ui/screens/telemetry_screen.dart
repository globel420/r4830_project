import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../live/ble_controller.dart';
import '../../live/charger_telemetry.dart';

class TelemetryScreen extends StatelessWidget {
  const TelemetryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BleController>();
    final rxLogs = controller.rxLogs;
    final cmdMetrics = _extractLatestCmdMetrics(rxLogs);
    final telemetry = ChargerTelemetryState.fromLogs(rxLogs);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Telemetry'),
        actions: [
          IconButton(
            onPressed: controller.clearLogs,
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _statusCard(controller, rxLogs.length),
          const SizedBox(height: 12),
          _oemTelemetryCard(telemetry),
          const SizedBox(height: 12),
          _latestMetricsCard(cmdMetrics),
          const SizedBox(height: 12),
          _recentRxCard(context, rxLogs),
        ],
      ),
    );
  }

  Widget _statusCard(BleController controller, int rxCount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _statusItem('Connection', controller.connectionState.name),
            _statusItem('Subscribed', controller.isSubscribed ? 'yes' : 'no'),
            _statusItem('RX Frames', '$rxCount'),
            _statusItem(
              'Keepalive',
              controller.keepaliveEnabled ? 'on' : 'off',
            ),
            _statusItem(
              'RX Char',
              controller.rxChar?.characteristicUuid.str ?? 'not selected',
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusItem(String label, String value) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _latestMetricsCard(List<_CmdMetric> metrics) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Latest Decoded 0x06 RX Metrics',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (metrics.isEmpty)
              const Text(
                'No decodable 0x06 telemetry frames yet. Connect + subscribe in Live tab.',
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: metrics
                    .map(
                      (metric) => Container(
                        width: 220,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'cmd 0x${metric.cmdId.toRadixString(16).padLeft(2, '0')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(metric.valueText),
                            if (metric.boolCandidate != null)
                              Text('bool? ${metric.boolCandidate}'),
                            const SizedBox(height: 4),
                            Text(
                              metric.timestampIso,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _oemTelemetryCard(ChargerTelemetryState telemetry) {
    Widget cell(String label, String value) {
      return SizedBox(
        width: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    String numFmt(double? value, String unit) {
      if (value == null) return '--';
      return '${value.toStringAsFixed(value.abs() >= 100 ? 1 : 2)}$unit';
    }

    String boolFmt(bool? value) {
      if (value == null) return '--';
      return value ? 'Open' : 'Close';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OEM Field Feed (Live)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 10,
              children: [
                cell('Output voltage', numFmt(telemetry.outputVoltage, 'V')),
                cell('Output current', numFmt(telemetry.outputCurrent, 'A')),
                cell('Output power', numFmt(telemetry.outputPowerW, 'W')),
                cell('Stage2 voltage', numFmt(telemetry.stage2Voltage, 'V')),
                cell('Stage2 current', numFmt(telemetry.stage2Current, 'A')),
                cell(
                  'Power-off current',
                  numFmt(telemetry.powerOffCurrent, 'A'),
                ),
                cell(
                  'Soft start',
                  telemetry.softStartSeconds == null
                      ? '--'
                      : '${telemetry.softStartSeconds}s',
                ),
                cell('Output enable', boolFmt(telemetry.outputEnabled)),
                cell('Manual control', boolFmt(telemetry.manualControl)),
                cell('Two-stage', boolFmt(telemetry.twoStageEnabled)),
                cell(
                  'Strategy',
                  telemetry.equalDistributionMode == null
                      ? '--'
                      : telemetry.equalDistributionMode!
                      ? 'Balanced (Equal Distribution)'
                      : 'Adaptive (Intelligent)',
                ),
                cell('Language', telemetry.displayLanguage ?? '--'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentRxCard(BuildContext context, List<BleLogEntry> rxLogs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent RX Frames',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (rxLogs.isEmpty)
              const Text('No RX frames yet.')
            else
              SizedBox(
                height: 420,
                child: ListView.builder(
                  itemCount: rxLogs.length > 120 ? 120 : rxLogs.length,
                  itemBuilder: (context, index) {
                    final entry = rxLogs[index];
                    final summary = _rxSummary(entry.decoded);
                    return ListTile(
                      dense: true,
                      title: Text(entry.hex),
                      subtitle: Text(
                        '${entry.timestamp.toIso8601String()}  $summary',
                      ),
                      onTap: () => _showDecodedDialog(context, entry),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _rxSummary(Map<String, dynamic> decoded) {
    final frameType = decoded['frame_type'];
    if (frameType == '0x06') {
      return 'cmd ${decoded['cmd_id']} f32 ${decoded['data32_le_f']}';
    }
    if (frameType == '0x03_ack') {
      return 'ack cmd ${decoded['cmd_id']} ok ${decoded['ack_ok']}';
    }
    final prefix = decoded['pkt_prefix'];
    final len = decoded['len'];
    return 'pkt $prefix len $len';
  }

  Future<void> _showDecodedDialog(
    BuildContext context,
    BleLogEntry entry,
  ) async {
    final pretty = const JsonEncoder.withIndent('  ').convert(entry.decoded);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('RX frame'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(child: SelectableText(pretty)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  List<_CmdMetric> _extractLatestCmdMetrics(List<BleLogEntry> rxLogs) {
    final seen = <int>{};
    final out = <_CmdMetric>[];
    for (final entry in rxLogs) {
      final decoded = entry.decoded;
      if (decoded['frame_type'] != '0x06') continue;
      final cmd = decoded['cmd_id'];
      if (cmd is! int) continue;
      if (seen.contains(cmd)) continue;
      seen.add(cmd);
      out.add(
        _CmdMetric(
          cmdId: cmd,
          valueText:
              'u32 ${decoded['data32_le_u']} | f32 ${decoded['data32_le_f']}',
          boolCandidate: decoded['data32_bool_candidate'] as bool?,
          timestampIso: entry.timestamp.toIso8601String(),
        ),
      );
      if (out.length >= 18) break;
    }
    out.sort((a, b) => a.cmdId.compareTo(b.cmdId));
    return out;
  }
}

class _CmdMetric {
  _CmdMetric({
    required this.cmdId,
    required this.valueText,
    required this.boolCandidate,
    required this.timestampIso,
  });

  final int cmdId;
  final String valueText;
  final bool? boolCandidate;
  final String timestampIso;
}
