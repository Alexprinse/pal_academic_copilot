import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/agent/agent_context.dart';
import 'package:pal_academic_copilot/agent/agent_intent.dart';
import 'package:pal_academic_copilot/agent/agent_service.dart';
import 'package:pal_academic_copilot/models/deadline.dart';
import 'package:pal_academic_copilot/models/timetable_entry.dart';
import 'package:pal_academic_copilot/services/deadline_service.dart';
import 'package:pal_academic_copilot/services/timetable_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AgentService agent;
  late AgentContext context;
  final fixedMonday = DateTime(2026, 9, 14, 10, 0); // Monday 10:00 AM

  setUp(() {
    AgentService.resetInstanceForTesting();
    agent = AgentService.instance;
    context = AgentContext(currentDateTime: fixedMonday);

    // Setup test timetable
    TimetableService.instance.setEntriesForTesting([
      const TimetableEntry(
        id: 'tt-1',
        subject: 'Data Structures',
        dayOfWeek: 'Mon',
        startTime: '11:00 AM',
        endTime: '12:00 PM',
        room: 'Room 204',
        professor: 'Prof. Sharma',
        type: 'Lecture',
      ),
      const TimetableEntry(
        id: 'tt-2',
        subject: 'Operating Systems',
        dayOfWeek: 'Tue',
        startTime: '09:00 AM',
        endTime: '10:30 AM',
        room: 'Lab 2',
        professor: 'Dr. Rao',
        type: 'Lab',
      ),
    ]);

    // Setup test deadlines
    DeadlineService.instance.setDeadlinesForTesting([
      Deadline(
        id: 'task-1',
        title: 'OS Lab 2: Process Synchronization',
        course: 'Operating Systems',
        dueDate: fixedMonday.add(const Duration(days: 2)), // Wednesday
        priority: TaskPriority.high,
      ),
      Deadline(
        id: 'task-2',
        title: 'Wave Optics Numerical Problems',
        course: 'Engineering Physics',
        dueDate: fixedMonday.add(const Duration(days: 4)), // Friday
        priority: TaskPriority.medium,
      ),
      Deadline(
        id: 'task-3',
        title: 'Binary Tree Traversal Assignment',
        course: 'Data Structures',
        dueDate: fixedMonday.add(const Duration(days: 3)), // Thursday
        priority: TaskPriority.high,
      ),
    ]);
  });

  group('Section 11 — Comprehensive Tool Routing Tests', () {
    test(
        'Test 1: "What is my next class?" -> SCHEDULE_QUERY & get_upcoming_classes',
        () async {
      const query = 'What is my next class?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.scheduleQuery));

      final calls = agent.determineToolCalls(query);
      expect(calls.length, equals(1));
      expect(calls.first.tool, equals('get_upcoming_classes'));

      final response = await agent.process(prompt: query, context: context);
      expect(response.toolCalls.first.tool, equals('get_upcoming_classes'));
      expect(response.text.toLowerCase(), contains('data structures'));
      expect(response.text.toLowerCase(), contains('11:00 am'));
    });

    test(
        'Test 2: "Show my upcoming assignments." -> TASK_QUERY & get_upcoming_tasks',
        () async {
      const query = 'Show my upcoming assignments.';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.taskQuery));

      final calls = agent.determineToolCalls(query);
      expect(calls.length, equals(1));
      expect(calls.first.tool, equals('get_upcoming_tasks'));

      final response = await agent.process(prompt: query, context: context);
      expect(response.toolCalls.first.tool, equals('get_upcoming_tasks'));
      expect(response.text, isNot(contains('Room 204')));
      expect(response.text.toLowerCase(), contains('os lab 2'));
    });

    test(
        'Test 3: "Find my upcoming assignment deadlines." -> DEADLINE_QUERY & get_upcoming_tasks (NOT classes)',
        () async {
      const query = 'Find my upcoming assignment deadlines.';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.deadlineQuery));

      final calls = agent.determineToolCalls(query);
      expect(calls.length, equals(1));
      expect(calls.first.tool, equals('get_upcoming_tasks'));
      expect(calls.first.tool, isNot('get_upcoming_classes'));

      final response = await agent.process(prompt: query, context: context);
      expect(response.toolCalls.first.tool, equals('get_upcoming_tasks'));
      // Must NOT contain class/room/time
      expect(response.text, isNot(contains('Room 204')));
      expect(response.text,
          isNot(contains('Next class is Data Structures at 11:00 AM')));
      // Must contain deadlines
      expect(response.text.toLowerCase(), contains('os lab 2'));
    });

    test(
        'Test 4: "What is due this week?" -> DEADLINE_QUERY & get_upcoming_tasks (NOT classes)',
        () async {
      const query = 'What is due this week?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.deadlineQuery));

      final calls = agent.determineToolCalls(query);
      expect(calls.length, equals(1));
      expect(calls.first.tool, equals('get_upcoming_tasks'));
      expect(calls.first.tool, isNot('get_upcoming_classes'));

      final response = await agent.process(prompt: query, context: context);
      expect(response.toolCalls.first.tool, equals('get_upcoming_tasks'));
      expect(response.text, isNot(contains('Room 204')));
    });

    test(
        'Test 5: "When is my Data Structures assignment due?" -> DEADLINE_QUERY & get_upcoming_tasks (filtered by query)',
        () async {
      const query = 'When is my Data Structures assignment due?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.deadlineQuery));

      final calls = agent.determineToolCalls(query);
      expect(calls.length, equals(1));
      expect(calls.first.tool, equals('get_upcoming_tasks'));
      expect(calls.first.arguments['query'], equals('data structures'));

      final response = await agent.process(prompt: query, context: context);
      expect(response.toolCalls.first.tool, equals('get_upcoming_tasks'));
      expect(response.text.toLowerCase(), contains('binary tree traversal'));
      expect(response.text, isNot(contains('11:00 AM (Mon, Room 204)')));
    });

    test(
        'Test 6: "When is my next Data Structures class?" -> SCHEDULE_QUERY & get_upcoming_classes',
        () async {
      const query = 'When is my next Data Structures class?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.scheduleQuery));

      final calls = agent.determineToolCalls(query);
      expect(calls.length, equals(1));
      expect(calls.first.tool, equals('get_upcoming_classes'));
      expect(calls.first.arguments['subject'], equals('data structures'));

      final response = await agent.process(prompt: query, context: context);
      expect(response.toolCalls.first.tool, equals('get_upcoming_classes'));
      expect(response.text.toLowerCase(), contains('data structures'));
      expect(response.text, contains('11:00 AM'));
    });

    test(
        'Test 7: "Do I have anything to submit tomorrow?" -> DEADLINE_QUERY & get_upcoming_tasks',
        () async {
      const query = 'Do I have anything to submit tomorrow?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.deadlineQuery));

      final calls = agent.determineToolCalls(query);
      expect(calls.length, equals(1));
      expect(calls.first.tool, equals('get_upcoming_tasks'));
      expect(calls.first.arguments['filter'], equals('tomorrow'));

      final response = await agent.process(prompt: query, context: context);
      expect(response.toolCalls.first.tool, equals('get_upcoming_tasks'));
      // No assignments due tomorrow (Tuesday), so it must report clean empty state
      expect(response.text,
          contains("You don't have any upcoming assignment deadlines."));
      expect(
          response.text,
          isNot(
              contains('Operating Systems'))); // No fallback to Tuesday class!
    });

    test(
        'Test 8: "What\'s happening on my timetable tomorrow?" -> SCHEDULE_QUERY & get_upcoming_classes',
        () async {
      const query = "What's happening on my timetable tomorrow?";
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.scheduleQuery));

      final calls = agent.determineToolCalls(query);
      expect(calls.length, equals(1));
      expect(calls.first.tool, equals('get_upcoming_classes'));
      expect(calls.first.arguments['target'], equals('tomorrow'));

      final response = await agent.process(prompt: query, context: context);
      expect(response.toolCalls.first.tool, equals('get_upcoming_classes'));
      expect(response.text.toLowerCase(), contains('operating systems'));
      expect(response.text, contains('Lab 2'));
    });
  });

  group('Section 12 — Multi-Intent Query Tests', () {
    test(
        'Compound query: "What is my next class and what assignments are due today?" -> triggers both tools',
        () async {
      const query = 'What is my next class and what assignments are due today?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents, contains(AgentIntent.scheduleQuery));
      expect(intents, contains(AgentIntent.deadlineQuery));

      final calls = agent.determineToolCalls(query);
      expect(calls.length, equals(2));
      expect(calls.map((c) => c.tool),
          containsAll(['get_upcoming_classes', 'get_upcoming_tasks']));

      final response = await agent.process(prompt: query, context: context);
      expect(response.toolCalls.length, equals(2));
      // Must answer BOTH parts cleanly
      expect(response.text, contains('Data Structures'));
      expect(response.text,
          contains("You don't have any upcoming assignment deadlines."));
    });
  });

  group('Section 9 — Tool Result Validation & Routing Mismatch Guard', () {
    test('Zero deadlines returns clean message and NEVER timetable entries',
        () async {
      DeadlineService.instance
          .setDeadlinesForTesting([]); // Clear all deadlines

      const query = 'Find my upcoming assignment deadlines.';
      final response = await agent.process(prompt: query, context: context);

      expect(response.toolCalls.first.tool, equals('get_upcoming_tasks'));
      expect(response.text,
          equals("You don't have any upcoming assignment deadlines."));
      expect(response.text, isNot(contains('Data Structures')));
      expect(response.text, isNot(contains('Room 204')));
    });
  });
}
