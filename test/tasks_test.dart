import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/deadline.dart';
import 'package:pal_academic_copilot/services/deadline_service.dart';

void main() {
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

      final found = service.deadlines.firstWhere((d) => d.id == 'test_manual_1');
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
}
