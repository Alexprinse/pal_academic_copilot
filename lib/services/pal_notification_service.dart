import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PalNotificationService {
  static final PalNotificationService instance = PalNotificationService._();
  PalNotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    try {
      const androidInitSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
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
        onDidReceiveNotificationResponse: (NotificationResponse details) {
          debugPrint('Notification clicked: ${details.payload}');
        },
      );

      // Request Android 13+ runtime permissions
      final androidPlatform = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlatform != null) {
        await androidPlatform.requestNotificationsPermission();
      }

      _initialized = true;
      debugPrint('PalNotificationService initialized successfully.');
    } catch (e) {
      debugPrint('PalNotificationService initialization error: $e');
      _initialized = false;
    }
  }

  /// 10 minutes prior reminder alert
  Future<void> showPreClassAlert({
    required String subject,
    required String startTime,
    required int minutesLeft,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'pal_preclass_channel',
        'Class Alerts',
        channelDescription: 'Notifications for upcoming classes and auto-recording',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _notificationsPlugin.show(
        1001,
        'Upcoming Class: $subject',
        'Starts in $minutesLeft minutes ($startTime). Auto-record is ready.',
        notificationDetails,
        payload: 'preclass_$subject',
      );
    } catch (e) {
      debugPrint('Error showing pre-class alert: $e');
    }
  }

  /// Ongoing persistent recording notification
  Future<void> showRecordingNotification({
    required String subject,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'pal_recording_channel',
        'Active Recording',
        channelDescription: 'Active lecture audio recording status',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        icon: '@mipmap/ic_launcher',
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: false,
        ),
      );

      await _notificationsPlugin.show(
        1002,
        '🔴 Recording $subject Lecture',
        'Audio is being saved securely on your device.',
        notificationDetails,
        payload: 'recording_$subject',
      );
    } catch (e) {
      debugPrint('Error showing recording notification: $e');
    }
  }

  /// Cancels the ongoing recording notification
  Future<void> cancelRecordingNotification() async {
    try {
      await _notificationsPlugin.cancel(1002);
    } catch (e) {
      debugPrint('Error cancelling recording notification: $e');
    }
  }

  /// Completion notification after class recording finishes
  Future<void> showRecordingFinishedNotification({
    required String subject,
    required String durationText,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'pal_finish_channel',
        'Lecture Processing',
        channelDescription: 'Finished recording notifications and transcripts',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _notificationsPlugin.show(
        1003,
        'Lecture Saved: $subject',
        'Duration: $durationText. On-device transcription underway.',
        notificationDetails,
        payload: 'lecture_saved_$subject',
      );
    } catch (e) {
      debugPrint('Error showing recording finished notification: $e');
    }
  }
}
