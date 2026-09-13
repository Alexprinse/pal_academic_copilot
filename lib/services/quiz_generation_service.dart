import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/practice_exam.dart';
import '../models/rag_scope.dart';
import '../models/vault_item.dart';
import 'llm_service.dart';
import 'rag_service.dart';

export '../models/practice_exam.dart';

/// Service responsible for robust, independent, sequential quiz generation
/// running reliably on on-device LLMs (1B / 0.5B parameters).
class QuizGenerationService {
  static final QuizGenerationService instance = QuizGenerationService._();
  QuizGenerationService._();

  final LlmService _llmService = LlmService.instance;
  final RagService _ragService = RagService.instance;

  /// Generates a full practice exam question-by-question with progressive callbacks
  Future<GroundedPracticeExam> generatePracticeExam({
    required String query,
    required RagScope scope,
    int totalQuestions = 5,
    required void Function(GroundedPracticeExam exam) onProgress,
  }) async {
    // 1. Retrieve validated RAG context strictly once for this exam
    final citations = _ragService.search(
      query: query,
      scope: scope,
      topK: 5,
    );

    // Requirement 19 & 20: Validate citations strictly match scope
    final validatedCitations = citations.where((c) {
      if (!scope.matchesChunk(c.chunk)) {
        debugPrint(
          '[QUIZ_SOURCE_REJECTED] Chunk "${c.chunk.id}" (${c.chunk.subjectName} / ${c.chunk.unitName}) rejected from quiz scope: ${scope.displayLabel}',
        );
        return false;
      }
      return true;
    }).toList();

    // 2. Initialize exam state with waiting questions
    final exam = GroundedPracticeExam(
      id: 'quiz_${DateTime.now().millisecondsSinceEpoch}',
      scope: scope,
      totalQuestions: totalQuestions,
      citations: validatedCitations,
      questions: List.generate(
        totalQuestions,
        (i) => GroundedQuizQuestion(
          questionNumber: i + 1,
          totalQuestions: totalQuestions,
          status: QuizQuestionStatus.waiting,
        ),
      ),
    );

    onProgress(exam);

    if (validatedCitations.isEmpty && scope.type != RagScopeType.off) {
      debugPrint(
          '[QUIZ] No validated citations found in scope: ${scope.displayLabel}');
      return exam;
    }

    // 3. Sequential Question Generation: Q1 -> Q2 -> Q3 -> Q4 -> Q5
    for (int i = 0; i < totalQuestions; i++) {
      exam.activeIndex = i;
      await generateSingleQuestion(
        exam: exam,
        questionIndex: i,
        onProgress: onProgress,
      );
    }

    exam.isCompleted = true;
    onProgress(exam);
    return exam;
  }

  /// Generates or retries an individual question at [questionIndex]
  Future<bool> generateSingleQuestion({
    required GroundedPracticeExam exam,
    required int questionIndex,
    bool isRetry = false,
    required void Function(GroundedPracticeExam exam) onProgress,
  }) async {
    if (questionIndex < 0 || questionIndex >= exam.questions.length) {
      return false;
    }

    final targetQuestion = exam.questions[questionIndex];
    targetQuestion.status = QuizQuestionStatus.generating;
    targetQuestion.rawStreamingText = '';
    targetQuestion.errorMessage = null;
    onProgress(exam);

    // Build list of previously generated questions for diversity (Requirement 8)
    final previousQuestions = <String>[];
    for (int j = 0; j < exam.questions.length; j++) {
      if (j != questionIndex &&
          exam.questions[j].status == QuizQuestionStatus.complete &&
          exam.questions[j].question.isNotEmpty) {
        previousQuestions.add(
          'Q${exam.questions[j].questionNumber}: ${exam.questions[j].question}',
        );
      }
    }

    // Build compact per-question prompt (Requirement 16 & 17)
    final prompt = buildCompactQuizPrompt(
      questionNumber: targetQuestion.questionNumber,
      totalQuestions: exam.totalQuestions,
      scope: exam.scope,
      citations: exam.citations,
      previousQuestions: previousQuestions,
      isRetry: isRetry,
    );

    final systemPrompt =
        'You are Pal, an academic exam question generator running on-device.\n'
        'Scope: ${exam.scope.subjectName ?? "Subject"} > ${exam.scope.unitName ?? "Unit"}\n'
        'Generate exactly ONE practice exam question grounded ONLY in the supplied study material.\n'
        'Do not invent facts or mention other subjects.';

    final sw = Stopwatch()..start();
    final accumulated = StringBuffer();
    String? errorMsg;
    String finishReason = 'completed';

    const int maxTokensPerQuestion =
        384; // Sufficient for 1 concise question, answer, explanation

    try {
      final tokenStream = _llmService.generateStreaming(
        prompt: prompt,
        systemPrompt: systemPrompt,
        maxTokens: maxTokensPerQuestion,
        conversationHistory: const [], // Isolated prompt: do not leak global chat history
      );

      await for (final token in tokenStream) {
        accumulated.write(token);
        targetQuestion.rawStreamingText = accumulated.toString();
        onProgress(exam);
      }

      finishReason = _llmService.lastFinishReason;
    } catch (e) {
      errorMsg = e.toString();
      finishReason = 'error';
    } finally {
      sw.stop();
    }

    final generatedText = accumulated.toString();

    // Requirement 2: LOG GENERATION METADATA
    debugPrint('========================================');
    debugPrint('[QUIZ_LLM]');
    debugPrint('requestedQuestions: ${exam.totalQuestions}');
    debugPrint('questionIndex: ${targetQuestion.questionNumber}');
    debugPrint('maxOutputTokens: $maxTokensPerQuestion');
    debugPrint('promptTokens: ~${(prompt.length / 4).round()}');
    debugPrint('generatedTokens: ${_llmService.lastGeneratedTokens}');
    debugPrint('finishReason: $finishReason');
    debugPrint('generationTime: ${sw.elapsedMilliseconds}ms');
    debugPrint('error: ${errorMsg ?? "none"}');
    debugPrint('========================================');

    // Requirement 12: Validate parsed output strictly
    final parsed = parseQuestionOutput(
      text: generatedText,
      questionNumber: targetQuestion.questionNumber,
      totalQuestions: exam.totalQuestions,
      candidateSources: exam.citations,
      scope: exam.scope,
    );

    final bool isMalformed = generatedText.contains('I heard:') ||
        generatedText.contains('[1] [2] [3]');

    if (parsed != null && parsed.isValid && !isMalformed && errorMsg == null) {
      targetQuestion.question = parsed.question;
      targetQuestion.answer = parsed.answer;
      targetQuestion.explanation = parsed.explanation;
      targetQuestion.sources = parsed.sources;
      targetQuestion.status = QuizQuestionStatus.complete;
      targetQuestion.finishReason = finishReason;
      targetQuestion.errorMessage = null;
      onProgress(exam);
      return true;
    }

    // Incomplete output or generation failure detected!
    debugPrint(
      '[QUIZ_INCOMPLETE] Question ${targetQuestion.questionNumber} generation was invalid or truncated. Reason: $finishReason. Malformed: $isMalformed',
    );

    // Requirement 11: Automatic Retry once for transient failure
    if (!isRetry && targetQuestion.retryCount < 1) {
      targetQuestion.retryCount++;
      debugPrint(
          '[QUIZ_RETRY] Retrying Question ${targetQuestion.questionNumber} once automatically...');
      return await generateSingleQuestion(
        exam: exam,
        questionIndex: questionIndex,
        isRetry: true,
        onProgress: onProgress,
      );
    }

    // Mark question as failed so user can manually retry it without losing others (Requirement 10 & 25)
    targetQuestion.status = QuizQuestionStatus.failed;
    targetQuestion.finishReason = finishReason;
    targetQuestion.errorMessage =
        'Question ${targetQuestion.questionNumber} could not be generated completely.';
    onProgress(exam);
    return false;
  }

  /// Builds a dedicated compact prompt for generating a single question (Requirement 16 & 17)
  static String buildCompactQuizPrompt({
    required int questionNumber,
    required int totalQuestions,
    required RagScope scope,
    required List<ChunkMatch> citations,
    required List<String> previousQuestions,
    bool isRetry = false,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('=== ACADEMIC STUDY MATERIAL ===');
    for (int i = 0; i < citations.length; i++) {
      final c = citations[i];
      buffer.writeln(
          '[Source ${i + 1}: ${c.chunk.documentName}, p.${c.chunk.pageNumber}]:');
      buffer.writeln(c.chunk.text.trim());
      buffer.writeln();
    }
    buffer.writeln('=== END STUDY MATERIAL ===\n');

    if (previousQuestions.isNotEmpty) {
      buffer.writeln('=== PREVIOUSLY GENERATED QUESTIONS IN THIS EXAM ===');
      for (final prev in previousQuestions) {
        buffer.writeln('• $prev');
      }
      buffer.writeln(
          'IMPORTANT: Generate a question testing a DIFFERENT key concept. Do NOT repeat or overlap with previous questions.');
      buffer.writeln('=== END PREVIOUS QUESTIONS ===\n');
    }

    if (isRetry) {
      buffer.writeln(
          'NOTE: The previous attempt was incomplete or cut off. Keep your answer and explanation concise so they do not get cut off.\n');
    }

    buffer.writeln('INSTRUCTIONS:');
    buffer.writeln(
        'Generate practice exam Question $questionNumber of $totalQuestions.');
    buffer.writeln('Subject: ${scope.subjectName ?? "Selected Subject"}');
    buffer.writeln('Unit: ${scope.unitName ?? "Selected Unit"}');
    buffer.writeln('Topic: ${scope.displayLabel}');
    buffer.writeln('Length constraints:');
    buffer.writeln('- Question: 1–2 sentences');
    buffer.writeln('- Answer: 2–5 sentences');
    buffer.writeln('- Explanation: 2–5 sentences');
    buffer.writeln('Return STRICTLY in this format with nothing else:');
    buffer.writeln('QUESTION:');
    buffer.writeln('[Your question text]');
    buffer.writeln('ANSWER:');
    buffer.writeln('[Your direct answer]');
    buffer.writeln('EXPLANATION:');
    buffer.writeln('[Your explanation grounded in the study material]');

    return buffer.toString();
  }

  /// Parses text strictly into question, answer, and explanation (Requirement 5 & 12)
  static GroundedQuizQuestion? parseQuestionOutput({
    required String text,
    required int questionNumber,
    required int totalQuestions,
    required List<ChunkMatch> candidateSources,
    required RagScope scope,
  }) {
    if (text.trim().isEmpty) return null;

    final qPattern = RegExp(
        r'(?:^|\n)\s*(?:\*\*)?QUESTION\s*(?:\d+)?(?:\*\*)?\s*:\s*',
        caseSensitive: false);
    final aPattern = RegExp(r'(?:^|\n)\s*(?:\*\*)?ANSWER(?:\*\*)?\s*:\s*',
        caseSensitive: false);
    final ePattern = RegExp(r'(?:^|\n)\s*(?:\*\*)?EXPLANATION(?:\*\*)?\s*:\s*',
        caseSensitive: false);

    final qMatch = qPattern.firstMatch(text);
    final aMatch = aPattern.firstMatch(text);
    final eMatch = ePattern.firstMatch(text);

    String question = '';
    String answer = '';
    String explanation = '';

    if (qMatch != null && aMatch != null && aMatch.start > qMatch.end) {
      question = text.substring(qMatch.end, aMatch.start).trim();

      if (eMatch != null && eMatch.start > aMatch.end) {
        answer = text.substring(aMatch.end, eMatch.start).trim();
        explanation = text.substring(eMatch.end).trim();
      } else {
        // Missing explanation marker
        answer = text.substring(aMatch.end).trim();
      }
    } else {
      // Fallback parser for markdown bold headers: **Question:** / **Answer:** / **Explanation:**
      final lines = text.split('\n');
      String currentSection = '';
      final qLines = <String>[];
      final aLines = <String>[];
      final eLines = <String>[];

      for (final rawLine in lines) {
        final line = rawLine.trim();
        final lower = line.toLowerCase();
        if (lower.startsWith('**question') || lower.startsWith('question:')) {
          currentSection = 'q';
          final colonIdx = line.indexOf(':');
          if (colonIdx != -1 && colonIdx < line.length - 1) {
            qLines
                .add(line.substring(colonIdx + 1).replaceAll('**', '').trim());
          }
        } else if (lower.startsWith('**answer') ||
            lower.startsWith('> **answer') ||
            lower.startsWith('answer:')) {
          currentSection = 'a';
          final colonIdx = line.indexOf(':');
          if (colonIdx != -1 && colonIdx < line.length - 1) {
            aLines.add(line
                .substring(colonIdx + 1)
                .replaceAll('**', '')
                .replaceAll('>', '')
                .trim());
          }
        } else if (lower.startsWith('**explanation') ||
            lower.startsWith('> **explanation') ||
            lower.startsWith('explanation:')) {
          currentSection = 'e';
          final colonIdx = line.indexOf(':');
          if (colonIdx != -1 && colonIdx < line.length - 1) {
            eLines.add(line
                .substring(colonIdx + 1)
                .replaceAll('**', '')
                .replaceAll('>', '')
                .trim());
          }
        } else if (line.isNotEmpty && !line.startsWith('---')) {
          if (currentSection == 'q') {
            qLines.add(line);
          } else if (currentSection == 'a') {
            aLines.add(line.replaceAll('>', '').trim());
          } else if (currentSection == 'e') {
            eLines.add(line.replaceAll('>', '').trim());
          }
        }
      }

      question = qLines.join(' ').trim();
      answer = aLines.join(' ').trim();
      explanation = eLines.join(' ').trim();
    }

    // Clean markdown asterisks and residual prefixes
    question = question.replaceAll(RegExp(r'^\*+|\*+$'), '').trim();
    answer = answer.replaceAll(RegExp(r'^\*+|\*+$'), '').trim();
    explanation = explanation.replaceAll(RegExp(r'^\*+|\*+$'), '').trim();

    // Strict validation (Requirement 12)
    if (question.isEmpty || answer.isEmpty || explanation.isEmpty) {
      return null;
    }

    // Assign only matching sources within scope
    final matchedSources = candidateSources
        .where((c) => scope.matchesChunk(c.chunk))
        .take(2)
        .toList();

    return GroundedQuizQuestion(
      questionNumber: questionNumber,
      totalQuestions: totalQuestions,
      question: question,
      answer: answer,
      explanation: explanation,
      sources: matchedSources,
      status: QuizQuestionStatus.complete,
    );
  }
}
