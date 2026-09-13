import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'audio_noise_processor.dart';
import 'stt_service.dart';

/// Statistical deterministic word difference result between Path A and Path B.
/// Strictly computed without any LLM hallucination or nondeterminism.
class WordDiffResult {
  final int originalWordCount;
  final int processedWordCount;
  final List<String> uniqueToOriginal;
  final List<String> uniqueToProcessed;
  final List<String> commonWords;
  final double similarityScore; // Jaccard similarity [0.0 - 1.0]

  const WordDiffResult({
    required this.originalWordCount,
    required this.processedWordCount,
    required this.uniqueToOriginal,
    required this.uniqueToProcessed,
    required this.commonWords,
    required this.similarityScore,
  });

  bool get areIdentical =>
      uniqueToOriginal.isEmpty &&
      uniqueToProcessed.isEmpty &&
      originalWordCount == processedWordCount;

  @override
  String toString() {
    return 'WordDiff: Orig: $originalWordCount words, Proc: $processedWordCount words, '
        'Unique Orig: ${uniqueToOriginal.length}, Unique Proc: ${uniqueToProcessed.length}, '
        'Similarity: ${(similarityScore * 100).toStringAsFixed(1)}%';
  }
}

/// Comprehensive outcome of an on-device A/B audio transcription test.
class AudioComparisonResult {
  final String originalAudioPath;
  final String processedAudioPath;
  final DspConfig dspConfig;
  final int sampleRate;
  final int sampleCount;
  final double durationSeconds;
  final DspValidationResult validation;
  final AudioMetrics originalMetrics;
  final AudioMetrics processedMetrics;
  final int dspElapsedMs;
  final String originalTranscript;
  final String processedTranscript;
  final int originalSttElapsedMs;
  final int processedSttElapsedMs;
  final WordDiffResult wordDiff;

  const AudioComparisonResult({
    required this.originalAudioPath,
    required this.processedAudioPath,
    required this.dspConfig,
    required this.sampleRate,
    required this.sampleCount,
    required this.durationSeconds,
    required this.validation,
    required this.originalMetrics,
    required this.processedMetrics,
    required this.dspElapsedMs,
    required this.originalTranscript,
    required this.processedTranscript,
    required this.originalSttElapsedMs,
    required this.processedSttElapsedMs,
    required this.wordDiff,
  });

  /// Difference in RMS in dBFS (processed - original). Negative means attenuated floor.
  double get rmsChangeDb => processedMetrics.rmsDbFs - originalMetrics.rmsDbFs;

  /// Difference in Peak in dBFS.
  double get peakChangeDb =>
      processedMetrics.peakDbFs - originalMetrics.peakDbFs;
}

class AudioComparisonService {
  static final AudioComparisonService instance = AudioComparisonService._();
  AudioComparisonService._();

  /// Tokenizes text into a normalized list of lowercase alpha-numeric words
  static List<String> tokenizeWords(String text) {
    if (text.isEmpty) return [];
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Performs deterministic word difference analysis between two transcripts.
  static WordDiffResult computeWordDiff(String original, String processed) {
    final origWords = tokenizeWords(original);
    final procWords = tokenizeWords(processed);

    final origSet = origWords.toSet();
    final procSet = procWords.toSet();

    final uniqueToOrig =
        origWords.where((w) => !procSet.contains(w)).toSet().toList()..sort();
    final uniqueToProc =
        procWords.where((w) => !origSet.contains(w)).toSet().toList()..sort();
    final common = origSet.intersection(procSet).toList()..sort();

    final unionSize = origSet.union(procSet).length;
    final similarity = unionSize > 0 ? (common.length / unionSize) : 1.0;

    return WordDiffResult(
      originalWordCount: origWords.length,
      processedWordCount: procWords.length,
      uniqueToOriginal: uniqueToOrig,
      uniqueToProcessed: uniqueToProc,
      commonWords: common,
      similarityScore: similarity,
    );
  }

  /// Runs complete A/B comparison pipeline:
  /// - Path A: Original audio -> Whisper Tiny -> Original Transcription
  /// - Path B: Same original audio -> AudioNoiseProcessor -> Processed audio -> Whisper Tiny -> Processed Transcription
  ///
  /// Guarantees:
  /// 1. Original file is never mutated or overwritten.
  /// 2. Processed audio is written to a dedicated temporary file.
  /// 3. Same 25-second chunking and same Whisper Tiny engine.
  Future<AudioComparisonResult> runComparison({
    required String originalAudioPath,
    required String recordingId,
    DspConfig config = DspConfig.full,
    bool runStt = true,
  }) async {
    final origFile = File(originalAudioPath);
    if (!await origFile.exists()) {
      throw FileSystemException(
          'Original audio file does not exist', originalAudioPath);
    }
    final int origFileLengthBefore = await origFile.length();

    // 1. Read Original Audio
    Float32List originalSamples;
    int sampleRate = 16000;

    try {
      // Try pure-Dart WAV parser first for speed and zero-dependency safety
      final wavData = await AudioNoiseProcessor.readWavFile(originalAudioPath);
      originalSamples = wavData.samples;
      sampleRate = wavData.sampleRate;
    } catch (_) {
      // Native sherpa fallback if needed
      final wave = sherpa.readWave(originalAudioPath);
      originalSamples = wave.samples;
      sampleRate = wave.sampleRate;
    }

    if (originalSamples.isEmpty) {
      throw Exception('Original audio file contains no audio samples.');
    }

    final int sampleCount = originalSamples.length;
    final double durationSeconds = sampleCount / sampleRate;
    final AudioMetrics origMetrics =
        AudioNoiseProcessor.measureMetrics(originalSamples);

    // 2. Path B: Process with DSP
    final dspStopwatch = Stopwatch()..start();
    final Float32List processedSamples = AudioNoiseProcessor.process(
      originalSamples,
      sampleRate: sampleRate,
      config: config,
      verbose: false,
    );
    dspStopwatch.stop();
    final int dspElapsedMs = dspStopwatch.elapsedMilliseconds;

    // 3. Validate processed audio
    final DspValidationResult validation = AudioNoiseProcessor.validateSamples(
      processedSamples,
      expectedLength: sampleCount,
    );
    if (!validation.isValid) {
      debugPrint('[A/B TEST] Validation Warning: ${validation.errorMessage}');
    }

    final AudioMetrics procMetrics =
        AudioNoiseProcessor.measureMetrics(processedSamples);

    // 4. Save processed audio to temporary WAV file (never touching original)
    Directory tempDir;
    try {
      tempDir = await getTemporaryDirectory();
    } catch (_) {
      tempDir = Directory.systemTemp;
    }
    final String tempProcessedPath =
        '${tempDir.path}/processed_${recordingId}_${DateTime.now().millisecondsSinceEpoch}.wav';

    await AudioNoiseProcessor.writeWavFile(
      tempProcessedPath,
      processedSamples,
      sampleRate: sampleRate,
    );

    // Safety verification: Original file MUST NOT have been modified
    final int origFileLengthAfter = await origFile.length();
    if (origFileLengthBefore != origFileLengthAfter) {
      throw StateError(
          'CRITICAL: Original file was mutated during A/B testing! Length changed from $origFileLengthBefore to $origFileLengthAfter');
    }

    // 5. Run Whisper STT on Path A and Path B if requested
    String origTranscript = '';
    String procTranscript = '';
    int origSttElapsed = 0;
    int procSttElapsed = 0;

    if (runStt && SttService.instance.isInitialized) {
      debugPrint('[A/B TEST] Transcribing Path A (Recorded Audio)...');
      try {
        final resultA = await SttService.instance.transcribeWaveform(
          originalSamples,
          sampleRate,
        );
        origTranscript = resultA.text;
        origSttElapsed = resultA.elapsedMs;
      } catch (e) {
        origTranscript = 'Transcription error (Path A): $e';
      }

      debugPrint(
          '[A/B TEST] Transcribing Path B (Recorded Audio + Pal DSP)...');
      try {
        final resultB = await SttService.instance.transcribeWaveform(
          processedSamples,
          sampleRate,
        );
        procTranscript = resultB.text;
        procSttElapsed = resultB.elapsedMs;
      } catch (e) {
        procTranscript = 'Transcription error (Path B): $e';
      }
    } else if (runStt) {
      origTranscript = 'Whisper ONNX not initialized.';
      procTranscript = 'Whisper ONNX not initialized.';
    }

    // 6. Compute deterministic word differences
    final WordDiffResult wordDiff =
        computeWordDiff(origTranscript, procTranscript);

    return AudioComparisonResult(
      originalAudioPath: originalAudioPath,
      processedAudioPath: tempProcessedPath,
      dspConfig: config,
      sampleRate: sampleRate,
      sampleCount: sampleCount,
      durationSeconds: durationSeconds,
      validation: validation,
      originalMetrics: origMetrics,
      processedMetrics: procMetrics,
      dspElapsedMs: dspElapsedMs,
      originalTranscript: origTranscript,
      processedTranscript: procTranscript,
      originalSttElapsedMs: origSttElapsed,
      processedSttElapsedMs: procSttElapsed,
      wordDiff: wordDiff,
    );
  }
}
