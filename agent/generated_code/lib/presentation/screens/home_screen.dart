import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../services/ble_controller_service.dart';
import 'device_control_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanResults = ref.watch(scanResultsProvider);
    final isScanning = ref.watch(isScanningProvider);
    final connectionState = ref.watch(connectionStateProvider);

    ref.listen(connectionStateProvider, (previous, next) {
      if (next.asData?.value == BluetoothConnectionState.connected) {
        Navigator.of(context).push(MaterialPageRoute(builder: (context) => const DeviceControlScreen()));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('ChargeFast Controller'),
        actions: [
          isScanning.when(
            data: (scanning) => scanning
                ? IconButton(
                    icon: const Icon(Icons.stop),
                    onPressed: () => ref.read(bleControllerServiceProvider).stopScan(),
                  )
                : IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => ref.read(bleControllerServiceProvider).startScan(),
                  ),
            loading: () => const CircularProgressIndicator(),
            error: (err, stack) => const Icon(Icons.error),
          ),
        ],
      ),
      body: connectionState.when(
        data: (state) {
          if (state == BluetoothConnectionState.connected) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Connected!'),
                  ElevatedButton(
                    onPressed: () => ref.read(bleControllerServiceProvider).disconnect(),
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            );
          }
          return scanResults.when(
            data: (results) => ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                return ListTile(
                  title: Text(result.device.platformName.isNotEmpty
                      ? result.device.platformName
                      : 'Unknown Device'),
                  subtitle: Text(result.device.remoteId.toString()),
                  trailing: Text('${result.rssi} dBm'),
                  onTap: () => ref.read(bleControllerServiceProvider).connect(result.device),
                );
              },
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      )
    );
  }
}
