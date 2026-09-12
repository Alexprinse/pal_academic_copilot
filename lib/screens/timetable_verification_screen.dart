import 'package:flutter/material.dart';
import '../models/parsed_timetable_entry.dart';
import '../services/timetable_parser.dart';
import '../services/timetable_service.dart';
import '../theme/app_theme.dart';
import 'timetable_visual_overlay_screen.dart';

class TimetableVerificationScreen extends StatefulWidget {
  final ParsedTimetableResult parsedResult;
  final String imagePath;

  const TimetableVerificationScreen({
    super.key,
    required this.parsedResult,
    required this.imagePath,
  });

  @override
  State<TimetableVerificationScreen> createState() =>
      _TimetableVerificationScreenState();
}

class _TimetableVerificationScreenState
    extends State<TimetableVerificationScreen> {
  late List<ParsedTimetableEntry> _entries;
  late String _selectedDay;
  final TimetableService _timetableService = TimetableService.instance;

  static const List<String> _days = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  void initState() {
    super.initState();
    _entries = List.from(widget.parsedResult.entries);

    // Default selected day to first day that has extracted classes, or today's day
    final firstDayWithClass = _days.firstWhere(
      (d) => _entries.any((e) => e.dayOfWeek == d),
      orElse: () => _timetableService.getTodayDayOfWeek(),
    );
    _selectedDay = firstDayWithClass;
  }

  List<ParsedTimetableEntry> get _currentDayEntries {
    final list = _entries.where((e) => e.dayOfWeek == _selectedDay).toList();
    list.sort((a, b) {
      final aEntry = a.toTimetableEntry();
      final bEntry = b.toTimetableEntry();
      return aEntry.startHourDouble.compareTo(bEntry.startHourDouble);
    });
    return list;
  }

  int get _reviewCount => _entries.where((e) => e.requiresReview).length;

  void _openVisualOverlay() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TimetableVisualOverlayScreen(
          imagePath: widget.imagePath,
          dayHeaders: widget.parsedResult.dayHeaders,
          timeHeaders: widget.parsedResult.timeHeaders,
          entries: _entries,
          cellRects: widget.parsedResult.cellRects,
        ),
      ),
    );
  }

  void _deleteEntry(ParsedTimetableEntry entry) {
    setState(() {
      _entries.removeWhere((e) => e.id == entry.id);
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${entry.subject}'),
        action: SnackBarAction(
          label: 'Undo',
          textColor: AppTheme.primaryAccent,
          onPressed: () {
            setState(() {
              _entries.add(entry);
            });
          },
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _editEntry(ParsedTimetableEntry? existing) {
    final isNew = existing == null;
    final subjectCtrl = TextEditingController(text: existing?.subject ?? '');
    final startCtrl =
        TextEditingController(text: existing?.startTime ?? '09:00 AM');
    final endCtrl =
        TextEditingController(text: existing?.endTime ?? '10:00 AM');
    final roomCtrl = TextEditingController(text: existing?.room ?? '');
    final profCtrl = TextEditingController(text: existing?.professor ?? '');
    String selectedDay = existing?.dayOfWeek ?? _selectedDay;
    String selectedType = existing?.type ?? 'Lecture';

    TimeOfDay parseTime(String timeStr) {
      try {
        final clean = timeStr.trim().toUpperCase();
        final isPm = clean.contains('PM');
        final isAm = clean.contains('AM');

        final parts = clean.replaceAll(RegExp(r'[^\d:]'), '').split(':');
        int hour = int.parse(parts[0]);
        final minute = parts.length > 1 ? int.parse(parts[1]) : 0;

        if (isPm && hour < 12) hour += 12;
        if (isAm && hour == 12) hour = 0;

        return TimeOfDay(hour: hour, minute: minute);
      } catch (_) {
        return const TimeOfDay(hour: 9, minute: 0);
      }
    }

    String formatTime(TimeOfDay tod) {
      final hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
      final minute = tod.minute.toString().padLeft(2, '0');
      final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
      return '${hour.toString().padLeft(2, '0')}:$minute $period';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isNew ? 'Add Class' : 'Edit Class',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppTheme.textSecondary),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Subject field
                    TextField(
                      controller: subjectCtrl,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        labelText: 'Subject Name',
                        labelStyle:
                            const TextStyle(color: AppTheme.textSecondary),
                        filled: true,
                        fillColor: AppTheme.canvasBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.cardBorder),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Day Selector Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _days.map((d) {
                          final sel = d == selectedDay;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(d),
                              selected: sel,
                              selectedColor: AppTheme.primaryAccent,
                              backgroundColor: AppTheme.canvasBg,
                              labelStyle: TextStyle(
                                color:
                                    sel ? Colors.white : AppTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                              onSelected: (_) =>
                                  setModalState(() => selectedDay = d),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Time row with interactive TimePicker
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: startCtrl,
                            readOnly: true,
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: parseTime(startCtrl.text),
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
                                setModalState(() {
                                  startCtrl.text = formatTime(picked);
                                });
                              }
                            },
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: 'Start Time',
                              hintText: '09:00 AM',
                              filled: true,
                              fillColor: AppTheme.canvasBg,
                              suffixIcon: const Icon(Icons.schedule,
                                  size: 18, color: AppTheme.primaryAccent),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppTheme.cardBorder),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: endCtrl,
                            readOnly: true,
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: parseTime(endCtrl.text),
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
                                setModalState(() {
                                  endCtrl.text = formatTime(picked);
                                });
                              }
                            },
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: 'End Time',
                              hintText: '10:00 AM',
                              filled: true,
                              fillColor: AppTheme.canvasBg,
                              suffixIcon: const Icon(Icons.schedule,
                                  size: 18, color: AppTheme.primaryAccent),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppTheme.cardBorder),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Room & Professor
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: roomCtrl,
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Room (optional)',
                              hintText: 'Room 204',
                              filled: true,
                              fillColor: AppTheme.canvasBg,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppTheme.cardBorder),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: profCtrl,
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Professor (optional)',
                              hintText: 'Dr. Rao',
                              filled: true,
                              fillColor: AppTheme.canvasBg,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppTheme.cardBorder),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Type selector
                    Row(
                      children: ['Lecture', 'Lab', 'Tutorial'].map((t) {
                        final sel = t == selectedType;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(t),
                            selected: sel,
                            selectedColor:
                                AppTheme.primaryAccent.withValues(alpha: 0.2),
                            checkmarkColor: AppTheme.primaryAccent,
                            backgroundColor: AppTheme.canvasBg,
                            labelStyle: TextStyle(
                              color: sel
                                  ? AppTheme.primaryAccent
                                  : AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            onSelected: (_) =>
                                setModalState(() => selectedType = t),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          final subject = subjectCtrl.text.trim();
                          if (subject.isEmpty) return;

                          setState(() {
                            if (isNew) {
                              _entries.add(
                                ParsedTimetableEntry(
                                  id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
                                  subject: subject,
                                  dayOfWeek: selectedDay,
                                  startTime: startCtrl.text.trim(),
                                  endTime: endCtrl.text.trim(),
                                  room: roomCtrl.text.trim().isNotEmpty
                                      ? roomCtrl.text.trim()
                                      : null,
                                  professor: profCtrl.text.trim().isNotEmpty
                                      ? profCtrl.text.trim()
                                      : null,
                                  type: selectedType,
                                  confidence: 1.0,
                                  requiresReview: false,
                                ),
                              );
                            } else {
                              existing.subject = subject;
                              existing.dayOfWeek = selectedDay;
                              existing.startTime = startCtrl.text.trim();
                              existing.endTime = endCtrl.text.trim();
                              existing.room = roomCtrl.text.trim().isNotEmpty
                                  ? roomCtrl.text.trim()
                                  : null;
                              existing.professor =
                                  profCtrl.text.trim().isNotEmpty
                                      ? profCtrl.text.trim()
                                      : null;
                              existing.type = selectedType;
                              existing.requiresReview = false;
                              existing.reviewReason = null;
                            }
                          });
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          isNew ? 'Add Class' : 'Save Changes',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleSave() async {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No classes to save. Please add at least one class.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final candidateEntries = _entries.map((e) => e.toTimetableEntry()).toList();
    final existingEntries = _timetableService.entries;

    if (existingEntries.isNotEmpty) {
      final duplicateCount =
          _timetableService.findDuplicateCount(candidateEntries);

      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Save Timetable',
            style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You already have ${existingEntries.length} classes in your timetable.'
                '${duplicateCount > 0 ? " ($duplicateCount classes look identical)." : ""}',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              const Text(
                'How would you like to apply the extracted schedule?',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.primaryAccent),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, 'append'),
              child: const Text('Add to Existing',
                  style: TextStyle(color: AppTheme.primaryAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('Replace Timetable'),
            ),
          ],
        ),
      );

      if (action == null || action == 'cancel') return;

      if (action == 'replace') {
        await _timetableService.replaceEntries(candidateEntries);
      } else if (action == 'append') {
        await _timetableService.addEntries(candidateEntries);
      }
    } else {
      await _timetableService.addEntries(candidateEntries);
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Timetable saved! ${_entries.length} classes added.'),
        backgroundColor: AppTheme.cardSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Pop back to TimetableScreen
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dayClasses = _currentDayEntries;

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppTheme.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Review Timetable',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              'Verify extracted classes before saving',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.crop_free,
                size: 16, color: AppTheme.primaryAccent),
            label: const Text(
              'Overlay',
              style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.primaryAccent,
                  fontWeight: FontWeight.w700),
            ),
            onPressed: _openVisualOverlay,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Status & Privacy Banner
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.auto_awesome,
                        color: AppTheme.primaryAccent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Found ${_entries.length} classes',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Processed privately on your device · 100% Offline',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (_reviewCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.overduePillFill,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.overduePillText
                                .withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '$_reviewCount review',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.overduePillText,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Day Selector Tabs (Mon | Tue | Wed | Thu | Fri | Sat | Sun)
            SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final day = _days[index];
                  final isSelected = _selectedDay == day;
                  final classCount =
                      _entries.where((e) => e.dayOfWeek == day).length;

                  return InkWell(
                    onTap: () => setState(() => _selectedDay = day),
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryAccent
                            : AppTheme.cardSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryAccent
                              : AppTheme.cardBorder,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            day,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textPrimary,
                            ),
                          ),
                          if (classCount > 0) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : AppTheme.cardBorder,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$classCount',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? Colors.white
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Extracted Classes for selected day
            Expanded(
              child: dayClasses.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_busy,
                              color:
                                  AppTheme.textSecondary.withValues(alpha: 0.4),
                              size: 42),
                          const SizedBox(height: 10),
                          Text(
                            'No classes detected for $_selectedDay',
                            style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add a class for this day'),
                            onPressed: () => _editEntry(null),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: dayClasses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = dayClasses[index];
                        return _buildClassCard(entry);
                      },
                    ),
            ),

            // Bottom Action Bar: Add Class / Save Timetable / Cancel
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                color: AppTheme.cardSurface,
                border: Border(
                    top: BorderSide(color: AppTheme.cardBorder, width: 1)),
              ),
              child: Row(
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      side: const BorderSide(color: AppTheme.cardBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _editEntry(null),
                    child: const Icon(Icons.add,
                        color: AppTheme.primaryAccent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: _handleSave,
                      child: Text(
                        'Save Timetable (${_entries.length})',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
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

  Widget _buildClassCard(ParsedTimetableEntry entry) {
    final hasWarning = entry.requiresReview;

    return InkWell(
      onTap: () => _editEntry(entry),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasWarning
                ? AppTheme.overduePillText.withValues(alpha: 0.4)
                : AppTheme.cardBorder,
            width: hasWarning ? 1.5 : 1,
          ),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasWarning && entry.reviewReason != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.overduePillFill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 13, color: AppTheme.overduePillText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        entry.reviewReason!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.overduePillText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.subject,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppTheme.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _deleteEntry(entry),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.schedule,
                    size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${entry.startTime} – ${entry.endTime}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.type,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryAccent,
                    ),
                  ),
                ),
              ],
            ),
            if (entry.room != null || entry.professor != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (entry.room != null) ...[
                    const Icon(Icons.room_outlined,
                        size: 13, color: AppTheme.textSecondary),
                    const SizedBox(width: 3),
                    Text(
                      entry.room!,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (entry.professor != null) ...[
                    const Icon(Icons.person_outline,
                        size: 13, color: AppTheme.textSecondary),
                    const SizedBox(width: 3),
                    Text(
                      entry.professor!,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.textSecondary),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
