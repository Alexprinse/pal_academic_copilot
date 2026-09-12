import 'package:flutter/material.dart';
import '../models/timetable_entry.dart';
import '../services/lecture_recording_service.dart';
import '../services/recording_scheduler.dart';
import '../services/timetable_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auto_record_consent_sheet.dart';
import '../widgets/quick_add_class_sheet.dart';
import 'add_class_wizard_screen.dart';
import 'class_details_modal.dart';
import 'lectures_history_screen.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final TimetableService _timetableService = TimetableService.instance;
  late String _selectedDay;
  DateTime _currentWeekStart = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timetableService.addListener(_onServiceUpdate);
    _selectedDay = _timetableService.getTodayDayOfWeek();

    // Determine the Monday of the current week
    final now = DateTime.now();
    _currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
  }

  @override
  void dispose() {
    _timetableService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _previousWeek() {
    setState(() {
      _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
    });
  }

  String _formatWeekRange() {
    final start = _currentWeekStart;
    final end = _currentWeekStart.add(const Duration(days: 6));

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final startStr = '${months[start.month - 1]} ${start.day}';
    final endStr = '${months[end.month - 1]} ${end.day}, ${end.year}';
    return '$startStr – $endStr';
  }

  void _openAddClassWizard({String? day}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddClassWizardScreen(initialDay: day ?? _selectedDay),
      ),
    );
  }

  void _openQuickAdd({String? day}) {
    QuickAddClassSheet.show(context, initialDay: day ?? _selectedDay);
  }

  Color _getSubjectAccentColor(String subject) {
    final hash = subject.hashCode.abs();
    final colors = [
      AppTheme.primaryAccent,
      AppTheme.trustPillText,
      AppTheme.detectedPillText,
      const Color(0xFF6B5B95),
      const Color(0xFF3B6978),
    ];
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyEntries = !_timetableService.isEmpty;

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Timetable',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            SizedBox(height: 1),
            Text(
              'Plan your week, your way.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.textPrimary),
            color: AppTheme.cardSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (val) {
              if (val == 'quick_add') {
                _openQuickAdd();
              } else if (val == 'reset') {
                _timetableService.resetToDefaultSeed();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Timetable reset to sample academic schedule'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } else if (val == 'clear') {
                _timetableService.clearAll();
              } else if (val == 'auto_record_toggle') {
                final isEnabled = LectureRecordingService.instance.isAutoRecordEnabled;
                if (!isEnabled) {
                  AutoRecordConsentSheet.show(context);
                } else {
                  LectureRecordingService.instance.setAutoRecordEnabled(false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Auto-record disabled'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } else if (val == 'my_lectures') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LecturesHistoryScreen()),
                );
              } else if (val == 'dev_test_mode') {
                RecordingScheduler.instance.scheduleTestLecture(
                  subject: 'Operating Systems (Live Test)',
                  delaySeconds: 1,
                  durationSeconds: 10,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Test recording scheduled: starting in 1s, running for 10s'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'auto_record_toggle',
                child: Row(
                  children: [
                    Icon(
                      LectureRecordingService.instance.isAutoRecordEnabled
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: AppTheme.primaryAccent,
                    ),
                    const SizedBox(width: 8),
                    const Text('Auto-Record Lectures', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'my_lectures',
                child: Row(
                  children: [
                    Icon(Icons.mic, size: 18, color: AppTheme.primaryAccent),
                    SizedBox(width: 8),
                    Text('My Lectures', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'dev_test_mode',
                child: Row(
                  children: [
                    Icon(Icons.play_circle_outline, size: 18, color: AppTheme.primaryAccent),
                    SizedBox(width: 8),
                    Text('Test 10s Auto-Record', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'quick_add',
                child: Row(
                  children: [
                    Icon(Icons.bolt, size: 18, color: AppTheme.primaryAccent),
                    SizedBox(width: 8),
                    Text('Quick Add Class', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt, size: 18, color: AppTheme.textSecondary),
                    SizedBox(width: 8),
                    Text('Reset to Sample Schedule', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 18, color: AppTheme.overduePillText),
                    SizedBox(width: 8),
                    Text('Clear All Classes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.overduePillText)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: hasAnyEntries
            ? Column(
                children: [
                  const SizedBox(height: 6),
                  // Week Selector
                  _buildWeekSelector(),
                  const SizedBox(height: 12),
                  // Day Selector Pills
                  _buildDaySelectorBar(),
                  const SizedBox(height: 12),
                  // Timeline View
                  Expanded(
                    child: _buildTimelineView(),
                  ),
                  // Bottom Add Class Button
                  _buildBottomBar(),
                ],
              )
            : _buildEmptyState(),
      ),
    );
  }

  // Week Selector: < Sep 14 – Sep 20, 2026 >
  Widget _buildWeekSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: AppTheme.textPrimary),
            onPressed: _previousWeek,
          ),
          Text(
            _formatWeekRange(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: AppTheme.textPrimary),
            onPressed: _nextWeek,
          ),
        ],
      ),
    );
  }

  // Day Selector Bar (Mon | Tue | Wed | Thu | Fri | Sat | Sun)
  Widget _buildDaySelectorBar() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: TimetableService.defaultDays.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = TimetableService.defaultDays[index];
          final isSelected = _selectedDay == day;

          return InkWell(
            onTap: () => setState(() => _selectedDay = day),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryAccent : AppTheme.cardSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.primaryAccent : AppTheme.cardBorder,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppTheme.primaryAccent.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : AppTheme.cardShadow,
              ),
              alignment: Alignment.center,
              child: Text(
                day,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Vertical Timeline View
  Widget _buildTimelineView() {
    final dayClasses = _timetableService.getEntriesForDay(_selectedDay);

    if (dayClasses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppTheme.highlightBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_available, color: AppTheme.primaryAccent, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                'No classes on $_selectedDay',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enjoy your free time or add a study session.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryAccent,
                  side: const BorderSide(color: AppTheme.primaryAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: Text('Add class on $_selectedDay'),
                onPressed: () => _openAddClassWizard(day: _selectedDay),
              ),
            ],
          ),
        ),
      );
    }

    // Timeline Hours (8:00 AM to 5:00 PM)
    final hours = [
      '8:00', '9:00', '10:00', '11:00', '12:00',
      '1:00', '2:00', '3:00', '4:00', '5:00'
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        children: hours.map((hour) {
          // Find classes starting in this hour slot
          final hourNum = int.parse(hour.split(':')[0]);
          final slotClasses = dayClasses.where((c) {
            final startMins = (c.startHourDouble * 60).round();
            final classStartHour = (startMins ~/ 60);
            final displayHour = classStartHour == 0
                ? 12
                : (classStartHour > 12 ? classStartHour - 12 : classStartHour);
            return displayHour == hourNum;
          }).toList();

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time Label
                SizedBox(
                  width: 48,
                  child: Text(
                    hour,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textInactive,
                    ),
                  ),
                ),

                // Timeline Content / Cards
                Expanded(
                  child: slotClasses.isNotEmpty
                      ? Column(
                          children: slotClasses.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildClassCard(entry),
                            );
                          }).toList(),
                        )
                      : Container(
                          height: 24,
                          alignment: Alignment.centerLeft,
                          child: const Divider(
                            color: AppTheme.cardBorder,
                            height: 1,
                            thickness: 0.8,
                          ),
                        ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildClassCard(TimetableEntry entry) {
    final accentColor = _getSubjectAccentColor(entry.subject);

    return InkWell(
      onTap: () => ClassDetailsModal.show(context, entry),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
          boxShadow: AppTheme.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Accent Indicator Strip
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
                // Card Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (entry.room != null && entry.room!.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  entry.room!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Time Range Tag
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.neutralPillFill,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${entry.startTime.replaceAll(' ', '')} – ${entry.endTime.replaceAll(' ', '')}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 18, color: AppTheme.textInactive),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Bottom Fixed "+ Add Class" Bar
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: AppTheme.canvasBg,
        border: Border(top: BorderSide(color: AppTheme.cardBorder, width: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Add Class',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: () => _openAddClassWizard(),
            ),
          ),
        ],
      ),
    );
  }

  // Screen 9: Empty State (Your week is waiting ✨)
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sparkly Calendar Icon in Card
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.cardSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.cardBorder),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: const [
                  Icon(Icons.calendar_month, color: AppTheme.primaryAccent, size: 40),
                  Positioned(
                    top: 12,
                    right: 14,
                    child: Icon(Icons.auto_awesome, color: AppTheme.primaryAccent, size: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Your week is waiting',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first class and we\'ll build\nyour schedule.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Add Your First Class',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: () => _openAddClassWizard(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
