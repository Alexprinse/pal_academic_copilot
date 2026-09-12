import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class QuizQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String citation;
  final String topic;
  final String difficulty;

  const QuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.citation,
    required this.topic,
    this.difficulty = 'Medium',
  });
}

class QuizScreen extends StatefulWidget {
  final VoidCallback? onOpenVaultCitations;

  const QuizScreen({super.key, this.onOpenVaultCitations});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _currentIndex = 0;
  int? _selectedIndex;
  bool _hasSubmitted = false;
  int _correctCount = 0;

  final List<QuizQuestion> _questions = const [
    QuizQuestion(
      question:
          'Which normal form eliminates transitive functional dependencies on the primary key?',
      options: [
        'First Normal Form (1NF)',
        'Second Normal Form (2NF)',
        'Third Normal Form (3NF)',
        'Boyce-Codd Normal Form (BCNF)',
      ],
      correctIndex: 2,
      citation: 'Answer is 3NF — sourced from Ch.4 Database Systems, p. 114',
      topic: 'Database Normalization',
      difficulty: 'Medium',
    ),
    QuizQuestion(
      question:
          'Which of the following is NOT one of the three requirements for a solution to the critical-section problem?',
      options: [
        'Mutual Exclusion',
        'Progress',
        'Bounded Waiting',
        'Preemptive Priority Inversion',
      ],
      correctIndex: 3,
      citation: 'Answer is Preemptive Priority Inversion — sourced from Silberschatz OS §6.3, p. 142',
      topic: 'Peterson\'s Algorithm & Semaphores',
      difficulty: 'Hard',
    ),
    QuizQuestion(
      question:
          'What is the optical path difference in Young\'s double-slit experiment for constructive interference?',
      options: [
        'Δx = (2n + 1) · λ / 2',
        'Δx = n · λ',
        'Δx = n · λ / 4',
        'Δx = 2n · π',
      ],
      correctIndex: 1,
      citation: 'Answer is Δx = n · λ — sourced from Wave Optics Handbook, p. 48',
      topic: 'Wave Optics Interference',
      difficulty: 'Easy',
    ),
  ];

  void _selectOption(int index) {
    if (_hasSubmitted) return;
    setState(() {
      _selectedIndex = index;
      _hasSubmitted = true;
      if (index == _questions[_currentIndex].correctIndex) {
        _correctCount++;
      }
    });
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedIndex = null;
        _hasSubmitted = false;
      });
    } else {
      setState(() {
        _currentIndex++;
      });
    }
  }

  void _restartQuiz() {
    setState(() {
      _currentIndex = 0;
      _selectedIndex = null;
      _hasSubmitted = false;
      _correctCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isQuizFinished = _currentIndex >= _questions.length;

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Practice Quiz',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: isQuizFinished ? _buildResultsView() : _buildQuizView(),
        ),
      ),
    );
  }

  Widget _buildQuizView() {
    final currentQ = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),

        // Top Row: Question counter and difficulty pill
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'QUESTION ${_currentIndex + 1} OF ${_questions.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppTheme.textSecondary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.neutralPillFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Text(
                currentQ.difficulty,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.neutralPillText,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Progress bar in #B88628 on a #EAE6DC track
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppTheme.cardBorder,
            color: AppTheme.primaryAccent,
          ),
        ),

        const SizedBox(height: 20),

        // Question Card: White (#FFFFFF, #EAE6DC border, soft shadow), primary text #1E1D19
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentQ.topic,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryAccent,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                currentQ.question,
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Answer Options as individual cards
        Expanded(
          child: ListView.separated(
            itemCount: currentQ.options.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final optionText = currentQ.options[index];
              final isSelected = _selectedIndex == index;
              final isCorrect = index == currentQ.correctIndex;

              // Styling per prompt specifications
              Color cardBg = AppTheme.cardSurface;
              Color borderCol = AppTheme.cardBorder;
              Color textColor = AppTheme.textPrimary;
              Widget? trailingIcon;

              if (_hasSubmitted) {
                if (isCorrect) {
                  // Correct answer: #EAF2EC fill with #2D6A4F text and checkmark
                  cardBg = AppTheme.trustPillFill;
                  borderCol = AppTheme.trustPillText.withValues(alpha: 0.35);
                  textColor = AppTheme.trustPillText;
                  trailingIcon = const Icon(Icons.check_circle,
                      color: AppTheme.trustPillText, size: 20);
                } else if (isSelected) {
                  // Incorrect chosen: #FBEAE7 fill with #C0392B text and X (soft terracotta)
                  cardBg = AppTheme.overduePillFill;
                  borderCol = AppTheme.overduePillText.withValues(alpha: 0.35);
                  textColor = AppTheme.overduePillText;
                  trailingIcon = const Icon(Icons.cancel,
                      color: AppTheme.overduePillText, size: 20);
                }
              }

              return InkWell(
                onTap: () => _selectOption(index),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderCol, width: 1.2),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          optionText,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                      if (trailingIcon != null) ...[
                        const SizedBox(width: 8),
                        trailingIcon,
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Below the answer: citation caption in #706C62
        if (_hasSubmitted) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.neutralPillFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📖', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentQ.citation,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                      height: 1.35,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // "Next question" button: full-width, dark #1E1D19, rounded
        if (_hasSubmitted)
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _nextQuestion,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.darkSurface,
                foregroundColor: AppTheme.canvasBg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _currentIndex < _questions.length - 1
                    ? 'Next question →'
                    : 'View Quiz Summary',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildResultsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        // Score Header Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: AppTheme.cardDecoration,
          child: Column(
            children: [
              const Text(
                'Quiz Completed',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_correctCount / ${_questions.length}',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Keep going — revise your identified weak topics below.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Weak-Topic Result Card: soft peach/amber fill (#FDF4E7), warning icon,
        // topic name + mastery percentage, and "Re-read 2 Citations in Vault" in #B88628
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.detectedPillFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.detectedPillText.withValues(alpha: 0.3),
            ),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: AppTheme.detectedPillText, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'WEAK TOPIC IDENTIFIED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppTheme.detectedPillText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Peterson\'s Algorithm & Semaphores',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Topic Mastery: 42% · Missed critical section conditions',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.detectedPillText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),

              // "Re-read 2 Citations in Vault" action button in #B88628
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () {
                    widget.onOpenVaultCitations?.call();
                    Navigator.of(context).maybePop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text(
                    'Re-read 2 Citations in Vault',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        // Bottom CTA to retry
        SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: _restartQuiz,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.cardBorder, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Practice Again',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}
