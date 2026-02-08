import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ble_definitions.dart';
import '../../services/ble_controller_service.dart';

class SelectorWidget extends ConsumerWidget {
  final UiItem item;
  const SelectorWidget({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(item.label),
      trailing: DropdownButton<String>(
        items: item.values?.map((v) {
          return DropdownMenuItem<String>(
            value: v.command,
            child: Text(v.label),
          );
        }).toList(),
        onChanged: (String? commandKey) {
          if (commandKey != null) {
            ref.read(bleControllerServiceProvider).sendCommand(commandKey);
          }
        },
      ),
    );
  }
}
