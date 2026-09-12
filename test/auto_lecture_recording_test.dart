import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/lecture_recording.dart';
import 'package:pal_academic_copilot/models/timetable_entry.dart';
import 'package:pal_academic_copilot/screens/lectures_history_screen.dart';
import 'package:pal_academic_copilot/screens/lecture_details_screen.dart';
import 'package:pal_academic_copilot/services/lecture_recording_service.dart';
import 'package:pal_academic_copilot/services/recording_scheduler.dart';
import 'package:pal_academic_copilot/services/stt_service.dart';
import 'package:pal_academic_copilot/services/timetable_service.dart';
import 'package:pal_academic_copilot/widgets/auto_record_consent_sheet.dart';

import 'package:flutter/services.dart';

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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  group('Lecture Recording Models', () {
    test('LectureTranscriptChunk JSON serialization', () {
      const chunk = LectureTranscriptChunk(
        chunkIndex: 0,
        startTimestamp: '00:00',
        endTimestamp: '00:25',
        text: 'Hello world',
      );

      final json = chunk.toJson();
      expect(json['chunkIndex'], 0);
      expect(json['startTimestamp'], '00:00');
      expect(json['endTimestamp'], '00:25');
      expect(json['text'], 'Hello world');

      final deserialized = LectureTranscriptChunk.fromJson(json);
      expect(deserialized.text, 'Hello world');
      expect(deserialized.startTimestamp, '00:00');
    });

    test('LectureSummary JSON serialization', () {
      const summary = LectureSummary(
        keyPoints: ['Key 1', 'Key 2'],
        importantConcepts: ['Concept A'],
        actionItems: ['Submit lab by Friday'],
        reviewQuestions: ['What is mutex?'],
      );

      final json = summary.toJson();
      final deserialized = LectureSummary.fromJson(json);

      expect(deserialized.keyPoints.length, 2);
      expect(deserialized.importantConcepts.first, 'Concept A');
      expect(deserialized.actionItems.first, 'Submit lab by Friday');
      expect(deserialized.reviewQuestions.first, 'What is mutex?');
    });

    test('LectureRecording duration formatting', () {
      final now = DateTime.now();
      final rec1 = LectureRecording(
        id: 'r1',
        subject: 'Operating Systems',
        date: now,
        scheduledStart: '09:00 AM',
        scheduledEnd: '10:00 AM',
        actualStart: now,
        audioPath: 'mock.wav',
        durationSeconds: 3120, // 52 min
      );
      expect(rec1.formattedDuration, '52 min');

      final rec2 = rec1.copyWith(durationSeconds: 45);
      expect(rec2.formattedDuration, '45 sec');

      final rec3 = rec1.copyWith(durationSeconds: 3700); // 1 hr 1 min
      expect(rec3.formattedDuration, '1 hr 1 min');
    });

    test('LectureRecording file size formatting', () {
      final now = DateTime.now();
      final rec = LectureRecording(
        id: 'r_size',
        subject: 'Operating Systems',
        date: now,
        scheduledStart: '09:00 AM',
        scheduledEnd: '10:00 AM',
        actualStart: now,
        audioPath: 'test.wav',
        durationSeconds: 100,
        fileSizeBytes: 2450000,
      );

      expect(rec.formattedFileSize, '2.34 MB');
      expect(rec.copyWith(fileSizeBytes: 512000).formattedFileSize, '500.0 KB');
      expect(rec.copyWith(fileSizeBytes: 0).formattedFileSize, '0 KB');
    });
  });

  group('Audio & WAV Verification Pipeline', () {
    test('validateWavFile rejects non-existent audio file', () async {
      final result =
          await SttService.validateWavFile('non_existent_audio_path_12345.wav');
      expect(result.isValid, isFalse);
      expect(result.error, contains('File does not exist'));
    });

    test('validateWavFile rejects files smaller than 44-byte WAV header',
        () async {
      final tempFile = File(
          '${Directory.systemTemp.path}/test_small_${DateTime.now().millisecondsSinceEpoch}.wav');
      await tempFile.writeAsBytes([1, 2, 3, 4]);

      final result = await SttService.validateWavFile(tempFile.path);
      expect(result.isValid, isFalse);
      expect(
          result.error, contains('smaller than standard WAV 44-byte header'));

      if (await tempFile.exists()) await tempFile.delete();
    });

    test('validateWavFile validates synthetic 16kHz mono 16-bit PCM WAV',
        () async {
      final tempFile = File(
          '${Directory.systemTemp.path}/test_valid_${DateTime.now().millisecondsSinceEpoch}.wav');

      // Build valid 44-byte WAV header
      final header = Uint8List(44);
      final byteData = ByteData.sublistView(header);

      // "RIFF"
      header.setRange(0, 4, 'RIFF'.codeUnits);
      byteData.setUint32(4, 36 + 1000, Endian.little); // Chunk size
      // "WAVE"
      header.setRange(8, 12, 'WAVE'.codeUnits);
      // "fmt "
      header.setRange(12, 16, 'fmt '.codeUnits);
      byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
      byteData.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
      byteData.setUint16(22, 1, Endian.little); // NumChannels (1 = mono)
      byteData.setUint32(24, 16000, Endian.little); // SampleRate (16000 Hz)
      byteData.setUint32(28, 32000, Endian.little); // ByteRate (16000 * 1 * 2)
      byteData.setUint16(32, 2, Endian.little); // BlockAlign
      byteData.setUint16(34, 16, Endian.little); // BitsPerSample (16-bit)
      // "data"
      header.setRange(36, 40, 'data'.codeUnits);
      byteData.setUint32(40, 1000, Endian.little); // Data length

      final data = Uint8List(1044);
      data.setRange(0, 44, header);
      await tempFile.writeAsBytes(data);

      final result = await SttService.validateWavFile(tempFile.path);
      expect(result.isValid, isTrue);
      expect(result.sampleRate, 16000);
      expect(result.numChannels, 1);
      expect(result.bitsPerSample, 16);
      expect(result.fileSizeBytes, 1044);

      if (await tempFile.exists()) await tempFile.delete();
    });

    test(
        'SttService transcribeAudioFile rejects invalid audio with error and NO mock fallback',
        () async {
      final result = await SttService.instance
          .transcribeAudioFile('non_existent_file.wav');
      // Must NOT return the old mock Operating Systems Lab text!
      expect(result, isNot(contains('Assignment 2')));
      expect(result, isNot(contains('Dekker')));
      expect(result, isNot(contains('Peterson')));
      expect(result, contains("Couldn't transcribe this recording"));
    });
  });

  group('LectureRecordingService Lifecycle', () {
    setUp(() async {
      await TimetableService.instance.init();
      await LectureRecordingService.instance.init();
    });

    test('Toggling auto-record setting', () {
      final service = LectureRecordingService.instance;
      service.setAutoRecordEnabled(true);
      expect(service.isAutoRecordEnabled, isTrue);

      service.setAutoRecordEnabled(false);
      expect(service.isAutoRecordEnabled, isFalse);

      service.setAutoRecordEnabled(true);
      expect(service.isAutoRecordEnabled, isTrue);
    });

    test('Manual start and stop of class recording updates state', () async {
      final service = LectureRecordingService.instance;

      const entry = TimetableEntry(
        id: 'test-class',
        subject: 'Algorithms & Data Structures',
        dayOfWeek: 'Mon',
        startTime: '10:00 AM',
        endTime: '11:00 AM',
      );

      await service.startClassRecording(entry: entry);
      expect(service.isRecordingNow, isTrue);
      expect(service.activeRecording?.subject, 'Algorithms & Data Structures');

      final finalized = await service.stopActiveRecording();
      expect(service.isRecordingNow, isFalse);
      expect(finalized?.subject, 'Algorithms & Data Structures');
      expect(service.recordings.first.subject, 'Algorithms & Data Structures');
    });
  });

  group('RecordingScheduler Dev Test Mode', () {
    test('scheduleTestLecture triggers and stops without throwing', () async {
      RecordingScheduler.instance.scheduleTestLecture(
        subject: 'Test Schedule Lecture',
        delaySeconds: 0,
        durationSeconds: 1,
      );
      expect(RecordingScheduler.instance.isTestModeActive, isTrue);
      // Wait for test schedule timers to resolve to prevent isolate leakage across tests
      await Future.delayed(const Duration(milliseconds: 1200));
      expect(RecordingScheduler.instance.isTestModeActive, isFalse);
    });
  });

  group('Lecture Recording UI Widgets', () {
    testWidgets('AutoRecordConsentSheet renders key points and buttons',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AutoRecordConsentSheet(),
          ),
        ),
      );

      expect(find.text('Automatic Class Recording'), findsOneWidget);
      expect(find.text('100% On-Device Privacy'), findsOneWidget);
      expect(find.text('Enable Auto-Record'), findsOneWidget);
      expect(find.text('Keep Disabled'), findsOneWidget);
    });

    testWidgets('LecturesHistoryScreen renders list and past recordings',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LecturesHistoryScreen(),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('My Lectures'), findsOneWidget);
      expect(find.text('PAST RECORDINGS'), findsOneWidget);
    });

    testWidgets('LectureDetailsScreen renders tabs and transcript correctly',
        (tester) async {
      final now = DateTime.now();
      final sampleRecording = LectureRecording(
        id: 'rec_details_test',
        subject: 'Operating Systems',
        date: now,
        scheduledStart: '09:00 AM',
        scheduledEnd: '10:00 AM',
        actualStart: now,
        audioPath: 'test.wav',
        durationSeconds: 3000,
        transcriptionStatus: 'completed',
        summaryStatus: 'completed',
        chunks: const [
          LectureTranscriptChunk(
            chunkIndex: 0,
            startTimestamp: '00:00',
            endTimestamp: '00:25',
            text: 'Critical section problem and mutual exclusion.',
          ),
        ],
        summary: const LectureSummary(
          keyPoints: ['Mutual exclusion is critical'],
          importantConcepts: ['Peterson Algorithm'],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LectureDetailsScreen(recording: sampleRecording),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Operating Systems'), findsWidgets);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Transcript'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Deadlines'), findsOneWidget);

      // Tap on Transcript tab
      await tester.tap(find.text('Transcript'));
      await tester.pumpAndSettle();
      expect(find.text('Critical section problem and mutual exclusion.'),
          findsOneWidget);

      // Tap on Summary tab
      await tester.tap(find.text('Summary'));
      await tester.pumpAndSettle();
      expect(find.text('Key Takeaways'), findsOneWidget);
      expect(find.text('Mutual exclusion is critical'), findsOneWidget);
    });
  });
}
