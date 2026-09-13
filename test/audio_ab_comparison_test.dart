import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/lecture_recording.dart';
import 'package:pal_academic_copilot/screens/audio_comparison_screen.dart';
import 'package:pal_academic_copilot/services/audio_comparison_service.dart';
import 'package:pal_academic_copilot/services/audio_noise_processor.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async {
        return 1;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global/events'),
      (MethodCall methodCall) async {
        return null;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('xyz.luan/audioplayers/events/ab_player_orig'),
      MockStreamHandler.inline(
        onListen: (args, sink) {},
        onCancel: (args) {},
      ),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('xyz.luan/audioplayers/events/ab_player_proc'),
      MockStreamHandler.inline(
        onListen: (args, sink) {},
        onCancel: (args) {},
      ),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async {
        return 1;
      },
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers.global'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers.global/events'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
            const EventChannel('xyz.luan/audioplayers/events/ab_player_orig'),
            null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
            const EventChannel('xyz.luan/audioplayers/events/ab_player_proc'),
            null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers'), null);
  });

  group('Audio A/B Comparison - Validation & Integrity', () {
    test('validateSamples detects valid audio within [-1.0, 1.0]', () {
      final samples = Float32List.fromList([-0.9, -0.5, 0.0, 0.5, 0.95]);
      final result =
          AudioNoiseProcessor.validateSamples(samples, expectedLength: 5);

      expect(result.isValid, isTrue);
      expect(result.invalidSampleCount, 0);
      expect(result.minSample, closeTo(-0.9, 0.001));
      expect(result.maxSample, closeTo(0.95, 0.001));
    });

    test('validateSamples detects NaN and Infinity', () {
      final samples =
          Float32List.fromList([0.1, double.nan, 0.3, double.infinity]);
      final result = AudioNoiseProcessor.validateSamples(samples);

      expect(result.isValid, isFalse);
      expect(result.invalidSampleCount, 2);
    });

    test('validateSamples detects values exceeding [-1.0, 1.0]', () {
      final samples = Float32List.fromList([0.1, 1.25, -1.5, 0.0]);
      final result = AudioNoiseProcessor.validateSamples(samples);

      expect(result.isValid, isFalse);
      expect(result.invalidSampleCount, 2);
    });

    test('validateSamples detects length mismatch', () {
      final samples = Float32List(100);
      final result =
          AudioNoiseProcessor.validateSamples(samples, expectedLength: 120);

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Length mismatch'));
    });
  });

  group('Audio A/B Comparison - WAV Roundtrip (Pure Dart)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pal_wav_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writeWavFile and readWavFile preserve audio samples faithfully',
        () async {
      const int sampleRate = 16000;
      const int numSamples = 1600; // 100ms
      final Float32List original = Float32List(numSamples);

      // Generate a 440 Hz sine wave
      for (int i = 0; i < numSamples; i++) {
        original[i] = 0.6 * math.sin(2 * math.pi * 440 * i / sampleRate);
      }

      final targetPath = '${tempDir.path}/test_audio.wav';
      final file = await AudioNoiseProcessor.writeWavFile(
        targetPath,
        original,
        sampleRate: sampleRate,
      );

      expect(await file.exists(), isTrue);
      // 44-byte header + 1600 * 2 bytes = 3244 bytes
      expect(await file.length(), 3244);

      final readData = await AudioNoiseProcessor.readWavFile(targetPath);
      expect(readData.sampleRate, sampleRate);
      expect(readData.samples.length, numSamples);

      // Verify quantization error is within 16-bit resolution (< 1 / 32767)
      for (int i = 0; i < numSamples; i++) {
        expect(readData.samples[i], closeTo(original[i], 0.001));
      }
    });
  });

  group('Audio A/B Comparison - DSP Presets', () {
    const int sampleRate = 16000;
    final Float32List testSamples = Float32List(16000); // 1 second
    for (int i = 0; i < testSamples.length; i++) {
      testSamples[i] = 0.1 * math.sin(2 * math.pi * 30 * i / sampleRate) +
          0.3 * math.sin(2 * math.pi * 500 * i / sampleRate);
    }

    test('Preset A: Bypass produces bit-exact audio without modifications', () {
      final processed = AudioNoiseProcessor.process(
        testSamples,
        sampleRate: sampleRate,
        config: DspConfig.bypass,
        verbose: false,
      );

      expect(processed.length, testSamples.length);
      for (int i = 0; i < testSamples.length; i++) {
        expect(processed[i], equals(testSamples[i]));
      }
    });

    test(
        'Preset B: High-pass only suppresses rumble while keeping length identical',
        () {
      final processed = AudioNoiseProcessor.process(
        testSamples,
        sampleRate: sampleRate,
        config: DspConfig.highPassOnly,
        verbose: false,
      );

      expect(processed.length, testSamples.length);
      final validation = AudioNoiseProcessor.validateSamples(processed,
          expectedLength: testSamples.length);
      expect(validation.isValid, isTrue);
    });

    test('Preset G: Full pipeline executes and validates without clipping', () {
      final processed = AudioNoiseProcessor.process(
        testSamples,
        sampleRate: sampleRate,
        config: DspConfig.full,
        verbose: false,
      );

      expect(processed.length, testSamples.length);
      final validation = AudioNoiseProcessor.validateSamples(processed,
          expectedLength: testSamples.length);
      expect(validation.isValid, isTrue);
      for (final s in processed) {
        expect(s.abs(), lessThanOrEqualTo(1.0));
      }
    });
  });

  group('Audio A/B Comparison - Deterministic Word Diff', () {
    test('Identical transcripts report 100% similarity and empty unique sets',
        () {
      const textA =
          'Today we discussed polynomial roots and fundamental theorem of algebra.';
      const textB =
          'today we discussed polynomial roots and fundamental theorem of algebra';

      final diff = AudioComparisonService.computeWordDiff(textA, textB);
      expect(diff.areIdentical, isTrue);
      expect(diff.uniqueToOriginal, isEmpty);
      expect(diff.uniqueToProcessed, isEmpty);
      expect(diff.similarityScore, 1.0);
      expect(diff.originalWordCount, diff.processedWordCount);
    });

    test('Identifies words unique to original and processed deterministically',
        () {
      const original =
          'The professor mentioned exam is on Friday with chapter five.';
      const processed =
          'The professor mentioned quiz is on Friday with chapter six.';

      final diff = AudioComparisonService.computeWordDiff(original, processed);
      expect(diff.areIdentical, isFalse);
      expect(diff.uniqueToOriginal, contains('exam'));
      expect(diff.uniqueToOriginal, contains('five'));
      expect(diff.uniqueToProcessed, contains('quiz'));
      expect(diff.uniqueToProcessed, contains('six'));
      expect(diff.commonWords, contains('professor'));
      expect(diff.commonWords, contains('friday'));
      expect(diff.similarityScore, lessThan(1.0));
      expect(diff.similarityScore, greaterThan(0.5));
    });

    test('Empty transcripts handled safely', () {
      final diff = AudioComparisonService.computeWordDiff('', '');
      expect(diff.areIdentical, isTrue);
      expect(diff.similarityScore, 1.0);
      expect(diff.originalWordCount, 0);
      expect(diff.processedWordCount, 0);
    });
  });

  group('Audio A/B Comparison - Non-destructive Pipeline Guarantee', () {
    late Directory tempDir;
    late String wavPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pal_ab_run_');
      final originalSamples = Float32List(8000);
      for (int i = 0; i < 8000; i++) {
        originalSamples[i] = 0.2 * math.sin(2 * math.pi * 300 * i / 16000);
      }
      wavPath = '${tempDir.path}/original_lecture.wav';
      await AudioNoiseProcessor.writeWavFile(wavPath, originalSamples);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Original file is strictly preserved without mutation', () async {
      final origFile = File(wavPath);
      final beforeLength = await origFile.length();
      final beforeBytes = await origFile.readAsBytes();

      final result = await AudioComparisonService.instance.runComparison(
        originalAudioPath: wavPath,
        recordingId: 'test_rec_001',
        config: DspConfig.full,
        runStt:
            false, // In unit test, Whisper native library is not initialized
      );

      final afterLength = await origFile.length();
      final afterBytes = await origFile.readAsBytes();

      // Verify original file byte-for-byte unmodified
      expect(afterLength, equals(beforeLength));
      expect(afterBytes, equals(beforeBytes));

      // Verify processed file is a distinct temporary file
      expect(result.processedAudioPath, isNot(equals(wavPath)));
      final procFile = File(result.processedAudioPath);
      expect(await procFile.exists(), isTrue);

      // Verify metrics
      expect(result.sampleCount, 8000);
      expect(result.sampleRate, 16000);
      expect(result.durationSeconds, 0.5);
      expect(result.validation.isValid, isTrue);

      // Clean up temporary file
      await procFile.delete();
    });
  });

  group('AudioComparisonScreen - Widget Rendering', () {
    late LectureRecording recording;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pal_widget_test_');
      final wavPath = '${tempDir.path}/test_rec.wav';
      final samples = Float32List(3200);
      for (int i = 0; i < 3200; i++) {
        samples[i] = 0.2 * math.sin(2 * math.pi * 400 * i / 16000);
      }
      await AudioNoiseProcessor.writeWavFile(wavPath, samples);

      recording = LectureRecording(
        id: 'rec_test_widget',
        title: 'Signal Processing 101',
        subject: 'ECE',
        audioPath: wavPath,
        date: DateTime(2026, 9, 13),
        scheduledStart: '10:00 AM',
        scheduledEnd: '11:00 AM',
        actualStart: DateTime(2026, 9, 13, 10, 0),
        durationSeconds: 1,
        transcriptionStatus: 'completed',
        transcriptText: 'Introduction to Fourier analysis and filter design.',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('Renders all A/B sections correctly',
        (WidgetTester tester) async {
      AudioComparisonResult? initialResult;
      await tester.runAsync(() async {
        initialResult = await AudioComparisonService.instance.runComparison(
          originalAudioPath: recording.audioPath,
          recordingId: recording.id,
          config: DspConfig.full,
          runStt: false,
        );
      });

      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AudioComparisonScreen(
            recording: recording,
            initialResult: initialResult,
            enablePlayers: false,
          ),
        ),
      );

      await tester.pump();

      // Check header
      expect(find.text('Audio A/B Comparison'), findsOneWidget);
      expect(find.text('Signal Processing 101'), findsOneWidget);

      // Check info banner
      expect(find.text('Deterministic A/B Audio Pipeline'), findsOneWidget);

      // Check presets section
      expect(find.text('DSP Test Presets'), findsOneWidget);
      expect(find.text('Preset G (Full)'), findsOneWidget);
      expect(find.text('Preset A (Bypass)'), findsOneWidget);

      // Check dual player section
      expect(find.text('Auditory A/B Comparison'), findsOneWidget);
      expect(find.text('Path A: Recorded Audio'), findsWidgets);
      expect(find.text('Path B: Recorded Audio + Pal DSP'), findsWidgets);

      // Check metrics table
      expect(find.text('A/B Signal Metrics'), findsOneWidget);
      expect(find.text('DSP VALIDATED'), findsOneWidget);
      expect(find.text('RMS'), findsOneWidget);
      expect(find.text('Peak'), findsOneWidget);

      // Check deterministic word diff
      expect(find.text('Deterministic Word Diff'), findsOneWidget);
      expect(find.text('Transcription Outputs'), findsOneWidget);
    });
  });
}
