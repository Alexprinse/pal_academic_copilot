import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/agent/tools/search_knowledge_tool.dart';
import 'package:pal_academic_copilot/models/conversation_session.dart';
import 'package:pal_academic_copilot/models/rag_scope.dart';
import 'package:pal_academic_copilot/models/vault_item.dart';
import 'package:pal_academic_copilot/services/rag_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RagService ragService;

  setUp(() async {
    ragService = RagService.instance;
    await ragService.init();
  });

  group('Subject-Aware Academic Hierarchy & RagScope Models', () {
    test('RagIdHelper normalizes subject and unit names accurately', () {
      expect(RagIdHelper.toSubjectId('Operating Systems'), 'operating_systems');
      expect(RagIdHelper.toSubjectId('OS'), 'operating_systems');
      expect(RagIdHelper.toSubjectId('Computer Networks'), 'computer_networks');
      expect(RagIdHelper.toSubjectId('CN'), 'computer_networks');
      expect(RagIdHelper.toSubjectId('Machine Learning'), 'machine_learning');
      expect(RagIdHelper.toSubjectId('ML'), 'machine_learning');

      expect(
          RagIdHelper.toUnitId('Unit 2: CPU Scheduling & Deadlocks'), 'unit_2');
      expect(RagIdHelper.toUnitId('Unit 1: Process Synchronization'), 'unit_1');
      expect(RagIdHelper.toUnitId('os-unit-2'), 'unit_2');
      expect(RagIdHelper.toUnitId('U2'), 'unit_2');
    });

    test('RagScope display labels reflect subject-aware hierarchy', () {
      const allScope = RagScope.allNotes();
      expect(allScope.displayLabel, 'All Notes');

      const offScope = RagScope.off();
      expect(offScope.displayLabel, 'General Knowledge (No Vault)');

      final subScope = RagScope.subject(subjectName: 'Operating Systems');
      expect(subScope.displayLabel, 'Operating Systems');

      final unitScope = RagScope.subjectUnit(
        subjectName: 'Operating Systems',
        unitName: 'Unit 2: CPU Scheduling & Deadlocks',
      );
      expect(
        unitScope.displayLabel,
        'Operating Systems · Unit 2: CPU Scheduling & Deadlocks',
      );
    });

    test('Unit scope is never matched in isolation without subject match', () {
      final osUnit2Scope = RagScope.subjectUnit(
        subjectName: 'Operating Systems',
        unitName: 'Unit 2: CPU Scheduling & Deadlocks',
      );

      final osUnit2Chunk = TextChunk(
        id: 'chunk_os_2',
        subjectId: 'operating_systems',
        subjectName: 'Operating Systems',
        unitId: 'unit_2',
        unitName: 'Unit 2: CPU Scheduling & Deadlocks',
        documentId: 'doc_1',
        documentName: 'doc1.pdf',
        pageNumber: 1,
        text: 'OS Deadlock text',
        wordCount: 3,
      );

      final cnUnit2Chunk = TextChunk(
        id: 'chunk_cn_2',
        subjectId: 'computer_networks',
        subjectName: 'Computer Networks',
        unitId: 'unit_2',
        unitName: 'Unit 2: Network Layer & Routing',
        documentId: 'doc_2',
        documentName: 'doc2.pdf',
        pageNumber: 1,
        text: 'CN Routing text',
        wordCount: 3,
      );

      expect(osUnit2Scope.matchesChunk(osUnit2Chunk), isTrue);
      expect(osUnit2Scope.matchesChunk(cnUnit2Chunk), isFalse);
    });
  });

  group('Cross-Subject Isolation & Pre-Retrieval Candidate Filtering (Req 18)',
      () {
    test('Querying OS Unit 2 NEVER returns CN Unit 2 or ML Unit 2 tokens', () {
      final osScope = RagScope.subjectUnit(
        subjectName: 'Operating Systems',
        unitName: 'Unit 2: CPU Scheduling & Deadlocks',
      );

      // Search with common keyword "verification token algorithm"
      final results = ragService.search(
        query: 'verification token algorithm deadlock routing neural',
        scope: osScope,
        topK: 5,
      );

      expect(results.isNotEmpty, isTrue);
      expect(
        results.any((m) => m.chunk.text.contains('PAL_OS_UNIT2_TEST_8472')),
        isTrue,
      );

      for (final match in results) {
        expect(match.chunk.subjectId, 'operating_systems');
        expect(
          match.chunk.unitId == 'os-unit-2' || match.chunk.unitId == 'unit_2',
          isTrue,
        );
        expect(match.chunk.text.contains('PAL_CN_UNIT2_TEST_9631'), isFalse);
        expect(match.chunk.text.contains('PAL_ML_UNIT2_TEST_7314'), isFalse);
      }
    });

    test('Querying CN Unit 2 NEVER returns OS Unit 2 or ML Unit 2 tokens', () {
      final cnScope = RagScope.subjectUnit(
        subjectName: 'Computer Networks',
        unitName: 'Unit 2: Network Layer & Routing',
      );

      final results = ragService.search(
        query: 'verification token routing Dijkstra deadlock neural',
        scope: cnScope,
        topK: 5,
      );

      expect(results.isNotEmpty, isTrue);

      for (final match in results) {
        expect(match.chunk.subjectId, 'computer_networks');
        expect(
          match.chunk.unitId == 'cn-unit-2' || match.chunk.unitId == 'unit_2',
          isTrue,
        );
        expect(match.chunk.text.contains('PAL_CN_UNIT2_TEST_9631'), isTrue);
        expect(match.chunk.text.contains('PAL_OS_UNIT2_TEST_8472'), isFalse);
        expect(match.chunk.text.contains('PAL_ML_UNIT2_TEST_7314'), isFalse);
      }
    });

    test('Querying ML Unit 2 NEVER returns OS Unit 2 or CN Unit 2 tokens', () {
      final mlScope = RagScope.subjectUnit(
        subjectName: 'Machine Learning',
        unitName: 'Unit 2: Neural Networks & Deep Learning',
      );

      final results = ragService.search(
        query: 'verification token neural backpropagation routing deadlock',
        scope: mlScope,
        topK: 5,
      );

      expect(results.isNotEmpty, isTrue);

      for (final match in results) {
        expect(match.chunk.subjectId, 'machine_learning');
        expect(
          match.chunk.unitId == 'ml-unit-2' || match.chunk.unitId == 'unit_2',
          isTrue,
        );
        expect(match.chunk.text.contains('PAL_ML_UNIT2_TEST_7314'), isTrue);
        expect(match.chunk.text.contains('PAL_OS_UNIT2_TEST_8472'), isFalse);
        expect(match.chunk.text.contains('PAL_CN_UNIT2_TEST_9631'), isFalse);
      }
    });

    test(
        'Subject-wide scope retrieves all units of that subject and zero other subjects',
        () {
      final osSubjectScope = RagScope.subject(subjectName: 'Operating Systems');

      final results = ragService.search(
        query: 'mutual exclusion Peterson semaphores deadlock Banker',
        scope: osSubjectScope,
        topK: 10,
      );

      expect(results.isNotEmpty, isTrue);

      final unitIds = results.map((m) => m.chunk.unitId).toSet();
      expect(
          unitIds.length, greaterThanOrEqualTo(2)); // Unit 1 and Unit 2 present

      for (final match in results) {
        expect(match.chunk.subjectId, 'operating_systems');
        expect(match.chunk.subjectName, 'Operating Systems');
        expect(match.chunk.text.contains('PAL_CN_UNIT2_TEST_9631'), isFalse);
        expect(match.chunk.text.contains('PAL_ML_UNIT2_TEST_7314'), isFalse);
      }
    });

    test(
        'countChunksInScope returns exact counts for subjectUnit and subject scopes',
        () {
      final osUnit2Scope = RagScope.subjectUnit(
        subjectName: 'Operating Systems',
        unitName: 'Unit 2: CPU Scheduling & Deadlocks',
      );
      final osSubScope = RagScope.subject(subjectName: 'Operating Systems');
      const allScope = RagScope.allNotes();
      const offScope = RagScope.off();

      final unitCount = ragService.countChunksInScope(osUnit2Scope);
      final subCount = ragService.countChunksInScope(osSubScope);
      final allCount = ragService.countChunksInScope(allScope);
      final offCount = ragService.countChunksInScope(offScope);

      expect(unitCount, greaterThan(0));
      expect(subCount, greaterThan(unitCount));
      expect(allCount, greaterThan(subCount));
      expect(offCount, equals(0));
    });
  });

  group('Agent SearchKnowledgeTool with Subject-Aware Guardrails', () {
    test('Tool search strictly isolates to requested subject and unit',
        () async {
      final tool = SearchKnowledgeTool(ragService: ragService);

      final result = await tool.execute({
        'query': 'verification token',
        'subject': 'Operating Systems',
        'unit': 'Unit 2: CPU Scheduling & Deadlocks',
      });

      expect(result.success, isTrue);
      final data = result.data as Map<String, dynamic>;
      final matches = data['matches'] as List<dynamic>;
      expect(matches.isNotEmpty, isTrue);

      for (final m in matches) {
        expect(m['subjectId'], 'operating_systems');
        expect(m['text'].toString().contains('PAL_OS_UNIT2_TEST_8472'), isTrue);
        expect(
            m['text'].toString().contains('PAL_CN_UNIT2_TEST_9631'), isFalse);
      }
    });

    test(
        'Tool search rejects ambiguous unit without subject and requires disambiguation',
        () async {
      final tool = SearchKnowledgeTool(ragService: ragService);

      final result = await tool.execute({
        'query': 'What is in Unit 2?',
        'unit': 'Unit 2',
      });

      expect(result.success, isFalse);
      expect(result.data['needsSubjectDisambiguation'], isTrue);
      expect(result.message.contains('requires a subject'), isTrue);
    });
  });

  group('Session Persistence & Restoration of Discrete Scope Fields', () {
    test('ConversationSession preserves lossless subject and unit scope', () {
      final scope = RagScope.subjectUnit(
        subjectName: 'Computer Networks',
        unitName: 'Unit 2: Network Layer & Routing',
      );

      final session = ConversationSession(
        id: 'test_session_1',
        title: 'CN Routing Chat',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        ragScope: scope,
        messages: [],
      );

      expect(session.ragScopeType, 'subjectUnit');
      expect(session.subjectId, 'computer_networks');
      expect(session.subjectName, 'Computer Networks');
      expect(session.unitId, 'unit_2');
      expect(session.unitName, 'Unit 2: Network Layer & Routing');

      final json = session.toJson();
      final restored = ConversationSession.fromJson(json);

      expect(restored.ragScope.type, RagScopeType.subjectUnit);
      expect(restored.ragScope.subjectId, 'computer_networks');
      expect(restored.ragScope.unitId, 'unit_2');
      expect(restored.selectedRagScope,
          'Computer Networks · Unit 2: Network Layer & Routing');
    });
  });
}
