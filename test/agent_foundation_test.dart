import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/agent/agent_context.dart';
import 'package:pal_academic_copilot/agent/agent_parameter.dart';
import 'package:pal_academic_copilot/agent/agent_service.dart';
import 'package:pal_academic_copilot/agent/agent_tool.dart';
import 'package:pal_academic_copilot/agent/agent_tool_call.dart';
import 'package:pal_academic_copilot/agent/agent_tool_registry.dart';
import 'package:pal_academic_copilot/agent/agent_tool_result.dart';
import 'package:pal_academic_copilot/agent/tools/get_recent_lectures_tool.dart';
import 'package:pal_academic_copilot/agent/tools/get_today_schedule_tool.dart';
import 'package:pal_academic_copilot/agent/tools/get_upcoming_classes_tool.dart';
import 'package:pal_academic_copilot/agent/tools/get_upcoming_tasks_tool.dart';
import 'package:pal_academic_copilot/agent/tools/search_knowledge_tool.dart';
import 'package:pal_academic_copilot/services/deadline_service.dart';
import 'package:pal_academic_copilot/services/lecture_recording_service.dart';
import 'package:pal_academic_copilot/services/rag_service.dart';
import 'package:pal_academic_copilot/services/timetable_service.dart';

// Test Mock Tool as specified in prompt requirement 11
class MockDoubleValueTool extends AgentTool {
  MockDoubleValueTool()
      : super(
          name: 'test_tool',
          description: 'Multiplies input value by 2.',
          parameters: const [
            AgentParameter(
              name: 'value',
              type: AgentParameterType.integer,
              description: 'An integer number to double.',
              required: true,
            ),
          ],
        );

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  }) async {
    final val = arguments['value'] as int;
    return AgentToolResult.success(
      tool: name,
      message: 'Calculation complete',
      data: val * 2,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 1 — Agent Foundation & Safety Core', () {
    test('MockTool doubles input (value: 5 -> 10)', () async {
      final registry = AgentToolRegistry([MockDoubleValueTool()]);

      expect(registry.hasTool('test_tool'), isTrue);
      expect(registry.getTool('test_tool'), isNotNull);

      const call = AgentToolCall(
        tool: 'test_tool',
        arguments: {'value': 5},
      );

      final result = await registry.executeTool(call);

      expect(result.success, isTrue);
      expect(result.tool, 'test_tool');
      expect(result.data, 10);
      expect(result.message, 'Calculation complete');
    });

    test('Tool Safety: Unknown tools are rejected without executing', () async {
      final registry = AgentToolRegistry([MockDoubleValueTool()]);

      const maliciousCall = AgentToolCall(
        tool: 'system_execute_dart_code',
        arguments: {'code': 'exit(0)'},
      );

      final result = await registry.executeTool(maliciousCall);

      expect(result.success, isFalse);
      expect(result.error, 'TOOL_NOT_FOUND');
      expect(result.message, contains('Unknown tool'));
    });

    test('Validation: Missing required arguments return validation error',
        () async {
      final registry = AgentToolRegistry([MockDoubleValueTool()]);

      const invalidCall = AgentToolCall(
        tool: 'test_tool',
        arguments: {}, // missing required 'value'
      );

      final result = await registry.executeTool(invalidCall);

      expect(result.success, isFalse);
      expect(result.error, 'ARGUMENT_VALIDATION_ERROR');
      expect(result.message, contains('Missing required parameter: "value"'));
    });

    test('Validation: Wrong type parameter returns validation error', () async {
      final registry = AgentToolRegistry([MockDoubleValueTool()]);

      const typeErrorCall = AgentToolCall(
        tool: 'test_tool',
        arguments: {'value': 'not_an_int'},
      );

      final result = await registry.executeTool(typeErrorCall);

      expect(result.success, isFalse);
      expect(result.error, 'ARGUMENT_VALIDATION_ERROR');
      expect(result.message, contains('must be an integer'));
    });

    test('AgentToolCall safely parses markdown code block JSON', () {
      const llmOutput = '''
Sure! I will check that for you.
```json
{
  "tool": "test_tool",
  "arguments": {
    "value": 21
  }
}
```
''';

      final call = AgentToolCall.tryParse(llmOutput);
      expect(call, isNotNull);
      expect(call!.tool, 'test_tool');
      expect(call.arguments['value'], 21);
    });

    test('AgentToolRegistry formats tools cleanly for LLM system prompt', () {
      final registry = AgentToolRegistry([MockDoubleValueTool()]);
      final promptString = registry.formatToolsForPrompt();

      expect(promptString, contains('AVAILABLE ON-DEVICE TOOLS:'));
      expect(promptString, contains('Tool: "test_tool"'));
      expect(promptString, contains('Multiplies input value by 2.'));
      expect(promptString, contains('value (integer, required)'));
    });
  });

  group('Phase 2 — Read-Only Agent Tools', () {
    late TimetableService timetableService;
    late DeadlineService deadlineService;
    late RagService ragService;
    late LectureRecordingService recordingService;

    setUpAll(() async {
      timetableService = TimetableService.instance;
      deadlineService = DeadlineService.instance;
      ragService = RagService.instance;
      recordingService = LectureRecordingService.instance;

      await timetableService.init();
      await deadlineService.init(loadSeedData: true);
      await ragService.init();
      await recordingService.init();
    });

    test('All Phase 2 tools strictly enforce readOnly == true', () {
      final tools = [
        GetTodayScheduleTool(),
        GetUpcomingClassesTool(),
        GetUpcomingTasksTool(),
        SearchKnowledgeTool(),
        GetRecentLecturesTool(),
      ];

      for (final tool in tools) {
        expect(tool.isReadOnly, isTrue,
            reason: '${tool.name} must be read-only in Phase 2');
      }
    });

    test('Tool 1: get_today_schedule retrieves actual timetable for today',
        () async {
      final tool = GetTodayScheduleTool(timetableService: timetableService);
      // Simulate Monday (2026-09-14 is Monday)
      final mondayContext =
          AgentContext(currentDateTime: DateTime(2026, 9, 14, 8, 30));

      final result = await tool.execute({}, context: mondayContext);

      expect(result.success, isTrue);
      expect(result.data['day'], 'Mon');
      expect(result.data['classCount'], greaterThan(0));

      final classes = result.data['classes'] as List;
      expect(classes.first['subject'], 'Data Structures');
      expect(classes.first['start'], '09:00 AM');
      expect(classes.first['room'], 'Room 204');
    });

    test('Tool 1: get_today_schedule reports no classes without hallucination',
        () async {
      final tool = GetTodayScheduleTool(timetableService: timetableService);
      // Simulate Sunday (2026-09-20 is Sunday, which has no seed classes)
      final sundayContext =
          AgentContext(currentDateTime: DateTime(2026, 9, 20, 10, 0));

      final result = await tool.execute({}, context: sundayContext);

      expect(result.success, isTrue);
      expect(result.data['classCount'], 0);
      expect(result.message, contains('No classes scheduled for Sun'));
      expect((result.data['classes'] as List).isEmpty, isTrue);
    });

    test('Tool 2: get_upcoming_classes answers "When is my next class?"',
        () async {
      final tool = GetUpcomingClassesTool(timetableService: timetableService);
      // Simulate Monday at 10:30 AM (between Data Structures at 9am and OS at 11am)
      final mondayMidday =
          AgentContext(currentDateTime: DateTime(2026, 9, 14, 10, 30));

      final result =
          await tool.execute({'target': 'next'}, context: mondayMidday);

      expect(result.success, isTrue);
      final classes = result.data['classes'] as List;
      expect(classes.isNotEmpty, isTrue);
      expect(classes.first['subject'], 'Operating Systems');
      expect(classes.first['start'], '11:00 AM');
    });

    test(
        'Tool 2: get_upcoming_classes answers "What class do I have tomorrow?"',
        () async {
      final tool = GetUpcomingClassesTool(timetableService: timetableService);
      // Simulate Monday (tomorrow is Tuesday)
      final mondayContext =
          AgentContext(currentDateTime: DateTime(2026, 9, 14, 10, 0));

      final result =
          await tool.execute({'target': 'tomorrow'}, context: mondayContext);

      expect(result.success, isTrue);
      final classes = result.data['classes'] as List;
      expect(classes.isNotEmpty, isTrue);
      expect(classes.first['subject'], 'Operating Systems');
      expect(classes.first['start'], '10:00 AM');
    });

    test('Tool 3: get_upcoming_tasks answers "What assignments are due?"',
        () async {
      final tool = GetUpcomingTasksTool(deadlineService: deadlineService);

      final result = await tool.execute({'filter': 'pending'});

      expect(result.success, isTrue);
      final tasks = result.data['tasks'] as List;
      expect(tasks.isNotEmpty, isTrue);
      expect(
          tasks.any((t) => t['title'].toString().contains('Peterson')), isTrue);
    });

    test(
        'Tool 4: search_knowledge retrieves RAG chunks with page numbers and sources',
        () async {
      final tool = SearchKnowledgeTool(ragService: ragService);

      final result = await tool.execute({'query': 'Peterson mutual exclusion'});

      expect(result.success, isTrue);
      final matches = result.data['matches'] as List;
      expect(matches.isNotEmpty, isTrue);

      final first = matches.first;
      expect(first['documentName'], isNotNull);
      expect(first['pageNumber'], isNotNull);
      expect(first['extractionType'], isNotNull);
      expect(first['text'], contains('Peterson'));
    });

    test(
        'Tool 5: get_recent_lectures returns recorded lectures and transcript status',
        () async {
      final tool = GetRecentLecturesTool(recordingService: recordingService);

      final result = await tool.execute({'limit': 5});

      expect(result.success, isTrue);
      expect(result.data['recordings'], isA<List>());
    });

    test('Intent Routing in AgentService maps user questions to correct tools',
        () {
      final agent = AgentService();

      // "What is my next class?" -> get_upcoming_classes
      final call1 = agent.determineToolCall('What is my next class?');
      expect(call1, isNotNull);
      expect(call1!.tool, 'get_upcoming_classes');

      // "What classes do I have today?" -> get_today_schedule
      final call2 = agent.determineToolCall('What classes do I have today?');
      expect(call2, isNotNull);
      expect(call2!.tool, 'get_today_schedule');

      // "What assignments are due?" -> get_upcoming_tasks
      final call3 =
          agent.determineToolCall('What assignments are due this week?');
      expect(call3, isNotNull);
      expect(call3!.tool, 'get_upcoming_tasks');

      // "What did yesterday's lecture discuss?" -> get_recent_lectures
      final call4 =
          agent.determineToolCall("What did yesterday's lecture discuss?");
      expect(call4, isNotNull);
      expect(call4!.tool, 'get_recent_lectures');

      // "What did my notes say about process scheduling?" -> search_knowledge
      final call5 = agent
          .determineToolCall('What did my notes say about process scheduling?');
      expect(call5, isNotNull);
      expect(call5!.tool, 'search_knowledge');
      expect(call5.arguments['query'], 'process scheduling');
    });

    test(
        'Full Agent Pipeline: process() produces grounded, hallucination-free response',
        () async {
      final agent = AgentService();
      final mondayContext =
          AgentContext(currentDateTime: DateTime(2026, 9, 14, 8, 30));

      final response = await agent.process(
        prompt: 'What classes do I have today?',
        context: mondayContext,
      );

      expect(response.hasToolExecution, isTrue);
      expect(response.toolCalls.first.tool, 'get_today_schedule');
      expect(response.toolResults.first.success, isTrue);
      expect(response.text, contains('Data Structures'));
      expect(response.text, contains('09:00 AM'));
      expect(response.text, contains('Room 204'));
    });
  });
}
