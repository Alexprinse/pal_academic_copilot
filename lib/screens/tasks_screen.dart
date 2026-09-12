import 'package:flutter/material.dart';
import '../models/deadline.dart';
import '../services/deadline_service.dart';
import '../theme/app_theme.dart';

class TasksScreen extends StatefulWidget {
  final Function(int, {String? initialQuery})? onNavigateToTab;

  const TasksScreen({super.key, this.onNavigateToTab});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final DeadlineService _deadlineService = DeadlineService.instance;
  int _selectedFilterIndex =
      0; // 0: All, 1: Spoken Detected, 2: Manual, 3: Done

  final List<String> _filters = ['All', '🎙️ Detected', '✍️ Manual', 'Done'];

  @override
  void initState() {
    super.initState();
    _deadlineService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _deadlineService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  List<Deadline> get _filteredTasks {
    final all = _deadlineService.deadlines;
    switch (_selectedFilterIndex) {
      case 1:
        return all.where((t) => t.isSpokenDetected && !t.isCompleted).toList();
      case 2:
        return all.where((t) => !t.isSpokenDetected && !t.isCompleted).toList();
      case 3:
        return all.where((t) => t.isCompleted).toList();
      case 0:
      default:
        return all;
    }
  }

  String _formatDateShort(DateTime dt) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    return '${weekdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  String _formatTimeShort(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  void _showAddTaskDialog() {
    final titleCtrl = TextEditingController();
    final courseCtrl = TextEditingController(text: 'Operating Systems');
    DateTime selectedDate = DateTime.now().add(const Duration(days: 2));
    TimeOfDay selectedTime = const TimeOfDay(hour: 23, minute: 59);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add Task Manually',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'e.g., Read Silberschatz Chapter 6',
                  filled: true,
                  fillColor: AppTheme.neutralPillFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: AppTheme.primaryAccent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: courseCtrl,
                decoration: InputDecoration(
                  hintText: 'Course Name',
                  filled: true,
                  fillColor: AppTheme.neutralPillFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: AppTheme.primaryAccent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Date & Time Picker Row
              Row(
                children: [
                  // Date Picker Tile
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate:
                              DateTime.now().subtract(const Duration(days: 1)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365 * 2)),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: AppTheme.primaryAccent,
                                  onPrimary: Colors.white,
                                  surface: AppTheme.cardSurface,
                                  onSurface: AppTheme.textPrimary,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.neutralPillFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.cardBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                size: 16, color: AppTheme.primaryAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Due Date',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    _formatDateShort(selectedDate),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Time Picker Tile
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: AppTheme.primaryAccent,
                                  onPrimary: Colors.white,
                                  surface: AppTheme.cardSurface,
                                  onSurface: AppTheme.textPrimary,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setModalState(() => selectedTime = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.neutralPillFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.cardBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 16, color: AppTheme.primaryAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Due Time',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    _formatTimeShort(selectedTime),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Quick Presets Row (Days Chips)
              Row(
                children: [
                  const Text(
                    'Quick Presets:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [1, 2, 3, 5, 7].map((days) {
                          final targetDate =
                              DateTime.now().add(Duration(days: days));
                          final isSel = selectedDate.year == targetDate.year &&
                              selectedDate.month == targetDate.month &&
                              selectedDate.day == targetDate.day;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text('+${days}d'),
                              selected: isSel,
                              selectedColor: AppTheme.primaryAccent,
                              backgroundColor: AppTheme.neutralPillFill,
                              side: BorderSide(
                                color: isSel
                                    ? AppTheme.primaryAccent
                                    : AppTheme.cardBorder,
                              ),
                              labelStyle: TextStyle(
                                color:
                                    isSel ? Colors.white : AppTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                              onSelected: (val) {
                                if (val) {
                                  setModalState(() {
                                    selectedDate = DateTime.now()
                                        .add(Duration(days: days));
                                  });
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;
                    final finalDueDate = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedTime.hour,
                      selectedTime.minute,
                    );
                    _deadlineService.addDeadline(
                      Deadline(
                        id: 'dl_${DateTime.now().millisecondsSinceEpoch}',
                        title: title,
                        course: courseCtrl.text.trim().isNotEmpty
                            ? courseCtrl.text.trim()
                            : 'General',
                        dueDate: finalDueDate,
                        isSpokenDetected: false,
                      ),
                    );
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.darkSurface,
                    foregroundColor: AppTheme.canvasBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Save Task',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _filteredTasks;

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Academic Tasks',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),

            // Segmented Filter Tabs
            // Active: dark #1E1D19 fill, white text
            // Inactive: white with #EAE6DC border
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_filters.length, (index) {
                    final isActive = _selectedFilterIndex == index;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () =>
                            setState(() => _selectedFilterIndex = index),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppTheme.darkSurface
                                : AppTheme.cardSurface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isActive
                                  ? AppTheme.darkSurface
                                  : AppTheme.cardBorder,
                              width: 1,
                            ),
                            boxShadow: isActive ? AppTheme.cardShadow : null,
                          ),
                          child: Text(
                            _filters[index],
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isActive
                                  ? AppTheme.canvasBg
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Task Cards List
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Text(
                        'No tasks found in this view.',
                        style: TextStyle(
                          color: AppTheme.textInactive,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _buildTaskCard(tasks[index]);
                      },
                    ),
            ),

            // Bottom CTA: dark #1E1D19 "Add task manually" button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _showAddTaskDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.darkSurface,
                    foregroundColor: AppTheme.canvasBg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'Add task manually',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(Deadline task) {
    final isOverdue = task.timeLeft.isNegative && !task.isCompleted;

    // Overdue tasks get #FBEAE7 fill with terracotta accent
    // Regular white with soft shadow
    final cardBg = isOverdue
        ? AppTheme.overduePillFill
        : (task.isCompleted ? AppTheme.neutralPillFill : AppTheme.cardSurface);

    final borderCol = isOverdue
        ? AppTheme.overduePillText.withValues(alpha: 0.3)
        : AppTheme.cardBorder;

    return Opacity(
      // Manual/completed tasks shown at reduced opacity with strikethrough
      opacity: task.isCompleted ? 0.6 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderCol, width: 1),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Checkbox toggle
                InkWell(
                  onTap: () => _deadlineService.toggleComplete(task.id),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 2),
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

                // Title & Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          color: isOverdue
                              ? AppTheme.overduePillText
                              : AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            task.course,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('•',
                              style: TextStyle(color: AppTheme.textInactive)),
                          const SizedBox(width: 6),
                          Text(
                            task.countdownString,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isOverdue
                                  ? AppTheme.overduePillText
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Detected tasks show an amber pill: 🎙️ Detected at [time] · [source]
            // with a "Jump to audio timestamp →" link in accent color
            if (task.isSpokenDetected && !task.isCompleted) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.detectedPillFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.detectedPillText.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '🎙️ Detected at ${task.audioTimestamp ?? "18:40"} · ${task.sourceLocation ?? "Lecture 3 Audio"}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.detectedPillText,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        widget.onNavigateToTab
                            ?.call(1); // Jump to Voice capture
                      },
                      child: const Text(
                        'Jump to audio timestamp →',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
