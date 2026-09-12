import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/timetable_entry.dart';
import 'package:pal_academic_copilot/models/timetable_ocr_item.dart';
import 'package:pal_academic_copilot/services/timetable_parser.dart';
import 'package:pal_academic_copilot/services/timetable_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('TimetableParser Spatial Reconstruction Tests', () {
    late TimetableParser parser;

    setUp(() {
      parser = TimetableParser();
    });

    test('1. Standard Monday-Friday grid with explicit time ranges', () {
      final items = <TimetableOcrItem>[
        // Day column headers (y = 50, x spaced horizontally)
        const TimetableOcrItem(
            text: 'MON', boundingBox: Rect.fromLTWH(100, 40, 80, 20)),
        const TimetableOcrItem(
            text: 'TUE', boundingBox: Rect.fromLTWH(200, 40, 80, 20)),
        const TimetableOcrItem(
            text: 'WED', boundingBox: Rect.fromLTWH(300, 40, 80, 20)),
        const TimetableOcrItem(
            text: 'THU', boundingBox: Rect.fromLTWH(400, 40, 80, 20)),
        const TimetableOcrItem(
            text: 'FRI', boundingBox: Rect.fromLTWH(500, 40, 80, 20)),

        // Time row headers (x = 20, y spaced vertically)
        const TimetableOcrItem(
            text: '09:00 - 10:00', boundingBox: Rect.fromLTWH(10, 100, 80, 20)),
        const TimetableOcrItem(
            text: '10:00 - 11:00', boundingBox: Rect.fromLTWH(10, 200, 80, 20)),

        // Cell: Monday 09:00 -> Artificial Intelligence
        const TimetableOcrItem(
            text: 'Artificial Intelligence',
            boundingBox: Rect.fromLTWH(100, 100, 80, 20)),
        // Cell: Tuesday 09:00 -> Operating Systems, Room 204
        const TimetableOcrItem(
            text: 'Operating Systems',
            boundingBox: Rect.fromLTWH(200, 95, 80, 15)),
        const TimetableOcrItem(
            text: 'Room 204', boundingBox: Rect.fromLTWH(200, 115, 80, 15)),
        // Cell: Wednesday 10:00 -> Database Systems
        const TimetableOcrItem(
            text: 'Database Systems',
            boundingBox: Rect.fromLTWH(300, 200, 80, 20)),
        // Cell: Friday 10:00 -> Computer Networks Lab
        const TimetableOcrItem(
            text: 'Computer Networks Lab',
            boundingBox: Rect.fromLTWH(500, 200, 80, 20)),
      ];

      final result = parser.parse(items);

      expect(result.entries.length, 4);

      // Check Mon 09:00 AI
      final monClass = result.entries.firstWhere((e) => e.dayOfWeek == 'Mon');
      expect(monClass.subject, 'Artificial Intelligence');
      expect(monClass.startTime, '09:00 AM');
      expect(monClass.endTime, '10:00 AM');
      expect(monClass.requiresReview, isFalse);

      // Check Tue 09:00 OS Room 204
      final tueClass = result.entries.firstWhere((e) => e.dayOfWeek == 'Tue');
      expect(tueClass.subject, 'Operating Systems');
      expect(tueClass.room, 'Room 204');

      // Check Fri 10:00 Lab
      final friClass = result.entries.firstWhere((e) => e.dayOfWeek == 'Fri');
      expect(friClass.subject, 'Computer Networks Lab');
      expect(friClass.type, 'Lab');
    });

    test('2. Monday-Saturday grid with varied column spacing', () {
      final items = <TimetableOcrItem>[
        // 6 days Mon-Sat
        const TimetableOcrItem(
            text: 'Monday', boundingBox: Rect.fromLTWH(80, 30, 90, 25)),
        const TimetableOcrItem(
            text: 'Tuesday', boundingBox: Rect.fromLTWH(190, 30, 85, 25)),
        const TimetableOcrItem(
            text: 'Wednesday', boundingBox: Rect.fromLTWH(295, 30, 100, 25)),
        const TimetableOcrItem(
            text: 'Thursday', boundingBox: Rect.fromLTWH(415, 30, 90, 25)),
        const TimetableOcrItem(
            text: 'Friday', boundingBox: Rect.fromLTWH(525, 30, 85, 25)),
        const TimetableOcrItem(
            text: 'Saturday', boundingBox: Rect.fromLTWH(630, 30, 95, 25)),

        // Time row
        const TimetableOcrItem(
            text: '11:00-12:00', boundingBox: Rect.fromLTWH(10, 120, 60, 20)),

        // Saturday Class
        const TimetableOcrItem(
            text: 'Engineering Economics',
            boundingBox: Rect.fromLTWH(630, 120, 80, 20)),
      ];

      final result = parser.parse(items);
      expect(result.entries.length, 1);
      final satClass = result.entries.first;
      expect(satClass.dayOfWeek, 'Sat');
      expect(satClass.subject, 'Engineering Economics');
      expect(satClass.startTime, '11:00 AM');
      expect(satClass.endTime, '12:00 PM');
    });

    test('3. Transposed Grid: Times as Columns and Days as Rows', () {
      final items = <TimetableOcrItem>[
        // Times as column headers across X (y = 50)
        const TimetableOcrItem(
            text: '09:00 - 10:00', boundingBox: Rect.fromLTWH(150, 50, 90, 20)),
        const TimetableOcrItem(
            text: '10:00 - 11:00', boundingBox: Rect.fromLTWH(260, 50, 90, 20)),
        const TimetableOcrItem(
            text: '11:15 - 12:15', boundingBox: Rect.fromLTWH(370, 50, 90, 20)),

        // Days as row headers down Y (x = 30)
        const TimetableOcrItem(
            text: 'MON', boundingBox: Rect.fromLTWH(30, 100, 60, 25)),
        const TimetableOcrItem(
            text: 'TUE', boundingBox: Rect.fromLTWH(30, 180, 60, 25)),
        const TimetableOcrItem(
            text: 'WED', boundingBox: Rect.fromLTWH(30, 260, 60, 25)),

        // Content
        // Mon 09:00 -> Algorithms
        const TimetableOcrItem(
            text: 'Algorithms', boundingBox: Rect.fromLTWH(155, 100, 80, 20)),
        // Tue 10:00 -> Compiler Design
        const TimetableOcrItem(
            text: 'Compiler Design',
            boundingBox: Rect.fromLTWH(265, 180, 80, 20)),
      ];

      final result = parser.parse(items);
      expect(result.entries.length, 2);

      final algo = result.entries.firstWhere((e) => e.subject == 'Algorithms');
      expect(algo.dayOfWeek, 'Mon');
      expect(algo.startTime, '09:00 AM');

      final cd =
          result.entries.firstWhere((e) => e.subject == 'Compiler Design');
      expect(cd.dayOfWeek, 'Tue');
      expect(cd.startTime, '10:00 AM');
    });

    test(
        '4. Period Number Timetable (I, II, III) flags requiresReview with explanation',
        () {
      final items = <TimetableOcrItem>[
        // Days
        const TimetableOcrItem(
            text: 'Monday', boundingBox: Rect.fromLTWH(100, 40, 80, 20)),
        const TimetableOcrItem(
            text: 'Tuesday', boundingBox: Rect.fromLTWH(200, 40, 80, 20)),

        // Period numbers as rows
        const TimetableOcrItem(
            text: 'I', boundingBox: Rect.fromLTWH(20, 100, 40, 20)),
        const TimetableOcrItem(
            text: 'II', boundingBox: Rect.fromLTWH(20, 180, 40, 20)),

        // Cell
        const TimetableOcrItem(
            text: 'Discrete Mathematics',
            boundingBox: Rect.fromLTWH(100, 100, 80, 20)),
      ];

      final result = parser.parse(items);
      expect(result.entries.length, 1);

      final math = result.entries.first;
      expect(math.subject, 'Discrete Mathematics');
      expect(math.dayOfWeek, 'Mon');
      expect(math.requiresReview, isTrue);
      expect(math.reviewReason, contains('inferred from'));
    });

    test('5. 09:00 vs 9:00 single time formats are correctly formatted', () {
      final items = <TimetableOcrItem>[
        const TimetableOcrItem(
            text: 'Mon', boundingBox: Rect.fromLTWH(100, 40, 80, 20)),
        const TimetableOcrItem(
            text: '9:00', boundingBox: Rect.fromLTWH(10, 100, 60, 20)),
        const TimetableOcrItem(
            text: '14:00', boundingBox: Rect.fromLTWH(10, 200, 60, 20)),
        const TimetableOcrItem(
            text: 'Morning Class',
            boundingBox: Rect.fromLTWH(100, 100, 80, 20)),
        const TimetableOcrItem(
            text: 'Afternoon Class',
            boundingBox: Rect.fromLTWH(100, 200, 80, 20)),
      ];

      final result = parser.parse(items);
      expect(result.entries.length, 2);

      final morning =
          result.entries.firstWhere((e) => e.subject == 'Morning Class');
      expect(morning.startTime, '09:00 AM');

      final afternoon =
          result.entries.firstWhere((e) => e.subject == 'Afternoon Class');
      expect(afternoon.startTime, '02:00 PM');
    });

    test('6. Empty cells (free periods) are safely ignored', () {
      final items = <TimetableOcrItem>[
        const TimetableOcrItem(
            text: 'Mon', boundingBox: Rect.fromLTWH(100, 40, 80, 20)),
        const TimetableOcrItem(
            text: 'Tue', boundingBox: Rect.fromLTWH(200, 40, 80, 20)),

        const TimetableOcrItem(
            text: '09:00 - 10:00', boundingBox: Rect.fromLTWH(10, 100, 80, 20)),
        const TimetableOcrItem(
            text: '10:00 - 11:00', boundingBox: Rect.fromLTWH(10, 200, 80, 20)),

        // Only Mon 09:00 has content. Other 3 cells are free.
        const TimetableOcrItem(
            text: 'Machine Learning',
            boundingBox: Rect.fromLTWH(100, 100, 80, 20)),
      ];

      final result = parser.parse(items);
      expect(result.entries.length, 1);
      expect(result.entries.first.subject, 'Machine Learning');
    });

    test('7. OCR noise and table borders are filtered from subject names', () {
      final items = <TimetableOcrItem>[
        const TimetableOcrItem(
            text: 'Mon', boundingBox: Rect.fromLTWH(100, 40, 80, 20)),
        const TimetableOcrItem(
            text: '09:00 - 10:00', boundingBox: Rect.fromLTWH(10, 100, 80, 20)),

        // Content with stray border lines
        const TimetableOcrItem(
            text: '|', boundingBox: Rect.fromLTWH(95, 95, 5, 25)),
        const TimetableOcrItem(
            text: 'Computer Graphics',
            boundingBox: Rect.fromLTWH(105, 100, 80, 20)),
        const TimetableOcrItem(
            text: '---', boundingBox: Rect.fromLTWH(105, 125, 80, 5)),
      ];

      final result = parser.parse(items);
      expect(result.entries.length, 1);
      expect(result.entries.first.subject, 'Computer Graphics');
    });

    test('8. Day Agenda / List layout (Format B)', () {
      final items = <TimetableOcrItem>[
        const TimetableOcrItem(
            text: 'MONDAY', boundingBox: Rect.fromLTWH(20, 40, 120, 30)),
        const TimetableOcrItem(
            text: '09:00 - 10:00', boundingBox: Rect.fromLTWH(20, 80, 100, 20)),
        const TimetableOcrItem(
            text: 'Cyber Security',
            boundingBox: Rect.fromLTWH(130, 80, 120, 20)),
        const TimetableOcrItem(
            text: 'TUESDAY', boundingBox: Rect.fromLTWH(20, 130, 120, 30)),
        const TimetableOcrItem(
            text: '10:00 - 11:00',
            boundingBox: Rect.fromLTWH(20, 170, 100, 20)),
        const TimetableOcrItem(
            text: 'Cloud Computing',
            boundingBox: Rect.fromLTWH(130, 170, 120, 20)),
      ];

      final result = parser.parse(items);
      expect(result.entries.length, 2);

      final cs =
          result.entries.firstWhere((e) => e.subject == 'Cyber Security');
      expect(cs.dayOfWeek, 'Mon');
      expect(cs.startTime, '09:00 AM');

      final cc =
          result.entries.firstWhere((e) => e.subject == 'Cloud Computing');
      expect(cc.dayOfWeek, 'Tue');
      expect(cc.startTime, '10:00 AM');
    });

    test('9. TimetableService duplicate detection and replacement behavior',
        () async {
      final service = TimetableService.instance;
      await service.clearAll(saveToDisk: false);

      // Seed 1 class
      await service.addEntry(
        const TimetableEntry(
          id: 'test-1',
          subject: 'Operating Systems',
          dayOfWeek: 'Mon',
          startTime: '09:00 AM',
          endTime: '10:00 AM',
        ),
      );

      // Candidate 1 is duplicate, Candidate 2 is new
      final candidates = [
        const TimetableEntry(
          id: 'cand-1',
          subject: 'Operating Systems',
          dayOfWeek: 'Mon',
          startTime: '09:00 AM',
          endTime: '10:00 AM',
        ),
        const TimetableEntry(
          id: 'cand-2',
          subject: 'Data Science',
          dayOfWeek: 'Wed',
          startTime: '11:00 AM',
          endTime: '12:00 PM',
        ),
      ];

      final dupCount = service.findDuplicateCount(candidates);
      expect(dupCount, 1);

      // Test Replace
      await service.replaceEntries(candidates, saveToDisk: false);
      expect(service.entries.length, 2);
      expect(service.entries.any((e) => e.subject == 'Data Science'), isTrue);

      // Restore seed
      await service.resetToDefaultSeed(saveToDisk: false);
    });

    test(
        '10. Period-to-period end time calculation from sequential start times',
        () {
      // Simulates the exact user timetable (09:00 Books/Play -> 09:20 Circle Time -> ... -> 12:05 Music Class)
      final items = <TimetableOcrItem>[
        const TimetableOcrItem(
            text: 'MONDAY', boundingBox: Rect.fromLTWH(20, 20, 100, 30)),
        const TimetableOcrItem(
            text: '09:00', boundingBox: Rect.fromLTWH(20, 60, 60, 20)),
        const TimetableOcrItem(
            text: 'Books / Play', boundingBox: Rect.fromLTWH(100, 60, 150, 20)),
        const TimetableOcrItem(
            text: '09:20', boundingBox: Rect.fromLTWH(20, 100, 60, 20)),
        const TimetableOcrItem(
            text: 'Circle Time', boundingBox: Rect.fromLTWH(100, 100, 150, 20)),
        const TimetableOcrItem(
            text: '09:35', boundingBox: Rect.fromLTWH(20, 140, 60, 20)),
        const TimetableOcrItem(
            text: 'News Time', boundingBox: Rect.fromLTWH(100, 140, 150, 20)),
        const TimetableOcrItem(
            text: '09:55', boundingBox: Rect.fromLTWH(20, 180, 60, 20)),
        const TimetableOcrItem(
            text: 'Montessori Work',
            boundingBox: Rect.fromLTWH(100, 180, 150, 20)),
        const TimetableOcrItem(
            text: '10:55', boundingBox: Rect.fromLTWH(20, 220, 60, 20)),
        const TimetableOcrItem(
            text: 'Snack Time', boundingBox: Rect.fromLTWH(100, 220, 150, 20)),
        const TimetableOcrItem(
            text: '11:10', boundingBox: Rect.fromLTWH(20, 260, 60, 20)),
        const TimetableOcrItem(
            text: 'Garden Play', boundingBox: Rect.fromLTWH(100, 260, 150, 20)),
        const TimetableOcrItem(
            text: '11:40', boundingBox: Rect.fromLTWH(20, 300, 60, 20)),
        const TimetableOcrItem(
            text: 'Jigsaws', boundingBox: Rect.fromLTWH(100, 300, 150, 20)),
        const TimetableOcrItem(
            text: '12:05', boundingBox: Rect.fromLTWH(20, 340, 60, 20)),
        const TimetableOcrItem(
            text: 'Music Class', boundingBox: Rect.fromLTWH(100, 340, 150, 20)),
      ];

      final result = parser.parse(items);
      expect(result.entries.length, 8);

      // Period 1: 09:00 -> ends at 09:20 AM (not 10:00 AM)
      final e1 = result.entries[0];
      expect(e1.subject, 'Books / Play');
      expect(e1.startTime, '09:00 AM');
      expect(e1.endTime, '09:20 AM');

      // Period 2: 09:20 -> ends at 09:35 AM (not 10:20 AM)
      final e2 = result.entries[1];
      expect(e2.subject, 'Circle Time');
      expect(e2.startTime, '09:20 AM');
      expect(e2.endTime, '09:35 AM');

      // Period 3: 09:35 -> ends at 09:55 AM
      final e3 = result.entries[2];
      expect(e3.subject, 'News Time');
      expect(e3.startTime, '09:35 AM');
      expect(e3.endTime, '09:55 AM');

      // Period 4: 09:55 -> ends at 10:55 AM
      final e4 = result.entries[3];
      expect(e4.subject, 'Montessori Work');
      expect(e4.startTime, '09:55 AM');
      expect(e4.endTime, '10:55 AM');

      // Period 5: 10:55 -> ends at 11:10 AM
      final e5 = result.entries[4];
      expect(e5.subject, 'Snack Time');
      expect(e5.startTime, '10:55 AM');
      expect(e5.endTime, '11:10 AM');

      // Period 6: 11:10 -> ends at 11:40 AM
      final e6 = result.entries[5];
      expect(e6.subject, 'Garden Play');
      expect(e6.startTime, '11:10 AM');
      expect(e6.endTime, '11:40 AM');

      // Period 7: 11:40 -> ends at 12:05 PM
      final e7 = result.entries[6];
      expect(e7.subject, 'Jigsaws');
      expect(e7.startTime, '11:40 AM');
      expect(e7.endTime, '12:05 PM');

      // Period 8: 12:05 -> inherits duration of previous period (25 min) -> 12:30 PM (not 01:05 PM)
      final e8 = result.entries[7];
      expect(e8.subject, 'Music Class');
      expect(e8.startTime, '12:05 PM');
      expect(e8.endTime, '12:30 PM');
    });

    test(
        '11. Grid layout with single time row headers calculates sequential period end times',
        () {
      final items = <TimetableOcrItem>[
        // Days
        const TimetableOcrItem(
            text: 'MON', boundingBox: Rect.fromLTWH(100, 30, 80, 20)),
        const TimetableOcrItem(
            text: 'TUE', boundingBox: Rect.fromLTWH(200, 30, 80, 20)),

        // Single time rows (50-minute periods: 09:00, 09:50, 10:40)
        const TimetableOcrItem(
            text: '09:00', boundingBox: Rect.fromLTWH(10, 80, 70, 20)),
        const TimetableOcrItem(
            text: '09:50', boundingBox: Rect.fromLTWH(10, 150, 70, 20)),
        const TimetableOcrItem(
            text: '10:40', boundingBox: Rect.fromLTWH(10, 220, 70, 20)),

        // Classes
        const TimetableOcrItem(
            text: 'Compiler Design',
            boundingBox: Rect.fromLTWH(100, 80, 80, 20)),
        const TimetableOcrItem(
            text: 'Computer Networks',
            boundingBox: Rect.fromLTWH(100, 150, 80, 20)),
        const TimetableOcrItem(
            text: 'Software Engineering',
            boundingBox: Rect.fromLTWH(100, 220, 80, 20)),
      ];

      final result = parser.parse(items);
      expect(result.entries.length, 3);

      final cd =
          result.entries.firstWhere((e) => e.subject == 'Compiler Design');
      expect(cd.startTime, '09:00 AM');
      expect(cd.endTime, '09:50 AM');

      final cn =
          result.entries.firstWhere((e) => e.subject == 'Computer Networks');
      expect(cn.startTime, '09:50 AM');
      expect(cn.endTime, '10:40 AM');

      final se =
          result.entries.firstWhere((e) => e.subject == 'Software Engineering');
      expect(se.startTime, '10:40 AM');
      expect(se.endTime, '11:30 AM'); // 50 min inherited duration
    });

    test(
        '12. Preserves explicit time ranges with break intervals between periods',
        () {
      final items = <TimetableOcrItem>[
        const TimetableOcrItem(
            text: 'MON', boundingBox: Rect.fromLTWH(100, 30, 80, 20)),
        // Explicit ranges with a 15-minute break (09:45 to 10:00)
        const TimetableOcrItem(
            text: '09:00 - 09:45', boundingBox: Rect.fromLTWH(10, 80, 80, 20)),
        const TimetableOcrItem(
            text: '10:00 - 10:45', boundingBox: Rect.fromLTWH(10, 160, 80, 20)),

        const TimetableOcrItem(
            text: 'Physics', boundingBox: Rect.fromLTWH(100, 80, 80, 20)),
        const TimetableOcrItem(
            text: 'Chemistry', boundingBox: Rect.fromLTWH(100, 160, 80, 20)),
      ];

      final result = parser.parse(items);
      expect(result.entries.length, 2);

      final physics = result.entries.firstWhere((e) => e.subject == 'Physics');
      expect(physics.startTime, '09:00 AM');
      expect(physics.endTime, '09:45 AM'); // Not overwritten to 10:00 AM!

      final chem = result.entries.firstWhere((e) => e.subject == 'Chemistry');
      expect(chem.startTime, '10:00 AM');
      expect(chem.endTime, '10:45 AM');
    });
  });
}
