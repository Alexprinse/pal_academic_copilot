import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../models/lecture_recording.dart';

class WavAudioMetadata {
  final bool isValid;
  final String? error;
  final int sampleRate;
  final int numChannels;
  final int bitsPerSample;
  final int fileSizeBytes;
  final double durationSeconds;

  const WavAudioMetadata({
    required this.isValid,
    this.error,
    this.sampleRate = 0,
    this.numChannels = 0,
    this.bitsPerSample = 0,
    this.fileSizeBytes = 0,
    this.durationSeconds = 0.0,
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

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      sherpa.initBindings();
      await _prepareModelFiles();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing Sherpa Whisper STT: $e');
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

      final recognizerConfig =
          sherpa.OfflineRecognizerConfig(model: modelConfig);
      _recognizer = sherpa.OfflineRecognizer(recognizerConfig);
      debugPrint('Whisper Tiny INT8 recognizer initialized successfully.');
    }
  }

  /// Inspect and validate that a WAV file exists and has valid 16kHz mono 16-bit PCM header
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
      final header = await raf.read(44);
      if (header.length < 44) {
        return WavAudioMetadata(
          isValid: false,
          error: 'Could not read full 44-byte WAV header.',
          fileSizeBytes: size,
        );
      }

      final riff = String.fromCharCodes(header.sublist(0, 4));
      final wave = String.fromCharCodes(header.sublist(8, 12));
      if (riff != 'RIFF' || wave != 'WAVE') {
        return WavAudioMetadata(
          isValid: false,
          error:
              'Invalid WAV container: RIFF signature "$riff", WAVE signature "$wave".',
          fileSizeBytes: size,
        );
      }

      final formatCode = header[20] | (header[21] << 8);
      if (formatCode != 1) {
        return WavAudioMetadata(
          isValid: false,
          error:
              'Audio format is not PCM ($formatCode). Whisper requires 16-bit PCM WAV.',
          fileSizeBytes: size,
        );
      }
      final channels = header[22] | (header[23] << 8);
      final sampleRate = header[24] |
          (header[25] << 8) |
          (header[26] << 16) |
          (header[27] << 24);
      final bitsPerSample = header[34] | (header[35] << 8);

      final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
      final double duration = byteRate > 0 ? (size - 44) / byteRate : 0.0;

      return WavAudioMetadata(
        isValid: true,
        sampleRate: sampleRate,
        numChannels: channels,
        bitsPerSample: bitsPerSample,
        fileSizeBytes: size,
        durationSeconds: duration,
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
    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    );

    debugPrint('[RECORD] Starting audio recording -> $filePath');
    await _recorder.start(config, path: filePath);
    _recordingPath = filePath;
    _isRecording = true;
    _transcription = '';
    notifyListeners();
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

      debugPrint('[TRANSCRIBE] START');
      debugPrint('[TRANSCRIBE] Input audio: $wavFilePath');
      debugPrint('[TRANSCRIBE] File size: ${metadata.fileSizeBytes} bytes');
      debugPrint('[TRANSCRIBE] Sample rate: ${metadata.sampleRate} Hz');
      debugPrint('[TRANSCRIBE] Channels: ${metadata.numChannels}');
      debugPrint(
          '[TRANSCRIBE] Duration: ${metadata.durationSeconds.toStringAsFixed(1)}s');

      final wave = sherpa.readWave(wavFilePath);
      if (wave.samples.isEmpty || wave.sampleRate == 0) {
        throw Exception('Invalid audio file or no samples found in WAV.');
      }

      final int sampleRate = wave.sampleRate;
      final Float32List allSamples = wave.samples;

      // 25-second chunking
      final int maxChunkSamples = sampleRate * 25;
      final int totalSamples = allSamples.length;
      final StringBuffer resultBuffer = StringBuffer();

      int offset = 0;
      int chunkIdx = 0;
      while (offset < totalSamples) {
        final int end = (offset + maxChunkSamples < totalSamples)
            ? offset + maxChunkSamples
            : totalSamples;

        final Float32List chunk = allSamples.sublist(offset, end);
        final stream = _recognizer!.createStream();
        stream.acceptWaveform(samples: chunk, sampleRate: sampleRate);
        _recognizer!.decode(stream);
        final String chunkText = _recognizer!.getResult(stream).text.trim();
        stream.free();

        debugPrint('[WHISPER] Chunk $chunkIdx: "$chunkText"');
        if (chunkText.isNotEmpty) {
          if (resultBuffer.isNotEmpty) resultBuffer.write(' ');
          resultBuffer.write(chunkText);
        }

        chunkIdx++;
        offset = end;
      }

      _transcription = resultBuffer.toString().trim();
      if (_transcription.isEmpty) {
        _transcription = 'No speech detected in recording.';
      }
      return _transcription;
    } catch (e) {
      debugPrint('[TRANSCRIBE] Transcription error: $e');
      _transcription = "Couldn't transcribe this recording.";
      return _transcription;
    } finally {
      _isTranscribing = false;
      notifyListeners();
    }
  }

  /// Transcribes the given audio file with 25s chunk timestamps - NO DUMMY FALLBACKS
  Future<({String text, List<LectureTranscriptChunk> chunks})>
      transcribeAudioFileWithTimestamps(String wavFilePath) async {
    _isTranscribing = true;
    notifyListeners();

    try {
      if (_recognizer == null) {
        debugPrint('[TRANSCRIBE] Whisper ONNX recognizer is not initialized.');
        throw Exception('Transcription engine (Whisper ONNX) not ready.');
      }

      final metadata = await validateWavFile(wavFilePath);
      if (!metadata.isValid) {
        debugPrint('[TRANSCRIBE] Audio validation failed: ${metadata.error}');
        throw Exception(metadata.error ?? 'Invalid audio file.');
      }

      debugPrint('[TRANSCRIBE] START');
      debugPrint('[TRANSCRIBE] Input audio: $wavFilePath');
      debugPrint('[TRANSCRIBE] File size: ${metadata.fileSizeBytes} bytes');
      debugPrint('[TRANSCRIBE] Sample rate: ${metadata.sampleRate} Hz');
      debugPrint('[TRANSCRIBE] Channels: ${metadata.numChannels}');
      debugPrint(
          '[TRANSCRIBE] Duration: ${metadata.durationSeconds.toStringAsFixed(1)}s');

      final wave = sherpa.readWave(wavFilePath);
      if (wave.samples.isEmpty || wave.sampleRate == 0) {
        throw Exception('Invalid audio file or no samples found in WAV.');
      }

      final int sampleRate = wave.sampleRate;
      final Float32List allSamples = wave.samples;

      // 25-second chunking
      final int maxChunkSamples = sampleRate * 25;
      final int totalSamples = allSamples.length;
      final StringBuffer resultBuffer = StringBuffer();
      final List<LectureTranscriptChunk> chunks = [];

      int offset = 0;
      int chunkIdx = 0;
      while (offset < totalSamples) {
        final int end = (offset + maxChunkSamples < totalSamples)
            ? offset + maxChunkSamples
            : totalSamples;

        final Float32List chunk = allSamples.sublist(offset, end);

        final stream = _recognizer!.createStream();
        stream.acceptWaveform(samples: chunk, sampleRate: sampleRate);
        _recognizer!.decode(stream);
        final String chunkText = _recognizer!.getResult(stream).text.trim();
        stream.free();

        final int startSec = (offset / sampleRate).floor();
        final int endSec = (end / sampleRate).floor();
        final startTs = _formatTimestamp(startSec);
        final endTs = _formatTimestamp(endSec);

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
      }

      final fullText = resultBuffer.toString().trim();
      _transcription =
          fullText.isNotEmpty ? fullText : 'No speech detected in recording.';
      return (text: _transcription, chunks: chunks);
    } catch (e) {
      debugPrint('[TRANSCRIBE] Timestamped transcription error: $e');
      rethrow;
    } finally {
      _isTranscribing = false;
      notifyListeners();
    }
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
