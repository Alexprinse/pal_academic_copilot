import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/deadline.dart';
import 'package:pal_academic_copilot/services/deadline_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Manual Task Date & Time Creation', () {
    test('Can create task with custom date and time', () async {
      final service = DeadlineService.instance;
      final targetDate = DateTime(2026, 9, 20, 23, 59);

      final task = Deadline(
        id: 'test_manual_1',
        title: 'Submit OS Lab Report',
        course: 'Operating Systems',
        dueDate: targetDate,
        isSpokenDetected: false,
      );

      service.addDeadline(task);

      final found =
          service.deadlines.firstWhere((d) => d.id == 'test_manual_1');
      expect(found.title, 'Submit OS Lab Report');
      expect(found.dueDate.year, 2026);
      expect(found.dueDate.month, 9);
      expect(found.dueDate.day, 20);
      expect(found.dueDate.hour, 23);
      expect(found.dueDate.minute, 59);
      expect(found.isSpokenDetected, isFalse);

      service.deleteDeadline('test_manual_1');
    });
  });

  group('TaskDashboardStats Specification & Boundary Tests (Section 14)', () {
    final service = DeadlineService.instance;

    setUp(() {
      // Clear out any test leftovers
      for (final d in List.of(service.deadlines)) {
        service.deleteDeadline(d.id);
      }
    });

    tearDown(() {
      for (final d in List.of(service.deadlines)) {
        service.deleteDeadline(d.id);
      }
    });

    test(
        'Section 14 Controlled Scenario: Task A (today, pending), B (tomorrow, pending), C (yesterday, pending), D (today, completed)',
        () {
      final now = DateTime(2026, 9, 12, 14, 0); // Reference: Sep 12, 2026 2 PM

      // Task A: Due today (Sep 12, 23:59), incomplete
      final taskA = Deadline(
        id: 'task-a',
        title: 'Task A - Due Today',
        course: 'Computer Networks',
        dueDate: DateTime(2026, 9, 12, 23, 59),
        isCompleted: false,
      );

      // Task B: Due tomorrow (Sep 13, 10:00), incomplete
      final taskB = Deadline(
        id: 'task-b',
        title: 'Task B - Due Tomorrow',
        course: 'Operating Systems',
        dueDate: DateTime(2026, 9, 13, 10, 0),
        isCompleted: false,
      );

      // Task C: Due yesterday (Sep 11, 17:00), incomplete (Overdue)
      final taskC = Deadline(
        id: 'task-c',
        title: 'Task C - Overdue Yesterday',
        course: 'Data Structures',
        dueDate: DateTime(2026, 9, 11, 17, 0),
        isCompleted: false,
      );

      // Task D: Due today (Sep 12, 12:00), completed
      final taskD = Deadline(
        id: 'task-d',
        title: 'Task D - Completed Today',
        course: 'Mathematics',
        dueDate: DateTime(2026, 9, 12, 12, 0),
        isCompleted: true,
      );

      service.addDeadline(taskA);
      service.addDeadline(taskB);
      service.addDeadline(taskC);
      service.addDeadline(taskD);

      final stats = service.getDashboardStats(now);

      // Strict assertions matching Section 14:
      // Due Today = 1 (Task A only)
      // Pending = 3 (Task A, Task B, Task C)
      // Overdue = 1 (Task C)
      // Completed = 1 (Task D)
      // Total = 4
      expect(stats.dueToday, equals(1));
      expect(stats.pending, equals(3));
      expect(stats.overdue, equals(1));
      expect(stats.completed, equals(1));
      expect(stats.total, equals(4));
    });

    test('Midnight Calendar Date Boundaries: 23:59 vs 00:01', () {
      final now = DateTime(2026, 9, 12, 12, 0);

      // 23:59:59 on reference day is dueToday
      service.addDeadline(Deadline(
        id: 'edge-today',
        title: 'Edge Today',
        course: 'Algorithms',
        dueDate: DateTime(2026, 9, 12, 23, 59, 59),
        isCompleted: false,
      ));

      // 00:01 next morning is NOT due today
      service.addDeadline(Deadline(
        id: 'edge-tomorrow',
        title: 'Edge Tomorrow',
        course: 'Algorithms',
        dueDate: DateTime(2026, 9, 13, 0, 1),
        isCompleted: false,
      ));

      final stats = service.getDashboardStats(now);
      expect(stats.dueToday, equals(1));
      expect(stats.pending, equals(2));
      expect(stats.overdue, equals(0));
    });

    test('Reactive update when task is completed or restored', () {
      final now = DateTime(2026, 9, 12, 10, 0);

      final task = Deadline(
        id: 'task-reactive',
        title: 'Reactive Task',
        course: 'Discrete Math',
        dueDate: DateTime(2026, 9, 12, 18, 0),
        isCompleted: false,
      );
      service.addDeadline(task);

      var stats = service.getDashboardStats(now);
      expect(stats.dueToday, equals(1));
      expect(stats.pending, equals(1));
      expect(stats.completed, equals(0));

      // User marks task as complete
      service.toggleComplete('task-reactive');
      stats = service.getDashboardStats(now);
      expect(stats.dueToday, equals(0));
      expect(stats.pending, equals(0));
      expect(stats.completed, equals(1));

      // User unchecks task
      service.toggleComplete('task-reactive');
      stats = service.getDashboardStats(now);
      expect(stats.dueToday, equals(1));
      expect(stats.pending, equals(1));
      expect(stats.completed, equals(0));
    });

    test('Duplicate task protection for identical title and lectureId', () {
      final task1 = Deadline(
        id: 'dl-initial',
        title: 'TCP vs UDP Comparison',
        course: 'Computer Networks',
        dueDate: DateTime(2026, 9, 15, 12, 0),
        lectureId: 'lec-101',
      );
      final task2 = Deadline(
        id: 'dl-reprocessed',
        title: 'TCP vs UDP Comparison',
        course: 'Computer Networks',
        dueDate: DateTime(2026, 9, 15, 12, 0),
        lectureId: 'lec-101',
      );

      service.addDeadline(task1);
      service.addDeadline(task2);

      expect(service.deadlines.length, equals(1));
      expect(service.deadlines.first.id, equals('dl-reprocessed'));
    });
  });
}
