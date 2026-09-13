import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/chat_message.dart';
import 'package:pal_academic_copilot/models/conversation_session.dart';
import 'package:pal_academic_copilot/models/conversation_state.dart';
import 'package:pal_academic_copilot/screens/pal_brain_screen.dart';
import 'package:pal_academic_copilot/services/active_quiz_service.dart';
import 'package:pal_academic_copilot/services/conversation_service.dart';
import 'package:pal_academic_copilot/services/llm_service.dart';

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

  setUp(() {
    ConversationService.instance.clearForTesting();
  });

  group('Pal Conversation State & Context Retention Tests', () {
    test('ActiveQuizService generates valid questions and evaluates answers',
        () {
      final service = ActiveQuizService.instance;
      expect(service.isQuizRequest('Quiz me on operating systems concepts'),
          isTrue);
      expect(service.isQuizAnswer('A'), isTrue);
      expect(service.isQuizAnswer('Option B'), isTrue);
      expect(service.isQuizAnswer('Explain it simply'), isFalse);

      final quiz = service.createQuiz(topic: 'operating systems concepts');
      expect(quiz.totalQuestions, equals(3));
      expect(quiz.currentQuestionIndex, equals(0));
      expect(quiz.currentQuestion?.number, equals(1));
      expect(quiz.currentQuestion?.correctLetter, equals('A'));

      // Test Question 1 Evaluation
      final eval1 = service.evaluateAnswer(quiz: quiz, answerLetter: 'A');
      expect(eval1, contains('Correct!'));
      expect(eval1, contains('Question 2 of 3'));
      expect(quiz.currentQuestionIndex, equals(1));
      expect(quiz.score, equals(1));

      // Test Question 2 Evaluation (incorrect answer)
      final eval2 = service.evaluateAnswer(quiz: quiz, answerLetter: 'C');
      expect(eval2, contains('Incorrect'));
      expect(eval2, contains('Question 3 of 3'));
      expect(quiz.currentQuestionIndex, equals(2));
      expect(quiz.score, equals(1));

      // Test Question 3 Evaluation (correct answer completes quiz)
      final eval3 = service.evaluateAnswer(quiz: quiz, answerLetter: 'B');
      expect(eval3, contains('Correct!'));
      expect(eval3, contains('Quiz Complete!'));
      expect(eval3, contains('2 / 3'));
      expect(quiz.isCompleted, isTrue);
    });

    testWidgets('Test 1: Quiz starts -> Answer "A" -> evaluated against Q1',
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

      // Step 1: User sends quiz request
      await key.currentState
          ?.sendMessageForTesting('Quiz me on operating systems concepts');
      await tester.pumpAndSettle();

      final state = key.currentState;
      expect(state, isNotNull);
      expect(
          state!.activeSessionForTesting?.activeMode, equals(ActiveMode.quiz));
      expect(state.activeSessionForTesting?.activeQuiz, isNotNull);

      // Verify Question 1 is presented
      final messages = state.messagesForTesting;
      expect(messages.length, greaterThanOrEqualTo(2));
      final q1Msg = messages.last.text;
      expect(q1Msg, contains("Here's your first question:"));
      expect(
          q1Msg,
          contains(
              'What is the primary function of the kernel in an operating system?'));
      expect(q1Msg, contains('A) Manage hardware resources'));

      // Step 2: User responds with "A"
      await key.currentState?.sendMessageForTesting('A');
      await tester.pumpAndSettle();

      // Step 3: Verify "A" is evaluated against Q1 and Question 2 is presented
      final updatedMessages = state.messagesForTesting;
      final evalMsg = updatedMessages.last.text;

      // Must NOT say the generic greeting
      expect(
          evalMsg,
          isNot(
              contains("I'm Pal, your copilot! How can I assist you today?")));
      expect(evalMsg, contains('Correct!'));
      expect(evalMsg, contains('Question 2 of 3'));
      expect(state.activeSessionForTesting?.activeQuiz?.currentQuestionIndex,
          equals(1));
    });

    testWidgets(
        'Test 2: "What is a kernel?" -> "Explain it simply." (anaphora retention)',
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

      // Turn 1
      await key.currentState?.sendMessageForTesting('What is a kernel?');
      await tester.pumpAndSettle();

      final state = key.currentState!;
      expect(state.messagesForTesting.last.text, contains('foundational core'));

      // Turn 2: Anaphora "Explain it simply"
      await key.currentState?.sendMessageForTesting('Explain it simply.');
      await tester.pumpAndSettle();

      final response2 = state.messagesForTesting.last.text;
      // Should retain context that "it" refers to the kernel
      expect(response2, contains('kernel'));
      expect(response2, contains('manager or brain of your computer'));
    });

    testWidgets(
        'Test 3: "What is TCP?" -> "Compare it with UDP." (dialogue retention)',
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

      // Turn 1
      await key.currentState?.sendMessageForTesting('What is TCP?');
      await tester.pumpAndSettle();

      final state = key.currentState!;
      expect(state.messagesForTesting.last.text,
          contains('Transport Layer protocol'));

      // Turn 2: Compare it with UDP
      await key.currentState?.sendMessageForTesting('Compare it with UDP.');
      await tester.pumpAndSettle();

      final response2 = state.messagesForTesting.last.text;
      expect(response2, contains('TCP'));
      expect(response2, contains('UDP'));
      expect(response2, contains('Connection-oriented'));
      expect(response2, contains('Connectionless'));
    });

    testWidgets(
        'Test 4: Multi-question quiz flow (Q1 -> answer -> Q2 -> answer -> Q3)',
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

      // Start quiz
      await key.currentState
          ?.sendMessageForTesting('Quiz me on operating systems concepts');
      await tester.pumpAndSettle();

      final state = key.currentState!;
      expect(
          state.activeSessionForTesting?.activeMode, equals(ActiveMode.quiz));
      expect(state.activeSessionForTesting?.activeQuiz?.currentQuestionIndex,
          equals(0));

      // Answer Q1
      await key.currentState?.sendMessageForTesting('A');
      await tester.pumpAndSettle();
      expect(state.messagesForTesting.last.text, contains('Question 2 of 3'));
      expect(state.activeSessionForTesting?.activeQuiz?.currentQuestionIndex,
          equals(1));

      // Answer Q2
      await key.currentState?.sendMessageForTesting('B');
      await tester.pumpAndSettle();
      expect(state.messagesForTesting.last.text, contains('Question 3 of 3'));
      expect(state.activeSessionForTesting?.activeQuiz?.currentQuestionIndex,
          equals(2));

      // Answer Q3
      await key.currentState?.sendMessageForTesting('B');
      await tester.pumpAndSettle();
      expect(state.messagesForTesting.last.text, contains('Quiz Complete!'));
      expect(state.messagesForTesting.last.text, contains('3 / 3'));
      expect(state.activeSessionForTesting?.activeQuiz?.isCompleted, isTrue);
      expect(
          state.activeSessionForTesting?.activeMode, equals(ActiveMode.chat));
    });

    testWidgets(
        'Test 5: "+ New" resets context so "A" is not treated as answer to old quiz',
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

      // Start quiz
      await key.currentState
          ?.sendMessageForTesting('Quiz me on operating systems concepts');
      await tester.pumpAndSettle();

      final state = key.currentState!;
      expect(
          state.activeSessionForTesting?.activeMode, equals(ActiveMode.quiz));
      expect(state.activeSessionForTesting?.activeQuiz, isNotNull);

      // Tap "+ New" button in AppBar
      final newBtn = find.text('New');
      expect(newBtn, findsOneWidget);
      await tester.tap(newBtn);
      await tester.pumpAndSettle();

      // Confirm New Chat dialog
      final confirmBtn = find.widgetWithText(ElevatedButton, 'New Chat');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify active mode is reset to chat and activeQuiz is null
      expect(
          state.activeSessionForTesting?.activeMode, equals(ActiveMode.chat));
      expect(state.activeSessionForTesting?.activeQuiz, isNull);

      // In the new session, send "A"
      await key.currentState?.sendMessageForTesting('A');
      await tester.pumpAndSettle();

      // It must NOT be treated as a quiz answer (does not contain "Correct!" or "Question 2 of 3")
      final lastMsg = state.messagesForTesting.last.text;
      expect(lastMsg, isNot(contains('Correct!')));
      expect(lastMsg, isNot(contains('Question 2 of 3')));
      expect(lastMsg, isNot(contains('Quiz Complete!')));
    });
  });
}
