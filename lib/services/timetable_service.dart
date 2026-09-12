import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/timetable_entry.dart';

class TimetableService extends ChangeNotifier {
  static final TimetableService instance = TimetableService._();
  TimetableService._();

  final List<TimetableEntry> _entries = [];
  List<TimetableEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;

  static const List<String> defaultDays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const Map<int, String> _weekdayMap = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  static const List<String> suggestedSubjects = [
    'Operating Systems',
    'Data Structures',
    'Computer Networks',
    'Algorithms',
    'Technical Writing',
    'Digital Logic',
  ];

  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/timetable_entries.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(content);
          _entries.clear();
          for (final item in decoded) {
            _entries.add(TimetableEntry.fromJson(item as Map<String, dynamic>));
          }
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('Note: unable to load timetable_entries.json: $e');
    }

    // Populate initial seed classes if empty
    if (_entries.isEmpty) {
      _populateSeedEntries();
      await _saveToDisk();
    }
  }

  void _populateSeedEntries() {
    _entries.clear();
    _entries.addAll([
      // Monday (matching reference screenshot)
      const TimetableEntry(
        id: 'tt-mon-1',
        subject: 'Data Structures',
        dayOfWeek: 'Mon',
        startTime: '09:00 AM',
        endTime: '10:00 AM',
        room: 'Room 204',
        professor: 'Prof. Sharma',
        type: 'Lecture',
        repeatWeekly: true,
      ),
      const TimetableEntry(
        id: 'tt-mon-2',
        subject: 'Operating Systems',
        dayOfWeek: 'Mon',
        startTime: '11:00 AM',
        endTime: '12:30 PM',
        room: 'Lab 2',
        professor: 'Dr. Rao',
        notes: 'Bring lab observation book',
        type: 'Lab',
        repeatWeekly: true,
      ),
      const TimetableEntry(
        id: 'tt-mon-3',
        subject: 'Computer Networks',
        dayOfWeek: 'Mon',
        startTime: '02:00 PM',
        endTime: '03:00 PM',
        room: 'Room 301',
        professor: 'Prof. Mehta',
        type: 'Lecture',
        repeatWeekly: true,
      ),
      const TimetableEntry(
        id: 'tt-mon-4',
        subject: 'Technical Writing',
        dayOfWeek: 'Mon',
        startTime: '04:00 PM',
        endTime: '05:00 PM',
        room: 'Room 105',
        professor: 'Dr. Evelyn Carter',
        type: 'Lecture',
        repeatWeekly: true,
      ),

      // Tuesday
      const TimetableEntry(
        id: 'tt-tue-1',
        subject: 'Operating Systems',
        dayOfWeek: 'Tue',
        startTime: '10:00 AM',
        endTime: '11:30 AM',
        room: 'Room 204',
        professor: 'Dr. Rao',
        type: 'Lecture',
        repeatWeekly: true,
      ),
      const TimetableEntry(
        id: 'tt-tue-2',
        subject: 'Algorithms',
        dayOfWeek: 'Tue',
        startTime: '02:00 PM',
        endTime: '03:30 PM',
        room: 'Hall B',
        professor: 'Prof. Sen',
        type: 'Lecture',
        repeatWeekly: true,
      ),

      // Wednesday
      const TimetableEntry(
        id: 'tt-wed-1',
        subject: 'Data Structures',
        dayOfWeek: 'Wed',
        startTime: '09:00 AM',
        endTime: '10:30 AM',
        room: 'Lab 1',
        professor: 'Prof. Sharma',
        type: 'Lab',
        repeatWeekly: true,
      ),
      const TimetableEntry(
        id: 'tt-wed-2',
        subject: 'Digital Logic',
        dayOfWeek: 'Wed',
        startTime: '11:00 AM',
        endTime: '12:30 PM',
        room: 'Room 102',
        professor: 'Prof. Iyer',
        type: 'Lecture',
        repeatWeekly: true,
      ),

      // Thursday
      const TimetableEntry(
        id: 'tt-thu-1',
        subject: 'Computer Networks',
        dayOfWeek: 'Thu',
        startTime: '10:00 AM',
        endTime: '11:30 AM',
        room: 'Room 301',
        professor: 'Prof. Mehta',
        type: 'Lecture',
        repeatWeekly: true,
      ),
      const TimetableEntry(
        id: 'tt-thu-2',
        subject: 'Operating Systems',
        dayOfWeek: 'Thu',
        startTime: '02:00 PM',
        endTime: '04:00 PM',
        room: 'Lab 2',
        professor: 'Dr. Rao',
        type: 'Lab',
        repeatWeekly: true,
      ),

      // Friday
      const TimetableEntry(
        id: 'tt-fri-1',
        subject: 'Technical Writing',
        dayOfWeek: 'Fri',
        startTime: '10:00 AM',
        endTime: '11:00 AM',
        room: 'Room 105',
        professor: 'Dr. Evelyn Carter',
        type: 'Lecture',
        repeatWeekly: true,
      ),
      const TimetableEntry(
        id: 'tt-fri-2',
        subject: 'Discrete Mathematics',
        dayOfWeek: 'Fri',
        startTime: '01:30 PM',
        endTime: '03:00 PM',
        room: 'Room 402',
        professor: 'Prof. Raman',
        type: 'Lecture',
        repeatWeekly: true,
      ),
    ]);
    notifyListeners();
  }

  Future<void> _saveToDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/timetable_entries.json');
      final jsonList = _entries.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Note: unable to write timetable_entries.json: $e');
    }
  }

  Future<void> addEntry(TimetableEntry entry) async {
    _entries.add(entry);
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> addEntries(List<TimetableEntry> newEntries,
      {bool saveToDisk = true}) async {
    _entries.addAll(newEntries);
    notifyListeners();
    if (saveToDisk) {
      await _saveToDisk();
    }
  }

  Future<void> replaceEntries(List<TimetableEntry> newEntries,
      {bool saveToDisk = true}) async {
    _entries.clear();
    _entries.addAll(newEntries);
    notifyListeners();
    if (saveToDisk) {
      await _saveToDisk();
    }
  }

  /// Counts how many classes in [candidates] match existing classes by day, time, and subject.
  int findDuplicateCount(List<TimetableEntry> candidates) {
    int count = 0;
    for (final candidate in candidates) {
      final isDuplicate = _entries.any((existing) =>
          _normalizeDay(existing.dayOfWeek) ==
              _normalizeDay(candidate.dayOfWeek) &&
          existing.startTime.trim().toUpperCase() ==
              candidate.startTime.trim().toUpperCase() &&
          existing.subject.trim().toLowerCase() ==
              candidate.subject.trim().toLowerCase());
      if (isDuplicate) count++;
    }
    return count;
  }

  Future<void> updateEntry(TimetableEntry updated) async {
    final idx = _entries.indexWhere((e) => e.id == updated.id);
    if (idx != -1) {
      _entries[idx] = updated;
      notifyListeners();
      await _saveToDisk();
    }
  }

  Future<void> deleteEntry(String id) async {
    _entries.removeWhere((e) => e.id == id);
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> resetToDefaultSeed({bool saveToDisk = true}) async {
    _populateSeedEntries();
    if (saveToDisk) {
      await _saveToDisk();
    }
  }

  Future<void> clearAll({bool saveToDisk = true}) async {
    _entries.clear();
    notifyListeners();
    if (saveToDisk) {
      await _saveToDisk();
    }
  }

  List<TimetableEntry> getEntriesForDay(String day) {
    final normalized = _normalizeDay(day);
    final dayEntries = _entries.where((e) {
      return _normalizeDay(e.dayOfWeek) == normalized;
    }).toList();

    dayEntries.sort((a, b) => a.startHourDouble.compareTo(b.startHourDouble));
    return dayEntries;
  }

  List<String> getRecentSubjects() {
    final subjects = <String>{};
    for (final e in _entries) {
      if (e.subject.trim().isNotEmpty) {
        subjects.add(e.subject.trim());
      }
    }
    for (final s in suggestedSubjects) {
      subjects.add(s);
    }
    return subjects.take(6).toList();
  }

  // Future Pal Copilot Architectural Query Helpers
  String getTodayDayOfWeek() {
    final weekday = DateTime.now().weekday;
    return _weekdayMap[weekday] ?? 'Mon';
  }

  List<TimetableEntry> getTodayClasses() {
    return getEntriesForDay(getTodayDayOfWeek());
  }

  TimetableEntry? getCurrentClass() {
    final now = DateTime.now();
    final today = getTodayDayOfWeek();
    final currentHourDouble = now.hour + (now.minute / 60.0);

    for (final entry in getEntriesForDay(today)) {
      if (currentHourDouble >= entry.startHourDouble &&
          currentHourDouble <= entry.endHourDouble) {
        return entry;
      }
    }
    return null;
  }

  TimetableEntry? getNextClass() {
    final now = DateTime.now();
    final today = getTodayDayOfWeek();
    final currentHourDouble = now.hour + (now.minute / 60.0);

    for (final entry in getEntriesForDay(today)) {
      if (entry.startHourDouble > currentHourDouble) {
        return entry;
      }
    }
    return null;
  }

  static String _normalizeDay(String day) {
    final clean = day.trim().toLowerCase();
    if (clean.startsWith('mon')) return 'Mon';
    if (clean.startsWith('tue')) return 'Tue';
    if (clean.startsWith('wed')) return 'Wed';
    if (clean.startsWith('thu')) return 'Thu';
    if (clean.startsWith('fri')) return 'Fri';
    if (clean.startsWith('sat')) return 'Sat';
    if (clean.startsWith('sun')) return 'Sun';
    return day;
  }
}
