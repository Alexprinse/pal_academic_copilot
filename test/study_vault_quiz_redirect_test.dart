import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/main.dart';
import 'package:pal_academic_copilot/models/rag_scope.dart';
import 'package:pal_academic_copilot/models/vault_item.dart';
import 'package:pal_academic_copilot/screens/main_navigation_screen.dart';
import 'package:pal_academic_copilot/screens/study_vault/vault_unit_screen.dart';
import 'package:pal_academic_copilot/services/conversation_service.dart';
import 'package:pal_academic_copilot/services/rag_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await RagService.instance.init();
    await ConversationService.instance.init();
  });

  group('Study Vault Quiz Me -> LLM Redirect Tests', () {
    testWidgets(
        'VaultUnitScreen Quiz Me chip triggers onNavigateToBrain with index 2 and quiz query',
        (WidgetTester tester) async {
      int? navigatedIndex;
      String? receivedQuery;
      String? receivedSubject;
      String? receivedUnit;

      final testSubject = VaultSubject(
        id: 'operating_systems',
        name: 'Operating Systems',
        code: 'CS 301',
        iconCode: 'computer',
        units: [],
      );

      final testUnit = VaultUnit(
        id: 'unit_1',
        name: 'Unit 1: Introduction & Kernel Structure',
        subjectName: 'Operating Systems',
        documents: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VaultUnitScreen(
              subject: testSubject,
              unit: testUnit,
              onNavigateToBrain: (idx,
                  {initialQuery, filterSubject, filterUnit}) {
                navigatedIndex = idx;
                receivedQuery = initialQuery;
                receivedSubject = filterSubject;
                receivedUnit = filterUnit;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Locate the "Quiz Me" ActionChip
      final quizMeChip = find.widgetWithText(ActionChip, 'Quiz Me');
      expect(quizMeChip, findsOneWidget);

      // Tap "Quiz Me"
      await tester.tap(quizMeChip);
      await tester.pumpAndSettle();

      // Verify callback triggered with brain tab (2), quiz prompt, and unit scope
      expect(navigatedIndex, equals(2));
      expect(receivedQuery, contains('Generate 5 practice exam questions'));
      expect(receivedQuery, contains(testUnit.name));
      expect(receivedSubject, equals('Operating Systems'));
      expect(receivedUnit, equals(testUnit.name));

      // Verify a conversation session was initialized in ConversationService
      final activeConv = ConversationService.instance.activeConversation;
      expect(activeConv, isNotNull);
      expect(activeConv!.ragScope.type, equals(RagScopeType.subjectUnit));
      expect(activeConv.subjectName, equals('Operating Systems'));
    });

    testWidgets(
        'Clicking Quiz Me when VaultUnitScreen is pushed redirects MainNavigationScreen to PalBrainScreen',
        (WidgetTester tester) async {
      await tester.pumpWidget(const PalApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Navigate to Vault tab (index 4)
      await tester.tap(find.text('Vault').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Push VaultUnitScreen onto the navigation stack
      final testSubject = VaultSubject(
        id: 'operating_systems',
        name: 'Operating Systems',
        code: 'CS 301',
        iconCode: 'computer',
        units: [],
      );
      final testUnit = VaultUnit(
        id: 'unit_2',
        name: 'Unit 2: CPU Scheduling & Deadlocks',
        subjectName: 'Operating Systems',
        documents: [],
      );

      final navContext = tester.element(find.byType(MainNavigationScreen));
      Navigator.of(navContext).push(
        MaterialPageRoute(
          builder: (_) => VaultUnitScreen(
            subject: testSubject,
            unit: testUnit,
            onNavigateToBrain: (idx,
                {initialQuery, filterSubject, filterUnit}) {
              // Find the state and call switchTab
              final mainNavState = tester.state<MainNavigationScreenState>(
                  find.byType(MainNavigationScreen));
              mainNavState.switchTab(
                idx,
                initialQuery: initialQuery,
                filterSubject: filterSubject,
                filterUnit: filterUnit,
              );
            },
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify VaultUnitScreen is currently visible on screen
      expect(find.byType(VaultUnitScreen), findsOneWidget);
      expect(find.text('Unit 2: CPU Scheduling & Deadlocks'), findsWidgets);

      // Tap "Quiz Me" chip
      final quizMeChip = find.widgetWithText(ActionChip, 'Quiz Me');
      expect(quizMeChip, findsOneWidget);
      await tester.tap(quizMeChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify VaultUnitScreen was popped and the interface redirected to Ask tab (PalBrainScreen)
      expect(find.byType(VaultUnitScreen), findsNothing);

      // Bottom bar must now have 'Ask' selected (index 2)
      final bottomNavBar =
          tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bottomNavBar.currentIndex, equals(2));
    });
  });
}
