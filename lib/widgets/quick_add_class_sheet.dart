import 'package:flutter/material.dart';
import '../models/timetable_entry.dart';
import '../services/timetable_service.dart';
import '../theme/app_theme.dart';

class QuickAddClassSheet extends StatefulWidget {
  final String? initialDay;

  const QuickAddClassSheet({super.key, this.initialDay});

  static Future<bool?> show(BuildContext context, {String? initialDay}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickAddClassSheet(initialDay: initialDay),
    );
  }

  @override
  State<QuickAddClassSheet> createState() => _QuickAddClassSheetState();
}

class _QuickAddClassSheetState extends State<QuickAddClassSheet> {
  final _timetableService = TimetableService.instance;
  final _subjectController = TextEditingController();
  final _roomController = TextEditingController();
  final _professorController = TextEditingController();
  final _notesController = TextEditingController();

  late String _selectedDay;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);
  bool _repeatWeekly = true;
  bool _showMoreDetails = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDay ?? _timetableService.getTodayDayOfWeek();
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
    if (subject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a subject name'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final entry = TimetableEntry(
      id: 'tt-${DateTime.now().millisecondsSinceEpoch}',
      subject: subject,
      dayOfWeek: _selectedDay,
      startTime: _formatTimeOfDay(_startTime),
      endTime: _formatTimeOfDay(_endTime),
      room: _roomController.text.trim().isEmpty
          ? null
          : _roomController.text.trim(),
      professor: _professorController.text.trim().isEmpty
          ? null
          : _professorController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      repeatWeekly: _repeatWeekly,
      type: 'Lecture',
    );

    _timetableService.addEntry(entry);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.canvasBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + keyboardPadding),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick Add Class',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Fast schedule placement',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppTheme.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Subject Input
              const Text(
                'Subject',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _subjectController,
                autofocus: true,
                style:
                    const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g. Operating Systems',
                  hintStyle: const TextStyle(
                      color: AppTheme.textInactive, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.cardSurface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

              // Day Selector
              const Text(
                'Day of Week',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: TimetableService.defaultDays.map((day) {
                    final isSelected = _selectedDay == day;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(day),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) setState(() => _selectedDay = day);
                        },
                        selectedColor: AppTheme.primaryAccent,
                        backgroundColor: AppTheme.cardSurface,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color:
                              isSelected ? Colors.white : AppTheme.textPrimary,
                        ),
                        side: BorderSide(
                          color: isSelected
                              ? AppTheme.primaryAccent
                              : AppTheme.cardBorder,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),

              // Time Pickers Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Start Time',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: _pickStartTime,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 11),
                            decoration: BoxDecoration(
                              color: AppTheme.cardSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.cardBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.schedule,
                                    size: 16, color: AppTheme.primaryAccent),
                                const SizedBox(width: 8),
                                Text(
                                  _formatTimeOfDay(_startTime),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'End Time',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: _pickEndTime,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 11),
                            decoration: BoxDecoration(
                              color: AppTheme.cardSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.cardBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.schedule,
                                    size: 16, color: AppTheme.primaryAccent),
                                const SizedBox(width: 8),
                                Text(
                                  _formatTimeOfDay(_endTime),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Expandable "Add more details" section
              InkWell(
                onTap: () =>
                    setState(() => _showMoreDetails = !_showMoreDetails),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _showMoreDetails
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                        color: AppTheme.primaryAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showMoreDetails
                            ? 'Hide optional details'
                            : 'Add more details (Room, Prof, Notes)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_showMoreDetails) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _roomController,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.location_on_outlined,
                        size: 16, color: AppTheme.textSecondary),
                    hintText: 'Room number (e.g. Room 204)',
                    hintStyle: const TextStyle(
                        color: AppTheme.textInactive, fontSize: 12),
                    filled: true,
                    fillColor: AppTheme.cardSurface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _professorController,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person_outline,
                        size: 16, color: AppTheme.textSecondary),
                    hintText: 'Professor (e.g. Prof. Sharma)',
                    hintStyle: const TextStyle(
                        color: AppTheme.textInactive, fontSize: 12),
                    filled: true,
                    fillColor: AppTheme.cardSurface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.note_alt_outlined,
                        size: 16, color: AppTheme.textSecondary),
                    hintText: 'Notes (e.g. Bring textbook)',
                    hintStyle: const TextStyle(
                        color: AppTheme.textInactive, fontSize: 12),
                    filled: true,
                    fillColor: AppTheme.cardSurface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Repeat weekly',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
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
              ],
              const SizedBox(height: 18),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _saveClass,
                  child: const Text(
                    'Add Class',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
