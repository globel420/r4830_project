// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:r4830_controller/main.dart';

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
}
