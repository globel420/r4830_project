import 'package:flutter/material.dart';

import '../../domain/replay_controller.dart';

class ReplayControls extends StatelessWidget {
  const ReplayControls({super.key, required this.controller});

  final ReplayController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.events.length;
    final current = controller.currentIndex < 0 ? 0 : controller.currentIndex + 1;
    final speeds = const [0.25, 1.0, 4.0, 10.0];

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.tonal(
          onPressed: controller.isPlaying ? controller.pause : controller.play,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
              const SizedBox(width: 6),
              Text(controller.isPlaying ? 'Pause' : 'Play'),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: controller.step,
          icon: const Icon(Icons.skip_next),
          label: const Text('Step'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Speed'),
            const SizedBox(width: 6),
            DropdownButton<double>(
              value: controller.speed,
              items: speeds
                  .map(
                    (speed) => DropdownMenuItem(
                      value: speed,
                      child: Text('${speed}x'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) controller.setSpeed(value);
              },
            ),
          ],
        ),
        Text('Progress $current / $total'),
      ],
    );
  }
}
