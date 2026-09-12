import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/timetable_entry.dart';
import 'lecture_recording_service.dart';
import 'pal_notification_service.dart';
import 'timetable_service.dart';

class RecordingScheduler {
  static final RecordingScheduler instance = RecordingScheduler._();
  RecordingScheduler._();

  Timer? _pollingTimer;
  final Set<String> _notifiedPreClassAlerts = {};
  final Set<String> _recordedClassesToday = {};
  DateTime _lastCheckedDay = DateTime.now();

  bool _isTestModeActive = false;
  bool get isTestModeActive => _isTestModeActive;

  void start() {
    _pollingTimer?.cancel();
    // Check every 15 seconds for class start/end transitions
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _checkSchedule();
    });
    _checkSchedule();
    debugPrint('RecordingScheduler started.');
  }

  void stop() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    debugPrint('RecordingScheduler stopped.');
  }

  void _checkSchedule() {
    final now = DateTime.now();

    // Reset daily cache at midnight
    if (now.day != _lastCheckedDay.day) {
      _notifiedPreClassAlerts.clear();
      _recordedClassesToday.clear();
      _lastCheckedDay = now;
    }

    if (!LectureRecordingService.instance.isAutoRecordEnabled) {
      return;
    }

    final todayClasses = TimetableService.instance.getTodayClasses();
    final currentHourDouble = now.hour + (now.minute / 60.0);

    for (final entry in todayClasses) {
      final startDiffMinutes = ((entry.startHourDouble - currentHourDouble) * 60).round();

      // 1. Pre-class notification (approx 10 minutes prior, between 8 and 12 min)
      if (startDiffMinutes >= 8 && startDiffMinutes <= 12) {
        final alertKey = '${entry.id}_preclass_${now.day}';
        if (!_notifiedPreClassAlerts.contains(alertKey)) {
          _notifiedPreClassAlerts.add(alertKey);
          PalNotificationService.instance.showPreClassAlert(
            subject: entry.subject,
            startTime: entry.startTime,
            minutesLeft: startDiffMinutes,
          );
        }
      }

      // 2. Class is happening right now: auto-start recording if not already started/recorded
      final isDuringClass = currentHourDouble >= entry.startHourDouble &&
          currentHourDouble < entry.endHourDouble;

      if (isDuringClass) {
        final classRecordKey = '${entry.id}_${now.day}';
        if (!_recordedClassesToday.contains(classRecordKey) &&
            !LectureRecordingService.instance.isRecordingNow) {
          _recordedClassesToday.add(classRecordKey);
          LectureRecordingService.instance.startClassRecording(entry: entry);
        }
      }

      // 3. Class has ended: if active recording matches this entry, auto-stop
      if (currentHourDouble >= entry.endHourDouble) {
        final active = LectureRecordingService.instance.activeRecording;
        if (active != null && active.timetableEntryId == entry.id) {
          LectureRecordingService.instance.stopActiveRecording();
        }
      }
    }
  }

  /// Developer 1-minute test mode to simulate the full lifecycle without waiting:
  /// Starts recording after [delaySeconds] and automatically stops after [durationSeconds].
  void scheduleTestLecture({
    String subject = 'Operating Systems (Test)',
    int delaySeconds = 2,
    int durationSeconds = 15,
  }) {
    _isTestModeActive = true;
    debugPrint('Test lecture scheduled in $delaySeconds seconds for $durationSeconds seconds duration.');

    Timer(Duration(seconds: delaySeconds), () async {
      final testEntry = TimetableEntry(
        id: 'test_class_${DateTime.now().millisecondsSinceEpoch}',
        subject: subject,
        dayOfWeek: TimetableService.instance.getTodayDayOfWeek(),
        startTime: 'Now',
        endTime: '+${durationSeconds}s',
        room: 'Lab 101',
        type: 'Lecture',
      );

      await LectureRecordingService.instance.startClassRecording(entry: testEntry);

      Timer(Duration(seconds: durationSeconds), () async {
        await LectureRecordingService.instance.stopActiveRecording();
        _isTestModeActive = false;
        debugPrint('Test lecture completed and auto-stopped successfully.');
      });
    });
  }
}
