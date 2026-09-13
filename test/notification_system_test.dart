import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/deadline.dart';
import 'package:pal_academic_copilot/models/notification_payload.dart';
import 'package:pal_academic_copilot/models/scheduled_notification_record.dart';
import 'package:pal_academic_copilot/models/timetable_entry.dart';
import 'package:pal_academic_copilot/services/deadline_service.dart';
import 'package:pal_academic_copilot/services/pal_notification_service.dart';
import 'package:pal_academic_copilot/services/timetable_service.dart';

import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.UTC);

  group('NotificationPayload Tests', () {
    test('Serializes and deserializes JSON payload accurately', () {
      final original = NotificationPayload(
        type: NotificationType.classReminder,
        entityId: 'tt_101',
        action: NotificationAction.record,
        extra: {'subject': 'Cloud Computing', 'room': 'LH-302'},
      );

      final jsonStr = original.toJsonString();
      final parsed = NotificationPayload.tryParse(jsonStr);

      expect(parsed, isNotNull);
      expect(parsed!.type, NotificationType.classReminder);
      expect(parsed.entityId, 'tt_101');
      expect(parsed.action, NotificationAction.record);
      expect(parsed.extra['subject'], 'Cloud Computing');
      expect(parsed.extra['room'], 'LH-302');
    });

    test('Parses colon-delimited payload gracefully', () {
      const delimitedStr = 'lecture:rec_abc_123:askPal';
      final parsed = NotificationPayload.tryParse(delimitedStr);

      expect(parsed, isNotNull);
      expect(parsed!.type, NotificationType.lecture);
      expect(parsed.entityId, 'rec_abc_123');
      expect(parsed.action, NotificationAction.askPal);
    });

    test('Handles malformed or legacy strings with safe fallbacks', () {
      final parsedEmpty = NotificationPayload.tryParse('');
      expect(parsedEmpty, isNull);

      final parsedLegacyClass =
          NotificationPayload.tryParse('preclass_Algorithms');
      expect(parsedLegacyClass, isNotNull);
      expect(parsedLegacyClass!.type, NotificationType.classReminder);
      expect(parsedLegacyClass.entityId, 'Algorithms');

      final parsedUnknown =
          NotificationPayload.tryParse('invalid_random_string');
      expect(parsedUnknown, isNotNull);
      expect(parsedUnknown!.type, NotificationType.agent);
      expect(parsedUnknown.entityId, 'invalid_random_string');
    });

    test('Maps NotificationAction enum to string and back', () {
      expect(
          NotificationAction.fromString('record'), NotificationAction.record);
      expect(
          NotificationAction.fromString('listen'), NotificationAction.listen);
      expect(
          NotificationAction.fromString('askPal'), NotificationAction.askPal);
      expect(NotificationAction.fromString('transcribe'),
          NotificationAction.transcribe);
      expect(NotificationAction.fromString('stop'), NotificationAction.stop);
      expect(NotificationAction.fromString('view'), NotificationAction.view);
      expect(NotificationAction.fromString('unknown_verb'),
          NotificationAction.view);
    });
  });

  group('ScheduledNotificationRecord Tests', () {
    test('Serializes to JSON and parses back', () {
      final now = DateTime.now();
      final record = ScheduledNotificationRecord(
        id: 12345,
        type: 'deadline',
        entityId: 'dl_99',
        scheduledTime: now,
        title: 'Submit Assignment',
        body: 'Due in 2 hours',
        payload: '{"type":"task","entityId":"dl_99"}',
      );

      final map = record.toJson();
      final restored = ScheduledNotificationRecord.fromJson(map);

      expect(restored.id, 12345);
      expect(restored.type, 'deadline');
      expect(restored.entityId, 'dl_99');
      expect(restored.title, 'Submit Assignment');
      expect(restored.body, 'Due in 2 hours');
      expect(restored.payload, '{"type":"task","entityId":"dl_99"}');
    });
  });

  group('PalNotificationService ID Generation & Channels', () {
    test('Generates deterministic integer IDs within 31-bit limit', () {
      final id1 = PalNotificationService.generateNotificationId('class_tt_1');
      final id2 = PalNotificationService.generateNotificationId('class_tt_1');
      final id3 = PalNotificationService.generateNotificationId('class_tt_2');

      expect(id1, equals(id2),
          reason: 'Identical keys must yield identical IDs');
      expect(id1, isNot(equals(id3)),
          reason: 'Different keys must yield different IDs');
      expect(id1, greaterThanOrEqualTo(0));
      expect(id1, lessThan(0x7FFFFFFF));
    });

    test('Exposes canonical channel IDs matching Pal architecture', () {
      expect(PalNotificationService.classChannelId, 'pal_classes_channel');
      expect(
          PalNotificationService.recordingChannelId, 'pal_recording_channel');
      expect(PalNotificationService.deadlineChannelId, 'pal_deadlines_channel');
      expect(PalNotificationService.academicChannelId, 'pal_academic_channel');
      expect(PalNotificationService.agentChannelId, 'pal_agent_channel');
    });
  });

  group('Timetable & Deadline Service Integration', () {
    test(
        'Adding and removing timetable entry invokes notification hooks without throwing',
        () async {
      final ttService = TimetableService.instance;
      final entry = TimetableEntry(
        id: 'tt_notif_test',
        subject: 'Algorithms & Data Structures',
        dayOfWeek: 'Monday',
        startTime: '09:00',
        endTime: '10:00',
        room: 'Lab 4',
      );

      // Add entry (triggers notification scheduling)
      await ttService.addEntry(entry);
      expect(ttService.entries.any((e) => e.id == 'tt_notif_test'), isTrue);

      // Update entry
      final updated = entry.copyWith(room: 'Lab 5');
      await ttService.updateEntry(updated);

      // Remove entry (triggers notification cancellation)
      await ttService.deleteEntry('tt_notif_test');
      expect(ttService.entries.any((e) => e.id == 'tt_notif_test'), isFalse);
    });

    test(
        'Adding, toggling, and deleting deadline invokes notification hooks without throwing',
        () async {
      final dlService = DeadlineService.instance;
      final deadline = Deadline(
        id: 'dl_notif_test',
        title: 'Project Milestone 2',
        course: 'Software Engineering',
        dueDate: DateTime.now().add(const Duration(days: 2)),
      );

      // Add deadline
      dlService.addDeadline(deadline);
      expect(dlService.deadlines.any((d) => d.id == 'dl_notif_test'), isTrue);

      // Toggle complete (cancels upcoming notifications)
      dlService.toggleComplete('dl_notif_test');
      final completed =
          dlService.deadlines.firstWhere((d) => d.id == 'dl_notif_test');
      expect(completed.isCompleted, isTrue);

      // Delete deadline
      dlService.deleteDeadline('dl_notif_test');
      expect(dlService.deadlines.any((d) => d.id == 'dl_notif_test'), isFalse);
    });
  });
}
