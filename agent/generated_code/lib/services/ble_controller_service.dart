import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ble_definitions_service.dart';
import '../models/ble_definitions.dart';

class BleControllerService {
  final Ref _ref;
  BleDefinitions? _definitions;

  BleControllerService(this._ref) {
    _ref.listen(bleDefinitionsProvider, (previous, next) {
      if (next.hasValue) {
        _definitions = next.value;
      }
    });
  }

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  Stream<BluetoothConnectionState> get connectionStateStream =>
      _connectedDevice?.connectionState ?? Stream.value(BluetoothConnectionState.disconnected);
  
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;
  Timer? _keepaliveTimer;

  final _telemetryStreamController = StreamController<List<int>>.broadcast();
  Stream<List<int>> get telemetryStream => _telemetryStreamController.stream;


  Future<void> startScan() async {
    if (_definitions == null) {
      _definitions = await _ref.read(bleDefinitionsProvider.future);
    }
    
    List<Guid> serviceGuids = _definitions!.transport.serviceUuids.map((e) => Guid(e)).toList();

    await FlutterBluePlus.startScan(
        withServices: serviceGuids,
    );
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Future<void> connect(BluetoothDevice device) async {
    await device.connect();
    _connectedDevice = device;
    _ref.read(connectedDeviceProvider.notifier).state = device;
    await _discoverServices();
  }

  Future<void> disconnect() async {
    await _stopKeepalive();
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    _ref.read(connectedDeviceProvider.notifier).state = null;
  }

  Future<void> _discoverServices() async {
    if (_connectedDevice == null || _definitions == null) return;
    
    List<BluetoothService> services = await _connectedDevice!.discoverServices();
    
    for (var service in services) {
      for (var char in service.characteristics) {
        if (char.uuid == Guid(_definitions!.transport.tx.uuid)) {
          _txCharacteristic = char;
        }
        if (char.uuid == Guid(_definitions!.transport.rx.uuid)) {
          _rxCharacteristic = char;
        }
      }
    }

    if (_txCharacteristic != null) {
      await _startKeepalive();
    }
    if (_rxCharacteristic != null) {
      await _subscribeToTelemetry();
    }
  }

  Future<void> _subscribeToTelemetry() async {
    if (_rxCharacteristic!.properties.notify) {
      await _rxCharacteristic!.setNotifyValue(true);
      _rxCharacteristic!.value.listen((value) {
        _telemetryStreamController.add(value);
      });
    }
  }

  List<int> _hexToBytes(String hex) {
    return List<int>.generate(hex.length ~/ 2, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16));
  }

  Future<void> _startKeepalive() async {
    if (_definitions?.keepalive.enabled == true && _txCharacteristic != null) {
      final keepaliveDef = _definitions!.keepalive;
      final payload = _hexToBytes(keepaliveDef.payloadHex);
      
      _keepaliveTimer = Timer.periodic(Duration(milliseconds: keepaliveDef.intervalMs), (timer) async {
        await _txCharacteristic?.write(payload, withoutResponse: _definitions!.transport.tx.writeType == "write_without_response");
      });
    }
  }

  Future<void> _stopKeepalive() async {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
  }

  Future<void> sendCommand(String commandKey) async {
    if (_definitions == null || _txCharacteristic == null) return;

    final command = _definitions!.commands[commandKey];
    if (command != null) {
      final payload = _hexToBytes(command.payloadHex);
      await _txCharacteristic!.write(payload, withoutResponse: _definitions!.transport.tx.writeType == "write_without_response");
    }
  }

  List<ScanResult> filterScanResults(List<ScanResult> results) {
    if (_definitions == null) return [];
    
    return results.where((result) {
      final deviceName = result.device.platformName;
      if (deviceName.isEmpty) return false;

      return _definitions!.device.nameContains.any((name) => deviceName.contains(name));
    }).toList();
  }

  void dispose() {
    _telemetryStreamController.close();
  }
}

final bleControllerServiceProvider = Provider.autoDispose<BleControllerService>((ref) {
  final service = BleControllerService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

final scanResultsProvider = StreamProvider.autoDispose<List<ScanResult>>((ref) {
  final controller = ref.watch(bleControllerServiceProvider);
  return controller.scanResults.map((results) => controller.filterScanResults(results));
});

final isScanningProvider = StreamProvider.autoDispose<bool>((ref) {
  return ref.watch(bleControllerServiceProvider).isScanning;
});

final connectionStateProvider = StreamProvider.autoDispose<BluetoothConnectionState>((ref) {
  final controller = ref.watch(bleControllerServiceProvider);
  return controller.connectionStateStream;
});

final connectedDeviceProvider = StateProvider.autoDispose<BluetoothDevice?>((ref) {
  return ref.watch(bleControllerServiceProvider).connectedDevice;
});

final telemetryProvider = StreamProvider.autoDispose<List<int>>((ref) {
  return ref.watch(bleControllerServiceProvider).telemetryStream;
});
