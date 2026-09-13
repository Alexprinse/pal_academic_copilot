import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/deadline.dart';
import 'deadline_detector.dart';
import 'pal_notification_service.dart';

class TaskDashboardStats {
  final int total;
  final int pending;
  final int dueToday;
  final int overdue;
  final int completed;

  const TaskDashboardStats({
    required this.total,
    required this.pending,
    required this.dueToday,
    required this.overdue,
    required this.completed,
  });

  @override
  String toString() =>
      'TaskDashboardStats(total: $total, pending: $pending, dueToday: $dueToday, overdue: $overdue, completed: $completed)';
}

class DeadlineService extends ChangeNotifier {
  static final DeadlineService instance = DeadlineService._();
  DeadlineService._();

  final List<Deadline> _deadlines = [];
  List<Deadline> get deadlines => List.unmodifiable(_deadlines);

  int get pendingCount => _deadlines.where((d) => !d.isCompleted).length;
  int get completedCount => _deadlines.where((d) => d.isCompleted).length;
  int get totalCount => _deadlines.length;

  /// Computes authoritative dashboard task statistics from the current task snapshot
  /// using local calendar day boundaries.
  TaskDashboardStats getDashboardStats([DateTime? referenceNow]) {
    final now = referenceNow ?? DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    final int total = _deadlines.length;
    int completed = 0;
    int pending = 0;
    int dueToday = 0;
    int overdue = 0;

    for (final d in _deadlines) {
      if (d.isCompleted) {
        completed++;
        continue;
      }
      pending++;

      if (d.dueDate.isBefore(startOfToday)) {
        overdue++;
      } else if (!d.dueDate.isAfter(endOfToday)) {
        dueToday++;
      }
    }

    return TaskDashboardStats(
      total: total,
      pending: pending,
      dueToday: dueToday,
      overdue: overdue,
      completed: completed,
    );
  }

  bool _initialized = false;

  Future<File> _getStorageFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pal_deadlines.json');
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _getStorageFile();
      final data = _deadlines.map((d) => d.toMap()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint(
          '[DEADLINE-STORAGE] Notice: unable to write pal_deadlines.json: $e');
    }
  }

  /// Initialize DeadlineService from persistent local storage.
  /// Does NOT load seed mock data in production.
  Future<void> init({bool loadSeedData = false}) async {
    if (_initialized) return;
    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(content);
          _deadlines.clear();
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final dl = Deadline.fromMap(item);
              // Safe migration: purge known seed demo IDs and corrupted mock titles
              if (_isMockOrSeed(dl)) continue;
              _deadlines.add(dl);
            }
          }
        }
      }
    } catch (e) {
      debugPrint(
          '[DEADLINE-STORAGE] Notice: unable to load pal_deadlines.json: $e');
    }

    if (loadSeedData && _deadlines.isEmpty) {
      populateSeedDeadlinesForTesting();
    }

    _initialized = true;
    notifyListeners();
  }

  static bool _isMockOrSeed(Deadline dl) {
    if (dl.id == 'dl-1' ||
        dl.id == 'dl-2' ||
        dl.id == 'dl-3' ||
        dl.id == 'dl-4') {
      return true;
    }
    final titleLower = dl.title.toLowerCase().trim();
    if (titleLower == 'live video' || titleLower == 'general deadline') {
      return true;
    }
    return false;
  }

  @visibleForTesting
  void populateSeedDeadlinesForTesting() {
    final now = DateTime.now();
    _deadlines.addAll([
      Deadline(
        id: 'dl-1',
        title: 'OS Lab 2: Peterson\'s Algorithm & Semaphores',
        course: 'Operating Systems',
        dueDate: now.add(const Duration(days: 2, hours: 4)),
        priority: TaskPriority.high,
        isSpokenDetected: true,
        audioTimestamp: '18:40',
        sourceLocation: 'Lecture 3 Audio',
      ),
      Deadline(
        id: 'dl-2',
        title: 'Wave Optics Numerical Problem Set',
        course: 'Engineering Physics',
        dueDate: now.add(const Duration(days: 4, hours: 8)),
        priority: TaskPriority.medium,
        isSpokenDetected: false,
      ),
      Deadline(
        id: 'dl-3',
        title: 'Discrete Math: Graph Coloring Homework',
        course: 'Mathematics',
        dueDate: now.add(const Duration(days: 6)),
        priority: TaskPriority.low,
        isSpokenDetected: true,
        audioTimestamp: '32:15',
        sourceLocation: 'Lecture 5 Audio',
      ),
      Deadline(
        id: 'dl-4',
        title: 'Technical Communication Presentation Draft',
        course: 'English',
        dueDate: now.subtract(const Duration(days: 1)),
        priority: TaskPriority.medium,
        isCompleted: true,
        isSpokenDetected: false,
      ),
    ]);
    notifyListeners();
  }

  void addDeadline(Deadline deadline) {
    _deadlines.removeWhere((d) =>
        d.id == deadline.id ||
        (deadline.lectureId != null &&
            d.lectureId == deadline.lectureId &&
            d.title.trim().toLowerCase() ==
                deadline.title.trim().toLowerCase()));
    _deadlines.insert(0, deadline);
    _saveToDisk();
    notifyListeners();
    PalNotificationService.instance.scheduleDeadlineReminders(deadline);
    debugPrint('[PAL-DEADLINE] Task created: "${deadline.title}"');
    debugPrint('[PAL-DEADLINE] Task ID: ${deadline.id}');
  }

  void toggleComplete(String id) {
    final idx = _deadlines.indexWhere((d) => d.id == id);
    if (idx != -1) {
      _deadlines[idx].isCompleted = !_deadlines[idx].isCompleted;
      _saveToDisk();
      notifyListeners();
      if (_deadlines[idx].isCompleted) {
        PalNotificationService.instance.cancelEntityNotifications(id);
      } else {
        PalNotificationService.instance
            .scheduleDeadlineReminders(_deadlines[idx]);
      }
    }
  }

  void deleteDeadline(String id) {
    _deadlines.removeWhere((d) => d.id == id);
    _saveToDisk();
    notifyListeners();
    PalNotificationService.instance.cancelEntityNotifications(id);
  }

  /// Natural Language Deadline Extraction utilizing DeadlineDetector
  Deadline parseNaturalLanguage(
    String input, {
    DateTime? referenceDate,
    String? subject,
    String? lectureId,
    String? recordingId,
    String? audioTimestamp,
    int? audioTimestampSeconds,
  }) {
    // Path 1: Attempt JSON block extraction
    final jsonMatch =
        RegExp(r'```(?:event|json)?\s*(\{[\s\S]*?\})\s*```').firstMatch(input);
    if (jsonMatch != null) {
      try {
        final jsonStr = jsonMatch.group(1)!;
        final map = json.decode(jsonStr) as Map<String, dynamic>;
        final dl = Deadline(
          id: 'dl_${DateTime.now().millisecondsSinceEpoch}',
          title: map['title'] as String? ?? 'Course Assignment',
          course: map['course'] as String? ?? subject ?? 'General',
          dueDate: DateTime.tryParse(map['dueDate'] as String? ?? '') ??
              (referenceDate ?? DateTime.now()).add(const Duration(days: 2)),
          priority: TaskPriority.values.firstWhere(
            (p) => p.name == (map['priority'] as String? ?? 'medium'),
            orElse: () => TaskPriority.medium,
          ),
          description: map['description'] as String?,
          lectureId: lectureId,
          recordingId: recordingId,
          audioTimestamp: audioTimestamp,
          sourceTimestampSeconds: audioTimestampSeconds,
          isSpokenDetected: true,
        );
        debugPrint('[PAL-DEADLINE] Task created: "${dl.title}"');
        debugPrint('[PAL-DEADLINE] Task ID: ${dl.id}');
        return dl;
      } catch (e) {
        debugPrint('JSON parsing failed, moving to deterministic fallback: $e');
      }
    }

    // Path 2: Advanced DeadlineDetector
    final candidates = DeadlineDetector.detectCandidates(
      input,
      referenceDate: referenceDate,
      subject: subject,
      lectureId: lectureId,
      recordingId: recordingId,
      currentElapsedSeconds: audioTimestampSeconds,
    );

    if (candidates.isNotEmpty) {
      final best = candidates.firstWhere(
        (c) => c.isValid,
        orElse: () => candidates.first,
      );
      final dl = best.toDeadline();
      debugPrint('[PAL-DEADLINE] Task created: "${dl.title}"');
      debugPrint('[PAL-DEADLINE] Task ID: ${dl.id}');
      return dl;
    }

    // Fallback if completely unparseable
    final cleanSubject =
        (subject != null && subject != 'General') ? subject : 'General';
    final dl = Deadline(
      id: 'dl_${DateTime.now().millisecondsSinceEpoch}',
      title: cleanSubject != 'General'
          ? '$cleanSubject Assignment'
          : 'Course Assignment',
      course: cleanSubject,
      dueDate: (referenceDate ?? DateTime.now()).add(const Duration(days: 2)),
      priority: TaskPriority.medium,
      isSpokenDetected: true,
      audioTimestamp: audioTimestamp ?? '01:15',
      sourceLocation:
          cleanSubject != 'General' ? cleanSubject : 'Lecture Audio',
      lectureId: lectureId,
      recordingId: recordingId,
      sourceTimestampSeconds: audioTimestampSeconds,
      confidence: 0.5,
      needsReview: true,
      hasExplicitDueDate: false,
    );
    debugPrint('[PAL-DEADLINE] Task created: "${dl.title}"');
    debugPrint('[PAL-DEADLINE] Task ID: ${dl.id}');
    return dl;
  }

  @visibleForTesting
  void setDeadlinesForTesting(List<Deadline> items) {
    _deadlines.clear();
    _deadlines.addAll(items);
    notifyListeners();
  }
}
