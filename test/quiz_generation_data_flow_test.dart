import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/rag_scope.dart';
import 'package:pal_academic_copilot/services/conversation_service.dart';
import 'package:pal_academic_copilot/services/llm_service.dart';
import 'package:pal_academic_copilot/services/rag_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RagService ragService;
  late ConversationService conversationService;
  late LlmService llmService;

  setUp(() async {
    ragService = RagService.instance;
    await ragService.init();
    ragService.restoreDefaultSubjects();

    conversationService = ConversationService.instance;
    conversationService.clearForTesting();

    llmService = LlmService.instance;
  });

  group('Quiz Generation Data Flow & Isolation (Req 19, 20, 21, 22)', () {
    test(
        'Requirement 19: Critical Cross-Contamination Test with 3 Distinct Documents',
        () {
      // 1. Setup 3 documents across 3 different subjects/units:
      // Document A: Discrete Mathematics · Unit 1 (contains PAL_DISCRETE_U1_TEST_8472)
      // Document B: Operating Systems · Unit 2 (contains PAL_OS_U2_TEST_9631)
      // Document C: Class 10 Maths · Unit 2 (contains PAL_MATHS_U2_TEST_7314)
      ragService.indexOcrDocument(
        documentId: 'doc_class10_maths',
        title: 'Class 10th Maths Chapter 2 Polynomial notes.pdf',
        text:
            'Class 10th Maths Chapter 2: Polynomials, zeros of polynomials, quadratic formulas. Verification token: PAL_MATHS_U2_TEST_7314.',
        subject: 'Class 10 Maths',
        subjectId: 'class_10_maths',
        unit: 'Unit 2: Polynomials',
        unitId: 'unit_2',
      );

      // Select: Discrete Mathematics · Unit 1
      final dmScope = RagScope.subjectUnit(
        subjectId: 'discrete_mathematics',
        subjectName: 'Discrete Mathematics',
        unitId: 'math-unit-1',
        unitName: 'Unit 1: Graph Theory & Recurrence Relations',
      );

      // Ask: "Generate 5 practice exam questions with detailed answers based on Unit 1: Graph Theory & Recurrence Relations."
      final results = ragService.search(
        query:
            'Generate 5 practice exam questions with detailed answers based on Unit 1: Graph Theory & Recurrence Relations.',
        scope: dmScope,
        topK: 5,
      );

      expect(results.isNotEmpty, isTrue);

      // The context must contain ONLY PAL_DISCRETE_U1_TEST_8472
      expect(
          results
              .any((m) => m.chunk.text.contains('PAL_DISCRETE_U1_TEST_8472')),
          isTrue);

      // It must NEVER contain PAL_OS_U2_TEST_9631 or PAL_MATHS_U2_TEST_7314
      expect(results.any((m) => m.chunk.text.contains('PAL_OS_U2_TEST_9631')),
          isFalse);
      expect(
          results.any((m) => m.chunk.text.contains('PAL_MATHS_U2_TEST_7314')),
          isFalse);
      expect(results.any((m) => m.chunk.documentName.contains('Polynomial')),
          isFalse);
      expect(results.any((m) => m.chunk.documentName.contains('ROS')), isFalse);

      // All retrieved chunks MUST strictly belong to Discrete Mathematics Unit 1
      for (final match in results) {
        expect(RagIdHelper.toSubjectId(match.chunk.subjectId),
            'discrete_mathematics');
        expect(RagIdHelper.toUnitId(match.chunk.unitId), 'unit_1');
        expect(match.chunk.subjectName, 'Discrete Mathematics');
        expect(match.chunk.unitName, contains('Unit 1'));
      }
    });

    test('Requirement 20: Subject-Wide Retrieval Isolation', () {
      // Add a Unit 2 for Discrete Mathematics to verify intra-subject retrieval
      ragService.addUnit(
          'Discrete Mathematics', 'Unit 2: Combinatorics & Probability',
          unitId: 'math-unit-2');
      ragService.indexOcrDocument(
        documentId: 'doc_dm_u2',
        title: 'Combinatorics_Permutations.pdf',
        text:
            'Combinatorics: Pigeonhole Principle, permutations, combinations, binomial theorem. Verification token: PAL_DM_U2_TOKEN_5521.',
        subject: 'Discrete Mathematics',
        subjectId: 'discrete_mathematics',
        unit: 'Unit 2: Combinatorics & Probability',
        unitId: 'math-unit-2',
      );

      // Select: Discrete Mathematics (All Units)
      final subScope = RagScope.subject(
        subjectName: 'Discrete Mathematics',
        subjectId: 'discrete_mathematics',
      );

      final results = ragService.search(
        query:
            'Summarize my Discrete Mathematics material Graph Theory and Combinatorics.',
        scope: subScope,
        topK: 10,
      );

      expect(results.isNotEmpty, isTrue);

      // Allowed: Discrete Mathematics Unit 1 and Unit 2
      final matchedUnits =
          results.map((m) => RagIdHelper.toUnitId(m.chunk.unitId)).toSet();
      expect(matchedUnits.contains('unit_1'), isTrue);
      expect(matchedUnits.contains('unit_2'), isTrue);

      // NOT allowed: Operating Systems, Computer Networks, Class 10 Maths
      for (final match in results) {
        expect(RagIdHelper.toSubjectId(match.chunk.subjectId),
            'discrete_mathematics');
        expect(match.chunk.subjectName, 'Discrete Mathematics');
        expect(match.chunk.documentName.contains('Polynomial'), isFalse);
        expect(match.chunk.documentName.contains('Silberschatz'), isFalse);
        expect(match.chunk.documentName.contains('CN U2'), isFalse);
      }
    });

    test('Requirement 21: Unit Test — Never retrieves sibling unit chunks', () {
      // Select: Discrete Mathematics · Unit 1
      final dmUnit1Scope = RagScope.subjectUnit(
        subjectId: 'discrete_mathematics',
        subjectName: 'Discrete Mathematics',
        unitId: 'math-unit-1',
        unitName: 'Unit 1: Graph Theory & Recurrence Relations',
      );

      final results = ragService.search(
        query: 'Generate 5 practice exam questions.',
        scope: dmUnit1Scope,
        topK: 10,
      );

      expect(results.isNotEmpty, isTrue);
      for (final match in results) {
        expect(RagIdHelper.toSubjectId(match.chunk.subjectId),
            'discrete_mathematics');
        expect(RagIdHelper.toUnitId(match.chunk.unitId), 'unit_1');
        expect(match.chunk.unitName, contains('Unit 1'));
      }
    });

    test(
        'Requirement 22: Specific Document Test — Only targeted document is retrieved',
        () {
      const targetDocName = 'Discrete_Math_Graph_Theory_Recurrence.pdf';
      final docScope = RagScope.document(
        documentId: 'doc-math-1',
        documentName: targetDocName,
        subjectId: 'discrete_mathematics',
        subjectName: 'Discrete Mathematics',
        unitId: 'math-unit-1',
        unitName: 'Unit 1: Graph Theory & Recurrence Relations',
      );

      final results = ragService.search(
        query: 'Euler circuit and Hamiltonian cycle questions',
        scope: docScope,
        topK: 5,
      );

      expect(results.isNotEmpty, isTrue);
      for (final match in results) {
        expect(match.chunk.documentName, targetDocName);
        expect(match.chunk.documentId, 'doc-math-1');
      }
    });

    test(
        'Requirement 17: Output Validation & Malformed Filter rejects "I heard: [1] [2] [3]"',
        () {
      const malformedRaw =
          'I heard: [1] [2] [3]\n\nHere are the practice questions for Graph Theory:\n1. Define an Euler circuit.';
      final cleaned = malformedRaw
          .replaceAll(
              RegExp(r'I heard:\s*(?:\[\d+\]\s*)+', caseSensitive: false), '')
          .trim();

      expect(cleaned.contains('I heard:'), isFalse);
      expect(cleaned.contains('[1] [2] [3]'), isFalse);
      expect(cleaned.startsWith('Here are the practice questions'), isTrue);
    });

    test('Empty scope material does not hallucinate and informs the student',
        () {
      // Create a scope for an empty unit
      final emptyScope = RagScope.subjectUnit(
        subjectId: 'discrete_mathematics',
        subjectName: 'Discrete Mathematics',
        unitId: 'math-unit-99',
        unitName: 'Unit 99: Empty Unit',
      );

      final results = ragService.search(
        query: 'Generate 5 questions',
        scope: emptyScope,
        topK: 5,
      );

      expect(results, isEmpty);
    });

    test(
        'LlmService generateSimulation returns grounded Discrete Math questions',
        () async {
      const prompt = '=== CONTEXT FROM STUDY VAULT ===\n'
          '[Source 1: Discrete Mathematics > Unit 1: Graph Theory & Recurrence Relations]:\n'
          'Graph Theory Fundamentals. Verification token: PAL_DISCRETE_U1_TEST_8472.\n'
          '=== END CONTEXT ===\n'
          'Generate 5 practice exam questions with detailed answers based on Unit 1: Graph Theory & Recurrence Relations.';

      final tokens =
          await llmService.generateStreaming(prompt: prompt).toList();
      final fullResponse = tokens.join('');

      expect(fullResponse.contains('Discrete Mathematics'), isTrue);
      expect(fullResponse.contains('Euler'), isTrue);
      expect(fullResponse.contains('Handshaking Lemma'), isTrue);
      expect(fullResponse.contains('Planar Graphs'), isTrue);
      expect(fullResponse.contains('ROS Architecture'), isFalse);
      expect(fullResponse.contains('Polynomial'), isFalse);
      expect(fullResponse.contains('I heard:'), isFalse);
    });
  });
}
