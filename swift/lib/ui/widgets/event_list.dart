import 'package:flutter/material.dart';

import '../../data/att_event.dart';
import 'event_inspector.dart';

class EventList extends StatelessWidget {
  const EventList({
    super.key,
    required this.events,
    required this.firstTs,
  });

  final List<AttEvent> events;
  final int? firstTs;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(child: Text('No events yet'));
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Row(
            children: [
              SizedBox(width: 110, child: Text('t+ticks')),
              SizedBox(width: 40, child: Text('dir')),
              SizedBox(width: 190, child: Text('type')),
              SizedBox(width: 70, child: Text('handle')),
              Expanded(child: Text('value_hex')),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: events.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final event = events[index];
              final rel = firstTs == null ? '?' : '${event.ts - firstTs!}';
              return InkWell(
                onTap: () => showEventInspector(context, event),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(width: 110, child: Text(rel)),
                      SizedBox(width: 40, child: Text(event.dir)),
                      SizedBox(width: 190, child: Text(event.type)),
                      SizedBox(width: 70, child: Text(event.handle?.toString() ?? '-')),
                      Expanded(
                        child: Text(
                          event.valueHex,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
