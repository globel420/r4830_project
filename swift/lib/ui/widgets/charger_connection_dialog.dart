import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../live/ble_controller.dart';

class ChargerConnectionDialog extends StatefulWidget {
  const ChargerConnectionDialog({super.key, required this.controller});

  final BleController controller;

  @override
  State<ChargerConnectionDialog> createState() =>
      _ChargerConnectionDialogState();
}

class _ChargerConnectionDialogState extends State<ChargerConnectionDialog> {
  bool _connecting = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final candidates =
              List<ScanResult>.from(widget.controller.scanResults)
                ..sort((a, b) {
                  final aScore = _looksLikeCharger(a) ? 1 : 0;
                  final bScore = _looksLikeCharger(b) ? 1 : 0;
                  if (aScore != bScore) return bScore.compareTo(aScore);
                  return b.rssi.compareTo(a.rssi);
                });

          return AlertDialog(
            title: const Text('Connect Charger'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A live charger connection is required for control mode.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: widget.controller.isScanning
                            ? widget.controller.stopScan
                            : widget.controller.startScan,
                        child: Text(
                          widget.controller.isScanning
                              ? 'Stop Scan'
                              : 'Start Scan',
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_connecting)
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                    ],
                  ),
                  if (widget.controller.lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.controller.lastError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (candidates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No charger found yet. Start scan and keep this dialog open.',
                      ),
                    )
                  else
                    SizedBox(
                      height: 280,
                      child: ListView.builder(
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final result = candidates[index];
                          final name = _displayName(result);
                          return ListTile(
                            dense: true,
                            title: Text(
                              _looksLikeCharger(result)
                                  ? '$name  (charger match)'
                                  : name,
                            ),
                            subtitle: Text(result.device.remoteId.str),
                            trailing: Text('RSSI ${result.rssi}'),
                            onTap: _connecting
                                ? null
                                : () => _connect(result.device),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: _connecting
                    ? null
                    : () async {
                        await widget.controller.stopScan();
                        await widget.controller.disconnect();
                      },
                child: const Text('Reset'),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _looksLikeCharger(ScanResult result) {
    final name = _displayName(result).toLowerCase();
    return name.contains('chargefast') ||
        name.contains('go slow') ||
        name.contains('r48');
  }

  String _displayName(ScanResult result) {
    if (result.advertisementData.advName.isNotEmpty) {
      return result.advertisementData.advName;
    }
    if (result.device.platformName.isNotEmpty) {
      return result.device.platformName;
    }
    return 'Unknown';
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() {
      _connecting = true;
    });
    try {
      await widget.controller.connect(device);
      if (!mounted) return;
      if (widget.controller.isConnected) {
        await widget.controller.quickStart();
        if (!mounted) return;
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }
}
