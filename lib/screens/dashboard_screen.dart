import 'package:flutter/material.dart';
import '../models/deadline.dart';
import '../services/deadline_service.dart';
import '../theme/app_theme.dart';

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

  final List<ClassScheduleItem> _todayClasses = const [
    ClassScheduleItem(
      code: 'CS 301',
      name: 'Operating Systems: Concurrency & Locks',
      time: '10:00 AM – 11:30 AM',
      room: 'Lecture Hall B3',
      status: 'Ready to record',
      isReadyToRecord: true,
    ),
    ClassScheduleItem(
      code: 'MATH 220',
      name: 'Discrete Mathematics: Graph Theory',
      time: '01:30 PM – 03:00 PM',
      room: 'Room 402',
      status: 'Upcoming',
      isReadyToRecord: false,
    ),
    ClassScheduleItem(
      code: 'PHYS 102',
      name: 'Engineering Physics: Wave Optics',
      time: '03:30 PM – 05:00 PM',
      room: 'Science Complex C1',
      status: 'Recorded (52m)',
      isReadyToRecord: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _deadlineService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _deadlineService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
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

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      body: SafeArea(
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_getGreeting()}, Alex',
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Study Vault Quick Access Button
                        InkWell(
                          onTap: () =>
                              widget.onNavigateTab(98), // Open Study Vault
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.neutralPillFill,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.cardBorder),
                            ),
                            child: const Row(
                              children: [
                                Text('📚', style: TextStyle(fontSize: 14)),
                                SizedBox(width: 5),
                                Text(
                                  'Vault',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Academic Monogram Avatar Circle
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.cardSurface,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.cardBorder, width: 1.5),
                            boxShadow: AppTheme.cardShadow,
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'AP',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryAccent,
                              letterSpacing: 0.5,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.trustPillFill,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.trustPillText.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('✈️', style: TextStyle(fontSize: 12)),
                        SizedBox(width: 6),
                        Text(
                          'Airplane Mode Ready · Zero Cloud Sync',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.trustPillText,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Today's Focus Row (3 Compact Stat Cards)
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    // Card 1: Tasks Due Today (Amber Pill style)
                    Expanded(
                      child: _buildFocusCard(
                        title: 'Due Today',
                        count: '${_deadlineService.pendingCount}',
                        pillLabel: '3 pending',
                        pillBg: AppTheme.detectedPillFill,
                        pillTextColor: AppTheme.detectedPillText,
                        onTap: () =>
                            widget.onNavigateTab(3), // Navigate to Tasks
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
                        onTap: () => widget.onNavigateTab(2), // Navigate to Ask
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

            // 4. Section: Today's Classes
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Today\'s Classes',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '${_todayClasses.length} Scheduled',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = _todayClasses[index];
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                    child: _buildClassCard(item),
                  );
                },
                childCount: _todayClasses.length,
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
                      onTap: () => widget.onNavigateTab(3), // Tasks tab
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                    child: _buildTaskCard(task, index),
                  );
                },
                childCount: deadlines.length > 4 ? 4 : deadlines.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
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

  Widget _buildClassCard(ClassScheduleItem item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          // Class icon / mic button
          InkWell(
            onTap: () => widget.onNavigateTab(1), // Live Capture
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.isReadyToRecord
                    ? AppTheme.detectedPillFill
                    : AppTheme.neutralPillFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: item.isReadyToRecord
                      ? AppTheme.primaryAccent.withValues(alpha: 0.3)
                      : AppTheme.cardBorder,
                  width: 1,
                ),
              ),
              child: Icon(
                item.isReadyToRecord ? Icons.mic : Icons.school_outlined,
                color: item.isReadyToRecord
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
                  children: [
                    Text(
                      item.code,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryAccent,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• ${item.time}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.room,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Status Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: item.isReadyToRecord
                  ? AppTheme.detectedPillFill
                  : AppTheme.neutralPillFill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              item.status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: item.isReadyToRecord
                    ? AppTheme.detectedPillText
                    : AppTheme.textSecondary,
              ),
            ),
          ),
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
}
