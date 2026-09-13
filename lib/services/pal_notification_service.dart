import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/campus_vault.dart';
import '../models/deadline.dart';
import '../models/lecture_recording.dart';
import '../models/notification_payload.dart';
import '../models/scheduled_notification_record.dart';
import '../models/timetable_entry.dart';
import '../screens/lecture_details_screen.dart';
import '../screens/pal_brain_screen.dart';
import '../screens/study_vault/campus/academic_calendar_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/timetable_screen.dart';
import '../screens/voice_notes_screen.dart';
import '../theme/app_theme.dart';
import 'lecture_recording_service.dart';
import 'timetable_service.dart';

/// Central Notification Service for Pal.
///
/// Manages Android 16-compatible local notifications, persistent scheduling,
/// action button deep-links, and lifecycle reconciliation with real Pal services.
class PalNotificationService {
  static final PalNotificationService instance = PalNotificationService._();
  PalNotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  GlobalKey<NavigatorState>? _navigatorKey;

  // In-memory cache of scheduled notification metadata
  final Map<int, ScheduledNotificationRecord> _scheduledRecords = {};

  // Color tokens adhering to Pal's existing visual identity
  static const Color palGoldColor = AppTheme.primaryAccent; // 0xFFB88628
  static const String palSmallIcon = 'ic_stat_pal';
  static const String palFallbackIcon = '@mipmap/ic_launcher';

  // Android Notification Channels
  static const String classChannelId = 'pal_classes_channel';
  static const String recordingChannelId = 'pal_recording_channel';
  static const String deadlineChannelId = 'pal_deadlines_channel';
  static const String academicChannelId = 'pal_academic_channel';
  static const String agentChannelId = 'pal_agent_channel';

  // Constant Notification IDs
  static const int ongoingRecordingNotificationId = 1002;

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Initialize local notifications, timezone database, channels, and persistence
  Future<void> init() async {
    if (_initialized) return;

    try {
      // 1. Initialize Timezone database for precise scheduling
      tz.initializeTimeZones();
      try {
        final String timeZoneName = DateTime.now().timeZoneName;
        tz.setLocalLocation(tz.getLocation(timeZoneName));
      } catch (_) {
        tz.setLocalLocation(tz.UTC);
      }

      // 2. Platform initialization settings
      const androidInitSettings =
          AndroidInitializationSettings(palFallbackIcon);
      const darwinInitSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidInitSettings,
        iOS: darwinInitSettings,
        macOS: darwinInitSettings,
      );

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          _handleNotificationResponse(response);
        },
      );

      // 3. Create Android 8+ Notification Channels with Pal branding
      await _createNotificationChannels();

      // 4. Request Android 13+ runtime POST_NOTIFICATIONS permission
      final androidPlatform =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlatform != null) {
        await androidPlatform.requestNotificationsPermission();
      }

      // 5. Load persisted scheduled notification metadata
      await _loadPersistedScheduledRecords();

      _initialized = true;
      debugPrint(
          '[NOTIFICATIONS] PalNotificationService initialized successfully.');
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Initialization error: $e');
      _initialized = false;
    }
  }

  /// Explicitly requests notification permissions on Android 13+
  Future<bool> requestNotificationPermission() async {
    try {
      final androidPlatform =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlatform != null) {
        final granted = await androidPlatform.requestNotificationsPermission();
        return granted ?? false;
      }
      return true;
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Permission request error: $e');
      return false;
    }
  }

  /// Creates separate, distinct Android notification channels adhering to Android best practices
  Future<void> _createNotificationChannels() async {
    final androidPlatform =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlatform == null) return;

    // 1. Classes Channel (High importance, alert prior to class)
    await androidPlatform.createNotificationChannel(
      const AndroidNotificationChannel(
        classChannelId,
        'Pal · Classes',
        description:
            'Upcoming class reminders and automated lecture recording alerts',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      ),
    );

    // 2. Ongoing Recording Channel (Low importance, silent, persistent)
    await androidPlatform.createNotificationChannel(
      const AndroidNotificationChannel(
        recordingChannelId,
        'Pal · Recording',
        description: 'Active lecture audio recording status indicator',
        importance: Importance.low,
        enableVibration: false,
        playSound: false,
        showBadge: false,
      ),
    );

    // 3. Deadlines Channel (High importance, academic deadlines)
    await androidPlatform.createNotificationChannel(
      const AndroidNotificationChannel(
        deadlineChannelId,
        'Pal · Deadlines',
        description:
            'Reminders for assignment submissions, lab reports, and homework',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      ),
    );

    // 4. Academic Channel (Default importance, holidays and campus notices)
    await androidPlatform.createNotificationChannel(
      const AndroidNotificationChannel(
        academicChannelId,
        'Pal · Academic',
        description:
            'Campus holidays, vacation breaks, and academic calendar announcements',
        importance: Importance.defaultImportance,
        enableVibration: false,
        playSound: true,
      ),
    );

    // 5. Agent Channel (Default importance, Pal assistant schedule confirmations)
    await androidPlatform.createNotificationChannel(
      const AndroidNotificationChannel(
        agentChannelId,
        'Pal · Agent',
        description:
            'Autonomous actions, recording schedules, and intelligent study updates',
        importance: Importance.defaultImportance,
        enableVibration: false,
        playSound: true,
      ),
    );
  }

  // ===========================================================================
  // 1. CLASS REMINDERS (TIMETABLE INTEGRATION)
  // ===========================================================================

  /// Schedules pre-class reminders (15 min and 5 min prior) for a timetable entry
  Future<void> scheduleClassReminders(TimetableEntry entry) async {
    final now = DateTime.now();
    final todayWeekday = TimetableService.defaultDays[now.weekday - 1];

    // Only schedule if the entry occurs today or is set to repeat weekly
    if (entry.dayOfWeek != todayWeekday && !entry.repeatWeekly) {
      return;
    }

    final startTime = _parseTimeToDateTime(entry.startTime, now);
    if (startTime == null) return;

    // 15-minute prior reminder
    final reminder15 = startTime.subtract(const Duration(minutes: 15));
    if (reminder15.isAfter(now)) {
      await _scheduleSingleClassReminder(
        entry: entry,
        scheduledTime: reminder15,
        minutesLeft: 15,
        subId: 1,
      );
    }

    // 5-minute prior reminder
    final reminder5 = startTime.subtract(const Duration(minutes: 5));
    if (reminder5.isAfter(now)) {
      await _scheduleSingleClassReminder(
        entry: entry,
        scheduledTime: reminder5,
        minutesLeft: 5,
        subId: 2,
      );
    }
  }

  Future<void> _scheduleSingleClassReminder({
    required TimetableEntry entry,
    required DateTime scheduledTime,
    required int minutesLeft,
    required int subId,
  }) async {
    final notificationId = _generateNotificationId(entry.id, subId: subId);

    final payload = NotificationPayload(
      type: NotificationType.classReminder,
      entityId: entry.id,
      action: NotificationAction.view,
      extra: {
        'subject': entry.subject,
        'startTime': entry.startTime,
        'room': entry.room,
      },
    );

    final androidDetails = AndroidNotificationDetails(
      classChannelId,
      'Pal · Classes',
      channelDescription: 'Upcoming class reminders',
      importance: Importance.high,
      priority: Priority.high,
      color: palGoldColor,
      icon: palSmallIcon,
      actions: [
        AndroidNotificationAction(
          'view_class_${entry.id}',
          'View Class',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'record_class_${entry.id}',
          'Record',
          showsUserInterface: true,
        ),
      ],
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      final tzDateTime = _toTzDateTime(scheduledTime);
      await _notificationsPlugin.zonedSchedule(
        notificationId,
        '✨ Upcoming Class · ${entry.subject}',
        'Starts in $minutesLeft minutes (${entry.startTime})${(entry.room != null && entry.room!.isNotEmpty) ? " • ${entry.room}" : ""}',
        tzDateTime,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload.toJsonString(),
      );

      _recordScheduledNotification(ScheduledNotificationRecord(
        id: notificationId,
        type: 'class',
        entityId: entry.id,
        scheduledTime: scheduledTime,
        title: '✨ Upcoming Class · ${entry.subject}',
        body: 'Starts in $minutesLeft minutes (${entry.startTime})',
        payload: payload.toJsonString(),
      ));

      debugPrint(
          '[NOTIFICATIONS] Scheduled class reminder for ${entry.subject} at $scheduledTime (id: $notificationId)');
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Error scheduling class reminder: $e');
    }
  }

  // ===========================================================================
  // 2. ACTIVE LECTURE RECORDING (ONGOING NOTIFICATION)
  // ===========================================================================

  /// Shows or updates the ongoing foreground notification while recording a lecture
  Future<void> showRecordingNotification({
    required String subject,
    int elapsedSeconds = 0,
    String? recordingId,
  }) async {
    try {
      final durationText = _formatSecondsToTimer(elapsedSeconds);

      final payload = NotificationPayload(
        type: NotificationType.recording,
        entityId: recordingId ?? 'active',
        action: NotificationAction.view,
        extra: {'subject': subject},
      );

      final androidDetails = AndroidNotificationDetails(
        recordingChannelId,
        'Pal · Recording',
        channelDescription: 'Active lecture audio recording status',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showWhen: true,
        color: palGoldColor,
        icon: palSmallIcon,
        actions: const [
          AndroidNotificationAction(
            'open_lecture_active',
            'Open Lecture',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            'stop_lecture_active',
            'Stop',
            showsUserInterface: true,
          ),
        ],
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: false,
        ),
      );

      await _notificationsPlugin.show(
        ongoingRecordingNotificationId,
        '🎙 Recording · $subject',
        'Recording in progress · $durationText',
        notificationDetails,
        payload: payload.toJsonString(),
      );
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Error showing recording notification: $e');
    }
  }

  /// Cancels the ongoing recording notification
  Future<void> cancelRecordingNotification() async {
    try {
      await _notificationsPlugin.cancel(ongoingRecordingNotificationId);
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Error cancelling recording notification: $e');
    }
  }

  // ===========================================================================
  // 3. LECTURE READY NOTIFICATION
  // ===========================================================================

  /// Displays notification when a lecture has finished saving with actions for Listen, Transcribe, and Ask Pal
  Future<void> showLectureReadyNotification({
    required LectureRecording recording,
  }) async {
    try {
      final notificationId = _generateNotificationId(recording.id, subId: 8);

      final payload = NotificationPayload(
        type: NotificationType.lecture,
        entityId: recording.id,
        action: NotificationAction.view,
        extra: {'subject': recording.displayTitle},
      );

      final hasTranscript = recording.transcriptText.trim().isNotEmpty ||
          recording.chunks.isNotEmpty;

      final androidDetails = AndroidNotificationDetails(
        classChannelId,
        'Pal · Classes',
        channelDescription:
            'Finished lecture notifications and processing status',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        color: palGoldColor,
        icon: palSmallIcon,
        actions: [
          AndroidNotificationAction(
            'listen_${recording.id}',
            'Listen',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            hasTranscript
                ? 'ask_pal_${recording.id}'
                : 'transcribe_${recording.id}',
            hasTranscript ? 'Ask Pal' : 'Transcribe',
            showsUserInterface: true,
          ),
        ],
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _notificationsPlugin.show(
        notificationId,
        '✓ Lecture Ready · ${recording.displayTitle}',
        'Your lecture recording has been saved securely (${recording.formattedDuration}).',
        notificationDetails,
        payload: payload.toJsonString(),
      );

      debugPrint('[NOTIFICATIONS] Lecture Ready shown for ${recording.id}');
    } catch (e) {
      debugPrint(
          '[NOTIFICATIONS] Error showing lecture ready notification: $e');
    }
  }

  // ===========================================================================
  // 4. DEADLINE REMINDERS (TASK INTEGRATION)
  // ===========================================================================

  /// Schedules deadline reminders for a deadline (24 hours and 1 hour before)
  Future<void> scheduleDeadlineReminders(Deadline deadline) async {
    if (deadline.isCompleted) {
      await cancelEntityNotifications(deadline.id);
      return;
    }

    final now = DateTime.now();

    // 24-hour reminder
    final reminder24h = deadline.dueDate.subtract(const Duration(hours: 24));
    if (reminder24h.isAfter(now)) {
      await _scheduleSingleDeadlineReminder(
        deadline: deadline,
        scheduledTime: reminder24h,
        label: 'Due in 24 hours',
        subId: 1,
      );
    }

    // 1-hour reminder
    final reminder1h = deadline.dueDate.subtract(const Duration(hours: 1));
    if (reminder1h.isAfter(now)) {
      await _scheduleSingleDeadlineReminder(
        deadline: deadline,
        scheduledTime: reminder1h,
        label: 'Due in 1 hour',
        subId: 2,
      );
    }
  }

  Future<void> _scheduleSingleDeadlineReminder({
    required Deadline deadline,
    required DateTime scheduledTime,
    required String label,
    required int subId,
  }) async {
    final notificationId = _generateNotificationId(deadline.id, subId: subId);

    final payload = NotificationPayload(
      type: NotificationType.task,
      entityId: deadline.id,
      action: NotificationAction.view,
      extra: {'title': deadline.title, 'course': deadline.course},
    );

    final androidDetails = AndroidNotificationDetails(
      deadlineChannelId,
      'Pal · Deadlines',
      channelDescription: 'Academic task deadline reminders',
      importance: Importance.high,
      priority: Priority.high,
      color: palGoldColor,
      icon: palSmallIcon,
      actions: [
        AndroidNotificationAction(
          'view_task_${deadline.id}',
          'View Task',
          showsUserInterface: true,
        ),
      ],
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      final tzDateTime = _toTzDateTime(scheduledTime);
      await _notificationsPlugin.zonedSchedule(
        notificationId,
        '⏰ Deadline Soon · ${deadline.title}',
        '$label (${deadline.course})',
        tzDateTime,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload.toJsonString(),
      );

      _recordScheduledNotification(ScheduledNotificationRecord(
        id: notificationId,
        type: 'task',
        entityId: deadline.id,
        scheduledTime: scheduledTime,
        title: '⏰ Deadline Soon · ${deadline.title}',
        body: '$label (${deadline.course})',
        payload: payload.toJsonString(),
      ));

      debugPrint(
          '[NOTIFICATIONS] Scheduled deadline reminder for ${deadline.title} at $scheduledTime (id: $notificationId)');
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Error scheduling deadline reminder: $e');
    }
  }

  // ===========================================================================
  // 5. HOLIDAY & ACADEMIC REMINDERS
  // ===========================================================================

  /// Shows or schedules notification for an academic holiday or break
  Future<void> showHolidayAlert(CampusHoliday holiday) async {
    try {
      final notificationId = _generateNotificationId(holiday.id, subId: 5);

      final payload = NotificationPayload(
        type: NotificationType.holiday,
        entityId: holiday.id,
        action: NotificationAction.view,
        extra: {'name': holiday.name},
      );

      final androidDetails = AndroidNotificationDetails(
        academicChannelId,
        'Pal · Academic',
        channelDescription: 'Campus holidays and calendar notices',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        color: palGoldColor,
        icon: palSmallIcon,
        actions: const [
          AndroidNotificationAction(
            'view_calendar',
            'View Calendar',
            showsUserInterface: true,
          ),
        ],
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      );

      await _notificationsPlugin.show(
        notificationId,
        '📅 Tomorrow · No Classes',
        '${holiday.name} (${holiday.type.displayName})',
        notificationDetails,
        payload: payload.toJsonString(),
      );
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Error showing holiday alert: $e');
    }
  }

  // ===========================================================================
  // 6. PAL AGENT NOTIFICATION
  // ===========================================================================

  /// Shows confirmation notification when Pal Agent performs an autonomous schedule action
  Future<void> showAgentActionNotification({
    required String title,
    required String message,
    String? entityId,
    NotificationType type = NotificationType.agent,
  }) async {
    try {
      final notificationId = _generateNotificationId(
          entityId ?? 'agent_${DateTime.now().millisecondsSinceEpoch}',
          subId: 9);

      final payload = NotificationPayload(
        type: type,
        entityId: entityId ?? '',
        action: NotificationAction.view,
      );

      final androidDetails = AndroidNotificationDetails(
        agentChannelId,
        'Pal · Agent',
        channelDescription:
            'Pal Agent schedule confirmations and study assistant actions',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        color: palGoldColor,
        icon: palSmallIcon,
        actions: const [
          AndroidNotificationAction(
            'open_pal_agent',
            'View',
            showsUserInterface: true,
          ),
        ],
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      );

      await _notificationsPlugin.show(
        notificationId,
        title,
        message,
        notificationDetails,
        payload: payload.toJsonString(),
      );
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Error showing agent notification: $e');
    }
  }

  // ===========================================================================
  // 7. CANCELLATION & RECONCILIATION
  // ===========================================================================

  /// Cancels all notifications tied to a specific entity ID (e.g. deleted class or completed task)
  Future<void> cancelEntityNotifications(String entityId) async {
    try {
      final toCancel = _scheduledRecords.values
          .where((r) => r.entityId == entityId)
          .map((r) => r.id)
          .toList();

      for (final id in toCancel) {
        await _notificationsPlugin.cancel(id);
        _scheduledRecords.remove(id);
      }

      // Also cancel standard hashed IDs
      for (int subId = 1; subId <= 9; subId++) {
        final id = _generateNotificationId(entityId, subId: subId);
        await _notificationsPlugin.cancel(id);
        _scheduledRecords.remove(id);
      }

      await _savePersistedScheduledRecords();
      debugPrint(
          '[NOTIFICATIONS] Cancelled notifications for entity: $entityId');
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Error cancelling entity notifications: $e');
    }
  }

  /// Reconciles persisted schedules on app startup to remove stale reminders and reschedule active ones
  Future<void> reconcileSchedules({
    required List<TimetableEntry> classes,
    required List<Deadline> deadlines,
  }) async {
    final now = DateTime.now();
    final validClassIds = classes.map((c) => c.id).toSet();
    final validDeadlineIds =
        deadlines.where((d) => !d.isCompleted).map((d) => d.id).toSet();

    final expiredIds = <int>[];

    for (final record in _scheduledRecords.values) {
      // Remove passed schedules
      if (record.scheduledTime.isBefore(now)) {
        expiredIds.add(record.id);
        continue;
      }

      // Remove deleted class reminders
      if (record.type == 'class' && !validClassIds.contains(record.entityId)) {
        await _notificationsPlugin.cancel(record.id);
        expiredIds.add(record.id);
        continue;
      }

      // Remove completed/deleted deadline reminders
      if (record.type == 'task' &&
          !validDeadlineIds.contains(record.entityId)) {
        await _notificationsPlugin.cancel(record.id);
        expiredIds.add(record.id);
        continue;
      }
    }

    for (final id in expiredIds) {
      _scheduledRecords.remove(id);
    }

    await _savePersistedScheduledRecords();

    // Reschedule upcoming active classes and deadlines
    for (final entry in classes) {
      await scheduleClassReminders(entry);
    }
    for (final deadline in deadlines.where((d) => !d.isCompleted)) {
      await scheduleDeadlineReminders(deadline);
    }

    debugPrint(
        '[NOTIFICATIONS] Schedule reconciliation completed. Active schedules: ${_scheduledRecords.length}');
  }

  // ===========================================================================
  // 8. DEEP LINK ROUTING & ACTION DISPATCHER
  // ===========================================================================

  void _handleNotificationResponse(NotificationResponse response) {
    final rawPayload = response.payload;
    final actionId = response.actionId;
    debugPrint(
        '[NOTIFICATIONS] Response received: payload=$rawPayload, actionId=$actionId');

    final payload = NotificationPayload.tryParse(rawPayload);
    if (payload == null) return;

    // Check if an action button was tapped
    if (actionId != null && actionId.isNotEmpty) {
      _dispatchAction(actionId, payload);
    } else {
      _dispatchPayload(payload);
    }
  }

  void _dispatchAction(String actionId, NotificationPayload payload) {
    if (actionId.startsWith('record_class_')) {
      // Start recording for this timetable entry
      final entry = TimetableService.instance.entries.firstWhere(
        (e) => e.id == payload.entityId,
        orElse: () => TimetableEntry(
          id: payload.entityId,
          subject: payload.extra['subject'] as String? ?? 'Class',
          dayOfWeek: 'Mon',
          startTime: 'Now',
          endTime: 'Now',
        ),
      );
      LectureRecordingService.instance.startClassRecording(entry: entry);
      _navigateToScreen(VoiceNotesScreen(
        onNavigateToBrain: (tabIdx, {initialQuery}) {
          _navigateToScreen(PalBrainScreen(initialQuery: initialQuery));
        },
      ));
      return;
    }

    if (actionId == 'stop_lecture_active') {
      LectureRecordingService.instance.stopActiveRecording();
      return;
    }

    if (actionId.startsWith('listen_')) {
      _navigateToLecture(payload.entityId, startPlayback: true);
      return;
    }

    if (actionId.startsWith('transcribe_')) {
      LectureRecordingService.instance.transcribeLecture(
        payload.entityId,
        forceRetry: true,
      );
      _navigateToLecture(payload.entityId);
      return;
    }

    if (actionId.startsWith('ask_pal_')) {
      _navigateToAskPal(payload.entityId);
      return;
    }

    // Default to payload navigation
    _dispatchPayload(payload);
  }

  void _dispatchPayload(NotificationPayload payload) {
    switch (payload.type) {
      case NotificationType.classReminder:
        _navigateToScreen(const TimetableScreen());
        break;

      case NotificationType.recording:
        _navigateToScreen(VoiceNotesScreen(
          onNavigateToBrain: (tabIdx, {initialQuery}) {
            _navigateToScreen(PalBrainScreen(initialQuery: initialQuery));
          },
        ));
        break;

      case NotificationType.lecture:
        if (payload.action == NotificationAction.askPal) {
          _navigateToAskPal(payload.entityId);
        } else {
          _navigateToLecture(payload.entityId);
        }
        break;

      case NotificationType.task:
        _navigateToScreen(TasksScreen(
          onNavigateToTab: (tabIdx, {initialQuery}) {
            if (tabIdx == 2) {
              _navigateToScreen(PalBrainScreen(initialQuery: initialQuery));
            }
          },
        ));
        break;

      case NotificationType.holiday:
        _navigateToScreen(const AcademicCalendarScreen());
        break;

      case NotificationType.agent:
        _navigateToScreen(const PalBrainScreen());
        break;
    }
  }

  void _navigateToLecture(String recordingId, {bool startPlayback = false}) {
    final lecture = LectureRecordingService.instance.recordings.firstWhere(
      (r) => r.id == recordingId,
      orElse: () => LectureRecording(
        id: recordingId,
        subject: 'Lecture',
        date: DateTime.now(),
        scheduledStart: '00:00',
        scheduledEnd: '00:00',
        actualStart: DateTime.now(),
        audioPath: '',
        durationSeconds: 0,
      ),
    );

    if (lecture.audioPath.isEmpty) {
      _showErrorSnackBar('Lecture recording no longer exists.');
      return;
    }

    _navigateToScreen(LectureDetailsScreen(recording: lecture));
  }

  void _navigateToAskPal(String recordingId) {
    final lecture = LectureRecordingService.instance.recordings.firstWhere(
      (r) => r.id == recordingId,
      orElse: () => LectureRecording(
        id: recordingId,
        subject: 'Lecture',
        date: DateTime.now(),
        scheduledStart: '00:00',
        scheduledEnd: '00:00',
        actualStart: DateTime.now(),
        audioPath: '',
        durationSeconds: 0,
      ),
    );

    _navigateToScreen(PalBrainScreen(lectureRecording: lecture));
  }

  void _navigateToScreen(Widget screen) {
    final nav = _navigatorKey?.currentState;
    if (nav != null) {
      nav.push(MaterialPageRoute(builder: (_) => screen));
    } else {
      debugPrint('[NOTIFICATIONS] Navigator key not available for deep-link.');
    }
  }

  void _showErrorSnackBar(String message) {
    final context = _navigatorKey?.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.overduePillText,
        ),
      );
    }
  }

  // ===========================================================================
  // 9. PERSISTENCE HELPERS
  // ===========================================================================

  void _recordScheduledNotification(ScheduledNotificationRecord record) {
    _scheduledRecords[record.id] = record;
    _savePersistedScheduledRecords();
  }

  Future<void> _loadPersistedScheduledRecords() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/scheduled_notifications.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> list = jsonDecode(content);
          _scheduledRecords.clear();
          for (final item in list) {
            final record = ScheduledNotificationRecord.fromJson(
                item as Map<String, dynamic>);
            _scheduledRecords[record.id] = record;
          }
        }
      }
    } catch (e) {
      debugPrint(
          '[NOTIFICATIONS] Could not load scheduled_notifications.json: $e');
    }
  }

  Future<void> _savePersistedScheduledRecords() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/scheduled_notifications.json');
      final list = _scheduledRecords.values.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint(
          '[NOTIFICATIONS] Could not save scheduled_notifications.json: $e');
    }
  }

  // ===========================================================================
  // 10. ID & DATE UTILITIES
  // ===========================================================================

  /// Deterministic 31-bit integer notification ID generation from string ID and sub-index
  static int generateNotificationId(String entityId, {int subId = 0}) {
    final hash = entityId.hashCode & 0x07FFFFFF;
    return (hash * 10) + (subId % 10);
  }

  static int _generateNotificationId(String entityId, {int subId = 0}) =>
      generateNotificationId(entityId, subId: subId);

  /// Converts a DateTime into a TZDateTime safely even if tz is uninitialized
  static tz.TZDateTime _toTzDateTime(DateTime time) {
    try {
      return tz.TZDateTime.from(time, tz.local);
    } catch (_) {
      try {
        tz.initializeTimeZones();
        tz.setLocalLocation(tz.UTC);
        return tz.TZDateTime.from(time, tz.local);
      } catch (_) {
        return tz.TZDateTime.utc(
          time.year,
          time.month,
          time.day,
          time.hour,
          time.minute,
          time.second,
          time.millisecond,
        );
      }
    }
  }

  /// Parses timetable string (e.g. "09:00 AM", "2:30 PM", "14:00") into today's DateTime
  static DateTime? _parseTimeToDateTime(String timeStr, DateTime date) {
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPm = clean.contains('PM');
      final isAm = clean.contains('AM');

      final digits = clean.replaceAll(RegExp(r'[^0-9:]'), '').split(':');
      if (digits.isEmpty) return null;

      int hour = int.parse(digits[0]);
      int minute = digits.length > 1 ? int.parse(digits[1]) : 0;

      if (isPm && hour < 12) hour += 12;
      if (isAm && hour == 12) hour = 0;

      return DateTime(date.year, date.month, date.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  static String _formatSecondsToTimer(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // Backward-compatibility bridge methods for existing code
  Future<void> showPreClassAlert({
    required String subject,
    required String startTime,
    required int minutesLeft,
  }) async {
    final entry = TimetableEntry(
      id: 'preclass_${subject.toLowerCase().replaceAll(' ', '_')}',
      subject: subject,
      dayOfWeek: 'Mon',
      startTime: startTime,
      endTime: '',
    );
    await _scheduleSingleClassReminder(
      entry: entry,
      scheduledTime: DateTime.now(),
      minutesLeft: minutesLeft,
      subId: 1,
    );
  }

  Future<void> showRecordingFinishedNotification({
    required String subject,
    required String durationText,
  }) async {
    final recording = LectureRecording(
      id: 'lecture_saved_${subject.toLowerCase().replaceAll(' ', '_')}',
      subject: subject,
      date: DateTime.now(),
      scheduledStart: 'Now',
      scheduledEnd: 'Now',
      actualStart: DateTime.now(),
      audioPath: '',
      durationSeconds: 60,
    );
    await showLectureReadyNotification(recording: recording);
  }
}

/// Backward-compatibility alias
typedef NotificationService = PalNotificationService;
