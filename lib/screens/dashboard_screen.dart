import 'package:flutter/material.dart';
import '../models/deadline.dart';
import '../services/deadline_service.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int) onNavigateTab;

  const DashboardScreen({super.key, required this.onNavigateTab});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DeadlineService _deadlineService = DeadlineService.instance;
  String _filter = 'All'; // 'All', 'Pending', 'Completed'
  final TextEditingController _quickNlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _deadlineService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _deadlineService.removeListener(_onServiceUpdate);
    _quickNlController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  List<Deadline> get _filteredDeadlines {
    if (_filter == 'Pending') {
      return _deadlineService.deadlines.where((d) => !d.isCompleted).toList();
    }
    if (_filter == 'Completed') {
      return _deadlineService.deadlines.where((d) => d.isCompleted).toList();
    }
    return _deadlineService.deadlines;
  }

  void _showAddTaskSheet() {
    final titleController = TextEditingController();
    final courseController = TextEditingController(text: 'Operating Systems');
    DateTime selectedDate = DateTime.now().add(const Duration(days: 2));
    TimeOfDay selectedTime = const TimeOfDay(hour: 17, minute: 0);
    TaskPriority selectedPriority = TaskPriority.medium;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add Academic Task',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Task Title',
                  hintText: 'e.g., Lab Report, Quiz Revision',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: courseController,
                decoration: const InputDecoration(
                  labelText: 'Course / Subject',
                  hintText: 'e.g., Operating Systems, Physics',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text(
                        selectedTime.format(context),
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setSheetState(() => selectedTime = picked);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Priority Level',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: TaskPriority.values.map((p) {
                  final isSelected = selectedPriority == p;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p.name.toUpperCase()),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setSheetState(() => selectedPriority = p);
                      },
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cyanAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (titleController.text.trim().isEmpty) return;
                    final dueDateTime = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedTime.hour,
                      selectedTime.minute,
                    );
                    _deadlineService.addDeadline(Deadline(
                      id: 'dl_${DateTime.now().millisecondsSinceEpoch}',
                      title: titleController.text.trim(),
                      course: courseController.text.trim(),
                      dueDate: dueDateTime,
                      priority: selectedPriority,
                    ));
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save Task',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _runNaturalLanguageSchedule(String prompt) {
    final deadline = _deadlineService.parseNaturalLanguage(prompt);
    _deadlineService.addDeadline(deadline);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.cardDark,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.check_circle,
                color: AppTheme.greenAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Added "${deadline.title}" (${deadline.countdownString})',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 76,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Pal',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.cyanAccent,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.amberAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: AppTheme.amberAccent
                                    .withValues(alpha: 0.5)),
                          ),
                          child: const Text(
                            'iQOO 15',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.amberAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'On-Device Academic Copilot',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                // Offline Status Indicator
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.airplanemode_active,
                          size: 14, color: AppTheme.greenAccent),
                      SizedBox(width: 6),
                      Text(
                        '100% Offline',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.greenAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Hardware & Task Statistics Card
                  _buildHardwareStatsCard(),
                  const SizedBox(height: 16),

                  // 2. Quick AI Tools Grid
                  _buildAiToolsGrid(),
                  const SizedBox(height: 18),

                  // 3. Natural Language Scheduling Banner
                  _buildNaturalLanguageBanner(),
                  const SizedBox(height: 20),

                  // 4. Deadlines Header & Filters
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Academic Deadlines',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add,
                            size: 18, color: AppTheme.cyanAccent),
                        label: const Text('Add Task',
                            style: TextStyle(color: AppTheme.cyanAccent)),
                        onPressed: _showAddTaskSheet,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Filter Chips
                  Row(
                    children: ['All', 'Pending', 'Completed'].map((f) {
                      final isSelected = _filter == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) setState(() => _filter = f);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          // 5. Deadlines List
          _filteredDeadlines.isEmpty
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No deadlines found in this category.',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _filteredDeadlines[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: _buildDeadlineCard(item),
                      );
                    },
                    childCount: _filteredDeadlines.length,
                  ),
                ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildHardwareStatsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.surfaceDark,
            AppTheme.cardDark.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.memory, color: AppTheme.cyanAccent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Snapdragon 8 Elite NPU / Adreno 830',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.cyanAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '4.32 GHz',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.cyanAccent,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: AppTheme.cardBorder, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatCounter(
                'Pending',
                '${_deadlineService.pendingCount}',
                AppTheme.amberAccent,
              ),
              Container(width: 1, height: 32, color: AppTheme.cardBorder),
              _buildStatCounter(
                'Completed',
                '${_deadlineService.completedCount}',
                AppTheme.greenAccent,
              ),
              Container(width: 1, height: 32, color: AppTheme.cardBorder),
              _buildStatCounter(
                'Total Tasks',
                '${_deadlineService.totalCount}',
                AppTheme.cyanAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCounter(String label, String count, Color color) {
    return Column(
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildAiToolsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Multimodal Academic Tools',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildToolButton(
                icon: Icons.mic_none,
                title: 'Voice Notes',
                subtitle: 'Whisper STT',
                color: AppTheme.cyanAccent,
                onTap: () => widget.onNavigateTab(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildToolButton(
                icon: Icons.document_scanner,
                title: 'Textbook OCR',
                subtitle: 'ML Kit Vision',
                color: AppTheme.amberAccent,
                onTap: () => widget.onNavigateTab(3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildToolButton(
                icon: Icons.folder_copy,
                title: 'Study Vault',
                subtitle: 'Subject RAG',
                color: AppTheme.purpleAccent,
                onTap: () => widget.onNavigateTab(1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildToolButton(
                icon: Icons.psychology,
                title: 'Pal Brain',
                subtitle: 'GGUF Engine',
                color: AppTheme.greenAccent,
                onTap: () => widget.onNavigateTab(4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: color.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNaturalLanguageBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cyanAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: AppTheme.cyanAccent, size: 16),
              SizedBox(width: 6),
              Text(
                'Natural Language Scheduling',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.cyanAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '"Create a deadline this Friday by 5pm for English lab"',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quickNlController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    hintText: 'Type deadline natural language...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cyanAccent,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  final text = _quickNlController.text.trim().isNotEmpty
                      ? _quickNlController.text.trim()
                      : 'Create a deadline this Friday by 5pm for English lab';
                  _runNaturalLanguageSchedule(text);
                  _quickNlController.clear();
                },
                child: const Text('TRY NOW',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlineCard(Deadline item) {
    Color priorityColor = AppTheme.greenAccent;
    if (item.priority == TaskPriority.high) priorityColor = AppTheme.redAccent;
    if (item.priority == TaskPriority.medium)
      priorityColor = AppTheme.amberAccent;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.isCompleted
              ? AppTheme.cardBorder
              : priorityColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: item.isCompleted,
            activeColor: AppTheme.greenAccent,
            checkColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            onChanged: (_) => _deadlineService.toggleComplete(item.id),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: item.isCompleted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    color: item.isCompleted
                        ? AppTheme.textMuted
                        : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Course Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceDark,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.course,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.cyanAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Countdown Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule, size: 10, color: priorityColor),
                          const SizedBox(width: 4),
                          Text(
                            item.countdownString,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: priorityColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppTheme.textMuted),
            onPressed: () => _deadlineService.deleteDeadline(item.id),
          ),
        ],
      ),
    );
  }
}
