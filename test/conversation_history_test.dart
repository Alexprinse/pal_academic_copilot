import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/chat_message.dart';
import 'package:pal_academic_copilot/models/conversation_session.dart';
import 'package:pal_academic_copilot/models/vault_item.dart';
import 'package:pal_academic_copilot/screens/pal_brain_screen.dart';
import 'package:pal_academic_copilot/services/conversation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      },
    );
  });

  group('Deterministic Title Generation Tests', () {
    test('Generates TCP vs UDP from difference question', () {
      final title = ConversationService.generateTitle(
          'Explain the difference between TCP and UDP');
      expect(title, equals('TCP vs UDP'));
    });

    test('Generates Upcoming assignments from deadline question', () {
      final title = ConversationService.generateTitle(
          'What assignments are due this week?');
      expect(title, equals('Upcoming assignments'));
    });

    test('Generates Unit 3 Summary from summarize question', () {
      final title = ConversationService.generateTitle('Summarize Unit 3');
      expect(title, equals('Unit 3 Summary'));
    });

    test('Generates Process Scheduling from explain question', () {
      final title =
          ConversationService.generateTitle('Explain process scheduling');
      expect(title, equals('Process Scheduling'));
    });

    test('Handles empty prompt gracefully', () {
      final title = ConversationService.generateTitle('   ');
      expect(title, equals('Study Chat'));
    });
  });

  group('Conversation Model & Serialization Tests', () {
    test('Serializes and deserializes ConversationSession accurately', () {
      final now = DateTime.now();
      final chunk = TextChunk(
        id: 'chk-1',
        subject: 'Operating Systems',
        unit: 'Unit 1',
        documentName: 'OS Notes.pdf',
        pageNumber: 5,
        text: 'Peterson algorithm achieves mutual exclusion.',
        wordCount: 6,
      );

      final message = AcademicChatMessage(
        id: 'msg-1',
        conversationId: 'conv-123',
        role: 'assistant',
        text: 'Peterson algorithm guarantees mutual exclusion.',
        timestamp: now,
        citations: [ChunkMatch(chunk: chunk, score: 0.95)],
      );

      final session = ConversationSession(
        id: 'conv-123',
        title: 'Peterson Algorithm',
        createdAt: now,
        updatedAt: now,
        selectedRagScope: 'Unit 1 (OS)',
        messages: [message],
        isPinned: true,
      );

      final map = session.toMap();
      final restored = ConversationSession.fromMap(map);

      expect(restored.id, equals(session.id));
      expect(restored.title, equals(session.title));
      expect(restored.selectedRagScope, equals('Unit 1 (OS)'));
      expect(restored.isPinned, isTrue);
      expect(restored.messages.length, equals(1));
      expect(restored.messages.first.citations.length, equals(1));
      expect(restored.messages.first.citations.first.score, equals(0.95));
      expect(restored.messages.first.citations.first.chunk.documentName,
          equals('OS Notes.pdf'));
    });
  });

  group('ConversationService CRUD & Search Tests', () {
    final service = ConversationService.instance;

    setUp(() {
      service.clearForTesting();
    });

    test('Creates, renames, pins, searches, and deletes conversation',
        () async {
      final session = await service.createConversation(
        initialTitle: 'Initial Title',
        initialRagScope: 'Unit 1 (OS)',
      );

      expect(service.conversations.length, equals(1));
      expect(service.activeConversationId, equals(session.id));
      expect(session.selectedRagScope, equals('Unit 1 (OS)'));

      // Rename
      await service.renameConversation(session.id, 'Renamed Study Session');
      expect(
          service.activeConversation?.title, equals('Renamed Study Session'));

      // Pin
      expect(session.isPinned, isFalse);
      await service.togglePinConversation(session.id);
      expect(service.conversations.first.isPinned, isTrue);

      // Search
      final searchResults = service.searchConversations('Renamed');
      expect(searchResults.length, equals(1));
      expect(service.searchConversations('Nonexistent').length, equals(0));

      // Delete
      await service.deleteConversation(session.id);
      expect(service.conversations.length, equals(0));
    });
  });

  group('Pal Brain Screen Chat History & Drawer Widget Tests', () {
    setUp(() {
      ConversationService.instance.clearForTesting();
    });

    testWidgets('Opens History Drawer and displays header and search bar',
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
      await tester.pump();

      // Find hamburger menu icon
      final menuFinder = find.byIcon(Icons.menu);
      expect(menuFinder, findsOneWidget);

      // Tap to open drawer
      await tester.tap(menuFinder);
      await tester.pumpAndSettle();

      // Verify Chat History drawer is visible
      expect(find.text('Chat History'), findsOneWidget);
      expect(find.text('Search conversations...'), findsOneWidget);
      expect(find.byTooltip('New Chat'), findsWidgets);
    });

    testWidgets('New Chat button creates a new conversation session',
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
      await tester.pump();

      // Verify "New" button in AppBar
      final newBtnFinder = find.text('New');
      expect(newBtnFinder, findsOneWidget);

      // Add a user message to make chat non-empty
      key.currentState?.addMessageForTesting(
        AcademicChatMessage(
          id: 'usr-msg',
          role: 'user',
          text: 'Explain Deadlock',
          timestamp: DateTime.now(),
        ),
      );
      await tester.pump();

      // Tap New button -> confirmation dialog should open
      await tester.tap(newBtnFinder);
      await tester.pumpAndSettle();

      expect(find.text('Start a new chat?'), findsOneWidget);
      expect(find.text('New Chat'), findsWidgets);

      // Confirm New Chat
      final confirmBtn = find.widgetWithText(ElevatedButton, 'New Chat');
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Previous user message should not be in the newly cleared active view
      expect(find.text('Explain Deadlock'), findsNothing);
      // Service should now contain 2 conversations (the previous one and the new one)
      expect(ConversationService.instance.conversations.length, equals(2));
    });
  });
}
