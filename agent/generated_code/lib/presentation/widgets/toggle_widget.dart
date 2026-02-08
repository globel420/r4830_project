import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ble_definitions.dart';
import '../../services/ble_controller_service.dart';

class ToggleWidget extends ConsumerWidget {
  final UiItem item;
  const ToggleWidget({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      title: Text(item.label),
      value: false, // This needs to be connected to the device state
      onChanged: (bool value) {
        final commandKey = value ? item.onCommand : item.offCommand;
        if (commandKey != null) {
          ref.read(bleControllerServiceProvider).sendCommand(commandKey);
        }
      },
    );
  }
}
