import 'package:flutter/material.dart';
import '../models/timetable_entry.dart';
import '../services/timetable_service.dart';
import '../theme/app_theme.dart';

class AddClassWizardScreen extends StatefulWidget {
  final String? initialDay;

  const AddClassWizardScreen({super.key, this.initialDay});

  @override
  State<AddClassWizardScreen> createState() => _AddClassWizardScreenState();
}

class _AddClassWizardScreenState extends State<AddClassWizardScreen> {
  final _timetableService = TimetableService.instance;
  int _currentStep = 1;

  // Step 1: Selected Days (Set for multi-select)
  final Set<String> _selectedDays = {};

  // Step 2: Time
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);

  // Step 3: Subject
  final _subjectController = TextEditingController();

  // Step 4: Optional Details
  final _roomController = TextEditingController();
  final _professorController = TextEditingController();
  final _notesController = TextEditingController();

  // Step 5: Repeat
  bool _repeatWeekly = true;

  @override
  void initState() {
    super.initState();
    final day = widget.initialDay ?? _timetableService.getTodayDayOfWeek();
    _selectedDays.add(day);
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _roomController.dispose();
    _professorController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
    final minute = tod.minute.toString().padLeft(2, '0');
    final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  String get _calculatedDurationString {
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    int diff = endMinutes - startMinutes;
    if (diff <= 0) diff += 24 * 60;

    final hours = diff ~/ 60;
    final minutes = diff % 60;

    if (hours > 0 && minutes > 0) {
      return '$hours hr $minutes min';
    } else if (hours > 0) {
      return hours == 1 ? '1 hour' : '$hours hours';
    } else {
      return '$minutes min';
    }
  }

  void _nextStep() {
    if (_currentStep == 1) {
      if (_selectedDays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one day'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    } else if (_currentStep == 3) {
      if (_subjectController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter or select a subject'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    if (_currentStep < 5) {
      setState(() => _currentStep++);
    } else {
      _saveClass();
    }
  }

  void _prevStep() {
    if (_currentStep > 1) {
      setState(() => _currentStep--);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primaryAccent,
            onPrimary: Colors.white,
            surface: AppTheme.cardSurface,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        // Default end time to 1 hour after start
        final endHour = (picked.hour + 1) % 24;
        _endTime = TimeOfDay(hour: endHour, minute: picked.minute);
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primaryAccent,
            onPrimary: Colors.white,
            surface: AppTheme.cardSurface,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  void _saveClass() {
    final subject = _subjectController.text.trim();
    final room = _roomController.text.trim().isEmpty
        ? null
        : _roomController.text.trim();
    final prof = _professorController.text.trim().isEmpty
        ? null
        : _professorController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    final List<TimetableEntry> entriesToCreate = [];
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    int counter = 0;
    for (final day in _selectedDays) {
      entriesToCreate.add(
        TimetableEntry(
          id: 'tt-$timestamp-${counter++}',
          subject: subject,
          dayOfWeek: day,
          startTime: _formatTimeOfDay(_startTime),
          endTime: _formatTimeOfDay(_endTime),
          room: room,
          professor: prof,
          notes: notes,
          repeatWeekly: _repeatWeekly,
          type: 'Lecture',
        ),
      );
    }

    _timetableService.addEntries(entriesToCreate);

    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$subject added to your timetable ✨'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation & Step Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        size: 18, color: AppTheme.textPrimary),
                    onPressed: _prevStep,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildStepIndicator(),
                    ),
                  ),
                  const SizedBox(width: 48), // Balance back button
                ],
              ),
            ),

            // Step Body Content (Animated Switcher for smooth transitions)
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _buildCurrentStepView(),
                ),
              ),
            ),

            // Bottom Navigation Buttons
            _buildBottomButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final stepNum = index + 1;
        final isActive = stepNum == _currentStep;
        final isCompleted = stepNum < _currentStep;

        return Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted || isActive
                    ? AppTheme.primaryAccent
                    : AppTheme.cardBorder,
              ),
            ),
            if (index < 4)
              Container(
                width: 28,
                height: 2,
                color:
                    isCompleted ? AppTheme.primaryAccent : AppTheme.cardBorder,
              ),
          ],
        );
      }),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 1:
        return _buildStep1Day();
      case 2:
        return _buildStep2Time();
      case 3:
        return _buildStep3Subject();
      case 4:
        return _buildStep4Details();
      case 5:
        return _buildStep5Repeat();
      default:
        return const SizedBox();
    }
  }

  // STEP 1: Choose Day(s)
  Widget _buildStep1Day() {
    const row1 = ['Mon', 'Tue', 'Wed', 'Thu'];
    const row2 = ['Fri', 'Sat', 'Sun'];

    return Column(
      key: const ValueKey('step-1'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          "Let's add a class",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'First, select the day(s).',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 32),

        // Row 1 of Days
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: row1.map((day) => _buildDayChip(day)).toList(),
        ),
        const SizedBox(height: 12),
        // Row 2 of Days
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: row2.map((day) => _buildDayChip(day)).toList(),
        ),
      ],
    );
  }

  Widget _buildDayChip(String day) {
    final isSelected = _selectedDays.contains(day);

    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            if (_selectedDays.length > 1) {
              _selectedDays.remove(day);
            }
          } else {
            _selectedDays.add(day);
          }
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 68,
        height: 52,
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryAccent : AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryAccent : AppTheme.cardBorder,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : AppTheme.cardShadow,
        ),
        alignment: Alignment.center,
        child: Text(
          day,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  // STEP 2: Choose Time
  Widget _buildStep2Time() {
    return Column(
      key: const ValueKey('step-2'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'What time is it?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Select the start and end time.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 32),

        // Start & End Time Cards
        Row(
          children: [
            Expanded(
              child: _buildTimePickerCard(
                title: 'Start time',
                timeText: _formatTimeOfDay(_startTime),
                onTap: _pickStartTime,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildTimePickerCard(
                title: 'End time',
                timeText: _formatTimeOfDay(_endTime),
                onTap: _pickEndTime,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Duration Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.cardBorder),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.highlightBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.timelapse,
                    color: AppTheme.primaryAccent, size: 20),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Duration',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _calculatedDurationString,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimePickerCard({
    required String title,
    required String timeText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
          boxShadow: AppTheme.cardShadow,
        ),
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
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.schedule,
                    size: 18, color: AppTheme.primaryAccent),
                const SizedBox(width: 8),
                Text(
                  timeText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // STEP 3: What are you studying?
  Widget _buildStep3Subject() {
    final recentSubjects = _timetableService.getRecentSubjects();

    return Column(
      key: const ValueKey('step-3'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'What are you studying?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Search or type your subject.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 24),

        // Subject Text Field
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.cardBorder),
            boxShadow: AppTheme.cardShadow,
          ),
          child: TextField(
            controller: _subjectController,
            autofocus: true,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search,
                  color: AppTheme.textSecondary, size: 20),
              hintText: 'e.g. Operating Systems',
              hintStyle:
                  const TextStyle(color: AppTheme.textInactive, fontSize: 14),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 24),

        // Recent Subjects Header
        const Text(
          'Recent subjects',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 12),

        // Quick-select chips
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: recentSubjects.map((subject) {
            final isCurrent = _subjectController.text.trim().toLowerCase() ==
                subject.toLowerCase();

            return InkWell(
              onTap: () {
                setState(() {
                  _subjectController.text = subject;
                });
              },
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      isCurrent ? AppTheme.highlightBg : AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isCurrent
                        ? AppTheme.primaryAccent
                        : AppTheme.cardBorder,
                  ),
                ),
                child: Text(
                  subject,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                    color: isCurrent
                        ? AppTheme.primaryAccent
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // STEP 4: Add details (optional)
  Widget _buildStep4Details() {
    return Column(
      key: const ValueKey('step-4'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Add details (optional)',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Provide any additional information.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 28),

        // Room number field
        _buildDetailField(
          controller: _roomController,
          label: 'Room number',
          hint: 'e.g. Room 204',
          icon: Icons.location_on_outlined,
        ),
        const SizedBox(height: 16),

        // Professor field
        _buildDetailField(
          controller: _professorController,
          label: 'Professor',
          hint: 'e.g. Prof. Sharma',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 16),

        // Notes field
        _buildDetailField(
          controller: _notesController,
          label: 'Notes',
          hint: 'e.g. Bring textbook',
          icon: Icons.note_alt_outlined,
        ),
      ],
    );
  }

  Widget _buildDetailField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: AppTheme.primaryAccent, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                TextField(
                  controller: controller,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.only(top: 4, bottom: 2),
                    hintText: hint,
                    hintStyle: const TextStyle(
                        color: AppTheme.textInactive, fontSize: 13),
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // STEP 5: Repeat this class?
  Widget _buildStep5Repeat() {
    return Column(
      key: const ValueKey('step-5'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Repeat this class?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Add it to your timetable every week.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 32),

        // Repeat Card with Switch
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.cardBorder),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.highlightBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.repeat,
                    color: AppTheme.primaryAccent, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Repeat every week',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'This class will appear every week on the selected day(s).',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _repeatWeekly,
                onChanged: (val) => setState(() => _repeatWeekly = val),
                activeThumbColor: AppTheme.primaryAccent,
                activeTrackColor: AppTheme.highlightBg,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons() {
    final isLastStep = _currentStep == 5;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 1)
            TextButton.icon(
              onPressed: _prevStep,
              icon: const Icon(Icons.arrow_back,
                  size: 16, color: AppTheme.textSecondary),
              label: const Text(
                'Back',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
            )
          else
            const SizedBox(width: 80),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 0,
            ),
            onPressed: _nextStep,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isLastStep ? 'Add Class' : 'Next',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!isLastStep) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
