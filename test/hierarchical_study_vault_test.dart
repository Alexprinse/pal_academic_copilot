import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/rag_scope.dart';
import 'package:pal_academic_copilot/services/rag_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RagService ragService;

  setUp(() async {
    ragService = RagService.instance;
    await ragService.init();
    ragService.restoreDefaultSubjects();
  });

  group('Hierarchical Study Vault - Requirements 32, 33, 34', () {
    test(
        'Requirement 32: Operating Systems Unit 2 and Computer Networks Unit 2 contents',
        () {
      final osSubject = ragService.subjects.firstWhere(
        (s) =>
            s.id == 'operating_systems' || s.name.contains('Operating Systems'),
      );
      expect(osSubject, isNotNull);

      final osUnit2 = osSubject.units.firstWhere(
        (u) => u.id == 'unit_2' || u.name.contains('Unit 2'),
      );
      expect(osUnit2, isNotNull);

      // Verify the 4 specific documents in OS Unit 2
      final docNames = osUnit2.documents.map((d) => d.name).toList();
      expect(docNames, contains('FOM U2.pdf'));
      expect(docNames, contains('Lesson-2.pdf'));
      expect(docNames, contains('OS Lecture · Sep 12'));
      expect(docNames, contains('OS Handwritten Notes'));
      expect(docNames.length, 4);

      // Verify source types
      final lecture =
          osUnit2.documents.firstWhere((d) => d.name == 'OS Lecture · Sep 12');
      expect(lecture.isAudio, isTrue);
      expect(lecture.typeLabel, 'Lecture');

      final handwritten =
          osUnit2.documents.firstWhere((d) => d.name == 'OS Handwritten Notes');
      expect(handwritten.isHandwritten, isTrue);
      expect(handwritten.typeLabel, 'Handwritten');

      final pdfDoc =
          osUnit2.documents.firstWhere((d) => d.name == 'FOM U2.pdf');
      expect(pdfDoc.typeLabel, 'PDF');

      // Verify Computer Networks Unit 2 has CN U2.pdf
      final cnSubject = ragService.subjects.firstWhere(
        (s) =>
            s.id == 'computer_networks' || s.name.contains('Computer Networks'),
      );
      expect(cnSubject, isNotNull);

      final cnUnit2 = cnSubject.units.firstWhere(
        (u) => u.id == 'unit_2' || u.name.contains('Unit 2'),
      );
      expect(cnUnit2, isNotNull);
      final cnDocNames = cnUnit2.documents.map((d) => d.name).toList();
      expect(cnDocNames, contains('CN U2.pdf'));
    });

    test(
        'Requirement 33: Strict RAG retrieval isolation between same-named units',
        () async {
      final osUnit2Scope = RagScope.subjectUnit(
        subjectId: 'operating_systems',
        subjectName: 'Operating Systems',
        unitId: 'unit_2',
        unitName: 'Unit 2: CPU Scheduling & Deadlocks',
      );

      // Query broad terms that exist in both subjects
      final osResults = ragService.search(
        query: 'verification token algorithm deadlock routing neural',
        scope: osUnit2Scope,
        topK: 10,
      );

      expect(osResults.isNotEmpty, isTrue);
      // Verify token isolation
      expect(
          osResults.any((m) => m.chunk.text.contains('PAL_OS_UNIT2_TEST_8472')),
          isTrue);
      expect(
          osResults.any((m) => m.chunk.text.contains('PAL_CN_UNIT2_TEST_9631')),
          isFalse);
      for (final match in osResults) {
        expect(RagIdHelper.toSubjectId(match.chunk.subjectId),
            'operating_systems');
        expect(RagIdHelper.toUnitId(match.chunk.unitId), 'unit_2');
        expect(match.chunk.subjectName, contains('Operating Systems'));
      }

      // Now query Computer Networks Unit 2
      final cnUnit2Scope = RagScope.subjectUnit(
        subjectId: 'computer_networks',
        subjectName: 'Computer Networks',
        unitId: 'unit_2',
        unitName: 'Unit 2: Transport Layer & TCP/UDP',
      );

      final cnResults = ragService.search(
        query: 'verification token algorithm deadlock routing neural',
        scope: cnUnit2Scope,
        topK: 10,
      );

      expect(cnResults.isNotEmpty, isTrue);
      expect(
          cnResults.any((m) => m.chunk.text.contains('PAL_CN_UNIT2_TEST_9631')),
          isTrue);
      expect(
          cnResults.any((m) => m.chunk.text.contains('PAL_OS_UNIT2_TEST_8472')),
          isFalse);
      for (final match in cnResults) {
        expect(RagIdHelper.toSubjectId(match.chunk.subjectId),
            'computer_networks');
        expect(RagIdHelper.toUnitId(match.chunk.unitId), 'unit_2');
        expect(match.chunk.subjectName, contains('Computer Networks'));
      }
    });

    test('Requirement 34: Academic hierarchy relationship traversal', () {
      expect(ragService.subjects.isNotEmpty, isTrue);

      for (final subject in ragService.subjects) {
        expect(subject.id, isNotEmpty);
        expect(subject.name, isNotEmpty);
        expect(subject.code, isNotEmpty);
        expect(subject.units, isNotEmpty);

        var totalSourcesAcrossUnits = 0;
        for (final unit in subject.units) {
          expect(unit.id, isNotEmpty);
          expect(unit.name, isNotEmpty);
          totalSourcesAcrossUnits += unit.documents.length;

          for (final doc in unit.documents) {
            expect(doc.id, isNotEmpty);
            expect(doc.name, isNotEmpty);
            expect(doc.subjectId, subject.id);
            expect(doc.unitId, unit.id);
          }
        }

        expect(subject.totalSources, totalSourcesAcrossUnits);
        expect(subject.totalUnits, subject.units.length);
      }
    });
  });

  group('Unorganized Sources & Organization Flow', () {
    test(
        'Unorganized material is staged and can be organized into a target Subject & Unit',
        () {
      expect(ragService.unorganizedSources.isNotEmpty, isTrue);
      final initialUnorgCount = ragService.totalUnorganizedSources;

      final targetDoc = ragService.unorganizedSources.first;
      final targetDocId = targetDoc.id;

      // Organize into Machine Learning Unit 1
      final mlSubject = ragService.subjects.firstWhere(
        (s) =>
            s.id == 'machine_learning' || s.name.contains('Machine Learning'),
      );
      final mlUnit1 = mlSubject.units.first;

      ragService.organizeSource(
        sourceId: targetDocId,
        targetSubjectId: mlSubject.id,
        targetUnitId: mlUnit1.id,
      );

      // Verify moved from unorganized
      expect(ragService.totalUnorganizedSources, initialUnorgCount - 1);
      expect(ragService.unorganizedSources.any((d) => d.id == targetDocId),
          isFalse);

      // Verify added to ML Unit 1
      final foundInUnit =
          mlUnit1.documents.firstWhere((d) => d.id == targetDocId);
      expect(foundInUnit, isNotNull);
      expect(foundInUnit.subjectId, mlSubject.id);
      expect(foundInUnit.unitId, mlUnit1.id);

      // Verify all indexed chunks for that doc now reflect the new subject and unit
      final chunks = ragService.allChunks
          .where((c) => c.documentId == targetDocId)
          .toList();
      for (final chunk in chunks) {
        expect(chunk.subjectId, mlSubject.id);
        expect(chunk.unitId, mlUnit1.id);
        expect(chunk.subjectName, mlSubject.name);
        expect(chunk.unitName, mlUnit1.name);
      }
    });
  });

  group('Cascading Deletion of Units and Subjects', () {
    test('deleteUnit cascades chunk deletion and preserves sibling units', () {
      // Create a test subject and unit with a document
      ragService.addSubject('Distributed Systems', code: 'CS-401');
      final distSub = ragService.subjects
          .firstWhere((s) => s.name == 'Distributed Systems');
      ragService.addUnit(distSub.name, 'Unit 1: Consensus Protocols');
      ragService.addUnit(distSub.name, 'Unit 2: Byzantine Fault Tolerance');

      ragService.indexOcrDocument(
        documentId: 'doc_paxos',
        title: 'Paxos Algorithm.pdf',
        text:
            'Paxos is a consensus protocol in asynchronous distributed systems.',
        subject: distSub.name,
        subjectId: distSub.id,
        unit: 'Unit 1: Consensus Protocols',
        unitId: 'unit_1',
      );

      ragService.indexOcrDocument(
        documentId: 'doc_pbft',
        title: 'PBFT Overview.pdf',
        text:
            'Practical Byzantine Fault Tolerance operates in weakly synchronous systems.',
        subject: distSub.name,
        subjectId: distSub.id,
        unit: 'Unit 2: Byzantine Fault Tolerance',
        unitId: 'unit_2',
      );

      // Verify chunks exist
      expect(
          ragService.allChunks.any((c) => c.documentId == 'doc_paxos'), isTrue);
      expect(
          ragService.allChunks.any((c) => c.documentId == 'doc_pbft'), isTrue);

      // Delete Unit 1
      ragService.deleteUnit(distSub.id, 'unit_1');

      // Unit 1 is gone
      expect(distSub.units.any((u) => u.id == 'unit_1'), isFalse);
      // Unit 1 chunks are cascade deleted
      expect(ragService.allChunks.any((c) => c.documentId == 'doc_paxos'),
          isFalse);

      // Unit 2 and its chunks are preserved
      expect(distSub.units.any((u) => u.id == 'unit_2'), isTrue);
      expect(
          ragService.allChunks.any((c) => c.documentId == 'doc_pbft'), isTrue);
    });

    test(
        'deleteSubject cascades chunk deletion for all units and preserves other subjects',
        () {
      final initialSubjectCount = ragService.subjects.length;
      final osSubject =
          ragService.subjects.firstWhere((s) => s.id == 'operating_systems');
      final osChunkCount =
          ragService.allChunks.where((c) => c.subjectId == osSubject.id).length;
      expect(osChunkCount, greaterThan(0));

      // Create a temporary subject to delete
      ragService.addSubject('Cryptography', code: 'CS-505');
      final cryptoSub =
          ragService.subjects.firstWhere((s) => s.name == 'Cryptography');
      ragService.addUnit(cryptoSub.name, 'Unit 1: Symmetric Ciphers');

      ragService.indexOcrDocument(
        documentId: 'doc_aes',
        title: 'AES Specification.pdf',
        text:
            'Advanced Encryption Standard uses a substitution-permutation network.',
        subject: cryptoSub.name,
        subjectId: cryptoSub.id,
        unit: 'Unit 1: Symmetric Ciphers',
        unitId: 'unit_1',
      );

      expect(
          ragService.allChunks.any((c) => c.documentId == 'doc_aes'), isTrue);

      // Delete Cryptography subject
      ragService.deleteSubject(cryptoSub.id);

      // Cryptography is gone
      expect(ragService.subjects.any((s) => s.id == cryptoSub.id), isFalse);
      expect(
          ragService.allChunks.any((c) => c.documentId == 'doc_aes'), isFalse);
      expect(ragService.subjects.length, initialSubjectCount);

      // Operating Systems chunks are completely untouched
      final remainingOsChunks =
          ragService.allChunks.where((c) => c.subjectId == osSubject.id).length;
      expect(remainingOsChunks, osChunkCount);
    });
  });

  group('OCR Indexing Integration & Search', () {
    test('indexOcrDocument indexes correctly into unorganized when specified',
        () {
      const docId = 'ocr_test_unorg_101';
      ragService.indexOcrDocument(
        documentId: docId,
        title: 'Handwritten Exam Prep.pdf',
        text:
            'Exam preparation formulas for dynamic memory allocation and buddy system.',
        isUnorganized: true,
      );

      final unorgDoc =
          ragService.unorganizedSources.firstWhere((d) => d.id == docId);
      expect(unorgDoc, isNotNull);
      expect(unorgDoc.name, 'Handwritten Exam Prep.pdf');
      expect(unorgDoc.isUnorganized, isTrue);

      // Can be found via search
      final results = ragService.searchVault('Exam Prep');
      expect(results.any((r) => r.title.contains('Exam Prep')), isTrue);
    });

    test(
        'searchVault returns structured results matching subjects, units, and sources',
        () {
      final subResults = ragService.searchVault('Operating Systems');
      expect(
          subResults.any((r) =>
              r.type.toLowerCase() == 'subject' &&
              r.title.contains('Operating Systems')),
          isTrue);

      final unitResults = ragService.searchVault('Deadlocks');
      expect(
          unitResults.any((r) =>
              r.type.toLowerCase() == 'unit' && r.title.contains('Deadlocks')),
          isTrue);

      final sourceResults = ragService.searchVault('FOM U2');
      expect(
          sourceResults.any((r) =>
              r.type.toLowerCase() == 'source' &&
              r.title.contains('FOM U2.pdf')),
          isTrue);
    });
  });
}
