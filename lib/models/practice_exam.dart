import 'rag_scope.dart';
import 'vault_item.dart';

enum QuizQuestionStatus {
  waiting,
  generating,
  complete,
  failed,
}

class GroundedQuizQuestion {
  final int questionNumber;
  final int totalQuestions;
  String question;
  String answer;
  String explanation;
  List<ChunkMatch> sources;
  QuizQuestionStatus status;
  String rawStreamingText;
  String? errorMessage;
  int retryCount;
  String? finishReason;

  GroundedQuizQuestion({
    required this.questionNumber,
    required this.totalQuestions,
    this.question = '',
    this.answer = '',
    this.explanation = '',
    this.sources = const [],
    this.status = QuizQuestionStatus.waiting,
    this.rawStreamingText = '',
    this.errorMessage,
    this.retryCount = 0,
    this.finishReason,
  });

  bool get isComplete => status == QuizQuestionStatus.complete;
  bool get isGenerating => status == QuizQuestionStatus.generating;
  bool get hasFailed => status == QuizQuestionStatus.failed;

  bool get isValid =>
      question.trim().isNotEmpty &&
      answer.trim().isNotEmpty &&
      explanation.trim().isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'questionNumber': questionNumber,
      'totalQuestions': totalQuestions,
      'question': question,
      'answer': answer,
      'explanation': explanation,
      'sources': sources.map((s) => s.toMap()).toList(),
      'status': status.name,
      'errorMessage': errorMessage,
      'retryCount': retryCount,
      'finishReason': finishReason,
    };
  }

  factory GroundedQuizQuestion.fromMap(Map<String, dynamic> map) {
    final rawSources = map['sources'] as List<dynamic>? ?? [];
    return GroundedQuizQuestion(
      questionNumber: map['questionNumber'] as int? ?? 1,
      totalQuestions: map['totalQuestions'] as int? ?? 5,
      question: map['question'] as String? ?? '',
      answer: map['answer'] as String? ?? '',
      explanation: map['explanation'] as String? ?? '',
      sources: rawSources
          .map((s) => ChunkMatch.fromMap(s as Map<String, dynamic>))
          .toList(),
      status: QuizQuestionStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => QuizQuestionStatus.complete,
      ),
      errorMessage: map['errorMessage'] as String?,
      retryCount: map['retryCount'] as int? ?? 0,
      finishReason: map['finishReason'] as String?,
    );
  }
}

class GroundedPracticeExam {
  final String id;
  final RagScope scope;
  final int totalQuestions;
  final List<GroundedQuizQuestion> questions;
  final List<ChunkMatch> citations;
  bool isCompleted;
  int activeIndex;

  GroundedPracticeExam({
    required this.id,
    required this.scope,
    required this.totalQuestions,
    required this.questions,
    required this.citations,
    this.isCompleted = false,
    this.activeIndex = 0,
  });

  int get completedCount =>
      questions.where((q) => q.status == QuizQuestionStatus.complete).length;

  int get failedCount =>
      questions.where((q) => q.status == QuizQuestionStatus.failed).length;

  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('### 📝 Practice Exam: **${scope.displayLabel}**\n');
    buffer.writeln(
        '*Generated on-device with Pal Local AI grounded in your Study Vault notes*\n');

    for (final q in questions) {
      if (q.isComplete) {
        buffer
            .writeln('**Question ${q.questionNumber} of ${q.totalQuestions}**');
        buffer.writeln(q.question);
        buffer.writeln();
        buffer.writeln('> **Answer:** ${q.answer}\n');
        buffer.writeln('> **Explanation:** ${q.explanation}\n');
        if (q.sources.isNotEmpty) {
          final srcList = q.sources
              .map((s) => '${s.chunk.documentName} (p.${s.chunk.pageNumber})')
              .toSet()
              .join(', ');
          buffer.writeln('*Sources: $srcList*\n');
        }
        buffer.writeln('---\n');
      }
    }
    return buffer.toString().trim();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'scope': scope.toMap(),
      'totalQuestions': totalQuestions,
      'questions': questions.map((q) => q.toMap()).toList(),
      'citations': citations.map((c) => c.toMap()).toList(),
      'isCompleted': isCompleted,
      'activeIndex': activeIndex,
    };
  }

  factory GroundedPracticeExam.fromMap(Map<String, dynamic> map) {
    final rawQuestions = map['questions'] as List<dynamic>? ?? [];
    final rawCitations = map['citations'] as List<dynamic>? ?? [];
    return GroundedPracticeExam(
      id: map['id'] as String,
      scope: RagScope.fromMap(map['scope'] as Map<String, dynamic>),
      totalQuestions: map['totalQuestions'] as int? ?? 5,
      questions: rawQuestions
          .map((q) => GroundedQuizQuestion.fromMap(q as Map<String, dynamic>))
          .toList(),
      citations: rawCitations
          .map((c) => ChunkMatch.fromMap(c as Map<String, dynamic>))
          .toList(),
      isCompleted: map['isCompleted'] as bool? ?? false,
      activeIndex: map['activeIndex'] as int? ?? 0,
    );
  }
}
