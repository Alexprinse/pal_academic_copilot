import 'package:flutter/material.dart';
import '../models/parsed_timetable_entry.dart';
import '../models/timetable_ocr_item.dart';

class ParsedTimetableResult {
  final List<ParsedTimetableEntry> entries;
  final String layoutDescription;
  final List<TimetableOcrItem> dayHeaders;
  final List<TimetableOcrItem> timeHeaders;
  final List<TimetableOcrItem> contentItems;
  final List<Rect> cellRects;

  const ParsedTimetableResult({
    required this.entries,
    required this.layoutDescription,
    required this.dayHeaders,
    required this.timeHeaders,
    required this.contentItems,
    required this.cellRects,
  });
}

class _DayHeaderMatch {
  final String dayCode; // 'Mon', 'Tue', etc.
  final TimetableOcrItem item;
  _DayHeaderMatch(this.dayCode, this.item);
}

class _TimeHeaderMatch {
  final String startTime;
  String endTime;
  final String rawLabel;
  final bool isInferredFromPeriod;
  final bool hasExplicitEndTime;
  final TimetableOcrItem item;

  _TimeHeaderMatch({
    required this.startTime,
    required this.endTime,
    required this.rawLabel,
    required this.isInferredFromPeriod,
    this.hasExplicitEndTime = false,
    required this.item,
  });
}

class TimetableParser {
  static const List<String> standardDays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static final Map<String, String> _dayRegexMap = {
    'Mon': r'\b(mon|monday|m0n)\b',
    'Tue': r'\b(tue|tues|tuesday|tu)\b',
    'Wed': r'\b(wed|weds|wednesday|w3d)\b',
    'Thu': r'\b(thu|thur|thurs|thursday)\b',
    'Fri': r'\b(fri|friday)\b',
    'Sat': r'\b(sat|saturday)\b',
    'Sun': r'\b(sun|sunday)\b',
  };

  static final Map<String, List<String>> _periodTimeSlots = {
    'I': ['09:00 AM', '10:00 AM'],
    '1': ['09:00 AM', '10:00 AM'],
    'P1': ['09:00 AM', '10:00 AM'],
    'II': ['10:00 AM', '11:00 AM'],
    '2': ['10:00 AM', '11:00 AM'],
    'P2': ['10:00 AM', '11:00 AM'],
    'III': ['11:15 AM', '12:15 PM'],
    '3': ['11:15 AM', '12:15 PM'],
    'P3': ['11:15 AM', '12:15 PM'],
    'IV': ['12:15 PM', '01:15 PM'],
    '4': ['12:15 PM', '01:15 PM'],
    'P4': ['12:15 PM', '01:15 PM'],
    'V': ['02:00 PM', '03:00 PM'],
    '5': ['02:00 PM', '03:00 PM'],
    'P5': ['02:00 PM', '03:00 PM'],
    'VI': ['03:00 PM', '04:00 PM'],
    '6': ['03:00 PM', '04:00 PM'],
    'P6': ['03:00 PM', '04:00 PM'],
    'VII': ['04:00 PM', '05:00 PM'],
    '7': ['04:00 PM', '05:00 PM'],
    'P7': ['04:00 PM', '05:00 PM'],
    'VIII': ['05:00 PM', '06:00 PM'],
    '8': ['05:00 PM', '06:00 PM'],
    'P8': ['05:00 PM', '06:00 PM'],
  };

  /// Parses spatial OCR items and reconstructs the structured timetable.
  ParsedTimetableResult parse(List<TimetableOcrItem> rawItems) {
    debugPrint(
        '[TIMETABLE PARSER] Starting spatial analysis with ${rawItems.length} items');

    // 1. Detect Day Headers
    final List<_DayHeaderMatch> detectedDays = [];
    final Set<TimetableOcrItem> consumedItems = {};

    for (final item in rawItems) {
      final day = _matchDay(item.text);
      if (day != null) {
        detectedDays.add(_DayHeaderMatch(day, item));
        consumedItems.add(item);
      }
    }

    debugPrint(
        '[TIMETABLE PARSER] Detected ${detectedDays.length} day headers');

    // 2. Detect Time / Period Headers from remaining items
    final List<_TimeHeaderMatch> detectedTimes = [];
    for (final item in rawItems) {
      if (consumedItems.contains(item)) continue;
      final timeMatch = _matchTimeOrPeriod(item);
      if (timeMatch != null) {
        detectedTimes.add(timeMatch);
        consumedItems.add(item);
      }
    }

    debugPrint(
        '[TIMETABLE PARSER] Detected ${detectedTimes.length} time/period headers');

    // Filter remaining items as candidate cell content
    final List<TimetableOcrItem> contentItems =
        rawItems.where((item) => !consumedItems.contains(item)).toList();

    // 3. Determine Layout / Orientation
    bool isAgendaList = false;
    if (detectedDays.length >= 2 && detectedTimes.isNotEmpty) {
      final sortedDays = List<_DayHeaderMatch>.from(detectedDays)
        ..sort((a, b) => a.item.top.compareTo(b.item.top));
      final sortedTimes = List<_TimeHeaderMatch>.from(detectedTimes)
        ..sort((a, b) => a.item.top.compareTo(b.item.top));

      final firstDay = sortedDays.first;
      final lastDay = sortedDays.last;
      final firstTime = sortedTimes.first;

      // If the first time header starts after the first day header and before the last day header,
      // days and times are interleaved vertically down the page (Agenda List / Format B).
      if (firstTime.item.top >= firstDay.item.bottom &&
          firstTime.item.top <= lastDay.item.top) {
        isAgendaList = true;
      }
    }

    final ParsedTimetableResult result;
    if (isAgendaList) {
      debugPrint(
          '[TIMETABLE PARSER] Orientation detected: Day Agenda List (Format B)');
      result = _parseDayAgendaList(
        detectedDays: detectedDays,
        detectedTimes: detectedTimes,
        contentItems: contentItems,
      );
    } else if (detectedDays.isNotEmpty && detectedTimes.isNotEmpty) {
      final bool isDaysColumns = _isDaysAsColumns(detectedDays, detectedTimes);
      debugPrint(
        '[TIMETABLE PARSER] Orientation detected: ${isDaysColumns ? "Days as Columns (Standard)" : "Days as Rows (Transposed)"}',
      );
      result = _parseGrid(
        detectedDays: detectedDays,
        detectedTimes: detectedTimes,
        contentItems: contentItems,
        isDaysColumns: isDaysColumns,
      );
    } else if (detectedDays.isNotEmpty) {
      result = _parseDayAgendaList(
        detectedDays: detectedDays,
        detectedTimes: detectedTimes,
        contentItems: contentItems,
      );
    } else {
      // Could not detect day headers reliably
      result = _parseGenericList(rawItems);
    }

    final adjustedEntries = _recalculateSequentialEndTimes(result.entries);

    return ParsedTimetableResult(
      entries: adjustedEntries,
      layoutDescription: result.layoutDescription,
      dayHeaders: result.dayHeaders,
      timeHeaders: result.timeHeaders,
      contentItems: result.contentItems,
      cellRects: result.cellRects,
    );
  }

  /// Match Day header text
  String? _matchDay(String text) {
    final clean =
        text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final entry in _dayRegexMap.entries) {
      if (RegExp(entry.value, caseSensitive: false).hasMatch(clean)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Match time range, single time, or period numeral
  _TimeHeaderMatch? _matchTimeOrPeriod(TimetableOcrItem item) {
    final raw = item.text.trim();
    final clean = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    // 1. Explicit Time Range (e.g. "09:00 - 10:00", "9:00-10:00", "09.00-10.00", "9-10", "9am - 10am")
    final rangeRegex = RegExp(
      r'(\d{1,2})[:.]?(\d{2})?\s*(am|pm)?\s*(?:-|to|–)\s*(\d{1,2})[:.]?(\d{2})?\s*(am|pm)?',
      caseSensitive: false,
    );
    final rangeMatch = rangeRegex.firstMatch(clean);
    if (rangeMatch != null) {
      final startH = int.parse(rangeMatch.group(1)!);
      final startM =
          rangeMatch.group(2) != null ? int.parse(rangeMatch.group(2)!) : 0;
      final startAmPm = rangeMatch.group(3);

      final endH = int.parse(rangeMatch.group(4)!);
      final endM =
          rangeMatch.group(5) != null ? int.parse(rangeMatch.group(5)!) : 0;
      final endAmPm = rangeMatch.group(6);

      final startFormatted = _formatTime(startH, startM, startAmPm ?? endAmPm);
      final endFormatted = _formatTime(endH, endM, endAmPm ?? startAmPm);

      return _TimeHeaderMatch(
        startTime: startFormatted,
        endTime: endFormatted,
        rawLabel: raw,
        isInferredFromPeriod: false,
        hasExplicitEndTime: true,
        item: item,
      );
    }

    // 2. Single Time (e.g. "09:00", "9:00", "09.00", "9 AM", "14:00")
    final singleRegex = RegExp(
      r'\b(\d{1,2})[:.](\d{2})\s*(am|pm)?\b',
      caseSensitive: false,
    );
    final singleMatch = singleRegex.firstMatch(clean);
    if (singleMatch != null) {
      final hour = int.parse(singleMatch.group(1)!);
      final minute = int.parse(singleMatch.group(2)!);
      final amPm = singleMatch.group(3);

      final startFormatted = _formatTime(hour, minute, amPm);
      final endFormatted = _formatTime(hour + 1, minute, amPm);

      return _TimeHeaderMatch(
        startTime: startFormatted,
        endTime: endFormatted,
        rawLabel: raw,
        isInferredFromPeriod: false,
        hasExplicitEndTime: false,
        item: item,
      );
    }

    // 3. Period Header (e.g. "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "Period 1", "P1")
    final periodToken = clean
        .replaceAll(RegExp(r'period\s*|\bno\.?\s*'), '')
        .trim()
        .toUpperCase();
    if (_periodTimeSlots.containsKey(periodToken)) {
      final slot = _periodTimeSlots[periodToken]!;
      return _TimeHeaderMatch(
        startTime: slot[0],
        endTime: slot[1],
        rawLabel: raw,
        isInferredFromPeriod: true,
        hasExplicitEndTime: false,
        item: item,
      );
    }

    return null;
  }

  String _formatTime(int hour, int minute, String? amPmHint) {
    var h = hour;
    String meridian = 'AM';

    if (amPmHint != null) {
      meridian = amPmHint.toUpperCase();
      if (h > 12) h -= 12;
    } else {
      if (h >= 12) {
        meridian = 'PM';
        if (h > 12) h -= 12;
      } else if (h < 8 && h > 0) {
        // College classes 1 to 7 are usually afternoon PM
        meridian = 'PM';
      }
    }
    final hStr = h.toString().padLeft(2, '0');
    final mStr = minute.toString().padLeft(2, '0');
    return '$hStr:$mStr $meridian';
  }

  /// Determines whether Day headers form columns (horizontal layout) or rows (vertical layout).
  bool _isDaysAsColumns(
      List<_DayHeaderMatch> days, List<_TimeHeaderMatch> times) {
    if (days.length < 2) {
      // If only 1 day is detected, inspect times orientation
      if (times.length >= 2) {
        final timesYDiff =
            (times.last.item.center.dy - times.first.item.center.dy).abs();
        final timesXDiff =
            (times.last.item.center.dx - times.first.item.center.dx).abs();
        return timesYDiff > timesXDiff;
      }
      return true;
    }

    // Measure variance/spread of day centers along X vs Y
    double minX = days.first.item.center.dx;
    double maxX = days.first.item.center.dx;
    double minY = days.first.item.center.dy;
    double maxY = days.first.item.center.dy;

    for (final d in days) {
      minX = d.item.center.dx < minX ? d.item.center.dx : minX;
      maxX = d.item.center.dx > maxX ? d.item.center.dx : maxX;
      minY = d.item.center.dy < minY ? d.item.center.dy : minY;
      maxY = d.item.center.dy > maxY ? d.item.center.dy : maxY;
    }

    final spreadX = maxX - minX;
    final spreadY = maxY - minY;

    return spreadX >= spreadY;
  }

  /// Standard or Transposed 2D Grid Reconstruction
  ParsedTimetableResult _parseGrid({
    required List<_DayHeaderMatch> detectedDays,
    required List<_TimeHeaderMatch> detectedTimes,
    required List<TimetableOcrItem> contentItems,
    required bool isDaysColumns,
  }) {
    final List<ParsedTimetableEntry> entries = [];
    final List<Rect> cellRects = [];

    if (isDaysColumns) {
      // Sort days by X (left to right)
      detectedDays.sort((a, b) => a.item.center.dx.compareTo(b.item.center.dx));
      // Sort times by Y (top to bottom)
      detectedTimes
          .sort((a, b) => a.item.center.dy.compareTo(b.item.center.dy));

      for (int t = 0; t < detectedTimes.length - 1; t++) {
        if (!detectedTimes[t].hasExplicitEndTime) {
          final curM = _timeStringToMinutes(detectedTimes[t].startTime);
          final nextM = _timeStringToMinutes(detectedTimes[t + 1].startTime);
          if (nextM > curM && (nextM - curM) <= 180) {
            detectedTimes[t].endTime = detectedTimes[t + 1].startTime;
          }
        }
      }
      if (detectedTimes.length >= 2 && !detectedTimes.last.hasExplicitEndTime) {
        final prevM = _timeStringToMinutes(
            detectedTimes[detectedTimes.length - 2].startTime);
        final prevEndM = _timeStringToMinutes(
            detectedTimes[detectedTimes.length - 2].endTime);
        final prevDur = prevEndM - prevM;
        if (prevDur >= 15 && prevDur <= 120) {
          final lastStartM = _timeStringToMinutes(detectedTimes.last.startTime);
          detectedTimes.last.endTime =
              _minutesToTimeString(lastStartM + prevDur);
        }
      }

      // Build column intervals for Days
      final List<_Interval> colIntervals = _buildIntervals(
        detectedDays.map((d) => d.item.center.dx).toList(),
      );

      // Build row intervals for Times
      final List<_Interval> rowIntervals = _buildIntervals(
        detectedTimes.map((t) => t.item.center.dy).toList(),
      );

      // Group content items into [colIdx][rowIdx]
      final Map<String, List<TimetableOcrItem>> cells = {};

      for (final item in contentItems) {
        final colIdx = _findIntervalIndex(item.center.dx, colIntervals);
        final rowIdx = _findIntervalIndex(item.center.dy, rowIntervals);

        if (colIdx != -1 && rowIdx != -1) {
          final key = '$colIdx:$rowIdx';
          cells.putIfAbsent(key, () => []).add(item);
        }
      }

      // Convert each non-empty cell into a class entry
      for (int c = 0; c < detectedDays.length; c++) {
        for (int r = 0; r < detectedTimes.length; r++) {
          final key = '$c:$r';
          final cellItems = cells[key];
          if (cellItems == null || cellItems.isEmpty) continue;

          // Compute cell bounding box
          final cellRect = _computeBoundingBox(cellItems);
          cellRects.add(cellRect);

          final day = detectedDays[c].dayCode;
          final time = detectedTimes[r];

          final entry = _createEntryFromCell(
            items: cellItems,
            dayOfWeek: day,
            startTime: time.startTime,
            endTime: time.endTime,
            isInferredFromPeriod: time.isInferredFromPeriod,
            hasExplicitEndTime: time.hasExplicitEndTime,
            periodLabel: time.rawLabel,
            sourceBoundingBox: cellRect,
          );

          if (entry != null) {
            entries.add(entry);
          }
        }
      }

      return ParsedTimetableResult(
        entries: entries,
        layoutDescription:
            'Grid: Days as Columns, Times as Rows (${detectedDays.length} days × ${detectedTimes.length} times)',
        dayHeaders: detectedDays.map((d) => d.item).toList(),
        timeHeaders: detectedTimes.map((t) => t.item).toList(),
        contentItems: contentItems,
        cellRects: cellRects,
      );
    } else {
      // Transposed: Times are Columns (sorted by X), Days are Rows (sorted by Y)
      detectedTimes
          .sort((a, b) => a.item.center.dx.compareTo(b.item.center.dx));
      detectedDays.sort((a, b) => a.item.center.dy.compareTo(b.item.center.dy));

      for (int t = 0; t < detectedTimes.length - 1; t++) {
        if (!detectedTimes[t].hasExplicitEndTime) {
          final curM = _timeStringToMinutes(detectedTimes[t].startTime);
          final nextM = _timeStringToMinutes(detectedTimes[t + 1].startTime);
          if (nextM > curM && (nextM - curM) <= 180) {
            detectedTimes[t].endTime = detectedTimes[t + 1].startTime;
          }
        }
      }
      if (detectedTimes.length >= 2 && !detectedTimes.last.hasExplicitEndTime) {
        final prevM = _timeStringToMinutes(
            detectedTimes[detectedTimes.length - 2].startTime);
        final prevEndM = _timeStringToMinutes(
            detectedTimes[detectedTimes.length - 2].endTime);
        final prevDur = prevEndM - prevM;
        if (prevDur >= 15 && prevDur <= 120) {
          final lastStartM = _timeStringToMinutes(detectedTimes.last.startTime);
          detectedTimes.last.endTime =
              _minutesToTimeString(lastStartM + prevDur);
        }
      }

      final List<_Interval> colIntervals = _buildIntervals(
        detectedTimes.map((t) => t.item.center.dx).toList(),
      );
      final List<_Interval> rowIntervals = _buildIntervals(
        detectedDays.map((d) => d.item.center.dy).toList(),
      );

      final Map<String, List<TimetableOcrItem>> cells = {};

      for (final item in contentItems) {
        final colIdx = _findIntervalIndex(item.center.dx, colIntervals);
        final rowIdx = _findIntervalIndex(item.center.dy, rowIntervals);

        if (colIdx != -1 && rowIdx != -1) {
          final key = '$colIdx:$rowIdx';
          cells.putIfAbsent(key, () => []).add(item);
        }
      }

      for (int c = 0; c < detectedTimes.length; c++) {
        for (int r = 0; r < detectedDays.length; r++) {
          final key = '$c:$r';
          final cellItems = cells[key];
          if (cellItems == null || cellItems.isEmpty) continue;

          final cellRect = _computeBoundingBox(cellItems);
          cellRects.add(cellRect);

          final day = detectedDays[r].dayCode;
          final time = detectedTimes[c];

          final entry = _createEntryFromCell(
            items: cellItems,
            dayOfWeek: day,
            startTime: time.startTime,
            endTime: time.endTime,
            isInferredFromPeriod: time.isInferredFromPeriod,
            hasExplicitEndTime: time.hasExplicitEndTime,
            periodLabel: time.rawLabel,
            sourceBoundingBox: cellRect,
          );

          if (entry != null) {
            entries.add(entry);
          }
        }
      }

      return ParsedTimetableResult(
        entries: entries,
        layoutDescription:
            'Grid: Times as Columns, Days as Rows (${detectedDays.length} days × ${detectedTimes.length} times)',
        dayHeaders: detectedDays.map((d) => d.item).toList(),
        timeHeaders: detectedTimes.map((t) => t.item).toList(),
        contentItems: contentItems,
        cellRects: cellRects,
      );
    }
  }

  /// Builds continuous coordinate intervals from a sorted list of center coordinates.
  List<_Interval> _buildIntervals(List<double> centers) {
    final List<_Interval> intervals = [];
    if (centers.isEmpty) return intervals;
    if (centers.length == 1) {
      intervals.add(_Interval(0, double.infinity));
      return intervals;
    }

    final avgGap = (centers.last - centers.first) / (centers.length - 1);

    for (int i = 0; i < centers.length; i++) {
      final left =
          i == 0 ? centers[0] - avgGap / 2 : (centers[i - 1] + centers[i]) / 2;
      final right = i == centers.length - 1
          ? centers[centers.length - 1] + avgGap / 2
          : (centers[i] + centers[i + 1]) / 2;
      intervals.add(_Interval(left, right));
    }
    return intervals;
  }

  int _findIntervalIndex(double coord, List<_Interval> intervals) {
    for (int i = 0; i < intervals.length; i++) {
      if (coord >= intervals[i].start && coord <= intervals[i].end) {
        return i;
      }
    }
    return -1;
  }

  /// Parses items clustered under day agenda lists (Format B)
  ParsedTimetableResult _parseDayAgendaList({
    required List<_DayHeaderMatch> detectedDays,
    required List<_TimeHeaderMatch> detectedTimes,
    required List<TimetableOcrItem> contentItems,
  }) {
    detectedDays.sort((a, b) => a.item.top.compareTo(b.item.top));
    final List<ParsedTimetableEntry> entries = [];
    final List<Rect> cellRects = [];

    for (int i = 0; i < detectedDays.length; i++) {
      final currentDay = detectedDays[i];
      final nextDayTop = i < detectedDays.length - 1
          ? detectedDays[i + 1].item.top
          : double.infinity;

      // Find all times belonging to this day's section
      final timesInDay = detectedTimes
          .where((t) =>
              t.item.top >= currentDay.item.bottom && t.item.top < nextDayTop)
          .toList()
        ..sort((a, b) => a.item.top.compareTo(b.item.top));

      for (int t = 0; t < timesInDay.length - 1; t++) {
        if (!timesInDay[t].hasExplicitEndTime) {
          final curM = _timeStringToMinutes(timesInDay[t].startTime);
          final nextM = _timeStringToMinutes(timesInDay[t + 1].startTime);
          if (nextM > curM && (nextM - curM) <= 180) {
            timesInDay[t].endTime = timesInDay[t + 1].startTime;
          }
        }
      }
      if (timesInDay.length >= 2 && !timesInDay.last.hasExplicitEndTime) {
        final prevM =
            _timeStringToMinutes(timesInDay[timesInDay.length - 2].startTime);
        final prevEndM =
            _timeStringToMinutes(timesInDay[timesInDay.length - 2].endTime);
        final prevDur = prevEndM - prevM;
        if (prevDur >= 15 && prevDur <= 120) {
          final lastStartM = _timeStringToMinutes(timesInDay.last.startTime);
          timesInDay.last.endTime = _minutesToTimeString(lastStartM + prevDur);
        }
      }

      for (int t = 0; t < timesInDay.length; t++) {
        final timeMatch = timesInDay[t];
        final nextTimeTop =
            t < timesInDay.length - 1 ? timesInDay[t + 1].item.top : nextDayTop;

        // Content items belonging to this time:
        // Either on the same horizontal line or below this time before the next time header
        final cellContent = contentItems.where((c) {
          final isSameLine = (c.center.dy - timeMatch.item.center.dy).abs() <
                  (timeMatch.item.height * 1.5) &&
              c.left >= (timeMatch.item.right - 10);
          final isBelowBeforeNext =
              c.top >= timeMatch.item.bottom && c.top < nextTimeTop;
          return isSameLine || isBelowBeforeNext;
        }).toList()
          ..sort((a, b) => a.top.compareTo(b.top));

        if (cellContent.isNotEmpty) {
          final rect = _computeBoundingBox([timeMatch.item, ...cellContent]);
          cellRects.add(rect);

          final entry = _createEntryFromCell(
            items: cellContent,
            dayOfWeek: currentDay.dayCode,
            startTime: timeMatch.startTime,
            endTime: timeMatch.endTime,
            isInferredFromPeriod: timeMatch.isInferredFromPeriod,
            hasExplicitEndTime: timeMatch.hasExplicitEndTime,
            periodLabel: timeMatch.rawLabel,
            sourceBoundingBox: rect,
          );

          if (entry != null) entries.add(entry);
        }
      }
    }

    return ParsedTimetableResult(
      entries: entries,
      layoutDescription:
          'Day Agenda List (${detectedDays.length} days detected)',
      dayHeaders: detectedDays.map((d) => d.item).toList(),
      timeHeaders: detectedTimes.map((t) => t.item).toList(),
      contentItems: contentItems,
      cellRects: cellRects,
    );
  }

  /// Fallback when no day headers could be detected
  ParsedTimetableResult _parseGenericList(List<TimetableOcrItem> items) {
    debugPrint(
        '[TIMETABLE PARSER] No day headers identified. Creating unassigned candidate list.');
    final List<ParsedTimetableEntry> entries = [];
    final List<Rect> cellRects = [];

    for (final item in items) {
      final text = item.text.trim();
      if (text.length < 3) continue;

      cellRects.add(item.boundingBox);
      entries.add(
        ParsedTimetableEntry(
          id: 'imported_${DateTime.now().millisecondsSinceEpoch}_${entries.length}',
          subject: text,
          dayOfWeek: 'Mon',
          startTime: '09:00 AM',
          endTime: '10:00 AM',
          type: 'Lecture',
          confidence: 0.4,
          requiresReview: true,
          reviewReason: 'Day and time could not be determined automatically.',
          sourceBoundingBox: item.boundingBox,
        ),
      );
    }

    return ParsedTimetableResult(
      entries: entries,
      layoutDescription: 'Unstructured Text List (Requires review)',
      dayHeaders: [],
      timeHeaders: [],
      contentItems: items,
      cellRects: cellRects,
    );
  }

  /// Extracts Subject, Room, Professor, and Type from a group of cell items
  ParsedTimetableEntry? _createEntryFromCell({
    required List<TimetableOcrItem> items,
    required String dayOfWeek,
    required String startTime,
    required String endTime,
    required bool isInferredFromPeriod,
    bool hasExplicitEndTime = false,
    required String periodLabel,
    required Rect sourceBoundingBox,
  }) {
    // Sort items vertically within cell
    items.sort((a, b) => a.top.compareTo(b.top));

    final rawLines =
        items.map((i) => i.text.trim()).where((t) => t.isNotEmpty).toList();

    if (rawLines.isEmpty) return null;

    String? room;
    String? professor;
    String type = 'Lecture';
    final List<String> subjectParts = [];

    final roomPattern = RegExp(
      r'\b(room|rm|lab|cr|lh|hall)\s*[-:]?\s*([a-z0-9]+)|\b[a-z]?-\d{2,4}\b|\b\d{3}\b',
      caseSensitive: false,
    );
    final profPattern = RegExp(
      r'\b(prof|dr|mr|mrs|ms)\.?\s+([a-z]+)|\bfaculty:\s*([a-z\s]+)',
      caseSensitive: false,
    );

    for (final line in rawLines) {
      final clean =
          line.replaceAll(RegExp(r'^[|\-_~*.]+|[|\-_~*.]+$'), '').trim();
      if (clean.isEmpty) continue;

      if (clean.toLowerCase().contains('lab') ||
          clean.toLowerCase().contains('laboratory')) {
        type = 'Lab';
      } else if (clean.toLowerCase().contains('tut') ||
          clean.toLowerCase().contains('tutorial')) {
        type = 'Tutorial';
      }

      if (roomPattern.hasMatch(clean)) {
        room = clean;
      } else if (profPattern.hasMatch(clean)) {
        professor = clean;
      } else {
        // Exclude pure punctuation or table borders
        if (!RegExp(r'^[\W_]+$').hasMatch(clean)) {
          subjectParts.add(clean);
        }
      }
    }

    if (subjectParts.isEmpty) {
      if (room != null) {
        subjectParts.add('Class in $room');
      } else {
        return null;
      }
    }

    final subject = subjectParts.join(' ');
    if (subject.length < 2) return null;

    bool requiresReview = false;
    String? reviewReason;

    if (isInferredFromPeriod) {
      requiresReview = true;
      reviewReason = 'Time inferred from $periodLabel. Please verify.';
    } else if (subject.length < 3 ||
        RegExp(r'[^a-zA-Z0-9\s&/-]').hasMatch(subject)) {
      requiresReview = true;
      reviewReason = 'Subject name may contain OCR noise. Please check.';
    }

    final double confidence = requiresReview ? 0.65 : 0.92;

    return ParsedTimetableEntry(
      id: 'imported_${DateTime.now().millisecondsSinceEpoch}_${subject.hashCode.abs()}',
      subject: subject,
      dayOfWeek: dayOfWeek,
      startTime: startTime,
      endTime: endTime,
      room: room,
      professor: professor,
      type: type,
      confidence: confidence,
      requiresReview: requiresReview,
      reviewReason: reviewReason,
      hasExplicitEndTime: hasExplicitEndTime,
      sourceBoundingBox: sourceBoundingBox,
    );
  }

  Rect _computeBoundingBox(List<TimetableOcrItem> items) {
    if (items.isEmpty) return Rect.zero;
    double left = items.first.left;
    double top = items.first.top;
    double right = items.first.right;
    double bottom = items.first.bottom;

    for (final item in items) {
      if (item.left < left) left = item.left;
      if (item.top < top) top = item.top;
      if (item.right > right) right = item.right;
      if (item.bottom > bottom) bottom = item.bottom;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Recalculates end times for consecutive periods within each day
  /// when the end time was not explicitly specified in the image.
  List<ParsedTimetableEntry> _recalculateSequentialEndTimes(
      List<ParsedTimetableEntry> entries) {
    if (entries.isEmpty) return entries;

    // Group entries by dayOfWeek
    final Map<String, List<ParsedTimetableEntry>> byDay = {};
    for (final entry in entries) {
      byDay.putIfAbsent(entry.dayOfWeek, () => []).add(entry);
    }

    final List<ParsedTimetableEntry> adjustedEntries = [];

    for (final dayEntries in byDay.values) {
      // Sort chronologically by start time
      dayEntries.sort((a, b) {
        final aMins = _timeStringToMinutes(a.startTime);
        final bMins = _timeStringToMinutes(b.startTime);
        return aMins.compareTo(bMins);
      });

      int lastComputedDuration = 0;

      for (int i = 0; i < dayEntries.length; i++) {
        final current = dayEntries[i];
        if (current.hasExplicitEndTime) {
          final startM = _timeStringToMinutes(current.startTime);
          final endM = _timeStringToMinutes(current.endTime);
          if (endM > startM) {
            lastComputedDuration = endM - startM;
          }
          adjustedEntries.add(current);
          continue;
        }

        final currStartMins = _timeStringToMinutes(current.startTime);

        // Look for the next class in the same day with a strictly later start time
        String? nextStartTime;
        int? nextStartMins;
        for (int j = i + 1; j < dayEntries.length; j++) {
          final candidateMins = _timeStringToMinutes(dayEntries[j].startTime);
          if (candidateMins > currStartMins) {
            nextStartMins = candidateMins;
            nextStartTime = dayEntries[j].startTime;
            break;
          }
        }

        if (nextStartTime != null && nextStartMins != null) {
          final diff = nextStartMins - currStartMins;
          // Valid period length: between 5 minutes and 3 hours (180 minutes)
          if (diff >= 5 && diff <= 180) {
            current.endTime = nextStartTime;
            lastComputedDuration = diff;
          }
        } else if (lastComputedDuration >= 15 && lastComputedDuration <= 120) {
          // For the final class of the day, maintain the duration of previous periods
          current.endTime =
              _minutesToTimeString(currStartMins + lastComputedDuration);
        }

        adjustedEntries.add(current);
      }
    }

    return adjustedEntries;
  }

  static int _timeStringToMinutes(String timeStr) {
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPm = clean.contains('PM');
      final isAm = clean.contains('AM');

      final parts = clean.replaceAll(RegExp(r'[^\d:]'), '').split(':');
      int hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? int.parse(parts[1]) : 0;

      if (isPm && hour < 12) hour += 12;
      if (isAm && hour == 12) hour = 0;

      return hour * 60 + minute;
    } catch (_) {
      return 9 * 60;
    }
  }

  static String _minutesToTimeString(int totalMinutes) {
    int normMinutes = totalMinutes % (24 * 60);
    int hour = normMinutes ~/ 60;
    final minute = normMinutes % 60;
    String meridian = 'AM';

    if (hour >= 12) {
      meridian = 'PM';
      if (hour > 12) hour -= 12;
    } else if (hour == 0) {
      hour = 12;
    }

    final hStr = hour.toString().padLeft(2, '0');
    final mStr = minute.toString().padLeft(2, '0');
    return '$hStr:$mStr $meridian';
  }
}

class _Interval {
  final double start;
  final double end;
  _Interval(this.start, this.end);
}
