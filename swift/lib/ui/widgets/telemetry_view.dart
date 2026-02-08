import 'package:flutter/material.dart';
import 'package:r4830_controller/data/att_event.dart';

class TelemetryView extends StatelessWidget {
  const TelemetryView({super.key, required this.events});

  final List<AttEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(child: Text('No telemetry events yet'));
    }

    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('T+${event.ts}: '),
              Expanded(
                child: Text(
                  event.valueHex,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
