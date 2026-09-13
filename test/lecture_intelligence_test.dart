import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/extracted_page_content.dart';
import 'package:pal_academic_copilot/models/lecture_recording.dart';
import 'package:pal_academic_copilot/screens/lecture_details_screen.dart';
import 'package:pal_academic_copilot/screens/lectures_history_screen.dart';
import 'package:pal_academic_copilot/screens/pal_brain_screen.dart';
import 'package:pal_academic_copilot/screens/quiz_screen.dart';
import 'package:pal_academic_copilot/services/conversation_service.dart';
import 'package:pal_academic_copilot/services/lecture_intelligence_service.dart';
import 'package:pal_academic_copilot/services/lecture_recording_service.dart';
import 'package:pal_academic_copilot/services/rag_service.dart';

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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  group('LectureRecording Model & Source Types', () {
    test('Live Capture serialization with sourceType', () {
      final now = DateTime.now();
      final recording = LectureRecording(
        id: 'live_test_01',
        subject: 'Live Capture · Sep 12, 10:00 PM',
        title: 'Operating Systems Discussion',
        date: now,
        scheduledStart: '10:00 PM',
        scheduledEnd: '10:45 PM',
        actualStart: now,
        audioPath: '/data/live_test_01.wav',
        durationSeconds: 2700,
        fileSizeBytes: 1024 * 1024 * 5,
        sourceType: 'liveCapture',
        chunks: const [
          LectureTranscriptChunk(
            chunkIndex: 0,
            startTimestamp: '00:00',
            endTimestamp: '00:25',
            text: 'Welcome to operating systems and process management.',
          ),
          LectureTranscriptChunk(
            chunkIndex: 1,
            startTimestamp: '03:42',
            endTimestamp: '04:07',
            text: 'A context switch is the mechanism that saves process state.',
          ),
        ],
      );

      expect(recording.isLiveCapture, isTrue);
      expect(recording.displayTitle, 'Operating Systems Discussion');
      expect(recording.formattedDuration, '45 min');

      final json = recording.toJson();
      expect(json['sourceType'], 'liveCapture');
      expect(json['title'], 'Operating Systems Discussion');

      final deserialized = LectureRecording.fromJson(json);
      expect(deserialized.id, 'live_test_01');
      expect(deserialized.sourceType, 'liveCapture');
      expect(deserialized.isLiveCapture, isTrue);
      expect(deserialized.chunks.length, 2);
      expect(deserialized.chunks[1].startTimestamp, '03:42');
    });

    test('Scheduled lecture defaults to scheduledLecture', () {
      final now = DateTime.now();
      final rec = LectureRecording(
        id: 'sched_01',
        subject: 'Algorithms',
        date: now,
        scheduledStart: '09:00 AM',
        scheduledEnd: '10:00 AM',
        actualStart: now,
        audioPath: '/data/sched_01.wav',
        durationSeconds: 3600,
      );

      expect(rec.sourceType, 'scheduledLecture');
      expect(rec.isLiveCapture, isFalse);
      expect(rec.displayTitle, 'Algorithms');
    });
  });

  group('RAG Indexing & BM25 Timestamp Citations', () {
    test('indexLectureRecording creates timestamped chunks in RagService', () {
      final now = DateTime(2026, 9, 12, 10, 0);
      final recording = LectureRecording(
        id: 'live_os_rec',
        subject: 'Operating Systems',
        date: now,
        scheduledStart: '10:00 AM',
        scheduledEnd: '10:30 AM',
        actualStart: now,
        audioPath: 'live_os_rec.wav',
        durationSeconds: 1800,
        sourceType: 'liveCapture',
        chunks: const [
          LectureTranscriptChunk(
            chunkIndex: 0,
            startTimestamp: '00:00',
            endTimestamp: '00:25',
            text:
                'Introduction to operating systems and scheduling algorithms.',
          ),
          LectureTranscriptChunk(
            chunkIndex: 1,
            startTimestamp: '03:42',
            endTimestamp: '04:07',
            text:
                'Context switching saves the register state of the running process before swapping.',
          ),
        ],
      );

      RagService.instance.indexLectureRecording(recording);

      // Verify chunks were indexed
      final audioChunks = RagService.instance.allChunks
          .where((c) => c.id.startsWith('live_os_rec_'))
          .toList();
      expect(audioChunks.length, 2);

      final chunk2 = audioChunks.firstWhere((c) => c.id == 'live_os_rec_c1');
      expect(chunk2.timestamp, '03:42');
      expect(chunk2.sourceType, 'lectureTranscript');
      expect(chunk2.extractionType, ExtractionType.audioTranscript);
      expect(chunk2.isAudio, isTrue);
      expect(chunk2.documentName,
          contains('Live Capture · Operating Systems · 12 Sep'));

      // Perform BM25 Search
      final matches =
          RagService.instance.search(query: 'context switching process state');
      expect(matches.isNotEmpty, isTrue);

      final topMatch =
          matches.firstWhere((m) => m.chunk.id == 'live_os_rec_c1');
      expect(topMatch.chunk.timestamp, '03:42');
      expect(topMatch.chunk.text, contains('Context switching'));
    });

    test('unindexLectureRecording removes chunks cleanly', () {
      final chunksBefore = RagService.instance.allChunks
          .where((c) => c.id.startsWith('live_os_rec_'))
          .length;
      expect(chunksBefore, greaterThan(0));

      RagService.instance.unindexLectureRecording('live_os_rec');

      final chunksAfter = RagService.instance.allChunks
          .where((c) => c.id.startsWith('live_os_rec_'))
          .length;
      expect(chunksAfter, 0);
    });
  });

  group('Grounded Quiz Generation', () {
    test('generateQuizQuestions constructs grounded questions with citations',
        () {
      final now = DateTime.now();
      const summary = LectureSummary(
        keyPoints: [
          'Process scheduling controls CPU allocation.',
          'Context switching overhead should be minimized.',
        ],
        importantConcepts: [
          'Preemptive CPU Scheduling',
          'Process Control Block (PCB)',
        ],
        reviewQuestions: [
          'What structure holds the process state during context switching',
          'How does preemptive scheduling differ from cooperative scheduling',
        ],
      );

      final recording = LectureRecording(
        id: 'quiz_test_rec',
        subject: 'Operating Systems',
        title: 'Operating Systems · Live Capture',
        date: now,
        scheduledStart: '10:00 AM',
        scheduledEnd: '10:30 AM',
        actualStart: now,
        audioPath: 'mock.wav',
        durationSeconds: 1800,
        sourceType: 'liveCapture',
        summary: summary,
        chunks: const [
          LectureTranscriptChunk(
            chunkIndex: 0,
            startTimestamp: '00:00',
            endTimestamp: '00:25',
            text: 'Intro to OS.',
          ),
          LectureTranscriptChunk(
            chunkIndex: 1,
            startTimestamp: '02:15',
            endTimestamp: '02:40',
            text: 'The PCB stores the program counter and stack pointer.',
          ),
        ],
      );

      final questions =
          LectureIntelligenceService.instance.generateQuizQuestions(recording);
      expect(questions.length, greaterThanOrEqualTo(2));

      final q1 = questions.first;
      expect(q1.question, contains('context switching'));
      expect(q1.topic, 'Operating Systems · Live Capture');
      expect(q1.options.length, 4);
      expect(
          q1.options[q1.correctIndex], contains('Preemptive CPU Scheduling'));
      expect(q1.citation, contains('Operating Systems · Live Capture'));
    });

    testWidgets('QuizScreen renders with customQuestions',
        (WidgetTester tester) async {
      const customQ = [
        QuizQuestion(
          question: 'What is the function of the Process Control Block?',
          options: [
            'Stores process state and registers',
            'Manages hardware bus timing',
            'Compiles bytecode to native instructions',
            'Provides power management',
          ],
          correctIndex: 0,
          citation: 'Answer is PCB — sourced from OS Live Capture at 02:15',
          topic: 'Operating Systems',
          difficulty: 'Medium',
        ),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: QuizScreen(
            customQuestions: customQ,
            title: 'Quiz · Operating Systems',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quiz · Operating Systems'), findsOneWidget);
      expect(find.text('What is the function of the Process Control Block?'),
          findsOneWidget);
      expect(find.text('Stores process state and registers'), findsOneWidget);
      expect(find.text('QUESTION 1 OF 1'), findsOneWidget);

      // Select correct option
      await tester.tap(find.text('Stores process state and registers'));
      await tester.pumpAndSettle();

      expect(find.text('Answer is PCB — sourced from OS Live Capture at 02:15'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Live Capture & History UI', () {
    testWidgets(
        'LectureDetailsScreen renders Live Capture badge and Quiz Me button',
        (WidgetTester tester) async {
      final now = DateTime.now();
      final recording = LectureRecording(
        id: 'live_ui_rec',
        subject: 'Live Capture · Sep 12, 10:30 PM',
        title: 'Computer Architecture',
        date: now,
        scheduledStart: '10:30 PM',
        scheduledEnd: '11:15 PM',
        actualStart: now,
        audioPath: 'test_audio.wav',
        durationSeconds: 2700,
        sourceType: 'liveCapture',
        transcriptionStatus: 'completed',
        summaryStatus: 'completed',
        chunks: const [
          LectureTranscriptChunk(
            chunkIndex: 0,
            startTimestamp: '00:00',
            endTimestamp: '00:25',
            text: 'Instruction pipeline hazards and branch prediction.',
          ),
        ],
        summary: const LectureSummary(
          keyPoints: ['Pipelining improves throughput.'],
          importantConcepts: ['Branch Prediction'],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LectureDetailsScreen(recording: recording),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify display title
      expect(find.text('Computer Architecture'), findsWidgets);
      // Verify Live Capture badge
      expect(find.text('LIVE CAPTURE'), findsOneWidget);
      // Verify Ask Pal and Quiz Me buttons
      expect(find.text('Ask Pal'), findsOneWidget);
      expect(find.text('Quiz Me'), findsOneWidget);
      // Verify Rename action button exists
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('LecturesHistoryScreen displays LIVE badge for live capture',
        (WidgetTester tester) async {
      final now = DateTime.now();
      final liveRec = LectureRecording(
        id: 'history_live_rec',
        subject: 'Live Capture · Sep 12',
        title: 'Discrete Math Live Session',
        date: now,
        scheduledStart: '11:00 AM',
        scheduledEnd: '11:45 AM',
        actualStart: now,
        audioPath: 'mock.wav',
        durationSeconds: 2700,
        sourceType: 'liveCapture',
        transcriptionStatus: 'completed',
      );

      await LectureRecordingService.instance.updateRecordingInStore(liveRec);

      await tester.pumpWidget(
        const MaterialApp(
          home: LecturesHistoryScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Discrete Math Live Session'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Ask Pal Flow from Lecture Overview', () {
    testWidgets('Ask Pal shows Transcript Needed dialog if transcript is empty',
        (WidgetTester tester) async {
      final now = DateTime.now();
      final untranscribedRec = LectureRecording(
        id: 'untranscribed_01',
        subject: 'Database Systems',
        title: 'Database Systems Lecture',
        date: now,
        scheduledStart: '02:00 PM',
        scheduledEnd: '03:00 PM',
        actualStart: now,
        audioPath: 'mock_audio.wav',
        durationSeconds: 3600,
        transcriptionStatus: 'pending',
        transcriptText: '',
        chunks: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LectureDetailsScreen(recording: untranscribedRec),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Ask Pal
      await tester.tap(find.text('Ask Pal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify dialog appears
      expect(find.text('Transcript Needed'), findsOneWidget);
      expect(
        find.text(
            'Pal needs the lecture transcript first to analyze concepts and answer questions grounded in the lecture audio.'),
        findsOneWidget,
      );
      expect(find.text('Transcribe Recording'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Ask Pal shows SnackBar if transcription is in progress',
        (WidgetTester tester) async {
      final now = DateTime.now();
      final transcribingRec = LectureRecording(
        id: 'transcribing_01',
        subject: 'Database Systems',
        title: 'Database Systems Lecture',
        date: now,
        scheduledStart: '02:00 PM',
        scheduledEnd: '03:00 PM',
        actualStart: now,
        audioPath: 'mock_audio.wav',
        durationSeconds: 3600,
        transcriptionStatus: 'transcribing',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LectureDetailsScreen(recording: transcribingRec),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Ask Pal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text(
            'Whisper transcription in progress. Pal will be ready once transcription completes.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'PalBrainScreen creates dedicated chat with assistant overview and NO raw user bubble',
        (WidgetTester tester) async {
      ConversationService.instance.clearForTesting();

      final lectureDate = DateTime(2026, 9, 12, 14, 0);
      const testChunks = [
        LectureTranscriptChunk(
          chunkIndex: 0,
          startTimestamp: '00:00',
          endTimestamp: '00:25',
          text: 'Welcome to Operating Systems. Today we discuss deadlock.',
        ),
        LectureTranscriptChunk(
          chunkIndex: 1,
          startTimestamp: '03:42',
          endTimestamp: '04:07',
          text:
              'Pal verification test. The secret number is 8472. Memorize it.',
        ),
      ];

      final recording = LectureRecording(
        id: 'os_lecture_ask_pal',
        subject: 'Operating Systems',
        title: 'Operating Systems Lecture',
        date: lectureDate,
        scheduledStart: '02:00 PM',
        scheduledEnd: '03:00 PM',
        actualStart: lectureDate,
        audioPath: 'mock.wav',
        durationSeconds: 3600,
        transcriptionStatus: 'completed',
        summaryStatus: 'completed',
        transcriptText:
            'Welcome to Operating Systems. Today we discuss deadlock. Pal verification test. The secret number is 8472. Memorize it.',
        chunks: testChunks,
        summary: const LectureSummary(
          keyPoints: [
            'Deadlock conditions require mutual exclusion and hold-and-wait.',
            'Resource allocation graphs detect circular wait.',
          ],
          importantConcepts: [
            'Coffman Conditions',
            'Banker Algorithm',
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PalBrainScreen(lectureRecording: recording),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final activeSession = ConversationService.instance.activeConversation;
      expect(activeSession, isNotNull);
      // Title must be deterministic "{lecture title} · {formatted date}"
      expect(activeSession!.title, 'Operating Systems Lecture · Sep 12');
      expect(activeSession.lectureId, 'os_lecture_ask_pal');
      expect(activeSession.lectureTitle, 'Operating Systems Lecture');
      expect(activeSession.selectedRagScope, 'This Lecture');

      // CRITICAL: There must NOT be any user bubble containing raw transcript!
      final userMessages =
          activeSession.messages.where((m) => m.role == 'user').toList();
      expect(userMessages, isEmpty);

      // The initial message must be an assistant message containing the grounded summary
      expect(activeSession.messages.length, 1);
      final initialAsstMsg = activeSession.messages.first;
      expect(initialAsstMsg.role, 'assistant');
      expect(initialAsstMsg.text, contains('Lecture Overview'));
      expect(initialAsstMsg.text, contains('Deadlock conditions'));
      expect(initialAsstMsg.text, contains('Coffman Conditions'));
      expect(initialAsstMsg.citations.isNotEmpty, isTrue);

      // Verify UI displays the lecture overview and scope indicator
      expect(find.text('Operating Systems Lecture · Sep 12'), findsWidgets);
      expect(find.text('Context: Operating Systems Lecture'), findsOneWidget);

      // Verify BM25 search over this lecture finds the secret number 8472 with timestamp 03:42
      final matches = RagService.instance.search(
        query: 'secret number',
        filterLectureId: recording.id,
      );
      expect(matches.isNotEmpty, isTrue);
      expect(matches.first.chunk.text, contains('8472'));
      expect(matches.first.chunk.timestamp, '03:42');

      // Re-opening Ask Pal with same recording reuses existing session without duplicating
      final existing = ConversationService.instance
          .findConversationByLectureId(recording.id);
      expect(existing, isNotNull);
      expect(existing!.id, activeSession.id);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
