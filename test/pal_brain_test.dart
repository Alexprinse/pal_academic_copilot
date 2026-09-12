import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/chat_message.dart';
import 'package:pal_academic_copilot/models/vault_item.dart';
import 'package:pal_academic_copilot/screens/pal_brain_screen.dart';
import 'package:pal_academic_copilot/services/conversation_service.dart';

void main() {
  group('Ask Screen (Pal Brain) Redesign & Markdown Rendering Tests', () {
    setUp(() {
      ConversationService.instance.clearForTesting();
    });

    testWidgets(
        'Renders ChatGPT-style assistant messages with Markdown and Action Row',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final key = GlobalKey<PalBrainScreenState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PalBrainScreen(key: key),
          ),
        ),
      );
      await tester.pump();

      // Initial welcome message should use MarkdownBody
      expect(find.byType(MarkdownBody), findsWidgets);

      // Verify action buttons exist on assistant message
      expect(find.byIcon(Icons.copy_outlined), findsWidgets);
      expect(find.byIcon(Icons.thumb_up_outlined), findsWidgets);
      expect(find.byIcon(Icons.thumb_down_outlined), findsWidgets);
      expect(find.byIcon(Icons.more_vert), findsWidgets);

      // Add a test assistant message with rich markdown and citation
      key.currentState?.addMessageForTesting(
        AcademicChatMessage(
          id: 'msg-test-1',
          role: 'assistant',
          text:
              '## Key Concepts\n- **Deadlock** occurs when processes are blocked.\n- *Preemption* avoids resource hold.',
          timestamp: DateTime.now(),
          tokensPerSecond: 18.5,
          citations: [
            ChunkMatch(
              chunk: TextChunk(
                id: 'c1',
                subject: 'Operating Systems',
                unit: 'Unit 1',
                documentName: 'OS Notes Unit 1.pdf',
                pageNumber: 3,
                text:
                    'Deadlock happens when four conditions hold simultaneously.',
                wordCount: 8,
              ),
              score: 0.92,
            ),
          ],
        ),
      );
      await tester.pump();

      // Verify formatted markdown text was rendered
      expect(find.textContaining('Key Concepts'), findsWidgets);
      expect(find.textContaining('Deadlock'), findsWidgets);

      // Verify tok/s telemetry badge
      expect(find.textContaining('18.5 tok/s'), findsOneWidget);

      // Verify citation chip
      final chipFinder = find.textContaining('OS Notes Unit 1.pdf');
      expect(chipFinder, findsOneWidget);

      // Test citation modal
      await tester.ensureVisible(chipFinder);
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();
      expect(find.text('VERIFIED SOURCE EXCERPT'), findsOneWidget);
      expect(find.textContaining('Deadlock happens when four conditions hold'),
          findsOneWidget);

      // Close modal (tap outside modal or back)
      Navigator.pop(tester.element(find.text('VERIFIED SOURCE EXCERPT')));
      await tester.pumpAndSettle();

      // Test like button toggle
      final likeBtn = find.byIcon(Icons.thumb_up_outlined).first;
      await tester.ensureVisible(likeBtn);
      await tester.tap(likeBtn);
      await tester.pump();
      expect(find.byIcon(Icons.thumb_up), findsWidgets);
    });

    testWidgets('Renders user message in clean right-aligned bubble',
        (WidgetTester tester) async {
      final key = GlobalKey<PalBrainScreenState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PalBrainScreen(key: key),
          ),
        ),
      );
      await tester.pump();

      key.currentState?.addMessageForTesting(
        AcademicChatMessage(
          id: 'msg-user-1',
          role: 'user',
          text: 'Explain Peterson algorithm',
          timestamp: DateTime.now(),
        ),
      );
      await tester.pump();

      expect(find.text('Explain Peterson algorithm'), findsOneWidget);
    });

    testWidgets('Opens Model Switcher Modal and shows Default Model option',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final key = GlobalKey<PalBrainScreenState>();

      await tester.pumpWidget(
        MaterialApp(
          home: PalBrainScreen(key: key),
        ),
      );
      await tester.pumpAndSettle();

      // Open model switcher modal directly
      key.currentState?.showModelSwitcherForTesting();
      await tester.pumpAndSettle();

      // Check that model switcher dialog is visible
      expect(find.text('On-Device GGUF Engine'), findsOneWidget);

      // Verify that at least one model has the DEFAULT badge
      expect(find.text('DEFAULT'), findsOneWidget);

      // Verify "Set Default" button exists for non-default models
      expect(find.text('Set Default'), findsWidgets);

      // Close modal
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });
  });
}
