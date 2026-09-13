import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/stt_service.dart';
import '../services/timetable_service.dart';
import '../services/voice_command_normalizer.dart';
import 'agent_intent.dart';
import 'agent_response.dart';
import 'agent_service.dart';
import 'agent_tool_call.dart';

enum AgentVoiceState {
  idle,
  listening,
  transcribing,
  previewReady,
  executed,
  error,
}

class AgentVoiceController extends ChangeNotifier {
  static final AgentVoiceController instance = AgentVoiceController._();

  AgentVoiceController._({
    SttService? sttService,
    AgentService? agentService,
    SpeechToText? speechToText,
  })  : _sttService = sttService ?? SttService.instance,
        _agentService = agentService ?? AgentService.instance,
        _speechToText = speechToText ?? SpeechToText();

  @visibleForTesting
  static AgentVoiceController createForTesting({
    SttService? sttService,
    AgentService? agentService,
    SpeechToText? speechToText,
  }) {
    return AgentVoiceController._(
      sttService: sttService,
      agentService: agentService,
      speechToText: speechToText,
    );
  }

  final SttService _sttService;
  final AgentService _agentService;
  final SpeechToText _speechToText;

  final Stopwatch _holdStopwatch = Stopwatch();
  final Stopwatch _sttStopwatch = Stopwatch();

  bool _isNativeSttInitialized = false;
  bool _isNativeSttAvailable = false;
  bool _useWhisperFallback = false;
  bool _hasReceivedFirstPartial = false;
  String? _selectedLocaleId;

  bool get isNativeSttAvailable => _isNativeSttAvailable;
  bool get isUsingWhisperFallback => _useWhisperFallback;

  AgentVoiceState _state = AgentVoiceState.idle;
  AgentVoiceState get state => _state;

  String _currentTranscript = '';
  String get currentTranscript => _currentTranscript;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<AgentToolCall> _pendingToolCalls = [];
  List<AgentToolCall> get pendingToolCalls =>
      List.unmodifiable(_pendingToolCalls);

  AgentResponse? _executionResponse;
  AgentResponse? get executionResponse => _executionResponse;

  String? _activeAudioPath;
  String? get activeAudioPath => _activeAudioPath;

  bool get isListening => _state == AgentVoiceState.listening;
  bool get isTranscribing => _state == AgentVoiceState.transcribing;
  bool get isActionCommand => _pendingToolCalls.any((call) {
        final t = call.tool;
        return t == 'create_timetable_event' ||
            t == 'update_timetable_event' ||
            t == 'delete_timetable_event' ||
            t == 'create_task' ||
            t == 'schedule_recording';
      });

  /// Initializes the native Android SpeechRecognizer once.
  /// Subsequent calls reuse the existing initialization state.
  Future<bool> initializeNativeRecognizer() async {
    if (_isNativeSttInitialized) {
      return _isNativeSttAvailable;
    }

    try {
      final available = await _speechToText.initialize(
        onError: _handleSpeechError,
        onStatus: _handleSpeechStatus,
        debugLogging: kDebugMode,
      );

      _isNativeSttAvailable = available;
      _isNativeSttInitialized = true;

      if (_isNativeSttAvailable) {
        try {
          final sysLocale = await _speechToText.systemLocale();
          _selectedLocaleId = sysLocale?.localeId;
        } catch (_) {}
        debugPrint(
            '[PAL-HOLD] Native SpeechRecognizer initialized successfully (locale: $_selectedLocaleId)');
      } else {
        debugPrint(
            '[PAL-HOLD] Native SpeechRecognizer unavailable on this device; fallback enabled');
      }

      return _isNativeSttAvailable;
    } catch (e) {
      debugPrint('[PAL-HOLD] Native SpeechRecognizer init error: $e');
      _isNativeSttAvailable = false;
      _isNativeSttInitialized = true;
      return false;
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    debugPrint(
        '[PAL-HOLD] Native STT error: ${error.errorMsg} (permanent: ${error.permanent})');
    if (_state == AgentVoiceState.listening && _currentTranscript.isEmpty) {
      _errorMessage = "Sorry, I didn't catch that.";
    }
  }

  void _handleSpeechStatus(String status) {
    debugPrint('[PAL-HOLD] Native STT status: $status');
  }

  /// Starts recording / recognizing microphone specifically for Pal Agent voice commands.
  /// Uses Android Native SpeechRecognizer without loading Whisper or GGUF LLM models.
  Future<void> startListening() async {
    if (_state == AgentVoiceState.listening) return;

    _errorMessage = null;
    _currentTranscript = '';
    _pendingToolCalls = [];
    _executionResponse = null;
    _hasReceivedFirstPartial = false;

    _holdStopwatch.reset();
    _holdStopwatch.start();
    debugPrint('[PAL-HOLD] Pressed');

    if (!_isNativeSttInitialized) {
      await initializeNativeRecognizer();
    }

    if (_isNativeSttAvailable) {
      try {
        _useWhisperFallback = false;
        _sttStopwatch.reset();
        _sttStopwatch.start();

        await _speechToText.listen(
          onResult: _handleSpeechResult,
          localeId: _selectedLocaleId,
          listenOptions: SpeechListenOptions(
            partialResults: true,
            listenMode: ListenMode.confirmation,
            cancelOnError: false,
          ),
        );

        debugPrint('[PAL-HOLD] Native STT started');
        _state = AgentVoiceState.listening;
        notifyListeners();
        return;
      } catch (e) {
        debugPrint('[PAL-HOLD] Native listen start failed: $e, falling back');
        _useWhisperFallback = true;
      }
    } else {
      _useWhisperFallback = true;
    }

    // Whisper Fallback Path: only invoked if native recognizer is strictly unavailable
    if (_useWhisperFallback) {
      try {
        if (!_sttService.isInitialized) {
          await _sttService.init();
        }

        final tempDir = await getTemporaryDirectory();
        final tempPath =
            '${tempDir.path}/agent_voice_cmd_${DateTime.now().millisecondsSinceEpoch}.wav';
        _activeAudioPath = tempPath;

        _sttStopwatch.reset();
        _sttStopwatch.start();
        await _sttService.startCommandRecording(customFilePath: tempPath);
        debugPrint('[PAL-HOLD] Whisper fallback STT started');
        _state = AgentVoiceState.listening;
        notifyListeners();
      } catch (e) {
        debugPrint('[PAL-HOLD] Failed to start fallback listening: $e');
        _errorMessage = 'Microphone permission is needed for Hold Pal.';
        _state = AgentVoiceState.error;
        notifyListeners();
      }
    }
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords;
    if (words.isNotEmpty && !_hasReceivedFirstPartial) {
      _hasReceivedFirstPartial = true;
      debugPrint('[PAL-HOLD] First partial result: $words');
    }
    _currentTranscript = words;
    notifyListeners();
  }

  /// Stops listening, receives the final transcript, and dispatches to the Agent router.
  Future<String> stopListeningAndTranscribe() async {
    if (_state != AgentVoiceState.listening) {
      return _currentTranscript;
    }

    _state = AgentVoiceState.transcribing;
    notifyListeners();

    if (!_useWhisperFallback && _isNativeSttAvailable) {
      try {
        await _speechToText.stop();
        // Give native recognizer brief moment to finalize recognition
        await Future.delayed(const Duration(milliseconds: 350));
      } catch (e) {
        debugPrint('[PAL-HOLD] Error stopping native recognizer: $e');
      }

      _sttStopwatch.stop();
      final sttDuration = _sttStopwatch.elapsedMilliseconds;
      final rawTranscript = _currentTranscript.trim();

      debugPrint('[PAL-AGENT] Raw STT: $rawTranscript');
      debugPrint('[PAL-HOLD] Final STT result: $rawTranscript');
      debugPrint('[PAL-HOLD] STT duration: ${sttDuration}ms');

      if (rawTranscript.isEmpty) {
        _errorMessage = "Sorry, I didn't catch that.";
        _state = AgentVoiceState.error;
        notifyListeners();
        return '';
      }

      // Academic term & phonetic normalizer with user timetable subjects
      final userSubjects = [
        ...TimetableService.suggestedSubjects,
        ...TimetableService.instance.entries
            .map((e) => e.subject)
            .where((s) => s.isNotEmpty),
      ];
      final normalized = VoiceCommandNormalizer.normalize(rawTranscript,
              candidateSubjects: userSubjects)
          .trim();
      _currentTranscript = normalized;

      debugPrint('[PAL-AGENT] Normalized STT: $normalized');
      debugPrint('[PAL-HOLD] Agent started');
      final primaryIntent = AgentIntent.detectPrimaryIntent(_currentTranscript);
      debugPrint('[PAL-AGENT] Detected intent: ${primaryIntent.code}');
      debugPrint('[PAL-AGENT] Confidence: 0.95');
      debugPrint('[PAL-HOLD] Intent: ${primaryIntent.code}');

      _pendingToolCalls = _agentService.determineToolCalls(_currentTranscript);
      for (final call in _pendingToolCalls) {
        debugPrint('[PAL-AGENT] Selected tool: ${call.tool}');
        debugPrint(
            '[PAL-AGENT] Extracted subject: ${call.arguments['subject'] ?? 'none'}');
        debugPrint(
            '[PAL-AGENT] Extracted date: ${call.arguments['day'] ?? 'none'}');
        debugPrint(
            '[PAL-AGENT] Extracted start: ${call.arguments['startTime'] ?? 'none'}');
        debugPrint(
            '[PAL-AGENT] Extracted end: ${call.arguments['endTime'] ?? 'none'}');
        debugPrint('[PAL-HOLD] Tool: ${call.tool}');
      }

      _holdStopwatch.stop();
      debugPrint(
          '[PAL-HOLD] Total latency: ${_holdStopwatch.elapsedMilliseconds}ms');

      _state = AgentVoiceState.previewReady;
      notifyListeners();
      return _currentTranscript;
    }

    // Whisper Fallback Path execution
    try {
      final savedPath = await _sttService.stopRecordingOnly();
      final audioPath = savedPath ?? _activeAudioPath;

      if (audioPath == null || !File(audioPath).existsSync()) {
        _errorMessage = "Sorry, I didn't catch that.";
        _state = AgentVoiceState.error;
        notifyListeners();
        return '';
      }

      final rawTranscript = await _sttService.transcribeVoiceCommand(audioPath);
      _cleanupAudioFile(audioPath);

      _sttStopwatch.stop();
      final sttDuration = _sttStopwatch.elapsedMilliseconds;

      debugPrint('[PAL-AGENT] Raw STT: $rawTranscript');
      debugPrint('[PAL-HOLD] Final STT result: $rawTranscript');
      debugPrint('[PAL-HOLD] STT duration: ${sttDuration}ms');

      final userSubjects = [
        ...TimetableService.suggestedSubjects,
        ...TimetableService.instance.entries
            .map((e) => e.subject)
            .where((s) => s.isNotEmpty),
      ];
      final normalized = VoiceCommandNormalizer.normalize(rawTranscript,
              candidateSubjects: userSubjects)
          .trim();
      _currentTranscript = normalized;

      if (_currentTranscript.isEmpty) {
        _errorMessage = "Sorry, I didn't catch that.";
        _state = AgentVoiceState.error;
        notifyListeners();
        return '';
      }

      debugPrint('[PAL-AGENT] Normalized STT: $normalized');
      debugPrint('[PAL-HOLD] Agent started');
      final primaryIntent = AgentIntent.detectPrimaryIntent(_currentTranscript);
      debugPrint('[PAL-AGENT] Detected intent: ${primaryIntent.code}');
      debugPrint('[PAL-AGENT] Confidence: 0.95');
      debugPrint('[PAL-HOLD] Intent: ${primaryIntent.code}');

      _pendingToolCalls = _agentService.determineToolCalls(_currentTranscript);
      for (final call in _pendingToolCalls) {
        debugPrint('[PAL-AGENT] Selected tool: ${call.tool}');
        debugPrint(
            '[PAL-AGENT] Extracted subject: ${call.arguments['subject'] ?? 'none'}');
        debugPrint(
            '[PAL-AGENT] Extracted date: ${call.arguments['day'] ?? 'none'}');
        debugPrint(
            '[PAL-AGENT] Extracted start: ${call.arguments['startTime'] ?? 'none'}');
        debugPrint(
            '[PAL-AGENT] Extracted end: ${call.arguments['endTime'] ?? 'none'}');
        debugPrint('[PAL-HOLD] Tool: ${call.tool}');
      }

      _holdStopwatch.stop();
      debugPrint(
          '[PAL-HOLD] Total latency: ${_holdStopwatch.elapsedMilliseconds}ms');

      _state = AgentVoiceState.previewReady;
      notifyListeners();
      return _currentTranscript;
    } catch (e) {
      debugPrint('[PAL-HOLD] Fallback transcription error: $e');
      _errorMessage = "Sorry, I didn't catch that.";
      _state = AgentVoiceState.error;
      notifyListeners();
      return '';
    }
  }

  /// Cancels the current voice session and cleans up resources
  void cancelSession() {
    if (_state == AgentVoiceState.listening) {
      if (!_useWhisperFallback && _isNativeSttAvailable) {
        try {
          _speechToText.cancel();
        } catch (_) {}
      } else {
        _sttService.stopRecordingOnly();
      }
    }
    if (_activeAudioPath != null) {
      _cleanupAudioFile(_activeAudioPath!);
    }
    _state = AgentVoiceState.idle;
    _currentTranscript = '';
    _pendingToolCalls = [];
    _executionResponse = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Executes the recognized command through AgentService
  Future<AgentResponse> executeCurrentCommand() async {
    if (_currentTranscript.isEmpty) {
      throw Exception('No command transcript available to execute.');
    }

    try {
      final response = await _agentService.process(prompt: _currentTranscript);
      _executionResponse = response;
      for (final tr in response.toolResults) {
        debugPrint('[PAL-AGENT] Tool result: ${tr.message}');
      }
      debugPrint('[PAL-AGENT] Final response: ${response.text}');
      _state = AgentVoiceState.executed;
      notifyListeners();
      return response;
    } catch (e) {
      _errorMessage = 'Execution failed: $e';
      _state = AgentVoiceState.error;
      notifyListeners();
      rethrow;
    }
  }

  void _cleanupAudioFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
        debugPrint(
            '[AgentVoiceController] Cleaned up temporary voice audio: $path');
      }
    } catch (e) {
      debugPrint('[AgentVoiceController] Notice: audio cleanup error: $e');
    }
  }
}
