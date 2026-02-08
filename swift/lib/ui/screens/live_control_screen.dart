import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../../live/ble_controller.dart';
import '../../live/payload_registry.dart';

class LiveControlScreen extends StatefulWidget {
  const LiveControlScreen({super.key});

  @override
  State<LiveControlScreen> createState() => _LiveControlScreenState();
}

class _LiveControlScreenState extends State<LiveControlScreen> {
  late BleController _controller;
  bool _boundController = false;
  late final Future<PayloadRegistry> _registryFuture;
  final TextEditingController _rawHexController = TextEditingController();
  final TextEditingController _keepaliveController = TextEditingController(
    text: '1.0',
  );

  @override
  void initState() {
    super.initState();
    _registryFuture = PayloadRegistry.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_boundController) {
      _controller = context.read<BleController>();
      _boundController = true;
    }
  }

  @override
  void dispose() {
    _rawHexController.dispose();
    _keepaliveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live BLE Control')),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final connected =
              _controller.connectionState == BluetoothConnectionState.connected;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _buildAdapterCard(),
              const SizedBox(height: 12),
              _buildScanCard(),
              const SizedBox(height: 12),
              _buildConnectionCard(connected),
              if (connected) ...[
                const SizedBox(height: 12),
                _buildCharacteristicsCard(),
                const SizedBox(height: 12),
                _buildKeepaliveCard(),
                const SizedBox(height: 12),
                _buildCommandsCard(),
              ],
              const SizedBox(height: 12),
              _buildLogsCard(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdapterCard() {
    return Card(
      child: ListTile(
        title: const Text('Adapter'),
        subtitle: Text('State: ${_controller.adapterState.name}'),
        trailing: _controller.lastError == null
            ? null
            : Tooltip(
                message: _controller.lastError!,
                child: const Icon(Icons.warning, color: Colors.orange),
              ),
      ),
    );
  }

  Widget _buildScanCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Scan', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: _controller.isScanning
                      ? _controller.stopScan
                      : _controller.startScan,
                  child: Text(_controller.isScanning ? 'Stop' : 'Start'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: _controller.scanResults.isEmpty
                  ? const Center(child: Text('No devices found yet.'))
                  : ListView.builder(
                      itemCount: _controller.scanResults.length,
                      itemBuilder: (context, index) {
                        final result = _controller.scanResults[index];
                        final name = result.advertisementData.advName.isNotEmpty
                            ? result.advertisementData.advName
                            : result.device.platformName.isNotEmpty
                            ? result.device.platformName
                            : 'Unknown';
                        return ListTile(
                          title: Text(name),
                          subtitle: Text(result.device.remoteId.str),
                          trailing: Text('RSSI ${result.rssi}'),
                          onTap: () => _controller.connect(result.device),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard(bool connected) {
    final device = _controller.device;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Connection',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (connected)
                  FilledButton.tonal(
                    onPressed: _controller.disconnect,
                    child: const Text('Disconnect'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('State: ${_controller.connectionState.name}'),
            const SizedBox(height: 4),
            Text('Device: ${device?.remoteId.str ?? '-'}'),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: connected ? _controller.discoverServices : null,
              child: const Text('Discover Services'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacteristicsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Characteristics',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Notify candidates: ${_controller.notifyChars.length}'),
            const SizedBox(height: 4),
            _buildCharacteristicDropdown(
              label: 'RX (notify/indicate)',
              value: _controller.rxChar,
              items: _controller.notifyChars,
              onChanged: _controller.selectRxChar,
            ),
            const SizedBox(height: 8),
            Text('Write candidates: ${_controller.writeChars.length}'),
            const SizedBox(height: 4),
            _buildCharacteristicDropdown(
              label: 'TX (write)',
              value: _controller.txChar,
              items: _controller.writeChars,
              onChanged: _controller.selectTxChar,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: _controller.isSubscribed
                      ? _controller.unsubscribeRx
                      : _controller.subscribeRx,
                  child: Text(
                    _controller.isSubscribed
                        ? 'Unsubscribe RX'
                        : 'Subscribe RX',
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _controller.isSubscribed ? 'Subscribed' : 'Not subscribed',
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _controller.quickStart,
                  child: const Text('Quick Start'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacteristicDropdown({
    required String label,
    required BluetoothCharacteristic? value,
    required List<BluetoothCharacteristic> items,
    required ValueChanged<BluetoothCharacteristic?> onChanged,
  }) {
    final safeValue = (value != null && items.contains(value)) ? value : null;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<BluetoothCharacteristic>(
          isExpanded: true,
          value: safeValue,
          hint: const Text('Select characteristic'),
          items: items
              .map(
                (chr) => DropdownMenuItem(
                  value: chr,
                  child: Text(_characteristicLabel(chr)),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildKeepaliveCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Keepalive', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _keepaliveController,
                    decoration: const InputDecoration(
                      labelText: 'Seconds',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onSubmitted: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null) {
                        _controller.setKeepaliveSeconds(parsed);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _controller.keepaliveEnabled
                      ? _controller.stopKeepalive
                      : _controller.startKeepalive,
                  child: Text(_controller.keepaliveEnabled ? 'Stop' : 'Start'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => _controller.sendHex(
                    '020606',
                    preferWithoutResponse: true,
                  ),
                  child: const Text('Send Once'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<PayloadRegistry>(
          future: _registryFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Text('Loading payload registry...');
            }
            final registry = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payload Registry',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text('Short frames (observed; replay only).'),
                const SizedBox(height: 6),
                _payloadWrap(registry.shortFrames),
                const SizedBox(height: 16),
                const Text(
                  '0x06 frames (observed; checksum applied; no semantics).',
                ),
                const SizedBox(height: 6),
                _payloadWrap(registry.frame06),
                const SizedBox(height: 16),
                const Text(
                  '0x05 frames (observed; checksum applied; no semantics).',
                ),
                const SizedBox(height: 6),
                _payloadWrap(registry.frame05),
                const SizedBox(height: 16),
                const Text('Raw payloads (opaque; replay only).'),
                const SizedBox(height: 6),
                _payloadWrap(registry.raw),
                const SizedBox(height: 16),
                Text(
                  'Raw Hex (TBD)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rawHexController,
                        decoration: const InputDecoration(
                          labelText: 'Hex payload',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: () => _controller.sendHex(
                        _rawHexController.text,
                        preferWithoutResponse: true,
                      ),
                      child: const Text('Send'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLogsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Logs', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: _controller.rotateLogFile,
                  child: const Text('New File'),
                ),
                TextButton(
                  onPressed: _controller.clearLogs,
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: _pickLogDirectory,
                  child: const Text('Pick Log Folder'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _useProjectLogDirectory,
                  child: const Text('Use Project Logs'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Log dir: ${_controller.logDirectory ?? "not set"}'),
            Text('Log file: ${_controller.logFilePath ?? "not set"}'),
            Text('JSONL: ${_controller.logJsonlPath ?? "not set"}'),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: _controller.logs.isEmpty
                  ? const Center(child: Text('No logs yet.'))
                  : ListView.builder(
                      itemCount: _controller.logs.length,
                      itemBuilder: (context, index) {
                        final entry = _controller.logs[index];
                        return ListTile(
                          dense: true,
                          title: Text('${entry.direction} ${entry.hex}'),
                          subtitle: Text(
                            '${entry.timestamp.toIso8601String()}  ${_logSummary(entry)}',
                          ),
                          onTap: () => _showLogInspector(entry),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _characteristicLabel(BluetoothCharacteristic chr) {
    final props = chr.properties;
    final flags = <String>[];
    if (props.notify) flags.add('notify');
    if (props.indicate) flags.add('indicate');
    if (props.write) flags.add('write');
    if (props.writeWithoutResponse) flags.add('writeNoRsp');
    final flagText = flags.isEmpty ? 'no-props' : flags.join(',');
    return '${chr.serviceUuid.str} / ${chr.characteristicUuid.str} ($flagText)';
  }

  Widget _payloadWrap(List<PayloadEntry> entries) {
    if (entries.isEmpty) {
      return const Text('None.');
    }
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: entries.map(_payloadButton).toList(),
    );
  }

  Widget _payloadButton(PayloadEntry entry) {
    final bytes = entry.buildBytes();
    return OutlinedButton(
      onPressed: bytes == null
          ? null
          : () => _controller.sendBytes(
              bytes,
              preferWithoutResponse: true,
              note: entry.notes ?? entry.id,
            ),
      child: Text(entry.displayLabel()),
    );
  }

  String _logSummary(BleLogEntry entry) {
    final decoded = entry.decoded;
    final prefix = decoded['pkt_prefix'];
    final len = decoded['len'];
    final frameType = decoded['frame_type'];
    if (frameType != null) {
      final note = entry.note == null ? '' : ' ${entry.note}';
      return 'frame $frameType cmd ${decoded['cmd_id']} checksum_ok ${decoded['checksum_ok']}$note';
    }
    if (prefix != null && len != null) {
      final note = entry.note == null ? '' : ' ${entry.note}';
      return 'pkt $prefix len $len$note';
    }
    return entry.note ?? '';
  }

  Future<void> _pickLogDirectory() async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    await _controller.setLogDirectory(dir);
  }

  Future<void> _useProjectLogDirectory() async {
    const path = '/Users/globel/r4830_project/swift/logs';
    await _controller.setLogDirectory(path);
  }

  Future<void> _showLogInspector(BleLogEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Log ${entry.direction}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('hex', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  SelectableText(entry.hex),
                  const SizedBox(height: 12),
                  Text(
                    'decoded',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(_prettyDecoded(entry.decoded)),
                ],
              ),
            ),
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

  String _prettyDecoded(Map<String, dynamic> decoded) {
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }
}
