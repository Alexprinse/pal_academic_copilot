import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/rag_scope.dart';
import 'package:pal_academic_copilot/services/quiz_generation_service.dart';
import 'package:pal_academic_copilot/services/rag_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RagService ragService;
  late QuizGenerationService quizService;

  setUp(() async {
    ragService = RagService.instance;
    await ragService.init();
    quizService = QuizGenerationService.instance;
  });

  group('Independent Quiz Generation Architecture (Requirements 1-31)', () {
    test(
        'Requirement 5 & 12: parseQuestionOutput strictly parses complete question, answer, and explanation',
        () {
      final scope = RagScope.subjectUnit(
        subjectId: 'discrete_mathematics',
        subjectName: 'Discrete Mathematics',
        unitId: 'math-unit-1',
        unitName: 'Unit 1: Graph Theory & Recurrence Relations',
      );
      final citations = ragService.search(query: 'Euler circuit', scope: scope);

      const validOutput = '''
QUESTION:
State the necessary and sufficient condition for an undirected connected graph to contain an Euler circuit.

ANSWER:
An undirected connected graph contains an Euler circuit if and only if every vertex has an even degree.

EXPLANATION:
Every traversal in an Euler circuit uses one edge to enter each vertex and another to leave, meaning vertex degrees must be even.
''';

      final parsed = QuizGenerationService.parseQuestionOutput(
        text: validOutput,
        questionNumber: 1,
        totalQuestions: 5,
        candidateSources: citations,
        scope: scope,
      );

      expect(parsed, isNotNull);
      expect(parsed!.isValid, isTrue);
      expect(parsed.questionNumber, 1);
      expect(parsed.question, contains('Euler circuit'));
      expect(parsed.answer, contains('even degree'));
      expect(parsed.explanation, contains('Euler circuit'));
      expect(parsed.sources.isNotEmpty, isTrue);
      for (final s in parsed.sources) {
        expect(s.chunk.subjectId, 'discrete_mathematics');
        expect(s.chunk.unitId, 'math-unit-1');
      }
    });

    test(
        'Requirement 12: parseQuestionOutput REJECTS incomplete/truncated output',
        () {
      final scope = RagScope.subjectUnit(
        subjectId: 'discrete_mathematics',
        subjectName: 'Discrete Mathematics',
        unitId: 'math-unit-1',
        unitName: 'Unit 1: Graph Theory & Recurrence Relations',
      );

      // Truncated question cut off mid-response (exact failure case reported by user)
      const cutOffText = '''
QUESTION:
Find the value of the polynomial
p(x) = 3x - 2x^2
''';

      final parsed = QuizGenerationService.parseQuestionOutput(
        text: cutOffText,
        questionNumber: 4,
        totalQuestions: 5,
        candidateSources: [],
        scope: scope,
      );

      // Must be rejected as incomplete!
      expect(parsed, isNull);
    });

    test('Requirement 12: parseQuestionOutput REJECTS missing explanation', () {
      final scope = RagScope.subjectUnit(
        subjectId: 'discrete_mathematics',
        subjectName: 'Discrete Mathematics',
        unitId: 'math-unit-1',
        unitName: 'Unit 1: Graph Theory & Recurrence Relations',
      );

      const missingExplanation = '''
QUESTION:
What is a Hamiltonian cycle?

ANSWER:
A closed loop that visits each vertex exactly once.
''';

      final parsed = QuizGenerationService.parseQuestionOutput(
        text: missingExplanation,
        questionNumber: 2,
        totalQuestions: 5,
        candidateSources: [],
        scope: scope,
      );

      expect(parsed, isNull);
    });

    test(
        'Requirement 8: buildCompactQuizPrompt passes previous questions to enforce diversity',
        () {
      final scope = RagScope.subjectUnit(
        subjectId: 'discrete_mathematics',
        subjectName: 'Discrete Mathematics',
        unitId: 'math-unit-1',
        unitName: 'Unit 1: Graph Theory & Recurrence Relations',
      );

      final prompt = QuizGenerationService.buildCompactQuizPrompt(
        questionNumber: 3,
        totalQuestions: 5,
        scope: scope,
        citations: [],
        previousQuestions: [
          'Q1: Euler circuit condition',
          'Q2: Handshaking Lemma formula',
        ],
      );

      expect(prompt, contains('PREVIOUSLY GENERATED QUESTIONS IN THIS EXAM'));
      expect(prompt, contains('Q1: Euler circuit condition'));
      expect(prompt, contains('Q2: Handshaking Lemma formula'));
      expect(prompt, contains('DIFFERENT key concept'));
      expect(prompt, contains('Do NOT repeat'));
    });

    test(
        'Requirement 3 & 4 & 26: Full 5-question sequential generation runs without cutoff',
        () async {
      final scope = RagScope.subjectUnit(
        subjectId: 'discrete_mathematics',
        subjectName: 'Discrete Mathematics',
        unitId: 'math-unit-1',
        unitName: 'Unit 1: Graph Theory & Recurrence Relations',
      );

      int progressCallbacks = 0;
      final exam = await quizService.generatePracticeExam(
        query:
            'Generate 5 practice exam questions with detailed answers based on Unit 1: Graph Theory & Recurrence Relations.',
        scope: scope,
        totalQuestions: 5,
        onProgress: (updatedExam) {
          progressCallbacks++;
        },
      );

      expect(exam.totalQuestions, 5);
      expect(exam.questions.length, 5);
      expect(exam.isCompleted, isTrue);
      expect(progressCallbacks, greaterThanOrEqualTo(5));

      // Verify EVERY single question is complete, valid, and not cut off!
      for (int i = 0; i < 5; i++) {
        final q = exam.questions[i];
        expect(q.questionNumber, i + 1);
        expect(q.status, QuizQuestionStatus.complete);
        expect(q.isValid, isTrue, reason: 'Question ${i + 1} must be valid');
        expect(q.question.isNotEmpty, isTrue,
            reason: 'Question text must not be empty');
        expect(q.answer.isNotEmpty, isTrue, reason: 'Answer must not be empty');
        expect(q.explanation.isNotEmpty, isTrue,
            reason: 'Explanation must not be empty');

        // Isolation check: zero presence of ROS or Polynomials!
        expect(q.question.contains('ROS'), isFalse);
        expect(q.question.contains('Polynomial'), isFalse);
        expect(q.answer.contains('ROS'), isFalse);
        expect(q.answer.contains('Polynomial'), isFalse);

        // Citations check
        for (final s in q.sources) {
          expect(s.chunk.subjectId, 'discrete_mathematics');
          expect(s.chunk.unitId, 'math-unit-1');
        }
      }

      // Verify markdown assembly
      final md = exam.toMarkdown();
      expect(
          md,
          contains(
              '### 📝 Practice Exam: **Discrete Mathematics · Unit 1: Graph Theory & Recurrence Relations**'));
      expect(md, contains('**Question 1 of 5**'));
      expect(md, contains('**Question 5 of 5**'));
    });

    test(
        'Requirement 10 & 25: Retrying a single failed question preserves other questions',
        () async {
      final scope = RagScope.subjectUnit(
        subjectId: 'discrete_mathematics',
        subjectName: 'Discrete Mathematics',
        unitId: 'math-unit-1',
        unitName: 'Unit 1: Graph Theory & Recurrence Relations',
      );

      // Initialize exam with Question 3 marked failed
      final exam = GroundedPracticeExam(
        id: 'test_exam_retry',
        scope: scope,
        totalQuestions: 5,
        citations: ragService.search(query: 'Graph Theory', scope: scope),
        questions: [
          GroundedQuizQuestion(
            questionNumber: 1,
            totalQuestions: 5,
            question: 'Question 1 about Euler circuits',
            answer: 'Even degree answer',
            explanation: 'Euler explanation',
            status: QuizQuestionStatus.complete,
          ),
          GroundedQuizQuestion(
            questionNumber: 2,
            totalQuestions: 5,
            question: 'Question 2 about Dirac theorem',
            answer: 'n/2 degree answer',
            explanation: 'Hamiltonian explanation',
            status: QuizQuestionStatus.complete,
          ),
          GroundedQuizQuestion(
            questionNumber: 3,
            totalQuestions: 5,
            question: '',
            answer: '',
            explanation: '',
            status: QuizQuestionStatus.failed,
            errorMessage: 'Cut off mid-generation',
          ),
          GroundedQuizQuestion(
            questionNumber: 4,
            totalQuestions: 5,
            question: 'Question 4 about Master Theorem',
            answer: 'T(n) formula',
            explanation: 'Divide-and-conquer explanation',
            status: QuizQuestionStatus.complete,
          ),
          GroundedQuizQuestion(
            questionNumber: 5,
            totalQuestions: 5,
            question: 'Question 5 about Planar graphs',
            answer: 'Kuratowski theorem answer',
            explanation: 'K5 and K3,3 explanation',
            status: QuizQuestionStatus.complete,
          ),
        ],
      );

      // Retry ONLY question index 2 (Question 3)
      final retrySuccess = await quizService.generateSingleQuestion(
        exam: exam,
        questionIndex: 2,
        isRetry: true,
        onProgress: (_) {},
      );

      expect(retrySuccess, isTrue);
      // Question 3 must now be complete!
      expect(exam.questions[2].status, QuizQuestionStatus.complete);
      expect(exam.questions[2].isValid, isTrue);
      expect(exam.questions[2].question.isNotEmpty, isTrue);

      // Crucially: Q1, Q2, Q4, Q5 were NOT touched or discarded!
      expect(exam.questions[0].question, 'Question 1 about Euler circuits');
      expect(exam.questions[1].question, 'Question 2 about Dirac theorem');
      expect(exam.questions[3].question, 'Question 4 about Master Theorem');
      expect(exam.questions[4].question, 'Question 5 about Planar graphs');
    });
  });
}
