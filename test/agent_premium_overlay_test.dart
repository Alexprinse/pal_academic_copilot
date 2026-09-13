import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/agent/agent_activity_service.dart';
import 'package:pal_academic_copilot/agent/agent_service.dart';
import 'package:pal_academic_copilot/agent/agent_tool.dart';
import 'package:pal_academic_copilot/agent/agent_tool_call.dart';
import 'package:pal_academic_copilot/agent/agent_tool_registry.dart';
import 'package:pal_academic_copilot/agent/agent_tool_result.dart';
import 'package:pal_academic_copilot/agent/planner/agent_plan_executor.dart';
import 'package:pal_academic_copilot/agent/ui/agent_action_preview_sheet.dart';
import 'package:pal_academic_copilot/agent/ui/agent_voice_overlay.dart';
import 'package:pal_academic_copilot/agent/ui/pal_agent_compact_modal.dart';
import 'package:pal_academic_copilot/agent/ui/pal_floating_button.dart';
import 'package:pal_academic_copilot/models/deadline.dart';
import 'package:pal_academic_copilot/models/timetable_entry.dart';
import 'package:pal_academic_copilot/screens/dashboard_screen.dart';
import 'package:pal_academic_copilot/services/deadline_service.dart';
import 'package:pal_academic_copilot/services/timetable_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    for (final channel in [
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/path_provider_macos',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        MethodChannel(channel),
        (MethodCall methodCall) async {
          return Directory.systemTemp.path;
        },
      );
    }
  });

  setUp(() {
    // Clear entries
    final entries =
        List<TimetableEntry>.from(TimetableService.instance.entries);
    for (final e in entries) {
      TimetableService.instance.deleteEntry(e.id);
    }

    // Seed predictable schedule
    TimetableService.instance.addEntry(const TimetableEntry(
      id: 'tt_mon_os',
      subject: 'Operating Systems',
      dayOfWeek: 'Mon',
      startTime: '10:00 AM',
      endTime: '11:00 AM',
      room: 'Room 204',
      professor: 'Dr. Silberschatz',
      type: 'Lecture',
    ));

    // Clear deadlines
    final deadlines = List<Deadline>.from(DeadlineService.instance.deadlines);
    for (final d in deadlines) {
      DeadlineService.instance.deleteDeadline(d.id);
    }

    AgentActivityService.instance.clear();
    AgentService.resetInstanceForTesting();
  });

  group('Phase 6 — Home Agent Button & Overlay', () {
    testWidgets('PalFloatingButton renders on Home with ✦ and label',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(onNavigateTab: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PalFloatingButton), findsOneWidget);
      expect(find.text('✦'), findsWidgets);
      expect(find.text('Hold Pal'), findsOneWidget);
    });

    testWidgets('Tap on PalFloatingButton opens PalAgentCompactModal',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(onNavigateTab: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on PalFloatingButton
      await tester.tap(find.byType(PalFloatingButton));
      await tester.pumpAndSettle();

      // Compact modal bottom sheet should appear
      expect(find.byType(PalAgentCompactModal), findsOneWidget);
      expect(find.text('What can I help you do?'), findsOneWidget);
      expect(find.text('Add a class'), findsOneWidget);
      expect(find.text('Schedule a recording'), findsOneWidget);
      expect(find.text('Check my schedule'), findsOneWidget);
      expect(find.text('Ask my notes'), findsOneWidget);
    });

    testWidgets(
        'AgentVoiceOverlay displays ✦, prompt hint, and listening state',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentVoiceOverlay(
              isListening: true,
              isTranscribing: false,
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('✦'), findsOneWidget);
      expect(find.text('Listening...'), findsOneWidget);
      expect(find.text('"Add AI tomorrow at 10"'), findsOneWidget);
      expect(find.text('Release when finished'), findsOneWidget);
    });

    testWidgets('Text command in compact modal launches Action Preview Sheet',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PalAgentCompactModal.show(context),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Enter text and submit
      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);
      await tester.enterText(inputFinder, 'Add AI tomorrow from 10 to 11');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(find.byType(AgentActionPreviewSheet), findsOneWidget);
      expect(find.text('YOU SAID'), findsOneWidget);
      expect(find.text('PAL WILL'), findsOneWidget);
      expect(find.text('Do it'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('Phase 6 — Action Preview, Execution, Success & Undo', () {
    testWidgets('Single action preview, execution and Undo rollback',
        (WidgetTester tester) async {
      final toolCall = const AgentToolCall(
        tool: 'create_timetable_event',
        arguments: {
          'subject': 'Artificial Intelligence',
          'day': 'tomorrow',
          'startTime': '10:00 AM',
          'endTime': '11:00 AM',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentActionPreviewSheet(
              transcript: 'Add AI tomorrow from 10 to 11',
              toolCalls: [toolCall],
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify preview content
      expect(find.text('YOU SAID'), findsOneWidget);
      expect(find.text('PAL WILL'), findsOneWidget);
      expect(find.text('Do it'), findsOneWidget);

      // Tap [Do it]
      await tester.tap(find.text('Do it'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify success state
      expect(find.text('Done'), findsWidgets);
      expect(find.text('View Class'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      // Verify entry was added to timetable
      final entriesAfterAdd = TimetableService.instance.entries
          .where((e) => e.subject == 'Artificial Intelligence');
      expect(entriesAfterAdd.isNotEmpty, isTrue);

      // Tap [Undo]
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Undone'), findsOneWidget);

      // Verify entry was removed by Undo
      final entriesAfterUndo = TimetableService.instance.entries
          .where((e) => e.subject == 'Artificial Intelligence');
      expect(entriesAfterUndo.isEmpty, isTrue);
    });

    testWidgets('Multi-step action card shows sequential steps and Done state',
        (WidgetTester tester) async {
      final calls = const [
        AgentToolCall(
          tool: 'create_timetable_event',
          arguments: {
            'subject': 'Artificial Intelligence',
            'day': 'tomorrow',
            'startTime': '10:00 AM',
            'endTime': '11:00 AM',
          },
        ),
        AgentToolCall(
          tool: 'schedule_recording',
          arguments: {
            'subject': 'Artificial Intelligence',
            'day': 'tomorrow',
            'startTime': '10:00 AM',
            'endTime': '11:00 AM',
          },
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentActionPreviewSheet(
              transcript: 'Add AI tomorrow 10-11 and record it',
              toolCalls: calls,
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('STEP 1'), findsOneWidget);
      expect(find.text('STEP 2'), findsOneWidget);

      // Tap [Do it]
      await tester.tap(find.text('Do it'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Done'), findsWidgets);
      expect(find.text('View Class'), findsOneWidget);
    });

    testWidgets(
        'Authoritative partial failure shows Try Again without stack traces',
        (WidgetTester tester) async {
      // Setup failing registry for schedule_recording
      final baseRegistry = AgentService.instance.registry;
      final failingRegistry = AgentToolRegistry([
        ...baseRegistry.tools.where((t) => t.name != 'schedule_recording'),
        _FailingRecTool(),
      ]);

      AgentService.resetInstanceForTesting();
      final agentService = AgentService(
        registry: failingRegistry,
        planExecutor: AgentPlanExecutor(registry: failingRegistry),
      );

      final calls = const [
        AgentToolCall(
          tool: 'create_timetable_event',
          arguments: {
            'subject': 'Artificial Intelligence',
            'day': 'tomorrow',
            'startTime': '10:00 AM',
            'endTime': '11:00 AM',
          },
        ),
        AgentToolCall(
          tool: 'schedule_recording',
          arguments: {
            'subject': 'Artificial Intelligence',
            'day': 'tomorrow',
            'startTime': '10:00 AM',
            'endTime': '11:00 AM',
          },
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentActionPreviewSheet(
              transcript: 'Add AI tomorrow 10-11 and record it.',
              toolCalls: calls,
              onCancel: () {},
              agentService: agentService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Execute through the failing setup
      await tester.tap(find.text('Do it'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Must state clean error without stack trace
      expect(find.text('Couldn\'t complete everything.'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('Question mode displays compact answer with citations',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentActionPreviewSheet(
              transcript: 'What is my next class?',
              toolCalls: const [
                AgentToolCall(
                  tool: 'get_upcoming_classes',
                  arguments: {'target': 'next', 'limit': 1},
                ),
              ],
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Read-only queries execute immediately
      expect(find.text('PAL'), findsOneWidget);
      expect(find.textContaining('Operating Systems'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets(
        'Lightweight Activity History records and displays recent actions',
        (WidgetTester tester) async {
      AgentActivityService.instance.recordActivity(
        title: 'Added AI class',
        subtitle: 'Tue · 10:00 AM–11:00 AM',
        isSuccess: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PalAgentCompactModal(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap history toggle icon
      await tester.tap(find.byTooltip('Recent Actions'));
      await tester.pumpAndSettle();

      expect(find.text('Recent Activity History'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Added AI class'), findsOneWidget);
      expect(find.text('Tue · 10:00 AM–11:00 AM'), findsOneWidget);
    });
  });
}

class _FailingRecTool extends AgentTool {
  _FailingRecTool()
      : super(
          name: 'schedule_recording',
          description: 'Failing mock',
          isReadOnly: false,
          parameters: const [],
        );

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    dynamic context,
  }) async {
    return AgentToolResult.failure(
      tool: name,
      message: 'Automatic recording couldn\'t be enabled',
      error: 'REC_UNAVAILABLE',
    );
  }
}
