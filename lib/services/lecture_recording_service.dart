import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/lecture_recording.dart';
import '../models/timetable_entry.dart';
import 'lecture_intelligence_service.dart';
import 'pal_notification_service.dart';
import 'rag_service.dart';
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
      sourceType: 'scheduledLecture',
    );

    PalNotificationService.instance.showRecordingNotification(
      subject: entry.subject,
      recordingId: newId,
      elapsedSeconds: 0,
    );

    debugPrint('[RECORD] Lecture Recording Started:');
    debugPrint('[RECORD] Subject: ${entry.subject}');
    debugPrint('[RECORD] ID: $newId');
    debugPrint('[RECORD] Audio path: $actualPath');

    notifyListeners();
  }

  /// Start recording for a manual Live Capture session
  Future<LectureRecording> startLiveCapture({String? customTitle}) async {
    if (isRecordingNow) {
      return _activeRecording!;
    }

    final now = DateTime.now();
    final dateSlug =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final newId = 'live_$dateSlug';

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
      debugPrint('SttService live start recording fallback: $e');
    }

    final actualPath = SttService.instance.recordingPath ?? targetAudioPath;

    final defaultTitle =
        'Live Capture · ${_formatMonthDay(now)}, ${_formatTime(now)}';
    final initialSubject = customTitle ?? defaultTitle;

    final recording = LectureRecording(
      id: newId,
      subject: initialSubject,
      title: customTitle,
      date: now,
      scheduledStart: _formatTime(now),
      scheduledEnd: _formatTime(now),
      actualStart: now,
      audioPath: actualPath,
      durationSeconds: 0,
      fileSizeBytes: 0,
      transcriptionStatus: 'pending',
      summaryStatus: 'none',
      sourceType: 'liveCapture',
    );

    _activeRecording = recording;

    PalNotificationService.instance.showRecordingNotification(
      subject: initialSubject,
      recordingId: newId,
      elapsedSeconds: 0,
    );

    debugPrint('[RECORD] Live Capture Started:');
    debugPrint('[RECORD] Subject: $initialSubject');
    debugPrint('[RECORD] ID: $newId');
    debugPrint('[RECORD] Audio path: $actualPath');

    notifyListeners();
    return recording;
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

    debugPrint('[RECORD] Lecture Recording Finished:');
    debugPrint('[RECORD] Subject: ${ongoing.displayTitle}');
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

    // Show native Pal notification with real lecture ID and actionable deep-links
    await PalNotificationService.instance.showLectureReadyNotification(
      recording: finalized,
    );

    debugPrint('[DATABASE] Saved new recording ${finalized.id} to storage.');

    // Trigger shared on-device LectureIntelligenceService pipeline
    _processRecordingPipeline(finalized);

    return finalized;
  }

  /// Stop manual Live Capture session (delegates to shared stopActiveRecording)
  Future<LectureRecording?> stopLiveCapture() async {
    return await stopActiveRecording();
  }

  /// Updates recording in store and notifies listeners
  Future<void> updateRecordingInStore(LectureRecording updated) async {
    final idx = _recordings.indexWhere((r) => r.id == updated.id);
    if (idx != -1) {
      _recordings[idx] = updated;
    } else {
      _recordings.insert(0, updated);
    }
    notifyListeners();
    _saveRecordings();
  }

  /// Allow the user to rename any lecture recording
  Future<void> updateRecordingTitle(String id, String newTitle) async {
    final idx = _recordings.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    final cleanTitle = newTitle.trim();
    if (cleanTitle.isEmpty) return;

    final updated = _recordings[idx].copyWith(
      subject: cleanTitle,
      title: cleanTitle,
    );
    _recordings[idx] = updated;
    notifyListeners();
    _saveRecordings();

    // Reindex in RAG with new title
    try {
      RagService.instance.indexLectureRecording(updated);
    } catch (e) {
      debugPrint('Notice: RAG reindex error on rename: $e');
    }
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

  Future<void> _processRecordingPipeline(
    LectureRecording recording, {
    bool forceRetry = false,
  }) async {
    await LectureIntelligenceService.instance.processLecture(
      recording,
      forceRetry: forceRetry,
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

      try {
        RagService.instance.unindexLectureRecording(id);
      } catch (e) {
        debugPrint('Notice: RAG unindex error: $e');
      }
    }
  }

  static String _formatMonthDay(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }
}
