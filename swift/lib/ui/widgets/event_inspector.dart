import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/att_event.dart';

Future<void> showEventInspector(BuildContext context, AttEvent event) async {
  await showDialog<void>(
    context: context,
    builder: (context) => EventInspectorDialog(event: event),
  );
}

class EventInspectorDialog extends StatelessWidget {
  const EventInspectorDialog({super.key, required this.event});

  final AttEvent event;

  void _copy(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Event #${event.index}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('value_hex', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              SelectableText(event.valueHex),
              const SizedBox(height: 8),
              Text('raw_hex', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              SelectableText(event.rawHex),
              const SizedBox(height: 12),
              Text('raw JSON', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              SelectableText(event.prettyJson()),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _copy(context, 'value_hex', event.valueHex),
          child: const Text('Copy value_hex'),
        ),
        TextButton(
          onPressed: () => _copy(context, 'raw_hex', event.rawHex),
          child: const Text('Copy raw_hex'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
