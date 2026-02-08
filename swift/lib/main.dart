import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import 'live/ble_controller.dart';
import 'ui/screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await FlutterBluePlus.setOptions(showPowerAlert: true, restoreState: false);
  } catch (_) {
    // Ignore if BLE options are not supported on this platform.
  }
  runApp(const R4830ReplayApp());
}

class R4830ReplayApp extends StatelessWidget {
  const R4830ReplayApp({
    super.key,
    this.enableBlePlatformBindings = true,
    this.requireConnectionOnLaunch = true,
  });

  final bool enableBlePlatformBindings;
  final bool requireConnectionOnLaunch;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          BleController(bindPlatformStreams: enableBlePlatformBindings)
            ..loadLogDirectory(),
      child: MaterialApp(
        title: 'R4830 Controller',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        ),
        home: HomeShell(requireConnectionOnLaunch: requireConnectionOnLaunch),
      ),
    );
  }
}
