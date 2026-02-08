import 'package:flutter/material.dart';

import '../../data/capture_repository.dart';
import '../../domain/replay_controller.dart';
import '../widgets/event_list.dart';
import '../widgets/replay_controls.dart';

class SessionViewerScreen extends StatefulWidget {
  const SessionViewerScreen({super.key, required this.capture});

  final CaptureInfo capture;

  @override
  State<SessionViewerScreen> createState() => _SessionViewerScreenState();
}

class _SessionViewerScreenState extends State<SessionViewerScreen>
    with SingleTickerProviderStateMixin {
  late final ReplayController _controller;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _controller = ReplayController();
    _tabController = TabController(length: 2, vsync: this);
    _controller.loadCapture(widget.capture.jsonlPath);
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Replay: ${widget.capture.name}'),
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final telemetryAll = _controller.filteredEvents(
            telemetry: true,
            playedOnly: false,
          );
          final commandAll = _controller.filteredEvents(
            telemetry: false,
            playedOnly: false,
          );
          final telemetryPlayed = _controller.filteredEvents(telemetry: true);
          final commandPlayed = _controller.filteredEvents(telemetry: false);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('File: ${widget.capture.jsonlPath}'),
                    const SizedBox(height: 4),
                    Text(
                      'Events: ${_controller.events.length} (total lines ${_controller.totalLines}, invalid ${_controller.invalidLines})',
                    ),
                    const SizedBox(height: 8),
                    ReplayControls(controller: _controller),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: 'Telemetry ${telemetryPlayed.length}/${telemetryAll.length}'),
                  Tab(text: 'Commands ${commandPlayed.length}/${commandAll.length}'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    EventList(events: telemetryPlayed, firstTs: _controller.firstTs),
                    EventList(events: commandPlayed, firstTs: _controller.firstTs),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
