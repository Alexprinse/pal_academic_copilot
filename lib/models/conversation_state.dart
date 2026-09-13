enum ActiveMode {
  chat,
  quiz,
  task,
  recording,
}

class ActiveQuizQuestion {
  final int number;
  final String question;
  final Map<String, String> options;
  final String correctLetter;
  final String explanation;
  String? selectedLetter;
  bool? isCorrect;

  ActiveQuizQuestion({
    required this.number,
    required this.question,
    required this.options,
    required this.correctLetter,
    required this.explanation,
    this.selectedLetter,
    this.isCorrect,
  });

  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'question': question,
      'options': options,
      'correctLetter': correctLetter,
      'explanation': explanation,
      'selectedLetter': selectedLetter,
      'isCorrect': isCorrect,
    };
  }

  factory ActiveQuizQuestion.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['options'] as Map<dynamic, dynamic>? ?? {};
    final stringOptions = rawOptions.map(
      (key, value) => MapEntry(key.toString().toUpperCase(), value.toString()),
    );

    return ActiveQuizQuestion(
      number: map['number'] as int? ?? 1,
      question: map['question'] as String? ?? '',
      options: stringOptions,
      correctLetter: (map['correctLetter'] as String? ?? 'A').toUpperCase(),
      explanation: map['explanation'] as String? ?? '',
      selectedLetter: (map['selectedLetter'] as String?)?.toUpperCase(),
      isCorrect: map['isCorrect'] as bool?,
    );
  }
}

class ActiveQuizState {
  final String id;
  final String topic;
  final List<ActiveQuizQuestion> questions;
  int currentQuestionIndex;
  bool isCompleted;
  int score;

  ActiveQuizState({
    required this.id,
    required this.topic,
    required this.questions,
    this.currentQuestionIndex = 0,
    this.isCompleted = false,
    this.score = 0,
  });

  ActiveQuizQuestion? get currentQuestion =>
      (currentQuestionIndex >= 0 && currentQuestionIndex < questions.length)
          ? questions[currentQuestionIndex]
          : null;

  int get totalQuestions => questions.length;

  String formatCurrentQuestion() {
    final q = currentQuestion;
    if (q == null) return '';

    final buffer = StringBuffer();
    if (currentQuestionIndex == 0) {
      buffer.writeln("I'll pose a question, and you try to answer!");
      buffer.writeln();
      buffer.writeln("Here's your first question:");
    } else {
      buffer.writeln('**Question ${q.number} of $totalQuestions:**');
    }
    buffer.writeln(q.question);
    buffer.writeln();

    for (final entry in q.options.entries) {
      buffer.writeln('${entry.key}) ${entry.value}');
    }
    buffer.writeln();
    buffer.write('Please respond with the letter of your answer.');
    return buffer.toString();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'topic': topic,
      'questions': questions.map((q) => q.toMap()).toList(),
      'currentQuestionIndex': currentQuestionIndex,
      'isCompleted': isCompleted,
      'score': score,
    };
  }

  factory ActiveQuizState.fromMap(Map<String, dynamic> map) {
    final rawQuestions = map['questions'] as List<dynamic>? ?? [];
    return ActiveQuizState(
      id: map['id'] as String? ?? '',
      topic: map['topic'] as String? ?? 'General Academic',
      questions: rawQuestions
          .map((q) => ActiveQuizQuestion.fromMap(q as Map<String, dynamic>))
          .toList(),
      currentQuestionIndex: map['currentQuestionIndex'] as int? ?? 0,
      isCompleted: map['isCompleted'] as bool? ?? false,
      score: map['score'] as int? ?? 0,
    );
  }
}
