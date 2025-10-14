// Basic widget smoke test adapted for IndianRideApp.
// This verifies the app builds and shows the expected splash title without
// relying on counter template artifacts.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_china1/main.dart';

void main() {
  testWidgets('App builds without pending timers', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const IndianRideApp());

    // Initial frame should contain the splash title.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Indian Ride'), findsOneWidget);

    // Let the splash timer elapse so no timers remain pending.
    await tester.pump(const Duration(seconds: 4));

    // Still renders a MaterialApp and no test-time timer assertions should fire.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
