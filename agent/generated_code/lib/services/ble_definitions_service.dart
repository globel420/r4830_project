import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ble_definitions.dart';

class BleDefinitionsService {
  BleDefinitions? _definitions;

  Future<void> loadDefinitions() async {
    final yamlString = await rootBundle.loadString('assets/ble_definitions.yaml');
    final dynamic yamlMap = loadYaml(yamlString);
    _definitions = BleDefinitions.fromYaml(yamlMap);
  }

  BleDefinitions get definitions {
    if (_definitions == null) {
      throw Exception("BleDefinitions not loaded. Call loadDefinitions() first.");
    }
    return _definitions!;
  }
}

final bleDefinitionsServiceProvider = Provider<BleDefinitionsService>((ref) {
  return BleDefinitionsService();
});

final bleDefinitionsProvider = FutureProvider<BleDefinitions>((ref) async {
  final service = ref.watch(bleDefinitionsServiceProvider);
  await service.loadDefinitions();
  return service.definitions;
});
