import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/deadline.dart';
import 'package:pal_academic_copilot/models/lecture_recording.dart';
import 'package:pal_academic_copilot/services/deadline_detector.dart';
import 'package:pal_academic_copilot/services/deadline_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Section 18 — Date & Time Parsing Tests', () {
    final refDate = DateTime(2026, 9, 12, 10, 0); // Saturday, Sep 12, 2026

    test('"Submit by September 15th at 12pm." -> Sep 15, 12:00 PM', () {
      final candidates = DeadlineDetector.detectCandidates(
        'Submit by September 15th at 12pm.',
        referenceDate: refDate,
      );

      expect(candidates.isNotEmpty, isTrue);
      final c = candidates.first;
      expect(c.dueDate?.year, 2026);
      expect(c.dueDate?.month, 9);
      expect(c.dueDate?.day, 15);
      expect(c.dueDate?.hour, 12);
      expect(c.dueDate?.minute, 0);
      expect(c.hasExplicitDueDate, isTrue);
      expect(c.hasExplicitDueTime, isTrue);
      expect(c.dueTimeFormatted, '12:00 PM');
    });

    test('"Submit by September 15th." -> Sep 15 (end of day)', () {
      final candidates = DeadlineDetector.detectCandidates(
        'Submit by September 15th.',
        referenceDate: refDate,
      );

      expect(candidates.isNotEmpty, isTrue);
      final c = candidates.first;
      expect(c.dueDate?.year, 2026);
      expect(c.dueDate?.month, 9);
      expect(c.dueDate?.day, 15);
      expect(c.hasExplicitDueDate, isTrue);
      expect(c.hasExplicitDueTime, isFalse);
    });

    test('"Submit by tomorrow at 5 PM." -> tomorrow at 5:00 PM', () {
      final candidates = DeadlineDetector.detectCandidates(
        'Submit by tomorrow at 5 PM.',
        referenceDate: refDate,
      );

      expect(candidates.isNotEmpty, isTrue);
      final c = candidates.first;
      expect(c.dueDate?.year, 2026);
      expect(c.dueDate?.month, 9);
      expect(c.dueDate?.day, 13); // 12 + 1
      expect(c.dueDate?.hour, 17);
      expect(c.dueDate?.minute, 0);
      expect(c.dueTimeFormatted, '5:00 PM');
    });

    test('"Submit this Friday." -> upcoming Friday', () {
      // refDate is Sat Sep 12. Next Friday is Sep 18.
      final candidates = DeadlineDetector.detectCandidates(
        'Submit this Friday.',
        referenceDate: refDate,
      );

      expect(candidates.isNotEmpty, isTrue);
      final c = candidates.first;
      expect(c.dueDate?.weekday, DateTime.friday);
      expect(c.hasExplicitDueDate, isTrue);
    });

    test(
        '"Today I am giving you an assignment. Submit it by Monday." -> Monday, NOT today',
        () {
      final candidates = DeadlineDetector.detectCandidates(
        'Today I am giving you an assignment. Submit it by Monday.',
        referenceDate: refDate,
      );

      expect(candidates.isNotEmpty, isTrue);
      final c = candidates.first;
      expect(c.dueDate?.weekday, DateTime.monday);
      expect(c.dueDate?.day, 14); // Sep 12 (Sat) + 2 days -> Sep 14 (Mon)
      expect(c.hasExplicitDueDate, isTrue);
    });

    test('"Start this today and submit it next week." -> next week, NOT today',
        () {
      final candidates = DeadlineDetector.detectCandidates(
        'Start this today and submit it next week.',
        referenceDate: refDate,
      );

      expect(candidates.isNotEmpty, isTrue);
      final c = candidates.first;
      expect(c.dueDate?.day, 19); // Sep 12 + 7 days = Sep 19
      expect(c.hasExplicitDueDate, isTrue);
    });

    test('"Assignment today." -> no invented due date', () {
      final candidates = DeadlineDetector.detectCandidates(
        'Now for your assignment today.',
        referenceDate: refDate,
      );

      if (candidates.isNotEmpty) {
        final c = candidates.first;
        expect(c.hasExplicitDueDate, isFalse);
        expect(c.needsReview, isTrue);
      }
    });

    test('Number guard: "5 differences" is NOT parsed as 5:00 AM/PM time', () {
      final candidates = DeadlineDetector.detectCandidates(
        'Prepare the comparison including 5 differences and submit by September 15th at 12pm.',
        referenceDate: refDate,
      );

      expect(candidates.isNotEmpty, isTrue);
      final c = candidates.first;
      expect(c.dueDate?.hour, 12);
      expect(c.dueDate?.minute, 0);
      expect(c.dueTimeFormatted, '12:00 PM');
    });
  });

  group('Section 19 — Exact Demo Lecture Transcript Test', () {
    const transcript =
        'Now for your assignment today prepare the comparison of TCP and UDP including at least 5 differences and submitted by September 15th at 12pm. Also in the next lecture we will discuss about the IP address and subnetting. So please review the basics of typing before coming to the class.';

    final refDate = DateTime(2026, 9, 12, 10, 0);

    test('Synthesizes TCP vs UDP Comparison with correct due date and subject',
        () {
      final chunks = [
        const LectureTranscriptChunk(
          chunkIndex: 0,
          startTimestamp: '00:00',
          endTimestamp: '00:45',
          text: 'Welcome to class everyone.',
        ),
        const LectureTranscriptChunk(
          chunkIndex: 1,
          startTimestamp: '01:15',
          endTimestamp: '02:00',
          text:
              'Now for your assignment today prepare the comparison of TCP and UDP including at least 5 differences and submitted by September 15th at 12pm.',
        ),
      ];

      final candidates = DeadlineDetector.detectCandidates(
        transcript,
        referenceDate: refDate,
        subject: 'Computer Networks',
        lectureId: 'rec_cn_01',
        chunks: chunks,
      );

      expect(candidates.isNotEmpty, isTrue);
      final c = candidates.first;

      // 1. Title
      expect(c.title, contains('TCP vs UDP Comparison'));

      // 2. Description
      expect(c.description, contains('comparison of TCP and UDP'));
      expect(c.description, contains('5 differences'));

      // 3. Due Date & Time
      expect(c.dueDate?.year, 2026);
      expect(c.dueDate?.month, 9);
      expect(c.dueDate?.day, 15);
      expect(c.dueDate?.hour, 12);
      expect(c.dueDate?.minute, 0);
      expect(c.dueTimeFormatted, '12:00 PM');

      // 4. Subject
      expect(c.subject, 'Computer Networks');

      // 5. Source timestamp & evidence
      expect(c.sourceTimestamp, '01:15');
      expect(c.sourceLectureId, 'rec_cn_01');
      expect(c.evidenceText, contains('September 15th at 12pm'));

      // 6. No unwanted tasks for "next lecture" or "typing"
      final titles = candidates.map((x) => x.title.toLowerCase()).toList();
      expect(titles.any((t) => t.contains('subnetting')), isFalse);
      expect(titles.any((t) => t.contains('typing')), isFalse);
    });

    test('Speech error normalization: ECB and UCP normalized to TCP and UDP',
        () {
      const errorTranscript =
          'Prepare the comparison of ECB and UCP including 5 differences and submit by September 15th at 12pm.';
      final candidates = DeadlineDetector.detectCandidates(
        errorTranscript,
        referenceDate: refDate,
      );

      expect(candidates.isNotEmpty, isTrue);
      expect(candidates.first.title, 'TCP vs UDP Comparison');
    });
  });

  group('Section 9 & 10 — Validation & Candidate Conversion', () {
    test('Rejects generic titles like "General Deadline" and "Live video"', () {
      final invalidCandidate = DeadlineCandidate(
        title: 'General Deadline',
        description: 'No description',
        subject: 'General',
        evidenceText: 'Submit by Friday',
        validationErrors: ['Generic title'],
      );

      expect(invalidCandidate.isValid, isFalse);
    });

    test('Converts valid candidate to Deadline preserving rich metadata', () {
      final candidate = DeadlineCandidate(
        title: 'TCP vs UDP Comparison',
        description: 'Prepare comparison of TCP and UDP',
        dueDate: DateTime(2026, 9, 15, 12, 0),
        dueTimeFormatted: '12:00 PM',
        subject: 'Computer Networks',
        sourceLectureId: 'lec_01',
        recordingId: 'rec_01',
        sourceTimestamp: '01:15',
        sourceTimestampSeconds: 75,
        evidenceText: 'submitted by September 15th at 12pm',
        hasExplicitDueDate: true,
        hasExplicitDueTime: true,
      );

      final dl = candidate.toDeadline(customId: 'dl_test_1');
      expect(dl.id, 'dl_test_1');
      expect(dl.title, 'TCP vs UDP Comparison');
      expect(dl.course, 'Computer Networks');
      expect(dl.dueDate, DateTime(2026, 9, 15, 12, 0));
      expect(dl.lectureId, 'lec_01');
      expect(dl.audioTimestamp, '01:15');
      expect(dl.sourceTimestampSeconds, 75);
      expect(dl.evidenceText, 'submitted by September 15th at 12pm');
      expect(dl.hasExplicitDueDate, isTrue);
      expect(dl.hasExplicitDueTime, isTrue);
    });
  });

  group('Section 16 & 22 — Persistence & Mock Data Audit', () {
    test('DeadlineService.init() does NOT load seed mock data in production',
        () async {
      final service = DeadlineService.instance;
      service.setDeadlinesForTesting([]);

      // Calling init without loadSeedData (defaults to false)
      await service.init(loadSeedData: false);

      expect(service.deadlines.any((d) => d.id == 'dl-1'), isFalse);
      expect(service.deadlines.any((d) => d.id == 'dl-2'), isFalse);
      expect(
          service.deadlines.any((d) => d.title.contains('Peterson')), isFalse);
      expect(service.deadlines.any((d) => d.title == 'Live video'), isFalse);
      expect(
          service.deadlines.any((d) => d.title == 'General Deadline'), isFalse);
    });

    test(
        'DeadlineService.populateSeedDeadlinesForTesting() populates on demand',
        () {
      final service = DeadlineService.instance;
      service.setDeadlinesForTesting([]);
      service.populateSeedDeadlinesForTesting();

      expect(service.deadlines.isNotEmpty, isTrue);
      expect(
          service.deadlines.any((d) => d.title.contains('Peterson')), isTrue);
      service.setDeadlinesForTesting([]);
    });

    test('addDeadline and deleteDeadline update local state safely', () {
      final service = DeadlineService.instance;
      final testTask = Deadline(
        id: 'user_created_task_99',
        title: 'Real User Task',
        course: 'Computer Networks',
        dueDate: DateTime(2026, 9, 15, 12, 0),
        isSpokenDetected: true,
      );

      service.addDeadline(testTask);
      expect(
          service.deadlines.any((d) => d.id == 'user_created_task_99'), isTrue);

      service.deleteDeadline('user_created_task_99');
      expect(service.deadlines.any((d) => d.id == 'user_created_task_99'),
          isFalse);
    });
  });
}
