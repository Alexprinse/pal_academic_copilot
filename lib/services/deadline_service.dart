import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/deadline.dart';

class DeadlineService extends ChangeNotifier {
  static final DeadlineService instance = DeadlineService._();
  DeadlineService._();

  final List<Deadline> _deadlines = [];
  List<Deadline> get deadlines => List.unmodifiable(_deadlines);

  int get pendingCount => _deadlines.where((d) => !d.isCompleted).length;
  int get completedCount => _deadlines.where((d) => d.isCompleted).length;
  int get totalCount => _deadlines.length;

  Future<void> init() async {
    if (_deadlines.isNotEmpty) return;
    _populateSeedDeadlines();
  }

  void _populateSeedDeadlines() {
    final now = DateTime.now();
    _deadlines.addAll([
      Deadline(
        id: 'dl-1',
        title: 'OS Lab 2: Peterson\'s Algorithm & Semaphores',
        course: 'Operating Systems',
        dueDate: now.add(const Duration(days: 2, hours: 4)),
        priority: TaskPriority.high,
      ),
      Deadline(
        id: 'dl-2',
        title: 'Wave Optics Numerical Problem Set',
        course: 'Engineering Physics',
        dueDate: now.add(const Duration(days: 4, hours: 8)),
        priority: TaskPriority.medium,
      ),
      Deadline(
        id: 'dl-3',
        title: 'Discrete Math: Graph Coloring Homework',
        course: 'Mathematics',
        dueDate: now.add(const Duration(days: 6)),
        priority: TaskPriority.low,
      ),
      Deadline(
        id: 'dl-4',
        title: 'Technical Communication Presentation Draft',
        course: 'English',
        dueDate: now.subtract(const Duration(days: 1)),
        priority: TaskPriority.medium,
        isCompleted: true,
      ),
    ]);
    notifyListeners();
  }

  void addDeadline(Deadline deadline) {
    _deadlines.insert(0, deadline);
    notifyListeners();
  }

  void toggleComplete(String id) {
    final idx = _deadlines.indexWhere((d) => d.id == id);
    if (idx != -1) {
      _deadlines[idx].isCompleted = !_deadlines[idx].isCompleted;
      notifyListeners();
    }
  }

  void deleteDeadline(String id) {
    _deadlines.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  /// Dual-path Natural Language Deadline Extraction
  Deadline parseNaturalLanguage(String input) {
    // Path 1: Attempt JSON block extraction
    final jsonMatch =
        RegExp(r'```(?:event|json)?\s*(\{[\s\S]*?\})\s*```').firstMatch(input);
    if (jsonMatch != null) {
      try {
        final jsonStr = jsonMatch.group(1)!;
        final map = json.decode(jsonStr) as Map<String, dynamic>;
        return Deadline(
          id: 'dl_${DateTime.now().millisecondsSinceEpoch}',
          title: map['title'] as String? ?? 'Academic Deadline',
          course: map['course'] as String? ?? 'General',
          dueDate: DateTime.tryParse(map['dueDate'] as String? ?? '') ??
              DateTime.now().add(const Duration(days: 2)),
          priority: TaskPriority.values.firstWhere(
            (p) => p.name == (map['priority'] as String? ?? 'medium'),
            orElse: () => TaskPriority.medium,
          ),
        );
      } catch (e) {
        debugPrint('JSON parsing failed, moving to deterministic fallback: $e');
      }
    }

    // Path 2: Deterministic Regex & Temporal Fallback
    final lower = input.toLowerCase();
    final now = DateTime.now();

    // 1. Detect Course
    String course = 'General';
    if (lower.contains('english')) {
      course = 'English';
    } else if (lower.contains('os') || lower.contains('operating systems')) {
      course = 'Operating Systems';
    } else if (lower.contains('physics')) {
      course = 'Engineering Physics';
    } else if (lower.contains('math')) {
      course = 'Discrete Mathematics';
    } else if (lower.contains('chemistry')) {
      course = 'Chemistry';
    } else if (lower.contains('dsa') || lower.contains('data structures')) {
      course = 'Data Structures';
    }

    // 2. Detect Priority
    TaskPriority priority = TaskPriority.medium;
    if (lower.contains('urgent') ||
        lower.contains('asap') ||
        lower.contains('important') ||
        lower.contains('exam')) {
      priority = TaskPriority.high;
    } else if (lower.contains('reading') || lower.contains('optional')) {
      priority = TaskPriority.low;
    }

    // 3. Detect Day
    DateTime targetDate = now;
    final weekdayMap = {
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
    };

    bool dayFound = false;
    if (lower.contains('tomorrow')) {
      targetDate = now.add(const Duration(days: 1));
      dayFound = true;
    } else if (lower.contains('today')) {
      targetDate = now;
      dayFound = true;
    } else {
      for (final entry in weekdayMap.entries) {
        if (lower.contains(entry.key)) {
          int daysToAdd = entry.value - now.weekday;
          if (daysToAdd <= 0) daysToAdd += 7; // Next occurrence
          targetDate = now.add(Duration(days: daysToAdd));
          dayFound = true;
          break;
        }
      }
    }

    if (!dayFound) {
      targetDate = now.add(const Duration(days: 2));
    }

    // 4. Detect Time (e.g., 5pm, 11:59pm, 17:00, 9 am)
    int hour = 17; // Default 5:00 PM
    int minute = 0;
    final timeMatch =
        RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?', caseSensitive: false)
            .firstMatch(input);
    if (timeMatch != null) {
      int parsedHour = int.tryParse(timeMatch.group(1) ?? '17') ?? 17;
      final parsedMin = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      final amPm = timeMatch.group(3)?.toLowerCase();

      if (amPm == 'pm' && parsedHour < 12) parsedHour += 12;
      if (amPm == 'am' && parsedHour == 12) parsedHour = 0;

      hour = parsedHour;
      minute = parsedMin;
    }

    final finalDueDate = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      hour,
      minute,
    );

    // 5. Detect Title
    String title = 'Course Assignment';
    final forMatch = RegExp(
            r'for\s+([a-zA-Z0-9\s]+?)(?:\s+by|\s+this|\s+on|\s+at|$)',
            caseSensitive: false)
        .firstMatch(input);
    if (forMatch != null && forMatch.group(1)!.trim().isNotEmpty) {
      title = forMatch.group(1)!.trim();
      // Capitalize first letter
      title = title[0].toUpperCase() + title.substring(1);
    } else {
      title = '$course Deadline';
    }

    return Deadline(
      id: 'dl_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      course: course,
      dueDate: finalDueDate,
      priority: priority,
    );
  }
}
