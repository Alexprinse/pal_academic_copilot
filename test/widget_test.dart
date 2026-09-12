import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/main.dart';

void main() {
  testWidgets('Pal App bottom bar has Camera instead of Tasks, and View all opens Tasks', (WidgetTester tester) async {
    await tester.pumpWidget(const PalApp());
    expect(find.byType(PalApp), findsOneWidget);

    // Verify 5 bottom bar destinations
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Capture'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Vault'), findsWidgets);

    // Verify Tasks is NOT in the bottom bar
    expect(find.widgetWithText(BottomNavigationBar, 'Tasks'), findsNothing);

    // Tap Camera tab on bottom bar
    await tester.tap(find.text('Camera'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Camera OCR Screen is active
    expect(find.text('Textbook & Notes OCR'), findsOneWidget);

    // Tap Vault tab on bottom bar
    await tester.tap(find.text('Vault').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Study Vault screen is active
    expect(find.text('Subject & Unit RAG Knowledge Base'), findsOneWidget);

    // Tap Home tab on bottom bar
    await tester.tap(find.text('Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Find and tap View all -> on dashboard
    final viewAllFinder = find.text('View all →');
    await tester.scrollUntilVisible(
      viewAllFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(viewAllFinder, findsOneWidget);
    await tester.tap(viewAllFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); await tester.pump();

    // Verify Tasks screen opened
    expect(find.text('Academic Tasks'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // Pop back to Dashboard
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); await tester.pump();

    // Verify back on Dashboard
    expect(find.text('View all →'), findsOneWidget);
  });
}
