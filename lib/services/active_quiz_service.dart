import '../models/conversation_state.dart';

class ActiveQuizService {
  static final ActiveQuizService instance = ActiveQuizService._();
  ActiveQuizService._();

  /// Determines if a user message is requesting a quiz
  bool isQuizRequest(String query) {
    final lower = query.toLowerCase().trim();
    return lower.startsWith('quiz me') ||
        lower.contains('quiz me on') ||
        lower.contains('start a quiz') ||
        lower.contains('give me a quiz') ||
        lower.contains('test me on') ||
        lower.contains('practice exam') ||
        lower.contains('practice questions') ||
        lower.contains('exam questions') ||
        (lower.contains('quiz') && !isQuizAnswer(query));
  }

  /// Extracts option letter if input is an option answer (e.g. 'A', 'Option B', '(c)', 'd)')
  String? extractAnswerLetter(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    // Direct single letter
    final singleRegex = RegExp(r'^[A-Da-d]$');
    if (singleRegex.hasMatch(trimmed)) {
      return trimmed.toUpperCase();
    }

    // Pattern like "A)", "(A)", "[A]", "Option A", "Option: A", "Answer: A", "Choice A"
    final patternRegex = RegExp(
      r'^(?:option|answer|choice)?\s*[\(\[]?\s*([A-Da-d])\s*[\)\]\.\:]?$',
      caseSensitive: false,
    );
    final match = patternRegex.firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.toUpperCase();
    }

    return null;
  }

  /// Determines if a user message is a quiz answer attempt
  bool isQuizAnswer(String query) {
    return extractAnswerLetter(query) != null;
  }

  /// Creates a structured, deterministic quiz state for a given topic
  ActiveQuizState createQuiz({
    required String topic,
    String? subjectId,
    String? unitId,
  }) {
    final lowerTopic = topic.toLowerCase();
    final quizId = 'quiz_${DateTime.now().millisecondsSinceEpoch}';

    if (lowerTopic.contains('network') ||
        lowerTopic.contains('tcp') ||
        lowerTopic.contains('udp')) {
      return ActiveQuizState(
        id: quizId,
        topic: 'Computer Networks',
        questions: [
          ActiveQuizQuestion(
            number: 1,
            question:
                'At which layer of the OSI model does the Transmission Control Protocol (TCP) operate?',
            options: {
              'A': 'Network Layer',
              'B': 'Transport Layer',
              'C': 'Data Link Layer',
              'D': 'Application Layer',
            },
            correctLetter: 'B',
            explanation:
                'TCP is a core protocol of the Transport Layer, responsible for reliable end-to-end communication and byte-stream delivery.',
          ),
          ActiveQuizQuestion(
            number: 2,
            question:
                'What mechanism does TCP use to establish a reliable connection before data transfer?',
            options: {
              'A': 'Two-way handshake',
              'B': 'Three-way handshake (SYN, SYN-ACK, ACK)',
              'C': 'Four-way handshake',
              'D': 'Stateless UDP broadcast',
            },
            correctLetter: 'B',
            explanation:
                'TCP uses a three-way handshake (SYN, SYN-ACK, ACK) to synchronize sequence numbers and establish connection parameters.',
          ),
          ActiveQuizQuestion(
            number: 3,
            question:
                'Which protocol is preferred for real-time applications like video streaming and gaming where speed is prioritized over reliability?',
            options: {
              'A': 'TCP',
              'B': 'FTP',
              'C': 'UDP',
              'D': 'SMTP',
            },
            correctLetter: 'C',
            explanation:
                'UDP (User Datagram Protocol) is connectionless and lightweight without retransmission overhead, making it ideal for low-latency streaming.',
          ),
        ],
      );
    }

    if (lowerTopic.contains('discrete') ||
        lowerTopic.contains('graph') ||
        lowerTopic.contains('math')) {
      return ActiveQuizState(
        id: quizId,
        topic: 'Discrete Mathematics',
        questions: [
          ActiveQuizQuestion(
            number: 1,
            question:
                'According to Euler\'s theorem, an undirected connected graph contains an Euler circuit if and only if:',
            options: {
              'A': 'Every vertex has an odd degree',
              'B': 'Every vertex has an even degree',
              'C': 'It contains no cycles',
              'D': 'It is a complete bipartite graph',
            },
            correctLetter: 'B',
            explanation:
                'An undirected connected graph has an Euler circuit if and only if every vertex has an even degree.',
          ),
          ActiveQuizQuestion(
            number: 2,
            question:
                'By the Handshaking Lemma, what is the sum of degrees of all vertices in an undirected graph?',
            options: {
              'A': 'Equal to the number of edges: |E|',
              'B': 'Twice the number of edges: 2|E|',
              'C': 'The square of the number of vertices: |V|^2',
              'D': 'Half the number of edges: |E| / 2',
            },
            correctLetter: 'B',
            explanation:
                'Each undirected edge has two endpoints, contributing exactly 2 to the sum of vertex degrees: sum(deg(v)) = 2|E|.',
          ),
          ActiveQuizQuestion(
            number: 3,
            question:
                'Which theorem states that a finite graph is planar if and only if it does not contain a subgraph homeomorphic to K5 or K3,3?',
            options: {
              'A': 'Dirac\'s Theorem',
              'B': 'Kuratowski\'s Theorem',
              'C': 'Four Color Theorem',
              'D': 'Master Theorem',
            },
            correctLetter: 'B',
            explanation:
                'Kuratowski\'s Theorem characterizes planar graphs by forbidden topological minors homeomorphic to K5 or K3,3.',
          ),
        ],
      );
    }

    // Default: Operating Systems Concepts (as specifically prompted by user)
    return ActiveQuizState(
      id: quizId,
      topic: 'Operating Systems Concepts',
      questions: [
        ActiveQuizQuestion(
          number: 1,
          question:
              'What is the primary function of the kernel in an operating system?',
          options: {
            'A': 'Manage hardware resources and system communication',
            'B': 'Provide a graphical user interface',
            'C': 'Compile high-level programming languages',
            'D': 'Route network packets between local hosts',
          },
          correctLetter: 'A',
          explanation:
              'The kernel is the core component of an operating system that manages system resources (CPU, memory, devices) and facilitates communication between hardware and application software.',
        ),
        ActiveQuizQuestion(
          number: 2,
          question:
              'What is the primary purpose of virtual memory in modern operating systems?',
          options: {
            'A': 'To increase physical CPU clock frequency',
            'B':
                'To allow execution of processes that may not be completely in physical RAM',
            'C': 'To eliminate the need for persistent secondary storage',
            'D': 'To compile machine code directly into hardware registers',
          },
          correctLetter: 'B',
          explanation:
              'Virtual memory provides an abstraction of main memory, enabling processes to address a large contiguous memory space regardless of physical RAM fragmentation and isolation.',
        ),
        ActiveQuizQuestion(
          number: 3,
          question: 'In process synchronization, what is a "critical section"?',
          options: {
            'A': 'The portion of code executed strictly during system boot',
            'B':
                'A code segment that accesses shared resources and must not be concurrently executed by multiple threads',
            'C': 'The memory segment reserved exclusively for device drivers',
            'D': 'The CPU cache hierarchy dedicated to interrupt vectors',
          },
          correctLetter: 'B',
          explanation:
              'A critical section is a sequence of instructions where shared data or hardware resources are accessed, requiring mutual exclusion to prevent race conditions.',
        ),
      ],
    );
  }

  /// Evaluates an answer for the current question and advances the state
  String evaluateAnswer({
    required ActiveQuizState quiz,
    required String answerLetter,
  }) {
    final currentQ = quiz.currentQuestion;
    if (currentQ == null) {
      return 'No active question found in this quiz.';
    }

    final isCorrect = answerLetter.toUpperCase() == currentQ.correctLetter;
    currentQ.selectedLetter = answerLetter.toUpperCase();
    currentQ.isCorrect = isCorrect;

    if (isCorrect) {
      quiz.score++;
    }

    final buffer = StringBuffer();

    // 1. Immediate answer feedback
    if (isCorrect) {
      buffer.writeln(
          '✅ **Correct!** (${currentQ.correctLetter}: ${currentQ.options[currentQ.correctLetter]})');
    } else {
      buffer.writeln(
          '❌ **Incorrect.** You selected **${answerLetter.toUpperCase()}**, but the correct answer is **${currentQ.correctLetter}** (${currentQ.options[currentQ.correctLetter]}).');
    }
    buffer.writeln();
    buffer.writeln('> ${currentQ.explanation}');
    buffer.writeln();

    // 2. Advance to next question or complete quiz
    quiz.currentQuestionIndex++;

    if (quiz.currentQuestionIndex < quiz.questions.length) {
      final nextQ = quiz.questions[quiz.currentQuestionIndex];
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln('**Question ${nextQ.number} of ${quiz.totalQuestions}:**');
      buffer.writeln(nextQ.question);
      buffer.writeln();

      for (final entry in nextQ.options.entries) {
        buffer.writeln('${entry.key}) ${entry.value}');
      }
      buffer.writeln();
      buffer.write('Please respond with the letter of your answer.');
    } else {
      quiz.isCompleted = true;
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln('🎉 **Quiz Complete!**');
      buffer.writeln(
          'You scored **${quiz.score} / ${quiz.totalQuestions}** (${(quiz.score / quiz.totalQuestions * 100).round()}%).');
      buffer.writeln();
      if (quiz.score == quiz.totalQuestions) {
        buffer.write('Excellent work! You mastered all the concepts.');
      } else {
        buffer.write('Good effort! Keep reviewing the concepts above.');
      }
    }

    return buffer.toString();
  }
}
