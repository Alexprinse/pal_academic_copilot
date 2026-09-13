import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/agent/agent_context.dart';
import 'package:pal_academic_copilot/agent/agent_service.dart';
import 'package:pal_academic_copilot/agent/agent_tool.dart';
import 'package:pal_academic_copilot/agent/agent_tool_registry.dart';
import 'package:pal_academic_copilot/agent/agent_tool_result.dart';
import 'package:pal_academic_copilot/agent/planner/agent_plan.dart';
import 'package:pal_academic_copilot/agent/planner/agent_plan_executor.dart';
import 'package:pal_academic_copilot/agent/planner/agent_plan_step.dart';
import 'package:pal_academic_copilot/agent/planner/agent_planner.dart';
import 'package:pal_academic_copilot/models/deadline.dart';
import 'package:pal_academic_copilot/models/lecture_recording.dart';
import 'package:pal_academic_copilot/models/timetable_entry.dart';
import 'package:pal_academic_copilot/services/deadline_service.dart';
import 'package:pal_academic_copilot/services/rag_service.dart';
import 'package:pal_academic_copilot/services/timetable_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testDateTime = DateTime(2026, 9, 14, 9, 0); // Monday 9:00 AM
  final testContext = AgentContext(
    currentDateTime: testDateTime,
    userId: 'test_user',
  );

  setUp(() {
    // Clear timetable
    final entries =
        List<TimetableEntry>.from(TimetableService.instance.entries);
    for (final e in entries) {
      TimetableService.instance.deleteEntry(e.id);
    }

    // Seed predictable schedule for upcoming classes
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

    // Clear deadlines
    final deadlines = List<Deadline>.from(DeadlineService.instance.deadlines);
    for (final d in deadlines) {
      DeadlineService.instance.deleteDeadline(d.id);
    }

    // Reset AgentService
    AgentService.resetInstanceForTesting();
  });

  group('Phase 5 — Multi-Step Pal Agent Planning', () {
    test('Scenario 1: Add AI tomorrow 10-11 and record it', () async {
      final planner = AgentPlanner();
      final plan = planner.createPlan('Add AI tomorrow 10-11 and record it.');

      expect(plan.isBlockedOnMissingInfo, isFalse);
      expect(plan.steps.length, equals(2));
      expect(plan.steps[0].tool, equals('create_timetable_event'));
      expect(plan.steps[0].arguments['subject'],
          equals('Artificial Intelligence'));
      expect(plan.steps[0].arguments['day'], equals('tomorrow'));
      expect(plan.steps[0].arguments['startTime'], equals('10'));
      expect(plan.steps[0].arguments['endTime'], equals('11'));

      expect(plan.steps[1].tool, equals('schedule_recording'));
      expect(plan.steps[1].arguments['subject'],
          equals('Artificial Intelligence'));
      expect(plan.steps[1].dependsOnPrevious, isTrue);

      // Execute through AgentService
      final response = await AgentService.instance.process(
        prompt: 'Add AI tomorrow 10-11 and record it.',
        context: testContext,
      );

      expect(response.toolCalls.length, equals(2));
      expect(response.toolResults.length, equals(2));
      expect(response.toolResults.every((r) => r.success), isTrue);
      expect(response.text, contains('Artificial Intelligence'));
      expect(response.text, contains('scheduled automatic recording'));

      // Verify timetable entry added
      final entries = TimetableService.instance.entries;
      final added = entries.where((e) =>
          e.subject == 'Artificial Intelligence' && e.dayOfWeek == 'Tue');
      expect(added.isNotEmpty, isTrue);
    });

    test('Scenario 2: Add OS tomorrow 2-3 and remind me 30 minutes before',
        () async {
      final planner = AgentPlanner();
      final plan = planner
          .createPlan('Add OS tomorrow 2-3 and remind me 30 minutes before.');

      expect(plan.isBlockedOnMissingInfo, isFalse);
      expect(plan.steps.length, equals(2));
      expect(plan.steps[0].tool, equals('create_timetable_event'));
      expect(plan.steps[0].arguments['subject'], equals('Operating Systems'));
      expect(plan.steps[1].tool, equals('create_task'));
      expect(plan.steps[1].arguments['title'], contains('30 mins before'));

      // Execute through AgentService
      final response = await AgentService.instance.process(
        prompt: 'Add OS tomorrow 2-3 and remind me 30 minutes before.',
        context: testContext,
      );

      expect(response.toolCalls.length, equals(2));
      expect(response.toolResults.every((r) => r.success), isTrue);
      expect(response.text, contains('Operating Systems'));
      expect(response.text, contains('reminder'));

      // Verify task/reminder created
      final deadlines = DeadlineService.instance.deadlines;
      final task = deadlines.where((d) => d.course == 'Operating Systems');
      expect(task.isNotEmpty, isTrue);
    });

    test(
        'Scenario 3: Read + Write: Tell me my next class and move it one hour later',
        () async {
      final planner = AgentPlanner();
      final plan = planner
          .createPlan('Tell me my next class and move it one hour later.');

      expect(plan.isBlockedOnMissingInfo, isFalse);
      expect(plan.steps.length, equals(2));
      expect(plan.steps[0].tool, equals('get_upcoming_classes'));
      expect(plan.steps[1].tool, equals('update_timetable_event'));
      expect(plan.steps[1].arguments['newStartTime'], equals('OFFSET_+1H'));
      expect(plan.steps[1].dependsOnPrevious, isTrue);

      // Execute through AgentService
      final response = await AgentService.instance.process(
        prompt: 'Tell me my next class and move it one hour later.',
        context: testContext,
      );

      expect(response.toolCalls.length, equals(2));
      expect(response.toolResults.length, equals(2));
      expect(response.toolResults[0].success, isTrue);
      expect(response.toolResults[1].success, isTrue);
      expect(response.text, contains('Artificial Intelligence'));
      expect(response.text, contains('11:00 AM'));

      // Verify entry was moved in timetable
      final entry = TimetableService.instance.entries
          .firstWhere((e) => e.id == 'tt_mon_ai');
      expect(entry.startTime, equals('11:00 AM'));
    });

    test(
        'Scenario 4: Knowledge + Action: Find the assignment from yesterday\'s lecture and add it',
        () async {
      // Seed RAG lecture recording with an assignment note
      final now = DateTime(2026, 9, 13, 10, 0);
      final recording = LectureRecording(
        id: 'lecture_os_test',
        subject: 'Operating Systems',
        date: now,
        scheduledStart: '10:00 AM',
        scheduledEnd: '11:00 AM',
        actualStart: now,
        audioPath: 'os_lecture.wav',
        durationSeconds: 3600,
        chunks: const [
          LectureTranscriptChunk(
            chunkIndex: 0,
            startTimestamp: '15:20',
            endTimestamp: '15:45',
            text:
                'Please note: Homework 3 on Virtual Memory is due on September 22. Make sure to submit on time.',
          ),
        ],
      );
      RagService.instance.indexLectureRecording(recording);

      final planner = AgentPlanner();
      final plan = planner.createPlan(
          'Find the assignment from yesterday\'s lecture and add it to my tasks.');

      expect(plan.isBlockedOnMissingInfo, isFalse);
      expect(plan.steps.length, equals(2));
      expect(plan.steps[0].tool, equals('search_knowledge'));
      expect(plan.steps[1].tool, equals('create_task'));

      // Execute through AgentService
      final response = await AgentService.instance.process(
        prompt:
            'Find the assignment from yesterday\'s lecture and add it to my tasks.',
        context: testContext,
      );

      expect(response.toolCalls.length, equals(2));
      expect(response.toolResults[0].success, isTrue);
      expect(response.toolResults[1].success, isTrue);
      expect(response.text, contains('Homework 3'));

      // Verify task created in DeadlineService
      final deadlines = DeadlineService.instance.deadlines;
      final match = deadlines.where((d) => d.title.contains('Homework 3'));
      expect(match.isNotEmpty, isTrue);
    });

    test('Scenario 5: Partial Failure Reporting (Exact Message)', () async {
      // Create a mock tool registry where create_timetable_event succeeds, but schedule_recording fails
      final baseRegistry = AgentService.instance.registry;
      final failingRegistry = AgentToolRegistry([
        ...baseRegistry.tools.where((t) => t.name != 'schedule_recording'),
        _FailingScheduleRecordingTool(),
      ]);

      final planExecutor = AgentPlanExecutor(registry: failingRegistry);
      final agentService = AgentService(
        registry: failingRegistry,
        planExecutor: planExecutor,
      );

      final response = await agentService.process(
        prompt: 'Add AI tomorrow 10-11 and record it.',
        context: testContext,
      );

      expect(response.toolResults.length, equals(2));
      expect(response.toolResults[0].success, isTrue);
      expect(response.toolResults[1].success, isFalse);

      // Must state exact required message and NOT invent success
      expect(
        response.text,
        equals(
            "The class was added to your timetable, but I couldn't enable automatic recording."),
      );
    });

    test('Scenario 6: Missing information halts execution and asks question',
        () async {
      final planner = AgentPlanner();
      // Prompt without start/end time
      final plan = planner.createPlan('Add AI tomorrow and record it.');

      expect(plan.isBlockedOnMissingInfo, isTrue);
      expect(plan.missingInformationQuestion, isNotNull);
      expect(plan.missingInformationQuestion,
          contains('What time does your Artificial Intelligence class start'));
      expect(plan.steps.isEmpty, isTrue);

      // Execute through AgentService
      final response = await AgentService.instance.process(
        prompt: 'Add AI tomorrow and record it.',
        context: testContext,
      );

      // No tools executed
      expect(response.toolCalls.isEmpty, isTrue);
      expect(response.toolResults.isEmpty, isTrue);
      expect(response.text,
          contains('What time does your Artificial Intelligence class start'));

      // Timetable should NOT have been modified
      final entries = TimetableService.instance.entries;
      final tuesdayClasses = entries.where((e) => e.dayOfWeek == 'Tue');
      expect(tuesdayClasses.isEmpty, isTrue);
    });

    test('Scenario 7: Loop Prevention / Bounded Execution (max steps <= 6)',
        () async {
      expect(AgentPlanner.maxPlanSteps, equals(6));

      // Construct an artificial plan with 10 steps
      final steps = List.generate(
        10,
        (i) => AgentPlanStep(
          id: 'step_$i',
          tool: 'get_today_schedule',
          arguments: {},
          description: 'Step $i',
        ),
      );
      final plan = AgentPlan(
        planId: 'loop_test',
        originalRequest: 'Run 10 steps',
        steps: steps,
      );

      final executor =
          AgentPlanExecutor(registry: AgentService.instance.registry);
      final executed = await executor.execute(plan, context: testContext);

      // Enforced cap: plan steps must be capped at 6
      expect(executed.steps.length, equals(6));
      expect(executed.completedSteps.length, equals(6));
      expect(executed.status, equals(AgentPlanStatus.success));
    });
  });
}

class _FailingScheduleRecordingTool extends AgentTool {
  _FailingScheduleRecordingTool()
      : super(
          name: 'schedule_recording',
          description: 'Mock failing schedule recording tool',
          isReadOnly: false,
          parameters: const [],
        );

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  }) async {
    return AgentToolResult.failure(
      tool: name,
      message: 'Background recording scheduler service unavailable.',
      error: 'SCHEDULER_UNAVAILABLE',
    );
  }
}
