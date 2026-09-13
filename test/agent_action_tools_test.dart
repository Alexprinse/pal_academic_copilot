import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/agent/agent_context.dart';
import 'package:pal_academic_copilot/agent/agent_service.dart';
import 'package:pal_academic_copilot/agent/tools/create_task_tool.dart';
import 'package:pal_academic_copilot/agent/tools/create_timetable_event_tool.dart';
import 'package:pal_academic_copilot/agent/tools/delete_timetable_event_tool.dart';
import 'package:pal_academic_copilot/agent/tools/schedule_recording_tool.dart';
import 'package:pal_academic_copilot/agent/tools/update_timetable_event_tool.dart';
import 'package:pal_academic_copilot/models/deadline.dart';
import 'package:pal_academic_copilot/models/timetable_entry.dart';
import 'package:pal_academic_copilot/services/deadline_service.dart';
import 'package:pal_academic_copilot/services/lecture_recording_service.dart';
import 'package:pal_academic_copilot/services/timetable_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Reference date: Monday, September 14, 2026 at 09:00 AM
  final testDateTime = DateTime(2026, 9, 14, 9, 0);
  final testContext = AgentContext(
    currentDateTime: testDateTime,
    userId: 'test_student',
  );

  setUp(() async {
    // Clear entries before each test
    final entries =
        List<TimetableEntry>.from(TimetableService.instance.entries);
    for (final e in entries) {
      TimetableService.instance.deleteEntry(e.id);
    }

    // Seed predictable schedule
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

    TimetableService.instance.addEntry(const TimetableEntry(
      id: 'tt_tue_ai',
      subject: 'Artificial Intelligence',
      dayOfWeek: 'Tue',
      startTime: '10:00 AM',
      endTime: '11:00 AM',
      room: 'Room 301',
      professor: 'Dr. Turing',
      type: 'Lecture',
    ));

    // Reset deadlines
    final deadlines = List<Deadline>.from(DeadlineService.instance.deadlines);
    for (final d in deadlines) {
      DeadlineService.instance.deleteDeadline(d.id);
    }

    // Reset AgentService
    AgentService.resetInstanceForTesting();
  });

  group('Phase 3 — Safety & Metadata Contracts', () {
    test('All Phase 3 Action Tools strictly declare isReadOnly == false', () {
      final createTool = CreateTimetableEventTool();
      final updateTool = UpdateTimetableEventTool();
      final deleteTool = DeleteTimetableEventTool();
      final taskTool = CreateTaskTool();
      final recTool = ScheduleRecordingTool();

      expect(createTool.isReadOnly, isFalse);
      expect(updateTool.isReadOnly, isFalse);
      expect(deleteTool.isReadOnly, isFalse);
      expect(taskTool.isReadOnly, isFalse);
      expect(recTool.isReadOnly, isFalse);
    });

    test('AgentToolRegistry registers all 10 Phase 2 & 3 tools', () {
      final service = AgentService.instance;
      expect(service.registry.toolNames.contains('create_timetable_event'),
          isTrue);
      expect(service.registry.toolNames.contains('update_timetable_event'),
          isTrue);
      expect(service.registry.toolNames.contains('delete_timetable_event'),
          isTrue);
      expect(service.registry.toolNames.contains('create_task'), isTrue);
      expect(service.registry.toolNames.contains('schedule_recording'), isTrue);
      expect(service.registry.toolNames.contains('get_today_schedule'), isTrue);
      expect(
          service.registry.toolNames.contains('get_upcoming_classes'), isTrue);
      expect(service.registry.toolNames.contains('get_upcoming_tasks'), isTrue);
      expect(service.registry.toolNames.contains('search_knowledge'), isTrue);
      expect(
          service.registry.toolNames.contains('get_recent_lectures'), isTrue);
    });
  });

  group('Tool 1: create_timetable_event', () {
    test('Adds class to TimetableService with correct day and time resolution',
        () async {
      final tool = CreateTimetableEventTool();

      final result = await tool.execute({
        'subject': 'Operating Systems',
        'day': 'tomorrow', // Tuesday relative to Monday Sep 14
        'startTime': '02:00 PM',
        'endTime': '03:30 PM',
        'room': 'Lab 102',
      }, context: testContext);

      expect(result.success, isTrue);
      expect(result.message, contains('Operating Systems'));

      // Verify state in TimetableService
      final added = TimetableService.instance.entries.firstWhere(
        (e) => e.subject == 'Operating Systems',
      );
      expect(added.dayOfWeek, 'Tue');
      expect(added.startTime, '02:00 PM');
      expect(added.endTime, '03:30 PM');
      expect(added.room, 'Lab 102');
    });

    test('Rejects duplicate class on same day and time', () async {
      final tool = CreateTimetableEventTool();

      // Attempt to add AI on Tue at 10:00 AM (already in seeded schedule)
      final result = await tool.execute({
        'subject': 'Artificial Intelligence',
        'day': 'Tue',
        'startTime': '10:00 AM',
      }, context: testContext);

      expect(result.success, isFalse);
      expect(result.error, 'DUPLICATE_EVENT');
    });

    test('Validates required fields', () async {
      final tool = CreateTimetableEventTool();
      final result = await tool.execute({
        'subject': '',
        'day': 'tomorrow',
        'startTime': '10:00 AM',
      }, context: testContext);

      expect(result.success, isFalse);
      expect(result.error, 'ARGUMENT_VALIDATION_ERROR');
    });
  });

  group('Tool 2: update_timetable_event', () {
    test('Moves class time when unambiguous', () async {
      final tool = UpdateTimetableEventTool();

      // "Move tomorrow's AI class to 11"
      final result = await tool.execute({
        'subject': 'AI',
        'currentDay': 'tomorrow',
        'newStartTime': '11:00 AM',
      }, context: testContext);

      expect(result.success, isTrue);
      expect(result.message, contains('Artificial Intelligence'));
      expect(result.message, contains('Moved'));

      // Verify updated entry in TimetableService
      final updated = TimetableService.instance.entries.firstWhere(
        (e) => e.subject == 'Artificial Intelligence' && e.dayOfWeek == 'Tue',
      );
      expect(updated.startTime, '11:00 AM');
    });

    test('Requires disambiguation when multiple classes match without day',
        () async {
      final tool = UpdateTimetableEventTool();

      // AI exists on Mon and Tue; no currentDay provided
      final result = await tool.execute({
        'subject': 'AI',
        'newStartTime': '11:00 AM',
      }, context: testContext);

      expect(result.success, isFalse);
      expect(result.error, 'AMBIGUOUS_MATCH');
      expect(result.message, contains('Multiple classes'));
      expect(result.message, contains('Which class would you like to move?'));
    });

    test('Returns not found error if class does not exist', () async {
      final tool = UpdateTimetableEventTool();

      final result = await tool.execute({
        'subject': 'Quantum Mechanics',
        'newStartTime': '11:00 AM',
      }, context: testContext);

      expect(result.success, isFalse);
      expect(result.error, 'ENTRY_NOT_FOUND');
    });
  });

  group('Tool 3: delete_timetable_event (Destructive Confirmation)', () {
    test('Demands confirmation before deleting class (confirmed: false)',
        () async {
      final tool = DeleteTimetableEventTool();

      final result = await tool.execute({
        'subject': 'AI',
        'day': 'Monday',
        'confirmed': false,
      }, context: testContext);

      expect(result.success, isTrue);
      expect(result.requiresConfirmation, isTrue);
      expect(
          result.message,
          contains(
              'Are you sure you want to remove Mon\'s Artificial Intelligence class'));

      // Class MUST NOT be deleted yet
      final stillExists = TimetableService.instance.entries.any(
        (e) => e.subject == 'Artificial Intelligence' && e.dayOfWeek == 'Mon',
      );
      expect(stillExists, isTrue);
    });

    test('Deletes class only after explicit confirmation (confirmed: true)',
        () async {
      final tool = DeleteTimetableEventTool();

      final result = await tool.execute({
        'subject': 'AI',
        'day': 'Monday',
        'confirmed': true,
      }, context: testContext);

      expect(result.success, isTrue);
      expect(result.requiresConfirmation, isFalse);
      expect(result.message,
          contains('Removed Mon\'s Artificial Intelligence class'));

      // Class MUST now be deleted from TimetableService
      final stillExists = TimetableService.instance.entries.any(
        (e) => e.subject == 'Artificial Intelligence' && e.dayOfWeek == 'Mon',
      );
      expect(stillExists, isFalse);
    });
  });

  group('Tool 4: create_task', () {
    test('Creates deadline task and inserts into DeadlineService', () async {
      final tool = CreateTaskTool();

      final result = await tool.execute({
        'title': 'Submit OS assignment',
        'dueDate': 'September 15',
        'priority': 'high',
      }, context: testContext);

      expect(result.success, isTrue);
      expect(result.message, contains('Operating Systems'));

      // Verify in DeadlineService
      expect(DeadlineService.instance.deadlines.isNotEmpty, isTrue);
      final task = DeadlineService.instance.deadlines.first;
      expect(task.title, 'Submit OS assignment');
      expect(task.course, 'Operating Systems');
      expect(task.priority, TaskPriority.high);
      expect(task.dueDate.month, 9);
      expect(task.dueDate.day, 15);
    });
  });

  group('Tool 5: schedule_recording', () {
    test('Schedules recording and ensures auto-record is enabled', () async {
      final tool = ScheduleRecordingTool();

      LectureRecordingService.instance.setAutoRecordEnabled(false);

      final result = await tool.execute({
        'subject': 'Computer Networks',
        'day': 'tomorrow',
        'startTime': '02:00 PM',
        'endTime': '03:00 PM',
      }, context: testContext);

      expect(result.success, isTrue);
      expect(result.message, contains('Computer Networks'));
      expect(LectureRecordingService.instance.isAutoRecordEnabled, isTrue);

      // Verify class was added to timetable so RecordingScheduler will capture it
      final classEntry = TimetableService.instance.entries.firstWhere(
        (e) => e.subject == 'Computer Networks',
      );
      expect(classEntry.dayOfWeek, 'Tue');
      expect(classEntry.startTime, '02:00 PM');
    });
  });

  group('Multi-Tool Execution & Full Agent Pipeline', () {
    test('Parses multi-tool request: "Add AI tomorrow at 10 and record it"',
        () {
      final service = AgentService.instance;
      final calls = service
          .determineToolCalls('Add AI tomorrow from 10 to 11 and record it');

      expect(calls.length, 2);
      expect(calls[0].tool, 'create_timetable_event');
      expect(calls[1].tool, 'schedule_recording');
      expect(calls[0].arguments['day'], 'tomorrow');
      expect(calls[1].arguments['subject'], 'Artificial Intelligence');
    });

    test('Executes multi-tool request through process() sequentially',
        () async {
      final service = AgentService.instance;

      final response = await service.process(
        prompt: 'Add Networking tomorrow from 2 to 3 and record it',
        context: testContext,
      );

      expect(response.toolCalls.length, 2);
      expect(response.toolResults.length, 2);
      expect(response.toolResults.every((r) => r.success), isTrue);

      // Verify class was created and recording enabled
      final exists = TimetableService.instance.entries.any(
        (e) => e.subject.toLowerCase().contains('network'),
      );
      expect(exists, isTrue);
      expect(LectureRecordingService.instance.isAutoRecordEnabled, isTrue);
    });

    test('AgentService process() handles delete confirmation flow correctly',
        () async {
      final service = AgentService.instance;

      // 1. User asks to delete class
      final response1 = await service.process(
        prompt: 'Delete my Monday AI class',
        context: testContext,
      );

      expect(response1.requiresConfirmation, isTrue);
      expect(
          response1.text,
          contains(
              'Are you sure you want to remove Mon\'s Artificial Intelligence class'));

      // Entry not deleted yet
      expect(
        TimetableService.instance.entries.any((e) => e.id == 'tt_mon_ai'),
        isTrue,
      );

      // 2. User confirms
      final response2 = await service.process(
        prompt: 'Yes, delete it',
        context: testContext,
      );

      expect(response2.requiresConfirmation, isFalse);
      expect(response2.text,
          contains('Removed Mon\'s Artificial Intelligence class'));

      // Entry is now deleted
      expect(
        TimetableService.instance.entries.any((e) => e.id == 'tt_mon_ai'),
        isFalse,
      );
    });
  });
}
