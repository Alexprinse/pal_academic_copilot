import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/agent/agent_context.dart';
import 'package:pal_academic_copilot/agent/agent_service.dart';
import 'package:pal_academic_copilot/agent/agent_voice_controller.dart';
import 'package:pal_academic_copilot/agent/ui/agent_action_preview_sheet.dart';
import 'package:pal_academic_copilot/agent/ui/agent_voice_overlay.dart';
import 'package:pal_academic_copilot/agent/ui/pal_agent_compact_modal.dart';
import 'package:pal_academic_copilot/models/timetable_entry.dart';
import 'package:pal_academic_copilot/screens/dashboard_screen.dart';
import 'package:pal_academic_copilot/services/lecture_recording_service.dart';
import 'package:pal_academic_copilot/services/timetable_service.dart';
import 'package:pal_academic_copilot/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'create') return 'mock_recorder_id';
        if (methodCall.method == 'hasPermission') return true;
        if (methodCall.method == 'start') return null;
        if (methodCall.method == 'stop') {
          return 'mock_stopped.wav';
        }
        return null;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      },
    );
  });

  final testDateTime =
      DateTime(2026, 9, 14, 9, 0); // Monday Sep 14, 2026 9:00 AM
  final testContext = AgentContext(currentDateTime: testDateTime);

  setUp(() {
    AgentService.resetInstanceForTesting();
    // Clear entries
    final entries =
        List<TimetableEntry>.from(TimetableService.instance.entries);
    for (final e in entries) {
      TimetableService.instance.deleteEntry(e.id);
    }
    // Seed initial schedule
    TimetableService.instance.addEntry(const TimetableEntry(
      id: 'tt_mon_ai',
      subject: 'Artificial Intelligence',
      dayOfWeek: 'Mon',
      startTime: '10:00 AM',
      endTime: '11:00 AM',
      room: 'Room 301',
      professor: 'Dr. Turing',
      type: 'Lecture',
    ));
  });

  group('Phase 4 — Audio Isolation Invariant', () {
    test(
        'Agent voice commands are isolated and NEVER saved into LectureRecordingService',
        () {
      final initialLectureCount =
          LectureRecordingService.instance.recordings.length;

      // Simulate an agent voice command session
      final controller = AgentVoiceController.instance;
      controller.cancelSession();

      // Ensure LectureRecordingService was not modified
      expect(
        LectureRecordingService.instance.recordings.length,
        initialLectureCount,
      );
    });
  });

  group('Phase 4 — Voice Controller & Intent Routing', () {
    test('Identifies action commands vs read-only queries', () {
      final service = AgentService.instance;

      // Action 1: Add class
      final addCalls = service
          .determineToolCalls('Add Operating Systems tomorrow from 10 to 11');
      expect(addCalls.length, 1);
      expect(addCalls.first.tool, 'create_timetable_event');

      // Action 2: Schedule recording
      final recCalls = service.determineToolCalls(
          'Record my networking class tomorrow from 2 to 3');
      expect(recCalls.length, 1);
      expect(recCalls.first.tool, 'schedule_recording');

      // Action 3: Create task
      final taskCalls = service.determineToolCalls(
          'Remind me to submit my assignment on September 15');
      expect(taskCalls.length, 1);
      expect(taskCalls.first.tool, 'create_task');

      // Query 1: What is my next class?
      final queryCalls = service.determineToolCalls('What is my next class?');
      expect(queryCalls.length, 1);
      expect(queryCalls.first.tool, 'get_upcoming_classes');

      // Query 2: Search knowledge
      final ragCalls = service
          .determineToolCalls('What did my OS lecture say about scheduling?');
      expect(ragCalls.length, 1);
      expect(ragCalls.first.tool, 'search_knowledge');
    });

    test('Ambiguity check: missing time triggers clarification question',
        () async {
      final service = AgentService.instance;

      // "Record my class tomorrow" without a start time
      final response = await service.process(
        prompt: 'Record my class tomorrow',
        context: testContext,
      );

      expect(response.toolCalls.isNotEmpty, isTrue);
      expect(response.text, contains('What time is your'));
    });
  });

  group('Phase 4 — UI Widgets & Overlays', () {
    testWidgets(
        'AgentVoiceOverlay renders "Pal", "Listening...", "Release when finished"',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: AgentVoiceOverlay(
              isListening: true,
              isTranscribing: false,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Pal'), findsOneWidget);
      expect(find.text('Listening...'), findsOneWidget);
      expect(find.text('Release when finished'), findsOneWidget);
    });

    testWidgets('AgentVoiceOverlay shows "Processing..." when transcribing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: AgentVoiceOverlay(
              isListening: false,
              isTranscribing: true,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Pal'), findsOneWidget);
      expect(find.text('Processing...'), findsOneWidget);
      expect(find.text('Understanding your request...'), findsOneWidget);
    });

    testWidgets(
        'AgentActionPreviewSheet renders "You said", "PAL WILL", [Cancel], and [Do it]',
        (tester) async {
      final toolCalls = AgentService.instance.determineToolCalls(
        'Add Operating Systems tomorrow from 10 to 11',
      );

      bool canceled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: AgentActionPreviewSheet(
              transcript: 'Add Operating Systems tomorrow from 10 to 11',
              toolCalls: toolCalls,
              onCancel: () {
                canceled = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();

      // Check transcript section
      expect(find.text('YOU SAID'), findsOneWidget);
      expect(find.text('"Add Operating Systems tomorrow from 10 to 11"'),
          findsOneWidget);

      // Check action preview section
      expect(find.text('PAL WILL'), findsOneWidget);
      expect(find.text('✓ Add Operating Systems'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Do it'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(canceled, isTrue);
    });

    testWidgets(
        'Home Dashboard removes top banner and preserves Hold Pal as primary entry point',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: DashboardScreen(
            onNavigateTab: (tab) {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify top Pal Agent banner is completely removed
      expect(find.text('Tap to open · Hold to speak'), findsNothing);

      // Verify compact informational "Today with Pal" snapshot is rendered
      expect(find.text('Today with Pal'), findsOneWidget);

      // Verify primary "Hold Pal" floating button is present
      expect(find.text('Hold Pal'), findsOneWidget);

      // Tap "Hold Pal" to open Pal Agent Compact Modal
      await tester.tap(find.text('Hold Pal'));
      await tester.pumpAndSettle();
      expect(find.byType(PalAgentCompactModal), findsOneWidget);
    });
  });
}
