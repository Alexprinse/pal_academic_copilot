import 'package:flutter/material.dart';
import '../models/campus_vault.dart';
import '../models/lecture_recording.dart';
import '../services/campus_vault_service.dart';
import '../services/deadline_service.dart';
import '../services/lecture_recording_service.dart';
import '../services/pal_notification_service.dart';
import '../services/timetable_service.dart';
import '../theme/app_theme.dart';

/// Developer Notification Test Panel to test all 14 notification scenarios on-device.
class NotificationTestScreen extends StatefulWidget {
  const NotificationTestScreen({super.key});

  @override
  State<NotificationTestScreen> createState() => _NotificationTestScreenState();
}

class _NotificationTestScreenState extends State<NotificationTestScreen> {
  String _lastStatus = 'Ready to test notifications.';
  int _recordingSeconds = 0;

  void _setStatus(String msg) {
    setState(() => _lastStatus = msg);
    debugPrint('[NOTIFICATION TEST] $msg');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notification Test Panel',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'Developer Verification · Android 16 & iQOO 12',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 20, color: AppTheme.primaryAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Test Engine Status',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _lastStatus,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 1. Permission
          _buildSectionHeader('1. Android Permission & Basic Alert'),
          _buildTestTile(
            title: 'Request Notification Permission',
            subtitle: 'Triggers Android 13+ POST_NOTIFICATIONS dialog',
            icon: Icons.security,
            onTap: () async {
              final granted = await PalNotificationService.instance
                  .requestNotificationPermission();
              _setStatus(
                  'Permission request result: ${granted ? "GRANTED" : "DENIED"}');
            },
          ),
          _buildTestTile(
            title: 'Show Basic Pal Agent Notification',
            subtitle: 'Direct confirmation via Pal · Agent channel',
            icon: Icons.psychology,
            onTap: () async {
              await PalNotificationService.instance.showAgentActionNotification(
                title: '✨ Pal Copilot',
                message: 'All on-device academic systems active and ready.',
              );
              _setStatus('Sent basic Pal Agent notification.');
            },
          ),

          const SizedBox(height: 16),

          // 2. Class Reminders
          _buildSectionHeader('2. Class Reminders (Timetable)'),
          _buildTestTile(
            title: 'Schedule Class Reminder (Real Timetable)',
            subtitle:
                'Uses first class from timetable with [View Class] & [Record] actions',
            icon: Icons.calendar_today,
            onTap: () async {
              final classes = TimetableService.instance.entries;
              if (classes.isEmpty) {
                _setStatus('No classes found in TimetableService.');
                return;
              }
              final target = classes.first;
              await PalNotificationService.instance.showPreClassAlert(
                subject: target.subject,
                startTime: target.startTime,
                minutesLeft: 10,
              );
              _setStatus('Triggered pre-class alert for "${target.subject}".');
            },
          ),
          _buildTestTile(
            title: 'Cancel Class Reminders',
            subtitle: 'Cancels scheduled notifications for the class ID',
            icon: Icons.event_busy,
            onTap: () async {
              final classes = TimetableService.instance.entries;
              if (classes.isNotEmpty) {
                await PalNotificationService.instance
                    .cancelEntityNotifications(classes.first.id);
                _setStatus(
                    'Cancelled notifications for "${classes.first.subject}".');
              }
            },
          ),

          const SizedBox(height: 16),

          // 3. Lecture Recording
          _buildSectionHeader('3. Lecture Audio Recording'),
          _buildTestTile(
            title: 'Show Recording Started Notification',
            subtitle:
                'Ongoing notification with [Open Lecture] and [Stop] actions',
            icon: Icons.mic,
            onTap: () async {
              _recordingSeconds = 0;
              await PalNotificationService.instance.showRecordingNotification(
                subject: 'Operating Systems',
                elapsedSeconds: _recordingSeconds,
                recordingId: 'test_rec_active',
              );
              _setStatus('Displayed ongoing recording notification.');
            },
          ),
          _buildTestTile(
            title: 'Update Recording Progress (+30s)',
            subtitle: 'Updates timer to prove ongoing notification stability',
            icon: Icons.update,
            onTap: () async {
              _recordingSeconds += 30;
              await PalNotificationService.instance.showRecordingNotification(
                subject: 'Operating Systems',
                elapsedSeconds: _recordingSeconds,
                recordingId: 'test_rec_active',
              );
              _setStatus(
                  'Updated ongoing recording notification to ${_recordingSeconds}s.');
            },
          ),
          _buildTestTile(
            title: 'Stop Recording & Cancel Notification',
            subtitle: 'Removes ongoing recording notification from tray',
            icon: Icons.stop_circle,
            onTap: () async {
              await PalNotificationService.instance
                  .cancelRecordingNotification();
              _setStatus('Cancelled ongoing recording notification.');
            },
          ),
          _buildTestTile(
            title: 'Show Lecture Ready Notification',
            subtitle:
                'With [Listen] and [Transcribe] / [Ask Pal] action deep-links',
            icon: Icons.check_circle_outline,
            onTap: () async {
              final recordings = LectureRecordingService.instance.recordings;
              final rec = recordings.isNotEmpty
                  ? recordings.first
                  : LectureRecording(
                      id: 'test_lecture_ready',
                      subject: 'Operating Systems',
                      date: DateTime.now(),
                      scheduledStart: '10:00 AM',
                      scheduledEnd: '11:00 AM',
                      actualStart:
                          DateTime.now().subtract(const Duration(minutes: 50)),
                      audioPath: '',
                      durationSeconds: 3000,
                    );
              await PalNotificationService.instance
                  .showLectureReadyNotification(
                recording: rec,
              );
              _setStatus(
                  'Shown Lecture Ready notification for "${rec.displayTitle}".');
            },
          ),

          const SizedBox(height: 16),

          // 4. Deadlines & Tasks
          _buildSectionHeader('4. Deadlines & Tasks'),
          _buildTestTile(
            title: 'Schedule Deadline Notification',
            subtitle:
                'Uses real deadline from DeadlineService with [View Task] action',
            icon: Icons.alarm,
            onTap: () async {
              final deadlines = DeadlineService.instance.deadlines;
              if (deadlines.isEmpty) {
                _setStatus('No deadlines found in DeadlineService.');
                return;
              }
              final target = deadlines.first;
              await PalNotificationService.instance
                  .scheduleDeadlineReminders(target);
              _setStatus(
                  'Scheduled reminders for deadline: "${target.title}".');
            },
          ),

          const SizedBox(height: 16),

          // 5. Holiday & Academic Calendar
          _buildSectionHeader('5. Holiday & Campus Calendar'),
          _buildTestTile(
            title: 'Show Campus Holiday Notification',
            subtitle:
                'Real holiday from CampusVaultService with [View Calendar] action',
            icon: Icons.beach_access,
            onTap: () async {
              final holidays = CampusVaultService.instance.holidays;
              final target = holidays.isNotEmpty
                  ? holidays.first
                  : CampusHoliday(
                      id: 'hol_test',
                      name: 'Ganesh Chaturthi',
                      date: DateTime.now().add(const Duration(days: 1)),
                      type: CampusHolidayType.gazetted,
                      description: 'Institute closed',
                    );
              await PalNotificationService.instance.showHolidayAlert(target);
              _setStatus('Triggered holiday alert for "${target.name}".');
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.primaryAccent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTestTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.cardDecoration,
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primaryAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppTheme.primaryAccent),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        trailing: const Icon(Icons.play_arrow,
            size: 16, color: AppTheme.primaryAccent),
        onTap: onTap,
      ),
    );
  }
}
