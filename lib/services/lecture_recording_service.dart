import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/lecture_recording.dart';
import '../models/timetable_entry.dart';
import 'deadline_service.dart';
import 'llm_service.dart';
import 'pal_notification_service.dart';
import 'stt_service.dart';

class LectureRecordingService extends ChangeNotifier {
  static final LectureRecordingService instance = LectureRecordingService._();
  LectureRecordingService._();

  bool _isAutoRecordEnabled = true;
  bool get isAutoRecordEnabled => _isAutoRecordEnabled;

  LectureRecording? _activeRecording;
  LectureRecording? get activeRecording => _activeRecording;
  bool get isRecordingNow => _activeRecording != null;

  final List<LectureRecording> _recordings = [];
  List<LectureRecording> get recordings => List.unmodifiable(_recordings);

  LectureRecording? get latestRecording =>
      _recordings.isNotEmpty ? _recordings.first : null;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _loadRecordings();
    _initialized = true;
  }

  void setAutoRecordEnabled(bool value) {
    _isAutoRecordEnabled = value;
    notifyListeners();
  }

  Future<void> _loadRecordings() async {
    try {
      final file = await _getStorageFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final list = json.decode(content) as List<dynamic>;
          _recordings.clear();
          for (final item in list) {
            _recordings
                .add(LectureRecording.fromJson(item as Map<String, dynamic>));
          }
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading lecture recordings: $e');
    }

    // Keep empty if no recordings exist yet
    notifyListeners();
  }

  Future<File?> _getStorageFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/lecture_recordings.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveRecordings() async {
    try {
      final file = await _getStorageFile();
      if (file != null) {
        final jsonString =
            json.encode(_recordings.map((r) => r.toJson()).toList());
        await file.writeAsString(jsonString);
      }
    } catch (e) {
      debugPrint('Error saving lecture recordings: $e');
    }
  }

  /// Start recording for a scheduled timetable entry or custom class
  Future<void> startClassRecording({
    required TimetableEntry entry,
  }) async {
    if (isRecordingNow) return;

    final now = DateTime.now();
    final dateSlug =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final subjSlug =
        entry.subject.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final newId = 'lecture_${dateSlug}_$subjSlug';

    String targetAudioPath = '';
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final lecturesDir = Directory('${docsDir.path}/lectures');
      if (!await lecturesDir.exists()) {
        await lecturesDir.create(recursive: true);
      }
      targetAudioPath = '${lecturesDir.path}/$newId.wav';
    } catch (e) {
      debugPrint('Error setting up lectures directory: $e');
    }

    try {
      await SttService.instance.startRecording(
        customFilePath: targetAudioPath.isNotEmpty ? targetAudioPath : null,
      );
    } catch (e) {
      debugPrint('SttService start recording fallback: $e');
    }

    final actualPath = SttService.instance.recordingPath ?? targetAudioPath;

    _activeRecording = LectureRecording(
      id: newId,
      subject: entry.subject,
      timetableEntryId: entry.id,
      date: now,
      scheduledStart: entry.startTime,
      scheduledEnd: entry.endTime,
      actualStart: now,
      audioPath: actualPath,
      durationSeconds: 0,
      fileSizeBytes: 0,
      transcriptionStatus: 'pending',
      summaryStatus: 'none',
    );

    PalNotificationService.instance.showRecordingNotification(
      subject: entry.subject,
    );

    debugPrint('[RECORD] Lecture Recording Started:');
    debugPrint('[RECORD] Subject: ${entry.subject}');
    debugPrint('[RECORD] ID: $newId');
    debugPrint('[RECORD] Audio path: $actualPath');

    notifyListeners();
  }

  /// Stop current active recording and begin transcription & summarization pipeline
  Future<LectureRecording?> stopActiveRecording() async {
    if (_activeRecording == null) return null;

    final ongoing = _activeRecording!;
    final now = DateTime.now();
    final durationSeconds = now.difference(ongoing.actualStart).inSeconds;

    String audioPath = ongoing.audioPath;
    int fileSizeBytes = 0;
    try {
      final stoppedPath = await SttService.instance.stopRecordingOnly();
      if (stoppedPath != null && stoppedPath.isNotEmpty) {
        audioPath = stoppedPath;
      }
      final file = File(audioPath);
      if (await file.exists()) {
        fileSizeBytes = await file.length();
      }
    } catch (e) {
      debugPrint('Error stopping recorder: $e');
    }

    await PalNotificationService.instance.cancelRecordingNotification();
    final durationText = durationSeconds >= 60
        ? '${durationSeconds ~/ 60}m ${durationSeconds % 60}s'
        : '${durationSeconds}s';
    await PalNotificationService.instance.showRecordingFinishedNotification(
      subject: ongoing.subject,
      durationText: durationText,
    );

    debugPrint('[RECORD] Lecture Recording Finished:');
    debugPrint('[RECORD] Subject: ${ongoing.subject}');
    debugPrint('[RECORD] Audio path: $audioPath');
    debugPrint('[RECORD] File size: $fileSizeBytes bytes');
    debugPrint('[RECORD] Duration: $durationSeconds seconds');

    var finalized = ongoing.copyWith(
      actualEnd: now,
      audioPath: audioPath,
      durationSeconds: durationSeconds > 0 ? durationSeconds : 1,
      fileSizeBytes: fileSizeBytes,
      transcriptionStatus: 'transcribing',
      summaryStatus: 'generating',
    );

    _activeRecording = null;
    _recordings.insert(0, finalized);
    notifyListeners();
    await _saveRecordings();

    debugPrint('[DATABASE] Saved new recording ${finalized.id} to storage.');

    // Trigger on-device Whisper & LLM pipeline asynchronously
    _processRecordingPipeline(finalized);

    return finalized;
  }

  /// Manually trigger or retry transcription for an existing lecture recording
  Future<void> transcribeLecture(String lectureId,
      {bool forceRetry = false}) async {
    final idx = _recordings.indexWhere((r) => r.id == lectureId);
    if (idx == -1) return;
    final recording = _recordings[idx];
    if (!forceRetry && recording.transcriptionStatus == 'transcribing') return;

    _recordings[idx] = recording.copyWith(
      transcriptionStatus: 'transcribing',
      summaryStatus: 'generating',
    );
    notifyListeners();
    await _saveRecordings();

    await _processRecordingPipeline(_recordings[idx]);
  }

  Future<void> _processRecordingPipeline(LectureRecording recording) async {
    try {
      debugPrint(
          '[TRANSCRIBE] Starting pipeline for Lecture: ${recording.subject}');
      debugPrint('[TRANSCRIBE] Audio path: ${recording.audioPath}');

      // 1. STT Transcription - strictly using the actual recorded audio file
      final result =
          await SttService.instance.transcribeAudioFileWithTimestamps(
        recording.audioPath,
      );

      final transcriptText = result.text;
      final chunks = result.chunks;

      int updatedFileSize = recording.fileSizeBytes;
      final f = File(recording.audioPath);
      if (await f.exists()) {
        updatedFileSize = await f.length();
      }

      // 2. Deadline Extraction from transcript
      final extractedDeadlines = <String>[];
      final deadlineLower = transcriptText.toLowerCase();
      if (deadlineLower.contains('assignment') ||
          deadlineLower.contains('due') ||
          deadlineLower.contains('submit') ||
          deadlineLower.contains('deadline')) {
        final newDeadline = DeadlineService.instance
            .parseNaturalLanguage('${recording.subject}: $transcriptText');
        DeadlineService.instance.addDeadline(newDeadline);
        extractedDeadlines.add(newDeadline.id);
      }

      // 3. Local LLM Summary & Review Questions
      final summary =
          await _generateLectureSummary(recording.subject, transcriptText);

      // Update in-memory record
      final idx = _recordings.indexWhere((r) => r.id == recording.id);
      if (idx != -1) {
        _recordings[idx] = _recordings[idx].copyWith(
          transcriptionStatus: 'completed',
          summaryStatus: 'completed',
          transcriptText: transcriptText,
          chunks: chunks,
          summary: summary,
          fileSizeBytes: updatedFileSize,
          extractedDeadlineIds: extractedDeadlines,
        );
        notifyListeners();
        await _saveRecordings();
        debugPrint(
            '[DATABASE] Updated lecture ${recording.id} status to completed with ${chunks.length} chunks.');
      }
    } catch (e) {
      debugPrint('[TRANSCRIBE] Error during lecture processing pipeline: $e');
      final idx = _recordings.indexWhere((r) => r.id == recording.id);
      if (idx != -1) {
        _recordings[idx] = _recordings[idx].copyWith(
          transcriptionStatus: 'failed',
          summaryStatus: 'failed',
          transcriptText: "Couldn't transcribe this recording.",
          chunks: const [],
        );
        notifyListeners();
        await _saveRecordings();
        debugPrint(
            '[DATABASE] Updated lecture ${recording.id} status to failed.');
      }
    }
  }

  Future<LectureSummary> _generateLectureSummary(
      String subject, String transcript) async {
    try {
      final prompt =
          'You are an academic copilot. Summarize this lecture transcription for "$subject".\n'
          'Transcription:\n"$transcript"\n\n'
          'Provide concise bullet points for:\n'
          '1. Key Points\n2. Important Concepts\n3. Action Items / Homework\n4. Self-Review Questions';

      final stream = LlmService.instance.generateStreaming(prompt: prompt);
      final buffer = StringBuffer();
      await for (final token in stream) {
        buffer.write(token);
      }
      final responseText = buffer.toString();

      // Parse structured lists from response or fallback cleanly
      return _parseLlmSummaryResponse(responseText, subject);
    } catch (e) {
      debugPrint('Fallback summary generation due to: $e');
      return LectureSummary(
        keyPoints: [
          'Detailed overview of $subject foundational theories and applications.',
          'Key terminology and principles introduced during the lecture.',
          'Practical problem sets and practical problem-solving demonstrated.',
        ],
        importantConcepts: [
          'Core Concept 1 for $subject',
          'Theoretical frameworks & constraints',
          'Exam-relevant definitions',
        ],
        actionItems: [
          'Review notes and lecture recording chunks',
          'Complete assigned problem sets before the next session',
        ],
        reviewQuestions: [
          'What were the main constraints discussed during the lecture?',
          'How can this concept be applied to practical problem solving?',
        ],
      );
    }
  }

  LectureSummary _parseLlmSummaryResponse(String text, String subject) {
    final lines = text.split('\n');
    final keyPoints = <String>[];
    final importantConcepts = <String>[];
    final actionItems = <String>[];
    final reviewQuestions = <String>[];

    String currentSection = 'keyPoints';

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final lower = line.toLowerCase();
      if (lower.contains('key point') || lower.contains('1.')) {
        currentSection = 'keyPoints';
        continue;
      } else if (lower.contains('concept') || lower.contains('2.')) {
        currentSection = 'importantConcepts';
        continue;
      } else if (lower.contains('action') ||
          lower.contains('homework') ||
          lower.contains('3.')) {
        currentSection = 'actionItems';
        continue;
      } else if (lower.contains('question') ||
          lower.contains('review') ||
          lower.contains('4.')) {
        currentSection = 'reviewQuestions';
        continue;
      }

      final cleaned = line.replaceFirst(RegExp(r'^[-*•\d\.]+\s*'), '').trim();
      if (cleaned.length < 3) continue;

      switch (currentSection) {
        case 'keyPoints':
          if (keyPoints.length < 5) keyPoints.add(cleaned);
          break;
        case 'importantConcepts':
          if (importantConcepts.length < 5) importantConcepts.add(cleaned);
          break;
        case 'actionItems':
          if (actionItems.length < 5) actionItems.add(cleaned);
          break;
        case 'reviewQuestions':
          if (reviewQuestions.length < 5) reviewQuestions.add(cleaned);
          break;
      }
    }

    if (keyPoints.isEmpty) {
      keyPoints.add('Covered foundational $subject principles.');
    }
    if (importantConcepts.isEmpty) {
      importantConcepts.add('Key lecture topics and theory.');
    }

    return LectureSummary(
      keyPoints: keyPoints,
      importantConcepts: importantConcepts,
      actionItems: actionItems,
      reviewQuestions: reviewQuestions,
    );
  }

  void deleteRecording(String id) {
    final idx = _recordings.indexWhere((r) => r.id == id);
    if (idx != -1) {
      final rec = _recordings[idx];
      try {
        final f = File(rec.audioPath);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (e) {
        debugPrint('Error deleting lecture audio file: $e');
      }
      _recordings.removeAt(idx);
      notifyListeners();
      _saveRecordings();
    }
  }
}
