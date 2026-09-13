import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/agent/agent_context.dart';
import 'package:pal_academic_copilot/agent/agent_service.dart';
import 'package:pal_academic_copilot/agent/agent_tool_call.dart';
import 'package:pal_academic_copilot/models/deadline.dart';
import 'package:pal_academic_copilot/models/timetable_entry.dart';
import 'package:pal_academic_copilot/services/deadline_service.dart';
import 'package:pal_academic_copilot/services/timetable_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Reference time: Monday, September 14, 2026 at 09:00 AM
  final testDateTime = DateTime(2026, 9, 14, 9, 0);
  final testContext = AgentContext(
    currentDateTime: testDateTime,
    userId: 'student_123',
  );

  setUp(() async {
    // Clear timetable entries
    final entries =
        List<TimetableEntry>.from(TimetableService.instance.entries);
    for (final e in entries) {
      TimetableService.instance.deleteEntry(e.id);
    }

    // Clear deadlines
    final deadlines = List<Deadline>.from(DeadlineService.instance.deadlines);
    for (final d in deadlines) {
      DeadlineService.instance.deleteDeadline(d.id);
    }

    AgentService.resetInstanceForTesting();
  });

  group('Pal Agent — Tool Calling Protocol & Extraction', () {
    test('AgentToolCall extracts standard <tool_call> tags', () {
      const llmOutput = '''
I will check your timetable now.
<tool_call>
{
  "name": "get_upcoming_classes",
  "arguments": {
    "target": "all",
    "limit": 5
  }
}
</tool_call>
''';
      final calls = AgentToolCall.extractCalls(llmOutput);
      expect(calls.length, 1);
      expect(calls.first.tool, 'get_upcoming_classes');
      expect(calls.first.arguments['target'], 'all');
      expect(calls.first.arguments['limit'], 5);
    });

    test('AgentToolCall extracts markdown code fences', () {
      const llmOutput = '''
```tool_call
{
  "name": "get_today_schedule",
  "arguments": {}
}
```
''';
      final calls = AgentToolCall.extractCalls(llmOutput);
      expect(calls.length, 1);
      expect(calls.first.tool, 'get_today_schedule');
    });

    test('AgentToolRegistry formats tools manifest and system prompt', () {
      final registry = AgentService.instance.registry;
      final prompt = registry.buildSystemPrompt();

      expect(prompt, contains('AVAILABLE ON-DEVICE TOOLS:'));
      expect(prompt, contains('get_upcoming_classes'));
      expect(prompt, contains('get_today_schedule'));
      expect(prompt, contains('TOOL CALLING PROTOCOL:'));
      expect(prompt, contains('<tool_call>'));
    });
  });

  group('Pal Agent — Real Timetable Execution and Grounding', () {
    test(
        'User asks "What are my upcoming classes?" -> executes get_upcoming_classes and returns real classes',
        () async {
      // Seed real classes into application TimetableService
      TimetableService.instance.addEntry(const TimetableEntry(
        id: 'tt_mon_os',
        subject: 'Operating Systems',
        dayOfWeek: 'Mon',
        startTime: '10:00 AM',
        endTime: '11:00 AM',
        room: 'Room 301',
        professor: 'Dr. Tanenbaum',
        type: 'Lecture',
      ));

      TimetableService.instance.addEntry(const TimetableEntry(
        id: 'tt_mon_cn',
        subject: 'Computer Networks',
        dayOfWeek: 'Mon',
        startTime: '02:00 PM',
        endTime: '03:00 PM',
        room: 'Lab 204',
        professor: 'Dr. Cerf',
        type: 'Lab',
      ));

      final service = AgentService.instance;

      // 1. Tool selection verification
      final calls = service.determineToolCalls(
        'What are my upcoming classes?',
      );
      expect(calls.isNotEmpty, isTrue);
      expect(calls.first.tool, 'get_upcoming_classes');

      // 2. Full Agent process pipeline verification
      final response = await service.process(
        prompt: 'What are my upcoming classes?',
        context: testContext,
      );

      expect(response.toolCalls.length, 1);
      expect(response.toolCalls.first.tool, 'get_upcoming_classes');
      expect(response.toolResults.length, 1);
      expect(response.toolResults.first.success, isTrue);

      // 3. Grounding: Answer must contain live timetable data
      expect(response.text, contains('Operating Systems'));
      expect(response.text, contains('10:00 AM'));
      expect(response.text, contains('Computer Networks'));
      expect(response.text, contains('02:00 PM'));

      // 4. Zero technical clutter
      expect(response.text, isNot(contains('<tool_call>')));
      expect(response.text, isNot(contains('</tool_call>')));
      expect(response.text, isNot(contains('{"name":')));
    });

    test(
        'User asks "What is my next class?" -> grounds accurately on next chronological class',
        () async {
      TimetableService.instance.addEntry(const TimetableEntry(
        id: 'tt_mon_os',
        subject: 'Operating Systems',
        dayOfWeek: 'Mon',
        startTime: '10:00 AM',
        endTime: '11:00 AM',
        room: 'Room 301',
        professor: 'Dr. Tanenbaum',
      ));

      final service = AgentService.instance;
      final response = await service.process(
        prompt: 'What is my next class?',
        context: testContext,
      );

      expect(response.toolCalls.first.tool, 'get_upcoming_classes');
      expect(response.text, contains('Operating Systems'));
      expect(response.text, contains('10:00 AM'));
      expect(response.text, contains('Room 301'));
    });

    test(
        'User asks "What classes do I have today?" -> executes get_today_schedule',
        () async {
      TimetableService.instance.addEntry(const TimetableEntry(
        id: 'tt_mon_ai',
        subject: 'Artificial Intelligence',
        dayOfWeek: 'Mon',
        startTime: '11:30 AM',
        endTime: '01:00 PM',
        room: 'Hall B',
        professor: 'Dr. Russell',
      ));

      final service = AgentService.instance;
      final response = await service.process(
        prompt: 'What classes do I have today?',
        context: testContext,
      );

      expect(response.toolCalls.first.tool, 'get_today_schedule');
      expect(response.text, contains('Artificial Intelligence'));
      expect(response.text, contains('11:30 AM'));
      expect(response.text, contains('Hall B'));
    });

    test('Empty timetable: Pal clearly states no classes without hallucination',
        () async {
      final service = AgentService.instance;
      final response = await service.process(
        prompt: 'What are my upcoming classes?',
        context: testContext,
      );

      expect(response.toolCalls.first.tool, 'get_upcoming_classes');
      expect(response.toolResults.first.success, isTrue);
      expect(response.text,
          contains("Your timetable doesn't contain any upcoming classes."));
      expect(response.text,
          isNot(contains("I'm not aware of your current schedule")));
    });

    test(
        'User asks "What assignments are due soon?" -> executes get_upcoming_tasks',
        () async {
      DeadlineService.instance.addDeadline(Deadline(
        id: 'task_os_1',
        title: 'Kernel Architecture Report',
        course: 'Operating Systems',
        dueDate: DateTime(2026, 9, 16, 23, 59),
        priority: TaskPriority.high,
      ));

      final service = AgentService.instance;
      final response = await service.process(
        prompt: 'What assignments are due soon?',
        context: testContext,
      );

      expect(response.toolCalls.first.tool, 'get_upcoming_tasks');
      expect(response.text, contains('Kernel Architecture Report'));
      expect(response.text, contains('Operating Systems'));
      expect(response.text, contains('HIGH'));
    });

    test('User asks notes question -> executes search_knowledge', () async {
      final service = AgentService.instance;
      final calls = service.determineToolCalls(
        'What did my OS lecture say about process scheduling?',
      );

      expect(calls.isNotEmpty, isTrue);
      expect(calls.first.tool, 'search_knowledge');
      expect(calls.first.arguments['query'], contains('process scheduling'));
    });
  });

  group('Pal Agent — Safety & Iteration Caps', () {
    test('MAX_TOOL_ITERATIONS constant is 5', () {
      expect(AgentService.maxToolIterations, 5);
    });

    test('Unknown tools are rejected with standardized error result', () async {
      final registry = AgentService.instance.registry;
      const call = AgentToolCall(
        tool: 'arbitrary_shell_command',
        arguments: {'cmd': 'rm -rf /'},
      );

      final result = await registry.executeTool(call);
      expect(result.success, isFalse);
      expect(result.error, 'TOOL_NOT_FOUND');
    });

    test('Malformed arguments fail with ARGUMENT_VALIDATION_ERROR', () async {
      final registry = AgentService.instance.registry;
      const call = AgentToolCall(
        tool: 'create_timetable_event',
        arguments: {
          // Missing required 'subject', 'day', and 'startTime'
        },
      );

      final result = await registry.executeTool(call);
      expect(result.success, isFalse);
      expect(result.error, 'ARGUMENT_VALIDATION_ERROR');
    });
  });
}
