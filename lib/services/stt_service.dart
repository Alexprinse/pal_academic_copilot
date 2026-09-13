import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../models/lecture_recording.dart';
import 'audio_noise_processor.dart';

class WavAudioMetadata {
  final bool isValid;
  final String? error;
  final int sampleRate;
  final int numChannels;
  final int bitsPerSample;
  final int fileSizeBytes;
  final double durationSeconds;
  final bool needsResampling;

  const WavAudioMetadata({
    required this.isValid,
    this.error,
    this.sampleRate = 0,
    this.numChannels = 0,
    this.bitsPerSample = 0,
    this.fileSizeBytes = 0,
    this.durationSeconds = 0.0,
    this.needsResampling = false,
  });
}

class SttService extends ChangeNotifier {
  static final SttService instance = SttService._();
  SttService._();

  final AudioRecorder _recorder = AudioRecorder();
  sherpa.OfflineRecognizer? _recognizer;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool _isTranscribing = false;
  bool get isTranscribing => _isTranscribing;

  String _transcription = '';
  String get transcription => _transcription;

  String? _recordingPath;
  String? get recordingPath => _recordingPath;

  bool _isAudioDspEnabled = true;
  bool get isAudioDspEnabled => _isAudioDspEnabled;

  void setAudioDspEnabled(bool enabled) {
    _isAudioDspEnabled = enabled;
    notifyListeners();
  }

  Future<void> init() async {
    if (_isInitialized && _recognizer != null) return;

    try {
      sherpa.initBindings();
      await _prepareModelFiles();
      _isInitialized = _recognizer != null;
      debugPrint('[STT-DEBUG] Whisper model initialized: $_isInitialized');
      notifyListeners();
    } catch (e, st) {
      debugPrint('[STT-DEBUG] Error initializing Sherpa Whisper STT: $e');
      debugPrint('[STT-ERROR] Stack: $st');
      _isInitialized = false;
    }
  }

  Future<void> _prepareModelFiles() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${docsDir.path}/whisper-tiny-en');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final filesToCopy = [
      'tiny.en-encoder.int8.onnx',
      'tiny.en-decoder.int8.onnx',
      'tiny.en-tokens.txt',
    ];

    for (final fileName in filesToCopy) {
      final destFile = File('${modelDir.path}/$fileName');
      if (!await destFile.exists() || await destFile.length() == 0) {
        try {
          ByteData data;
          try {
            data = await rootBundle.load(
                'assets/models/whisper-tiny-en/sherpa-onnx-whisper-tiny.en/$fileName');
          } catch (_) {
            data = await rootBundle
                .load('assets/models/whisper-tiny-en/$fileName');
          }
          await destFile.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
        } catch (e) {
          debugPrint('Notice: Asset $fileName not extracted yet: $e');
        }
      }
    }

    final encoderPath = '${modelDir.path}/tiny.en-encoder.int8.onnx';
    final decoderPath = '${modelDir.path}/tiny.en-decoder.int8.onnx';
    final tokensPath = '${modelDir.path}/tiny.en-tokens.txt';

    debugPrint('[STT-DEBUG] Whisper resolved model paths:');
    debugPrint(
        '[STT-DEBUG]   Encoder: $encoderPath (exists: ${File(encoderPath).existsSync()})');
    debugPrint(
        '[STT-DEBUG]   Decoder: $decoderPath (exists: ${File(decoderPath).existsSync()})');
    debugPrint(
        '[STT-DEBUG]   Tokens:  $tokensPath (exists: ${File(tokensPath).existsSync()})');

    if (File(encoderPath).existsSync() &&
        File(decoderPath).existsSync() &&
        File(tokensPath).existsSync()) {
      final whisperConfig = sherpa.OfflineWhisperModelConfig(
        encoder: encoderPath,
        decoder: decoderPath,
        language: 'en',
        task: 'transcribe',
      );

      final modelConfig = sherpa.OfflineModelConfig(
        whisper: whisperConfig,
        tokens: tokensPath,
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      );

      final recognizerConfig = sherpa.OfflineRecognizerConfig(
        model: modelConfig,
      );
      _recognizer = sherpa.OfflineRecognizer(recognizerConfig);
      _isInitialized = true;
      debugPrint(
          '[STT] Whisper Tiny INT8 recognizer initialized successfully.');
    }
  }

  /// Inspect and validate that a WAV file exists and has valid 16kHz mono 16-bit PCM header.
  /// Scans RIFF chunks dynamically without assuming fixed chunk offsets.
  static Future<WavAudioMetadata> validateWavFile(String wavFilePath) async {
    final file = File(wavFilePath);
    if (!await file.exists()) {
      return WavAudioMetadata(
        isValid: false,
        error: 'File does not exist at path: $wavFilePath',
      );
    }

    final int size = await file.length();
    if (size < 44) {
      return WavAudioMetadata(
        isValid: false,
        error:
            'File size ($size bytes) is smaller than standard WAV 44-byte header.',
        fileSizeBytes: size,
      );
    }

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final riffHeader = await raf.read(12);
      if (riffHeader.length < 12) {
        return WavAudioMetadata(
          isValid: false,
          error: 'Could not read full 12-byte RIFF/WAVE header.',
          fileSizeBytes: size,
        );
      }

      final riff = String.fromCharCodes(riffHeader.sublist(0, 4));
      final wave = String.fromCharCodes(riffHeader.sublist(8, 12));
      if (riff != 'RIFF' || wave != 'WAVE') {
        return WavAudioMetadata(
          isValid: false,
          error:
              'Invalid WAV container: RIFF signature "$riff", WAVE signature "$wave".',
          fileSizeBytes: size,
        );
      }

      int formatCode = 0;
      int channels = 0;
      int sampleRate = 0;
      int bitsPerSample = 0;
      bool foundFmt = false;
      bool foundData = false;
      int dataSizeBytes = 0;

      int currentOffset = 12;
      while (currentOffset + 8 <= size) {
        await raf.setPosition(currentOffset);
        final chunkHeader = await raf.read(8);
        if (chunkHeader.length < 8) break;

        final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
        final chunkSize = chunkHeader[4] |
            (chunkHeader[5] << 8) |
            (chunkHeader[6] << 16) |
            (chunkHeader[7] << 24);

        if (chunkId == 'fmt ') {
          foundFmt = true;
          final fmtData = await raf.read(math.min(chunkSize, 16));
          if (fmtData.length >= 16) {
            formatCode = fmtData[0] | (fmtData[1] << 8);
            channels = fmtData[2] | (fmtData[3] << 8);
            sampleRate = fmtData[4] |
                (fmtData[5] << 8) |
                (fmtData[6] << 16) |
                (fmtData[7] << 24);
            bitsPerSample = fmtData[14] | (fmtData[15] << 8);
          }
        } else if (chunkId == 'data') {
          foundData = true;
          dataSizeBytes = chunkSize;
          if (dataSizeBytes <= 0 || currentOffset + 8 + dataSizeBytes > size) {
            dataSizeBytes = size - (currentOffset + 8);
          }
          break;
        }

        final advance = 8 + chunkSize + (chunkSize % 2);
        if (advance <= 8) {
          currentOffset += 8;
        } else {
          currentOffset += advance;
        }
      }

      if (!foundFmt) {
        return WavAudioMetadata(
          isValid: false,
          error: 'Missing "fmt " chunk in WAV container.',
          fileSizeBytes: size,
        );
      }

      if (formatCode != 1 && formatCode != 3 && formatCode != 0xFFFE) {
        return WavAudioMetadata(
          isValid: false,
          error:
              'Audio format is not PCM ($formatCode). Whisper requires PCM or IEEE float WAV.',
          fileSizeBytes: size,
          sampleRate: sampleRate,
          numChannels: channels,
          bitsPerSample: bitsPerSample,
        );
      }

      if (channels < 1 || channels > 8) {
        return WavAudioMetadata(
          isValid: false,
          error:
              'Audio has $channels channels. Supported: 1 (mono) or 2 (stereo).',
          fileSizeBytes: size,
          sampleRate: sampleRate,
          numChannels: channels,
          bitsPerSample: bitsPerSample,
        );
      }

      if (sampleRate < 8000 || sampleRate > 96000) {
        return WavAudioMetadata(
          isValid: false,
          error:
              'Unsupported audio sample rate ($sampleRate Hz). Supported range: 8000 Hz to 96000 Hz.',
          fileSizeBytes: size,
          sampleRate: sampleRate,
          numChannels: channels,
          bitsPerSample: bitsPerSample,
        );
      }

      if (bitsPerSample != 16 && bitsPerSample != 24 && bitsPerSample != 32) {
        return WavAudioMetadata(
          isValid: false,
          error:
              'Bits per sample is $bitsPerSample. Supported: 16-bit, 24-bit, or 32-bit PCM/Float.',
          fileSizeBytes: size,
          sampleRate: sampleRate,
          numChannels: channels,
          bitsPerSample: bitsPerSample,
        );
      }

      if (!foundData || dataSizeBytes <= 0) {
        return WavAudioMetadata(
          isValid: false,
          error: 'Data chunk not found or empty (size $dataSizeBytes bytes).',
          fileSizeBytes: size,
          sampleRate: sampleRate,
          numChannels: channels,
          bitsPerSample: bitsPerSample,
        );
      }

      final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
      final double duration = byteRate > 0 ? dataSizeBytes / byteRate : 0.0;
      final bool needsResampling = (sampleRate != 16000 || channels != 1);

      return WavAudioMetadata(
        isValid: true,
        sampleRate: sampleRate,
        numChannels: channels,
        bitsPerSample: bitsPerSample,
        fileSizeBytes: size,
        durationSeconds: duration,
        needsResampling: needsResampling,
      );
    } catch (e) {
      return WavAudioMetadata(
        isValid: false,
        error: 'Failed to inspect WAV header: $e',
        fileSizeBytes: size,
      );
    } finally {
      await raf?.close();
    }
  }

  /// Start recording to specified custom path or default temporary file
  Future<void> startRecording({String? customFilePath}) async {
    if (_isRecording) return;

    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      throw Exception('Microphone permission not granted.');
    }

    String filePath;
    if (customFilePath != null && customFilePath.isNotEmpty) {
      filePath = customFilePath;
      final parentDir = File(filePath).parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
    } else {
      final tempDir = await getTemporaryDirectory();
      filePath =
          '${tempDir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    }

    // Must record in 16kHz mono WAV as required by Whisper ONNX
    // Hardware noise suppression & AGC enabled if supported by the Android device
    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      autoGain: true,
      noiseSuppress: true,
      echoCancel: true,
    );

    debugPrint('[RECORD] Starting audio recording -> $filePath');
    await _recorder.start(config, path: filePath);
    _recordingPath = filePath;
    _isRecording = true;
    _transcription = '';
    notifyListeners();
  }

  /// Start voice command recording to specified custom path or default temporary file.
  /// Disables telephony echo cancellation and hardware noise suppressor to prevent
  /// clipping conversational speech onset and vowel transitions during voice commands.
  Future<void> startCommandRecording({String? customFilePath}) async {
    if (_isRecording) return;

    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      throw Exception('Microphone permission not granted.');
    }

    String filePath;
    if (customFilePath != null && customFilePath.isNotEmpty) {
      filePath = customFilePath;
      final parentDir = File(filePath).parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
    } else {
      final tempDir = await getTemporaryDirectory();
      filePath =
          '${tempDir.path}/cmd_${DateTime.now().millisecondsSinceEpoch}.wav';
    }

    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      autoGain: true,
      noiseSuppress: false,
      echoCancel: false,
    );

    debugPrint('[PAL-VOICE] Recording started -> $filePath');
    await _recorder.start(config, path: filePath);
    _recordingPath = filePath;
    _isRecording = true;
    _transcription = '';
    notifyListeners();
  }

  /// Trims silence from start and end of samples with safety headroom.
  static Float32List trimSilence(
    Float32List samples, {
    int sampleRate = 16000,
    double threshold = 0.012,
    int headroomMs = 150,
  }) {
    if (samples.isEmpty) return samples;

    final headroomSamples = (sampleRate * (headroomMs / 1000.0)).round();

    // Find start of speech
    int startIndex = 0;
    for (int i = 0; i < samples.length; i++) {
      if (samples[i].abs() >= threshold) {
        startIndex = i;
        break;
      }
    }

    // Find end of speech
    int endIndex = samples.length - 1;
    for (int i = samples.length - 1; i >= 0; i--) {
      if (samples[i].abs() >= threshold) {
        endIndex = i;
        break;
      }
    }

    if (startIndex > endIndex) {
      return samples;
    }

    final actualStart = (startIndex - headroomSamples).clamp(0, samples.length);
    final actualEnd = (endIndex + headroomSamples + 1).clamp(0, samples.length);

    if (actualStart >= actualEnd) return samples;
    return samples.sublist(actualStart, actualEnd);
  }

  /// Dedicated, single-pass transcription for short voice commands (2-10 seconds).
  /// Bypasses 25-second chunking loops and aggressive telephony DSP expanders.
  /// Loads audio waveform from [wavFilePath], converting to mono Float32List,
  /// resampling to 16,000 Hz if needed, and applying on-device DSP if enabled.
  /// Original file on disk is NEVER modified.
  Future<Float32List> _loadAndNormalizeWaveform(
    String wavFilePath,
    WavAudioMetadata metadata,
  ) async {
    Float32List rawSamples = Float32List(0);
    int inputSampleRate = metadata.sampleRate;

    // 1. Try reading via sherpa.readWave first
    try {
      final wave = sherpa.readWave(wavFilePath);
      if (wave.samples.isNotEmpty && wave.sampleRate > 0) {
        rawSamples = wave.samples;
        inputSampleRate = wave.sampleRate;
      } else {
        throw Exception('sherpa.readWave returned empty samples');
      }
    } catch (e) {
      debugPrint(
          '[STT] Notice: sherpa.readWave fallback to pure Dart WAV reader: $e');
      final dartWave = await AudioNoiseProcessor.readWavFile(wavFilePath);
      rawSamples = dartWave.samples;
      inputSampleRate = dartWave.sampleRate;
    }

    if (rawSamples.isEmpty) {
      return Float32List(0);
    }

    // 2. Resample to 16000 Hz if needed (e.g. imported 48000 Hz or 44100 Hz audio)
    Float32List samples16k;
    if (inputSampleRate != 16000) {
      debugPrint(
          '[STT] Resampling audio from $inputSampleRate Hz -> 16000 Hz for Whisper ONNX...');
      samples16k = AudioNoiseProcessor.resample(
        rawSamples,
        inputRate: inputSampleRate,
        targetRate: 16000,
      );
      debugPrint(
          '[STT] Resampling complete: ${samples16k.length} samples at 16000 Hz (${(samples16k.length / 16000.0).toStringAsFixed(1)}s)');
    } else {
      samples16k = rawSamples;
    }

    // 3. Apply on-device DSP at 16000 Hz
    if (_isAudioDspEnabled) {
      try {
        debugPrint('[STT] Preprocessing audio with on-device DSP...');
        final processed = AudioNoiseProcessor.process(
          samples16k,
          sampleRate: 16000,
          verbose: true,
        );
        debugPrint('[STT] Using processed waveform for Whisper recognition.');
        return processed;
      } catch (e) {
        debugPrint(
            '[AUDIO DSP] Processing failed — falling back to raw waveform: $e');
        return samples16k;
      }
    } else {
      debugPrint(
          '[STT] Audio DSP disabled (A/B testing mode) — using raw waveform.');
      return samples16k;
    }
  }

  /// Dedicated, single-pass transcription for short voice commands (2-10 seconds).
  /// Bypasses 25-second chunking loops and aggressive telephony DSP expanders.
  Future<String> transcribeVoiceCommand(String wavFilePath) async {
    _isTranscribing = true;
    notifyListeners();

    try {
      if (_recognizer == null) {
        debugPrint(
            '[TRANSCRIBE] ERROR: Whisper ONNX recognizer is not initialized.');
        _transcription =
            "Couldn't transcribe this recording (Whisper ONNX not ready).";
        return _transcription;
      }

      final metadata = await validateWavFile(wavFilePath);
      if (!metadata.isValid) {
        debugPrint('[TRANSCRIBE] Audio validation failed: ${metadata.error}');
        _transcription =
            "Couldn't transcribe this recording: ${metadata.error ?? 'Invalid audio'}";
        return _transcription;
      }

      final Float32List allSamples =
          await _loadAndNormalizeWaveform(wavFilePath, metadata);
      if (allSamples.isEmpty) {
        throw Exception('Invalid audio file or no samples found in WAV.');
      }

      const int sampleRate = 16000;
      final Float32List trimmedSamples =
          trimSilence(allSamples, sampleRate: sampleRate);

      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: trimmedSamples, sampleRate: sampleRate);
      _recognizer!.decode(stream);
      final String rawResult = _recognizer!.getResult(stream).text.trim();
      stream.free();

      _transcription = rawResult;
      return _transcription;
    } catch (e) {
      debugPrint('[TRANSCRIBE] Voice command transcription error: $e');
      _transcription = "Couldn't transcribe this recording.";
      return _transcription;
    } finally {
      _isTranscribing = false;
      notifyListeners();
    }
  }

  /// Stops recording and returns ONLY the actual saved audio file path (does NOT transcribe)
  Future<String?> stopRecordingOnly() async {
    if (!_isRecording) return _recordingPath;

    final path = await _recorder.stop();
    _isRecording = false;
    _recordingPath = path ?? _recordingPath;
    notifyListeners();

    if (_recordingPath != null) {
      final file = File(_recordingPath!);
      final size = file.existsSync() ? file.lengthSync() : 0;
      debugPrint('[RECORD] Stopped recording.');
      debugPrint('[RECORD] Output path: $_recordingPath');
      debugPrint('[RECORD] File size: $size bytes');
    }
    return _recordingPath;
  }

  /// Stops recording and then runs transcription on the resulting audio file
  Future<String> stopRecording() async {
    final path = await stopRecordingOnly();
    if (path != null && File(path).existsSync()) {
      return await transcribeAudioFile(path);
    }
    return '';
  }

  /// Transcribe audio file with Whisper ONNX - NO DUMMY FALLBACKS
  Future<String> transcribeAudioFile(String wavFilePath) async {
    try {
      final result = await transcribeAudioFileWithTimestamps(wavFilePath);
      return result.text;
    } catch (e) {
      debugPrint('[TRANSCRIBE] transcribeAudioFile error: $e');
      _transcription = "Couldn't transcribe this recording.";
      return _transcription;
    }
  }

  /// Transcribes the given audio file with 25s chunk timestamps - NO DUMMY FALLBACKS
  Future<({String text, List<LectureTranscriptChunk> chunks})>
      transcribeAudioFileWithTimestamps(String wavFilePath) async {
    _isTranscribing = true;
    notifyListeners();

    try {
      if (_recognizer == null) {
        debugPrint(
            '[STT-DEBUG] Recognizer is null, attempting initialization...');
        await init();
      }

      if (_recognizer == null) {
        debugPrint('[TRANSCRIBE] Whisper ONNX recognizer is not initialized.');
        debugPrint('[STT-DEBUG] Whisper model initialized: false');
        debugPrint(
            '[STT-DEBUG] Error: Transcription engine (Whisper ONNX) not ready.');
        throw Exception('Transcription engine (Whisper ONNX) not ready.');
      }

      final metadata = await validateWavFile(wavFilePath);
      if (!metadata.isValid) {
        debugPrint('[TRANSCRIBE] Audio validation failed: ${metadata.error}');
        debugPrint('[STT-DEBUG] Error: ${metadata.error}');
        throw Exception(metadata.error ?? 'Invalid audio file.');
      }

      debugPrint('[TRANSCRIBE] START');
      debugPrint('[TRANSCRIBE] Input audio: $wavFilePath');
      debugPrint('[TRANSCRIBE] File size: ${metadata.fileSizeBytes} bytes');
      debugPrint('[TRANSCRIBE] Sample rate: ${metadata.sampleRate} Hz');
      debugPrint('[TRANSCRIBE] Channels: ${metadata.numChannels}');
      debugPrint(
          '[TRANSCRIBE] Duration: ${metadata.durationSeconds.toStringAsFixed(1)}s');

      if (metadata.durationSeconds <= 0.05) {
        _transcription = 'No usable audio was recorded.';
        final chunks = <LectureTranscriptChunk>[
          LectureTranscriptChunk(
            chunkIndex: 0,
            startTimestamp: '00:00',
            endTimestamp: '00:00',
            text: 'No usable audio was recorded.',
          ),
        ];
        return (text: _transcription, chunks: chunks);
      }

      // Load, convert to mono, resample to 16000 Hz, and apply DSP
      final Float32List allSamples =
          await _loadAndNormalizeWaveform(wavFilePath, metadata);

      if (allSamples.isEmpty) {
        throw Exception('Invalid audio file or no samples found in WAV.');
      }

      const int sampleRate = 16000;
      final int maxChunkSamples = sampleRate * 25; // 25 seconds per chunk
      final int totalSamples = allSamples.length;
      final double totalDurationSec = totalSamples / sampleRate;
      final StringBuffer resultBuffer = StringBuffer();
      final List<LectureTranscriptChunk> chunks = [];

      debugPrint(
          '[STT-DEBUG] Transcription started: ${DateTime.now().toIso8601String()}');

      // Short recording (<= 25 seconds): transcribe directly without chunking
      if (totalSamples <= maxChunkSamples) {
        debugPrint(
            '[WHISPER] Direct transcription for short recording (${totalDurationSec.toStringAsFixed(1)}s <= 25s)');
        final stream = _recognizer!.createStream();
        stream.acceptWaveform(samples: allSamples, sampleRate: sampleRate);
        _recognizer!.decode(stream);
        final String rawText = _recognizer!.getResult(stream).text.trim();
        stream.free();

        final int totalSec = math.max(1, totalDurationSec.round());
        final endTs = _formatTimestamp(totalSec);
        final displayText =
            rawText.isNotEmpty ? rawText : 'No speech detected in recording.';

        chunks.add(LectureTranscriptChunk(
          chunkIndex: 0,
          startTimestamp: '00:00',
          endTimestamp: endTs,
          text: displayText,
        ));

        _transcription = displayText;
        debugPrint(
            '[STT-DEBUG] Transcription completed: ${DateTime.now().toIso8601String()}');
        return (text: _transcription, chunks: chunks);
      }

      // Long recording (> 25 seconds): 25-second chunking with natural pause detection & isolate yielding
      debugPrint(
          '[WHISPER] Chunked transcription for long recording (${totalDurationSec.toStringAsFixed(1)}s > 25s)');
      int offset = 0;
      int chunkIdx = 0;
      while (offset < totalSamples) {
        int end;
        final int remaining = totalSamples - offset;
        if (remaining <= 30 * sampleRate) {
          // If remaining audio is <= 30 seconds, decode all remaining audio in this final chunk
          end = totalSamples;
        } else {
          // Find natural pause around nominal 25-second boundary
          final int nominalEnd = offset + maxChunkSamples;
          end = AudioNoiseProcessor.findNaturalPauseSplitPoint(
            allSamples,
            targetOffset: nominalEnd,
            searchRadiusSamples: 32000, // +/- 2s at 16kHz
          );
          // Safety: ensure progress is between 15s and 29s
          if (end <= offset + (15 * sampleRate)) {
            end = nominalEnd;
          }
          if (end > totalSamples) end = totalSamples;
        }

        final Float32List chunk = allSamples.sublist(offset, end);
        final int startSec = (offset / sampleRate).floor();
        final int endSec = (end / sampleRate).floor();
        final startTs = _formatTimestamp(startSec);
        final endTs = _formatTimestamp(endSec);

        String chunkText = '';
        try {
          final stream = _recognizer!.createStream();
          stream.acceptWaveform(samples: chunk, sampleRate: sampleRate);
          _recognizer!.decode(stream);
          chunkText = _recognizer!.getResult(stream).text.trim();
          stream.free();
        } catch (chunkErr) {
          debugPrint('[WHISPER] Chunk $chunkIdx decode warning: $chunkErr');
        }

        debugPrint(
            '[WHISPER] Chunk $chunkIdx ($startTs - $endTs) text: "$chunkText"');

        if (chunkText.isNotEmpty) {
          if (resultBuffer.isNotEmpty) resultBuffer.write(' ');
          resultBuffer.write(chunkText);

          chunks.add(LectureTranscriptChunk(
            chunkIndex: chunkIdx,
            startTimestamp: startTs,
            endTimestamp: endTs,
            text: chunkText,
          ));
        }

        chunkIdx++;
        offset = end;

        // CRITICAL: Yield to Flutter event loop between chunks!
        // Prevents Android main isolate ANR and allows UI updates / frame rendering.
        await Future.delayed(const Duration(milliseconds: 15));
      }

      final fullText = resultBuffer.toString().trim();
      _transcription =
          fullText.isNotEmpty ? fullText : 'No speech detected in recording.';
      if (chunks.isEmpty) {
        final totalSec = math.max(1, totalDurationSec.round());
        chunks.add(LectureTranscriptChunk(
          chunkIndex: 0,
          startTimestamp: '00:00',
          endTimestamp: _formatTimestamp(totalSec),
          text: _transcription,
        ));
      }
      debugPrint(
          '[STT-DEBUG] Transcription completed: ${DateTime.now().toIso8601String()}');
      return (text: _transcription, chunks: chunks);
    } catch (e, st) {
      debugPrint('[TRANSCRIBE] Timestamped transcription error: $e');
      debugPrint('[STT-DEBUG] Error: $e');
      debugPrint('[STT-ERROR] Exception: $e');
      debugPrint('[STT-ERROR] Stack: $st');
      debugPrint('[STT-ERROR] Audio path: $wavFilePath');
      debugPrint('[STT-ERROR] Model: Whisper Tiny INT8');
      rethrow;
    } finally {
      _isTranscribing = false;
      notifyListeners();
    }
  }

  /// Directly transcribes a [Float32List] buffer with 25s chunking for A/B testing without modifying global service state.
  Future<({String text, List<LectureTranscriptChunk> chunks, int elapsedMs})>
      transcribeWaveform(Float32List samples, int sampleRate) async {
    if (_recognizer == null) {
      throw Exception('Whisper ONNX recognizer is not initialized.');
    }

    final stopwatch = Stopwatch()..start();
    Float32List samples16k = samples;
    if (sampleRate != 16000) {
      samples16k = AudioNoiseProcessor.resample(
        samples,
        inputRate: sampleRate,
        targetRate: 16000,
      );
    }

    const int targetRate = 16000;
    final int maxChunkSamples = targetRate * 25;
    final int totalSamples = samples16k.length;
    final StringBuffer resultBuffer = StringBuffer();
    final List<LectureTranscriptChunk> chunks = [];

    int offset = 0;
    int chunkIdx = 0;
    while (offset < totalSamples) {
      int end;
      final int remaining = totalSamples - offset;
      if (remaining <= 30 * targetRate) {
        end = totalSamples;
      } else {
        final int nominalEnd = offset + maxChunkSamples;
        end = AudioNoiseProcessor.findNaturalPauseSplitPoint(
          samples16k,
          targetOffset: nominalEnd,
        );
        if (end <= offset + (15 * targetRate)) end = nominalEnd;
        if (end > totalSamples) end = totalSamples;
      }

      final Float32List chunk = samples16k.sublist(offset, end);

      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: chunk, sampleRate: targetRate);
      _recognizer!.decode(stream);
      final String chunkText = _recognizer!.getResult(stream).text.trim();
      stream.free();

      final int startSec = (offset / targetRate).floor();
      final int endSec = (end / targetRate).floor();
      final startTs = _formatTimestamp(startSec);
      final endTs = _formatTimestamp(endSec);

      if (chunkText.isNotEmpty) {
        if (resultBuffer.isNotEmpty) resultBuffer.write(' ');
        resultBuffer.write(chunkText);

        chunks.add(LectureTranscriptChunk(
          chunkIndex: chunkIdx,
          startTimestamp: startTs,
          endTimestamp: endTs,
          text: chunkText,
        ));
      }

      chunkIdx++;
      offset = end;
      await Future.delayed(const Duration(milliseconds: 10));
    }

    stopwatch.stop();
    final text = resultBuffer.toString().trim();
    return (
      text: text.isNotEmpty ? text : 'No speech detected in recording.',
      chunks: chunks,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  static String _formatTimestamp(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void clearTranscription() {
    _transcription = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _recorder.dispose();
    _recognizer?.free();
    super.dispose();
  }
}
