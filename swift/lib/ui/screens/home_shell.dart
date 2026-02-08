import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:r4830_controller/ui/screens/telemetry_screen.dart';

import '../../live/ble_controller.dart';
import 'capture_picker_screen.dart';
import 'hub_screen.dart';
import 'live_control_screen.dart';
import '../widgets/charger_connection_dialog.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.requireConnectionOnLaunch = true});

  final bool requireConnectionOnLaunch;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _connectionDialogShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLaunchConnectionDialog();
  }

  void _goTo(int value) {
    setState(() {
      _index = value;
    });
  }

  void _ensureLaunchConnectionDialog() {
    if (!widget.requireConnectionOnLaunch) return;
    if (_connectionDialogShown) return;
    final controller = context.read<BleController>();
    if (controller.isConnected) return;
    _connectionDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ChargerConnectionDialog(controller: controller),
      );
      if (!mounted) return;
      _connectionDialogShown = false;
      if (!controller.isConnected) {
        _ensureLaunchConnectionDialog();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HubScreen(
        onOpenReplay: () => _goTo(1),
        onOpenLive: () => _goTo(2),
        onOpenTelemetry: () => _goTo(3),
      ),
      const CapturePickerScreen(),
      const LiveControlScreen(),
      const TelemetryScreen(),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Hub',
          ),
          NavigationDestination(
            icon: Icon(Icons.replay_outlined),
            selectedIcon: Icon(Icons.replay),
            label: 'Replay',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth),
            selectedIcon: Icon(Icons.bluetooth_connected),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Telemetry',
          ),
        ],
      ),
    );
  }
}
