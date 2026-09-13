import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/agent/agent_intent.dart';
import 'package:pal_academic_copilot/agent/agent_service.dart';
import 'package:pal_academic_copilot/agent/agent_voice_controller.dart';
import 'package:pal_academic_copilot/services/stt_service.dart';
import 'package:pal_academic_copilot/services/voice_command_normalizer.dart';

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
        if (methodCall.method == 'stop') return 'mock_stopped.wav';
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

  group('VoiceCommandNormalizer Tests', () {
    test('Corrects phonetic confusions for schedule command and time range',
        () {
      const raw =
          'The people and the lecture of Tinto Levin on data structures.';
      final normalized = VoiceCommandNormalizer.normalize(raw);
      expect(
        normalized,
        'Hey Pal, schedule a class at 10 to 11 on Data Structures.',
      );
    });

    test('Corrects alternative greeting variations', () {
      const raw = 'Hey Paul, schedule a class at 10 to 11 on Data Structures.';
      final normalized = VoiceCommandNormalizer.normalize(raw);
      expect(
        normalized,
        'Hey Pal, schedule a class at 10 to 11 on Data Structures.',
      );
    });

    test('Normalizes technical network acronyms', () {
      const raw = 'prepare the comparison of ECB and UCP';
      final normalized = VoiceCommandNormalizer.normalize(raw);
      expect(normalized, contains('TCP'));
      expect(normalized, contains('UDP'));
    });
  });

  group('AgentIntent Voice Command Classification Tests', () {
    test('Classifies "Hey Pal, schedule a class..." as timetableAction', () {
      final intents = AgentIntent.detectIntents(
        'Hey Pal, schedule a class at 10 to 11 on Data Structures.',
      );
      expect(intents.first, equals(AgentIntent.timetableAction));
    });

    test(
        'Classifies "schedule a class at 10 to 11 on Data Structures" as timetableAction',
        () {
      final intents = AgentIntent.detectIntents(
        'schedule a class at 10 to 11 on Data Structures',
      );
      expect(intents.first, equals(AgentIntent.timetableAction));
    });

    test('Classifies "What is my next class?" as scheduleQuery', () {
      final intents = AgentIntent.detectIntents('What is my next class?');
      expect(intents.first, equals(AgentIntent.scheduleQuery));
    });

    test('Classifies "Find my upcoming assignment deadlines" as deadlineQuery',
        () {
      final intents = AgentIntent.detectIntents(
        'Find my upcoming assignment deadlines',
      );
      expect(intents.first, equals(AgentIntent.deadlineQuery));
    });
  });

  group('AgentService Tool Resolution for Voice Commands', () {
    late AgentService agentService;

    setUp(() {
      agentService = AgentService.instance;
    });

    test(
        'Resolves CREATE_TIMETABLE_EVENT with Data Structures and 10 to 11 times',
        () {
      final calls = agentService.determineToolCalls(
        'Hey Pal, schedule a class at 10 to 11 on Data Structures.',
      );
      expect(calls, isNotEmpty);
      final call = calls.first;
      expect(call.tool, equals('create_timetable_event'));
      expect(call.arguments['subject'], equals('Data Structures'));
      expect(call.arguments['startTime'], equals('10:00 AM'));
      expect(call.arguments['endTime'], equals('11:00 AM'));
    });

    test('Resolves CREATE_TIMETABLE_EVENT for normalized raw STT output', () {
      const raw =
          'The people and the lecture of Tinto Levin on data structures.';
      final clean = VoiceCommandNormalizer.normalize(raw);
      final calls = agentService.determineToolCalls(clean);
      expect(calls, isNotEmpty);
      final call = calls.first;
      expect(call.tool, equals('create_timetable_event'));
      expect(call.arguments['subject'], equals('Data Structures'));
      expect(call.arguments['startTime'], equals('10:00 AM'));
      expect(call.arguments['endTime'], equals('11:00 AM'));
    });
  });

  group('Academic Short Voice Command Suite (Section 18)', () {
    late AgentService agentService;

    setUp(() {
      agentService = AgentService.instance;
    });

    test('Command 1: "Hey Pal, what are my upcoming classes?"', () {
      final intents =
          AgentIntent.detectIntents('Hey Pal, what are my upcoming classes?');
      expect(intents.first, equals(AgentIntent.scheduleQuery));
      final calls = agentService
          .determineToolCalls('Hey Pal, what are my upcoming classes?');
      expect(calls.first.tool, equals('get_upcoming_classes'));
    });

    test('Command 2: "What\'s my next class?"', () {
      final intents = AgentIntent.detectIntents("What's my next class?");
      expect(intents.first, equals(AgentIntent.scheduleQuery));
      final calls = agentService.determineToolCalls("What's my next class?");
      expect(calls.first.tool, equals('get_upcoming_classes'));
      expect(calls.first.arguments['target'], equals('next'));
    });

    test('Command 3: "Show me my upcoming assignment deadlines."', () {
      final intents = AgentIntent.detectIntents(
          'Show me my upcoming assignment deadlines.');
      expect(intents.first, equals(AgentIntent.deadlineQuery));
      final calls = agentService
          .determineToolCalls('Show me my upcoming assignment deadlines.');
      expect(calls.first.tool, equals('get_upcoming_tasks'));
    });

    test('Command 4: "Schedule Data Structures from 10 AM to 11 AM."', () {
      final intents = AgentIntent.detectIntents(
          'Schedule Data Structures from 10 AM to 11 AM.');
      expect(intents.first, equals(AgentIntent.timetableAction));
      final calls = agentService
          .determineToolCalls('Schedule Data Structures from 10 AM to 11 AM.');
      expect(calls.first.tool, equals('create_timetable_event'));
      expect(calls.first.arguments['subject'], equals('Data Structures'));
      expect(calls.first.arguments['startTime'], equals('10:00 AM'));
      expect(calls.first.arguments['endTime'], equals('11:00 AM'));
    });

    test('Command 5: "Create a class for Operating Systems tomorrow at 2 PM."',
        () {
      final intents = AgentIntent.detectIntents(
          'Create a class for Operating Systems tomorrow at 2 PM.');
      expect(intents.first, equals(AgentIntent.timetableAction));
      final calls = agentService.determineToolCalls(
          'Create a class for Operating Systems tomorrow at 2 PM.');
      expect(calls.first.tool, equals('create_timetable_event'));
      expect(calls.first.arguments['subject'], equals('Operating Systems'));
      expect(calls.first.arguments['startTime'], equals('2:00 PM'));
    });

    test('Command 6: "Record my next class."', () {
      final intents = AgentIntent.detectIntents('Record my next class.');
      expect(intents.first, equals(AgentIntent.recordingAction));
      final calls = agentService.determineToolCalls('Record my next class.');
      expect(calls.first.tool, equals('schedule_recording'));
    });

    test('Command 7: "What assignments are due this week?"', () {
      final intents =
          AgentIntent.detectIntents('What assignments are due this week?');
      expect(intents.first, equals(AgentIntent.deadlineQuery));
      final calls = agentService
          .determineToolCalls('What assignments are due this week?');
      expect(calls.first.tool, equals('get_upcoming_tasks'));
    });

    test('Command 8: "Remind me about my TCP assignment tomorrow."', () {
      final intents = AgentIntent.detectIntents(
          'Remind me about my TCP assignment tomorrow.');
      expect(intents.first, equals(AgentIntent.taskAction));
      final calls = agentService
          .determineToolCalls('Remind me about my TCP assignment tomorrow.');
      expect(calls.first.tool, equals('create_task'));
    });

    test('Command 9: "What\'s on my timetable tomorrow?"', () {
      final intents =
          AgentIntent.detectIntents("What's on my timetable tomorrow?");
      expect(intents.first, equals(AgentIntent.scheduleQuery));
      final calls =
          agentService.determineToolCalls("What's on my timetable tomorrow?");
      expect(calls.first.tool, equals('get_upcoming_classes'));
    });

    test('Command 10: "Which assignment should I prioritize?"', () {
      final intents =
          AgentIntent.detectIntents('Which assignment should I prioritize?');
      expect(intents.first, equals(AgentIntent.taskQuery));
      final calls = agentService
          .determineToolCalls('Which assignment should I prioritize?');
      expect(calls.first.tool, equals('get_upcoming_tasks'));
    });
  });

  group('SttService Silence Trimming Tests', () {
    test('Trims leading and trailing silence with headroom preserved', () {
      // 16kHz audio: 16000 samples per sec
      // 500ms silence + 500ms speech + 500ms silence
      final sampleRate = 16000;
      final totalSamples = sampleRate * 3 ~/ 2; // 24000 samples
      final samples = Float32List(totalSamples);

      // Speech active between 8000 and 16000 (0.5s to 1.0s)
      for (int i = 8000; i < 16000; i++) {
        samples[i] = 0.5; // active sound
      }

      final trimmed = SttService.trimSilence(
        samples,
        sampleRate: sampleRate,
        threshold: 0.05,
        headroomMs: 150, // 2400 samples headroom
      );

      // Should be trimmed from around 8000 - 2400 = 5600 to 16000 + 2400 = 18400
      expect(trimmed.length, lessThan(totalSamples));
      expect(trimmed.length, greaterThan(8000));
    });
  });

  group('AgentVoiceController State Tests', () {
    test('Initial controller state is idle with empty transcript', () {
      final controller = AgentVoiceController.instance;
      expect(controller.state, equals(AgentVoiceState.idle));
      expect(controller.currentTranscript, isEmpty);
      expect(controller.pendingToolCalls, isEmpty);
    });

    test('Cancel session restores idle state and clears pending calls', () {
      final controller = AgentVoiceController.instance;
      controller.cancelSession();
      expect(controller.state, equals(AgentVoiceState.idle));
      expect(controller.currentTranscript, isEmpty);
      expect(controller.errorMessage, isNull);
    });
  });

  group('Section 12 — Hold Pal Intent Routing & Normalization Suite', () {
    late AgentService agentService;

    setUp(() {
      agentService = AgentService.instance;
    });

    test(
        'Test 1: Native STT "Hebbal create a data stitches class today for me from 10:00 a.m. to 11"',
        () async {
      const raw =
          'Hebbal create a data stitches class today for me from 10:00 a.m. to 11';
      final normalized = VoiceCommandNormalizer.normalize(raw);
      expect(normalized, contains('Data Structures'));
      expect(normalized, contains('10:00 AM'));

      final intents = AgentIntent.detectIntents(normalized);
      expect(intents.first, equals(AgentIntent.timetableAction));

      final calls = agentService.determineToolCalls(normalized);
      expect(calls.length, equals(1));
      final call = calls.first;
      expect(call.tool, equals('create_timetable_event'));
      expect(call.arguments['subject'], equals('Data Structures'));
      expect(call.arguments['day'], equals('today'));
      expect(call.arguments['startTime'], equals('10:00 AM'));
      expect(call.arguments['endTime'], equals('11:00 AM'));

      // Grounded processing test
      final response = await agentService.process(prompt: normalized);
      expect(response.text.toLowerCase(), contains('added'));
      expect(response.text.toLowerCase(), contains('data structures'));
      expect(response.text.toLowerCase(),
          isNot(contains('upcoming assignment deadlines')));
      expect(response.text.toLowerCase(), isNot(contains('sunday')));
    });

    test('Test 2: "Schedule OS lecture tomorrow 9 to 10"', () {
      const query = 'Schedule OS lecture tomorrow 9 to 10';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.timetableAction));

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('create_timetable_event'));
      expect(calls.first.arguments['subject'], equals('Operating Systems'));
      expect(calls.first.arguments['day'], equals('tomorrow'));
      expect(calls.first.arguments['startTime'], equals('9:00 AM'));
      expect(calls.first.arguments['endTime'], equals('10:00 AM'));
    });

    test('Test 3: "Add Computer Networks class on Monday from 2 PM to 3 PM"',
        () {
      const query = 'Add Computer Networks class on Monday from 2 PM to 3 PM';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.timetableAction));

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('create_timetable_event'));
      expect(calls.first.arguments['subject'], equals('Computer Networks'));
      expect(calls.first.arguments['day'].toLowerCase(), equals('monday'));
      expect(calls.first.arguments['startTime'], equals('2:00 PM'));
      expect(calls.first.arguments['endTime'], equals('3:00 PM'));
    });

    test('Test 4: "What classes do I have today?"', () {
      const query = 'What classes do I have today?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.scheduleQuery));

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('get_today_schedule'));
    });

    test('Test 5: "Do I have any assignments due tomorrow?"', () {
      const query = 'Do I have any assignments due tomorrow?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.deadlineQuery));

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('get_upcoming_tasks'));
      expect(calls.first.arguments['filter'], equals('tomorrow'));
    });

    test('Test 6: "Put an AI class today from 4 to 5"', () {
      const query = 'Put an AI class today from 4 to 5';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.timetableAction));

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('create_timetable_event'));
      expect(
          calls.first.arguments['subject'], equals('Artificial Intelligence'));
      expect(calls.first.arguments['day'], equals('today'));
      expect(calls.first.arguments['startTime'], equals('4:00 PM'));
      expect(calls.first.arguments['endTime'], equals('5:00 PM'));
    });

    test('Test 7: "When is my next class?"', () {
      const query = 'When is my next class?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.scheduleQuery));

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('get_upcoming_classes'));
      expect(calls.first.arguments['target'], equals('next'));
    });

    test('Test 8: "What are my deadlines this week?"', () {
      const query = 'What are my deadlines this week?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.deadlineQuery));

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('get_upcoming_tasks'));
      expect(calls.first.arguments['filter'], equals('this_week'));
    });

    test(
        'Test 9: "Hey Pal create Operating Systems class at 11 am to 12 pm today"',
        () {
      const query =
          'Hey Pal create Operating Systems class at 11 am to 12 pm today';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.timetableAction));

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('create_timetable_event'));
      expect(calls.first.arguments['subject'], equals('Operating Systems'));
      expect(calls.first.arguments['day'], equals('today'));
      expect(calls.first.arguments['startTime'], equals('11:00 AM'));
      expect(calls.first.arguments['endTime'], equals('12:00 PM'));
    });
  });

  group(
      'Section 8 & 12 — Task vs Timetable Separation and Disambiguation Suite',
      () {
    late AgentService agentService;

    setUp(() {
      agentService = AgentService.instance;
    });

    test(
        'TEST 1: "add a physics deadline to me today" -> CREATE_TASK with clarification question',
        () async {
      const query = 'add a physics deadline to me today';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.taskAction));
      expect(intents.contains(AgentIntent.timetableAction), isFalse);

      final response = await agentService.process(prompt: query);
      // Must NOT ask what time class starts/ends
      expect(
          response.text.toLowerCase().contains('what time does your'), isFalse);
      expect(
          response.text.toLowerCase().contains('class start and end'), isFalse);
      // Must ask clarifying question for deadline title
      expect(
          response.text, equals('What should I call this Physics deadline?'));
      expect(response.toolCalls.isEmpty, isTrue);
    });

    test(
        'TEST 2: "add my physics assignment due today" -> CREATE_TASK with title & resolved course',
        () async {
      const query = 'add my physics assignment due today';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.taskAction));

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('create_task'));
      expect(calls.first.arguments['title'], equals('Physics Assignment'));
      expect(calls.first.arguments['course'], equals('Engineering Physics'));
      expect(calls.first.arguments['dueDate'], equals('today'));

      final response = await agentService.process(prompt: query);
      expect(response.text, contains('Physics Assignment'));
      expect(response.text.toLowerCase().contains('what time'), isFalse);
    });

    test(
        'TEST 3: "schedule my physics class today from 10 to 11" -> CREATE_TIMETABLE_EVENT',
        () {
      const query = 'schedule my physics class today from 10 to 11';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.timetableAction));
      expect(intents.contains(AgentIntent.taskAction), isFalse);

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('create_timetable_event'));
      expect(calls.first.arguments['subject'], equals('Engineering Physics'));
      expect(calls.first.arguments['day'], equals('today'));
      expect(calls.first.arguments['startTime'], equals('10:00 AM'));
      expect(calls.first.arguments['endTime'], equals('11:00 AM'));
    });

    test(
        'TEST 4: "add a physics class from 10 to 11" -> CREATE_TIMETABLE_EVENT',
        () {
      const query = 'add a physics class from 10 to 11';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.timetableAction));
      expect(intents.contains(AgentIntent.taskAction), isFalse);

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('create_timetable_event'));
      expect(calls.first.arguments['subject'], equals('Engineering Physics'));
      expect(calls.first.arguments['startTime'], equals('10:00 AM'));
      expect(calls.first.arguments['endTime'], equals('11:00 AM'));
    });

    test('TEST 5: "when is my physics class?" -> SCHEDULE_QUERY', () {
      const query = 'when is my physics class?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.scheduleQuery));
      expect(intents.contains(AgentIntent.taskAction), isFalse);

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('get_upcoming_classes'));
      expect(calls.first.arguments['subject'], equals('physics'));
    });

    test('TEST 6: "what physics assignments are due?" -> DEADLINE_QUERY', () {
      const query = 'what physics assignments are due?';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.deadlineQuery));

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('get_upcoming_tasks'));
      expect(calls.first.arguments['query'], equals('physics'));
    });

    test('TEST 7: "remind me about physics tomorrow" -> CREATE_TASK', () {
      const query = 'remind me about physics tomorrow';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.taskAction));
      expect(intents.contains(AgentIntent.timetableAction), isFalse);

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('create_task'));
      expect(calls.first.arguments['course'], equals('Engineering Physics'));
      expect(calls.first.arguments['dueDate'], equals('tomorrow'));
    });

    test(
        'REGRESSION TEST: "Hey Pal, create a Data Structures class today from 10 to 11." -> create_timetable_event',
        () {
      const query =
          'Hey Pal, create a Data Structures class today from 10 to 11.';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.timetableAction));

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('create_timetable_event'));
      expect(calls.first.arguments['subject'], equals('Data Structures'));
    });

    test(
        'REGRESSION TEST: "Hey Pal, add a Data Structures assignment deadline today." -> create_task',
        () {
      const query = 'Hey Pal, add a Data Structures assignment deadline today.';
      final intents = AgentIntent.detectIntents(query);
      expect(intents.first, equals(AgentIntent.taskAction));
      expect(intents.contains(AgentIntent.timetableAction), isFalse);

      final calls = agentService.determineToolCalls(query);
      expect(calls.first.tool, equals('create_task'));
      expect(calls.first.arguments['course'], equals('Data Structures'));
    });
  });
}
