import 'package:flutter/material.dart';
import '../models/campus_vault.dart';
import '../models/deadline.dart';
import '../models/lecture_recording.dart';
import '../models/timetable_entry.dart';
import '../services/campus_vault_service.dart';
import '../services/deadline_service.dart';
import '../services/lecture_recording_service.dart';
import '../services/profile_service.dart';
import '../services/timetable_service.dart';
import '../agent/agent_voice_controller.dart';
import '../agent/ui/agent_action_preview_sheet.dart';
import '../agent/ui/agent_voice_overlay.dart';
import '../agent/ui/pal_agent_compact_modal.dart';
import '../agent/ui/pal_floating_button.dart';
import '../theme/app_theme.dart';
import 'lectures_history_screen.dart';
import 'timetable_screen.dart';

class ClassScheduleItem {
  final String code;
  final String name;
  final String time;
  final String room;
  final String status; // 'Ready to record', 'Recorded 48m', 'Upcoming'
  final bool isReadyToRecord;

  const ClassScheduleItem({
    required this.code,
    required this.name,
    required this.time,
    required this.room,
    required this.status,
    this.isReadyToRecord = false,
  });
}

class DashboardScreen extends StatefulWidget {
  final Function(int) onNavigateTab;

  const DashboardScreen({super.key, required this.onNavigateTab});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DeadlineService _deadlineService = DeadlineService.instance;
  final ProfileService _profileService = ProfileService.instance;
  final TimetableService _timetableService = TimetableService.instance;
  final LectureRecordingService _recordingService =
      LectureRecordingService.instance;
  final CampusVaultService _campusVaultService = CampusVaultService.instance;

  @override
  void initState() {
    super.initState();
    _deadlineService.addListener(_onUpdate);
    _profileService.addListener(_onUpdate);
    _timetableService.addListener(_onUpdate);
    _recordingService.addListener(_onUpdate);
    _campusVaultService.addListener(_onUpdate);
    AgentVoiceController.instance.addListener(_onVoiceUpdate);
    AgentVoiceController.instance.initializeNativeRecognizer();
  }

  @override
  void dispose() {
    _deadlineService.removeListener(_onUpdate);
    _profileService.removeListener(_onUpdate);
    _timetableService.removeListener(_onUpdate);
    _recordingService.removeListener(_onUpdate);
    _campusVaultService.removeListener(_onUpdate);
    AgentVoiceController.instance.removeListener(_onVoiceUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _onVoiceUpdate() {
    if (mounted && (_isVoiceListening || _isVoiceTranscribing)) {
      setState(() {});
    }
  }

  bool _isVoiceListening = false;
  bool _isVoiceTranscribing = false;

  void _startVoiceListening() async {
    setState(() {
      _isVoiceListening = true;
      _isVoiceTranscribing = false;
    });
    await AgentVoiceController.instance.startListening();
  }

  void _stopVoiceListening() async {
    if (!_isVoiceListening) return;

    setState(() {
      _isVoiceListening = false;
      _isVoiceTranscribing = true;
    });

    final transcript =
        await AgentVoiceController.instance.stopListeningAndTranscribe();

    if (!mounted) return;

    setState(() {
      _isVoiceTranscribing = false;
    });

    if (transcript.isNotEmpty) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AgentActionPreviewSheet(
          transcript: transcript,
          toolCalls: AgentVoiceController.instance.pendingToolCalls,
          onCancel: () => AgentVoiceController.instance.cancelSession(),
          onExecuted: (_) {
            setState(() {});
          },
        ),
      );
    } else {
      final err = AgentVoiceController.instance.errorMessage ??
          "Sorry, I didn't catch that.";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: const Color(0xFF1E1D19),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _cancelVoiceListening() {
    AgentVoiceController.instance.cancelSession();
    if (mounted) {
      setState(() {
        _isVoiceListening = false;
        _isVoiceTranscribing = false;
      });
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final deadlines = _deadlineService.deadlines;
    final taskStats = _deadlineService.getDashboardStats();

    debugPrint('[HOME-TASKS] Total tasks: ${taskStats.total}');
    debugPrint('[HOME-TASKS] Pending tasks: ${taskStats.pending}');
    debugPrint('[HOME-TASKS] Due today: ${taskStats.dueToday}');
    debugPrint('[HOME-TASKS] Overdue: ${taskStats.overdue}');
    debugPrint('[HOME-TASKS] Completed: ${taskStats.completed}');
    debugPrint('[HOME-TASKS] Dashboard dueToday: ${taskStats.dueToday}');
    debugPrint('[HOME-TASKS] Dashboard pending: ${taskStats.pending}');

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // 1. Header (Greeting + Date + Avatar)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_getGreeting()}, ${_profileService.profile.name.split(' ').first}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Saturday, September 12',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Timetable Quick Access Button
                            Tooltip(
                              message: 'Weekly Timetable',
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const TimetableScreen(),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppTheme.cardSurface,
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: AppTheme.cardBorder),
                                    boxShadow: AppTheme.cardShadow,
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.calendar_month_outlined,
                                    color: AppTheme.primaryAccent,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Academic Monogram Avatar Circle (Clickable -> Student Profile Screen)
                            Tooltip(
                              message: 'Student Profile',
                              child: InkWell(
                                onTap: () =>
                                    widget.onNavigateTab(97), // Open Profile
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppTheme.cardSurface,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: AppTheme.primaryAccent
                                            .withValues(alpha: 0.7),
                                        width: 1.5),
                                    boxShadow: AppTheme.cardShadow,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _profileService.profile.initials,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryAccent,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Offline Trust Chip
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.trustPillFill,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                AppTheme.trustPillText.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text('✈️', style: TextStyle(fontSize: 12)),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Airplane Mode Ready · Zero Cloud Sync',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.trustPillText,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 2.5 "Today with Pal" Snapshot Card (Compact & Informational)
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    child: _buildTodayWithPalSnapshot(),
                  ),
                ),

                // 3. Today's Focus Row (3 Compact Stat Cards)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        // Card 1: Tasks Due Today (Amber Pill style)
                        Expanded(
                          child: _buildFocusCard(
                            title: 'Due Today',
                            count: '${taskStats.dueToday}',
                            pillLabel: '${taskStats.pending} pending',
                            pillBg: AppTheme.detectedPillFill,
                            pillTextColor: AppTheme.detectedPillText,
                            onTap: () =>
                                widget.onNavigateTab(96), // Navigate to Tasks
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Card 2: Lecture to Review (Brass Accent style)
                        Expanded(
                          child: _buildFocusCard(
                            title: 'To Review',
                            count: '1',
                            pillLabel: 'OS Lec 4',
                            pillBg: AppTheme.neutralPillFill,
                            pillTextColor: AppTheme.primaryAccent,
                            onTap: () =>
                                widget.onNavigateTab(2), // Navigate to Ask
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Card 3: Study Streak (Dark #1E1D19 Contrast Card with Flame)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: AppTheme.darkSurface,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: AppTheme.cardShadow,
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Streak',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFC7C3B7),
                                      ),
                                    ),
                                    Text('🔥', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                                SizedBox(height: 6),
                                Text(
                                  '5 Days',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Top 5% student',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF9E9A8E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3.5 Live Recording Banner (if active)
                if (_recordingService.isRecordingNow)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: _buildActiveLiveRecordingCard(
                          _recordingService.activeRecording!),
                    ),
                  ),

                // 4. Section: Today's Classes (Dynamic from Timetable)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Today\'s Classes (${_timetableService.getTodayDayOfWeek()})',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TimetableScreen(),
                              ),
                            );
                          },
                          child: Text(
                            '${_timetableService.getTodayClasses().length} Scheduled →',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_timetableService.getTodayClasses().isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: AppTheme.cardDecoration,
                        child: Row(
                          children: [
                            const Icon(Icons.event_busy_outlined,
                                color: AppTheme.textSecondary, size: 24),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'No classes scheduled for today.',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const TimetableScreen()),
                                );
                              },
                              child: const Text('Add Class',
                                  style:
                                      TextStyle(color: AppTheme.primaryAccent)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = _timetableService.getTodayClasses()[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 5),
                          child: _buildTimetableClassCard(item),
                        );
                      },
                      childCount: _timetableService.getTodayClasses().length,
                    ),
                  ),

                // 4.5 Recently Recorded Lecture Card
                if (_recordingService.latestRecording != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: _buildRecentLectureCard(
                          _recordingService.latestRecording!),
                    ),
                  ),

                // 5. Section: Revision Card (Dark #1E1D19 Contrast Card)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: _buildWeakTopicRevisionCard(),
                  ),
                ),

                // 6. Section: Upcoming Tasks
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Upcoming Tasks',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        InkWell(
                          onTap: () => widget.onNavigateTab(96), // Tasks screen
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Text(
                              'View all →',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryAccent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Tasks List using the Refined Pill System
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final task = deadlines[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 5),
                        child: _buildTaskCard(task, index),
                      );
                    },
                    childCount: deadlines.length > 4 ? 4 : deadlines.length,
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ),
          ),
          // Persistent Floating Pal Button on Home
          Positioned(
            bottom: 24,
            right: 20,
            child: PalFloatingButton(
              onTap: () => PalAgentCompactModal.show(context,
                  onVoiceRecordRequested: _startVoiceListening),
              onLongPressStart: _startVoiceListening,
              onLongPressEnd: _stopVoiceListening,
              onLongPressCancel: _cancelVoiceListening,
            ),
          ),
          if (_isVoiceListening || _isVoiceTranscribing)
            Positioned.fill(
              child: AgentVoiceOverlay(
                isListening: _isVoiceListening,
                isTranscribing: _isVoiceTranscribing,
                liveTranscript: AgentVoiceController.instance.currentTranscript,
                onCancel: _cancelVoiceListening,
              ),
            ),
        ],
      ),
    );
  }

  // --- SUB-WIDGETS ---

  Widget _buildFocusCard({
    required String title,
    required String count,
    required String pillLabel,
    required Color pillBg,
    required Color pillTextColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              count,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                pillLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: pillTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveLiveRecordingCard(LectureRecording active) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.6), width: 1.5),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.fiber_manual_record,
                color: Colors.redAccent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'RECORDING NOW',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  active.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${active.scheduledStart} - ${active.scheduledEnd} • Auto-recording lecture',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LecturesHistoryScreen()),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('View',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetableClassCard(TimetableEntry item) {
    final now = DateTime.now();
    final currentHourDouble = now.hour + (now.minute / 60.0);
    final isHappeningNow = currentHourDouble >= item.startHourDouble &&
        currentHourDouble <= item.endHourDouble;
    final isPast = currentHourDouble > item.endHourDouble;
    final startDiffMinutes =
        ((item.startHourDouble - currentHourDouble) * 60).round();

    String statusText;
    Color statusBg;
    Color statusFg;

    if (isHappeningNow) {
      statusText =
          _recordingService.isRecordingNow ? '🔴 Recording' : 'Happening now';
      statusBg = AppTheme.detectedPillFill;
      statusFg = AppTheme.primaryAccent;
    } else if (isPast) {
      statusText = 'Completed';
      statusBg = AppTheme.neutralPillFill;
      statusFg = AppTheme.textSecondary;
    } else if (startDiffMinutes <= 60 && startDiffMinutes > 0) {
      statusText = 'In $startDiffMinutes min';
      statusBg = AppTheme.trustPillFill;
      statusFg = AppTheme.trustPillText;
    } else {
      statusText = 'Upcoming';
      statusBg = AppTheme.neutralPillFill;
      statusFg = AppTheme.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Class icon / action button
          InkWell(
            onTap: () {
              if (isHappeningNow && !_recordingService.isRecordingNow) {
                _recordingService.startClassRecording(entry: item);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TimetableScreen()),
                );
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isHappeningNow
                    ? AppTheme.detectedPillFill
                    : AppTheme.neutralPillFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isHappeningNow
                      ? AppTheme.primaryAccent.withValues(alpha: 0.3)
                      : AppTheme.cardBorder,
                  width: 1,
                ),
              ),
              child: Icon(
                isHappeningNow ? Icons.mic : Icons.school_outlined,
                color: isHappeningNow
                    ? AppTheme.primaryAccent
                    : AppTheme.textSecondary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Class details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.type.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryAccent,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusFg,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${item.startTime} – ${item.endTime}${item.room != null ? ' • ${item.room}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentLectureCard(LectureRecording lecture) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.history_edu,
                      size: 18, color: AppTheme.primaryAccent),
                  const SizedBox(width: 8),
                  const Text(
                    'RECENTLY RECORDED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppTheme.primaryAccent,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LecturesHistoryScreen()),
                  );
                },
                child: const Text(
                  'My Lectures →',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            lecture.subject,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${lecture.formattedDuration} • Status: ${lecture.transcriptionStatus}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          if (lecture.summary != null &&
              lecture.summary!.keyPoints.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Key takeaway: "${lecture.summary!.keyPoints.first}"',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeakTopicRevisionCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'DAILY REVISION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Color(0xFFE8BD65),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Operating Systems',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFB0ACA0),
                    ),
                  ),
                ],
              ),
              const Icon(Icons.arrow_forward, size: 16, color: Colors.white70),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '"Peterson\'s solution guarantees mutual exclusion, progress, and bounded waiting for 2 processes."',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              fontStyle: FontStyle.italic,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Topic Mastery: 42%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFC7C3B7),
                ),
              ),
              InkWell(
                onTap: () =>
                    widget.onNavigateTab(99), // Launch Practice Quiz Screen
                child: const Text(
                  'Practice 3 Quiz Qs →',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE8BD65),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Mini Progress Bar in Primary Accent
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 0.42,
              minHeight: 5,
              color: AppTheme.primaryAccent,
              backgroundColor: Color(0xFF38352D),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Deadline task, int index) {
    // Semantic pill selection
    Color pillBg = AppTheme.neutralPillFill;
    Color pillTextColor = AppTheme.neutralPillText;
    String pillLabel = 'Manual';

    if (task.timeLeft.isNegative && !task.isCompleted) {
      pillBg = AppTheme.overduePillFill;
      pillTextColor = AppTheme.overduePillText;
      pillLabel = 'Overdue';
    } else if (index % 2 == 0) {
    } else if (task.isSpokenDetected) {
      pillBg = AppTheme.detectedPillFill;
      pillTextColor = AppTheme.detectedPillText;
      pillLabel = '🎙️ Spoken';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Custom check circle
          InkWell(
            onTap: () => _deadlineService.toggleComplete(task.id),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: task.isCompleted
                    ? AppTheme.primaryAccent
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: task.isCompleted
                      ? AppTheme.primaryAccent
                      : AppTheme.cardBorder,
                  width: 1.5,
                ),
              ),
              child: task.isCompleted
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          // Task Title & Course
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    color: task.isCompleted
                        ? AppTheme.textSecondary
                        : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${task.course} • ${task.countdownString}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Pill Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              pillLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: pillTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayWithPalSnapshot() {
    final stats = _deadlineService.getDashboardStats();
    final todayClasses = _timetableService.getTodayClasses();
    final classCount = todayClasses.length;
    final nextClass = _timetableService.getNextClass();
    final dueTodayCount = stats.dueToday;
    final isRecording = _recordingService.isRecordingNow;
    final nextHoliday = _getNextUpcomingHoliday();

    final hasData = classCount > 0 ||
        dueTodayCount > 0 ||
        isRecording ||
        nextHoliday != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.cardBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row
          Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Today with Pal',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TimetableScreen(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Today',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: AppTheme.primaryAccent,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (!hasData) ...[
            // Empty State
            const Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 15,
                  color: AppTheme.trustPillText,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "You're all caught up · Nothing urgent today.",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Dynamic Data Rows
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (classCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: AppTheme.primaryAccent,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '$classCount ${classCount == 1 ? 'class' : 'classes'} today'
                            '${nextClass != null ? ' · Next: ${nextClass.subject} (${nextClass.startTime})' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_available_outlined,
                          size: 13,
                          color: AppTheme.textSecondary,
                        ),
                        SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'No classes scheduled today',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Secondary indicators row
                Wrap(
                  runSpacing: 6,
                  spacing: 16,
                  children: [
                    if (dueTodayCount > 0)
                      _buildSnapshotBullet(
                        icon: Icons.assignment_outlined,
                        iconColor: AppTheme.detectedPillText,
                        text:
                            '$dueTodayCount ${dueTodayCount == 1 ? 'task' : 'tasks'} due',
                      ),
                    if (isRecording)
                      _buildSnapshotBullet(
                        icon: Icons.fiber_manual_record,
                        iconColor: Colors.redAccent,
                        text: 'Recording in progress',
                      )
                    else if (_recordingService.isAutoRecordEnabled &&
                        classCount > 0)
                      _buildSnapshotBullet(
                        icon: Icons.mic_none_outlined,
                        iconColor: AppTheme.trustPillText,
                        text: 'Auto-record active',
                      )
                    else if (nextHoliday != null)
                      _buildSnapshotBullet(
                        icon: Icons.celebration_outlined,
                        iconColor: Colors.amberAccent,
                        text: 'Next holiday: ${nextHoliday.name}',
                      ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  CampusHoliday? _getNextUpcomingHoliday() {
    final now = DateTime.now();
    final upcoming = _campusVaultService.holidays.where((h) {
      return h.date.isAfter(now.subtract(const Duration(days: 1))) &&
          h.date.isBefore(now.add(const Duration(days: 14)));
    }).toList();
    if (upcoming.isEmpty) return null;
    upcoming.sort((a, b) => a.date.compareTo(b.date));
    return upcoming.first;
  }

  Widget _buildSnapshotBullet({
    required IconData icon,
    required Color iconColor,
    required String text,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: iconColor),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
