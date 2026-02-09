// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import 'package:r4830_controller/live/ble_controller.dart';
import 'package:r4830_controller/main.dart';
import 'package:r4830_controller/ui/screens/hub_screen.dart';

void main() {
  testWidgets('ChargeFast hub loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      const R4830ReplayApp(
        enableBlePlatformBindings: false,
        requireConnectionOnLaunch: false,
      ),
    );
    await tester.pump();
    expect(find.text('ChargeFast'), findsOneWidget);
    expect(find.text('Output'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Safety'), findsOneWidget);
  });

  testWidgets(
    'Output current input hydrates from telemetry setpoint on connect',
    (WidgetTester tester) async {
      final controller = BleController(bindPlatformStreams: false);
      controller.connectionState = BluetoothConnectionState.connected;
      controller.logs.insert(
        0,
        BleLogEntry(
          timestamp: DateTime.parse('2026-02-10T00:00:00Z'),
          direction: 'RX',
          hex: '0608',
          decoded: {'frame_type': '0x06', 'cmd_id': 0x08, 'data32_le_f': 6.7},
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<BleController>.value(
          value: controller,
          child: MaterialApp(
            home: HubScreen(
              onOpenReplay: () {},
              onOpenLive: () {},
              onOpenTelemetry: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      final outputCurrentFieldFinder = find.byKey(
        const Key('output-current-limit-input'),
      );
      for (
        var i = 0;
        i < 8 && outputCurrentFieldFinder.evaluate().isEmpty;
        i++
      ) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -320));
        await tester.pump();
      }

      final field = tester.widget<TextField>(outputCurrentFieldFinder);
      expect(field.controller?.text, '6.7');
    },
  );
}
