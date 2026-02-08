import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/ble_definitions_service.dart';
import '../widgets/toggle_widget.dart';
import '../widgets/selector_widget.dart';

class DeviceControlScreen extends ConsumerWidget {
  const DeviceControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final definitions = ref.watch(bleDefinitionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Control'),
      ),
      body: definitions.when(
        data: (def) {
          final uiGroups = def.ui.groups..sort((a, b) => a.order.compareTo(b.order));

          return ListView.builder(
            itemCount: uiGroups.length,
            itemBuilder: (context, index) {
              final group = uiGroups[index];
              return Card(
                margin: const EdgeInsets.all(8.0),
                child: ExpansionTile(
                  title: Text(group.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                  children: group.items.map((item) {
                    if (item.type == 'toggle') {
                      return ToggleWidget(item: item);
                    }
                    if (item.type == 'selector') {
                      return SelectorWidget(item: item);
                    }
                    return Text('Unknown widget type: ${item.type}');
                  }).toList(),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
