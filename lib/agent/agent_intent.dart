enum AgentIntent {
  scheduleQuery,
  taskQuery,
  deadlineQuery,
  lectureQuery,
  vaultSearch,
  messQuery,
  holidayQuery,
  academicCalendarQuery,
  recordingAction,
  timetableAction,
  taskAction,
  generalAcademicQuery;

  String get code {
    switch (this) {
      case AgentIntent.scheduleQuery:
        return 'SCHEDULE_QUERY';
      case AgentIntent.taskQuery:
        return 'TASK_QUERY';
      case AgentIntent.deadlineQuery:
        return 'DEADLINE_QUERY';
      case AgentIntent.lectureQuery:
        return 'LECTURE_QUERY';
      case AgentIntent.vaultSearch:
        return 'VAULT_SEARCH';
      case AgentIntent.messQuery:
        return 'MESS_QUERY';
      case AgentIntent.holidayQuery:
        return 'HOLIDAY_QUERY';
      case AgentIntent.academicCalendarQuery:
        return 'ACADEMIC_CALENDAR_QUERY';
      case AgentIntent.recordingAction:
        return 'RECORDING_ACTION';
      case AgentIntent.timetableAction:
        return 'TIMETABLE_ACTION';
      case AgentIntent.taskAction:
        return 'TASK_ACTION';
      case AgentIntent.generalAcademicQuery:
        return 'GENERAL_ACADEMIC_QUERY';
    }
  }

  /// Categorizes a user query into one or more academic intents.
  /// Strictly isolates the entity (class vs task/deadline) from temporal modifiers
  /// (upcoming, next, today, tomorrow).
  static List<AgentIntent> detectIntents(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return [AgentIntent.generalAcademicQuery];
    final lower = clean.toLowerCase();

    // 1. Multi-clause split check for compound questions:
    // e.g. "What is my next class and what assignments are due today?"
    final clauseSeparators = RegExp(
        r'(?:\s+(?:and|&|also)\s+|[;?]\s*(?:also\s+)?)',
        caseSensitive: false);
    if (clauseSeparators.hasMatch(lower)) {
      final clauses = lower.split(clauseSeparators);
      final combinedIntents = <AgentIntent>{};
      for (final clause in clauses) {
        final trimmed = clause.trim();
        if (trimmed.isNotEmpty) {
          final clauseIntent = _detectSingleClauseIntent(trimmed);
          if (clauseIntent != AgentIntent.generalAcademicQuery) {
            combinedIntents.add(clauseIntent);
          }
        }
      }
      if (combinedIntents.length > 1) {
        return combinedIntents.toList();
      }
    }

    // 2. Single-intent classification
    return [_detectSingleClauseIntent(lower)];
  }

  /// Detects the primary intent of a single clause or prompt.
  static AgentIntent detectPrimaryIntent(String input) {
    return detectIntents(input).first;
  }

  static AgentIntent _detectSingleClauseIntent(String lower) {
    final cleanLower = lower
        .replaceFirst(
            RegExp(
                r'^(?:(?:hey|hi|a|ok|he)?\s*(?:pal|paul|hebbal|apple|bell)|hebbal|apple)[,\s]*',
                caseSensitive: false),
            '')
        .trim();

    // ----------------------------------------------------
    // Action Intents (Destructive / Mutation / Recording)
    // Absolute priority over read-only queries
    // ----------------------------------------------------
    if (_isRecordingAction(cleanLower)) {
      return AgentIntent.recordingAction;
    }
    if (_isTaskAction(cleanLower)) {
      return AgentIntent.taskAction;
    }
    if (_isTimetableAction(cleanLower)) {
      return AgentIntent.timetableAction;
    }

    // ----------------------------------------------------
    // Deadline & Task Keywords (Noun/Entity Priority)
    // ----------------------------------------------------
    final hasDeadlineWords = _hasDeadlineVocabulary(cleanLower);
    final hasTaskWords = _hasTaskVocabulary(cleanLower);

    // If query asks about deadlines or due dates:
    if (hasDeadlineWords) {
      return AgentIntent.deadlineQuery;
    }

    // If query asks about assignments/tasks (without explicit due/deadline words):
    if (hasTaskWords) {
      return AgentIntent.taskQuery;
    }

    // ----------------------------------------------------
    // Schedule / Timetable / Class Queries
    // ----------------------------------------------------
    if (_isScheduleQuery(cleanLower)) {
      return AgentIntent.scheduleQuery;
    }

    // ----------------------------------------------------
    // Campus Auxiliary Information Queries
    // ----------------------------------------------------
    if (_isHolidayQuery(cleanLower)) {
      return AgentIntent.holidayQuery;
    }
    if (_isMessQuery(cleanLower)) {
      return AgentIntent.messQuery;
    }
    if (_isAcademicCalendarQuery(cleanLower)) {
      return AgentIntent.academicCalendarQuery;
    }
    if (_isLectureQuery(cleanLower)) {
      return AgentIntent.lectureQuery;
    }
    if (_isVaultSearch(cleanLower)) {
      return AgentIntent.vaultSearch;
    }

    return AgentIntent.generalAcademicQuery;
  }

  // --- Vocabulary Matchers ---

  static bool _hasDeadlineVocabulary(String lower) {
    return lower.contains('deadline') ||
        lower.contains('deadlines') ||
        lower.contains('due date') ||
        lower.contains('due dates') ||
        RegExp(r'\bdue\b').hasMatch(lower) ||
        lower.contains('submission') ||
        lower.contains('submissions') ||
        lower.contains('submit') ||
        lower.contains('anything to submit') ||
        lower.contains('need to submit') ||
        lower.contains('have to submit');
  }

  static bool _hasTaskVocabulary(String lower) {
    return lower.contains('assignment') ||
        lower.contains('assignments') ||
        lower.contains('homework') ||
        lower.contains('coursework') ||
        RegExp(r'\btasks?\b').hasMatch(lower) ||
        RegExp(r'\btodos?\b').hasMatch(lower);
  }

  static bool _isScheduleQuery(String lower) {
    // Explicit class/lecture/timetable terms
    final hasClassOrLecture = lower.contains('class') ||
        lower.contains('classes') ||
        lower.contains('lecture') ||
        lower.contains('lectures') ||
        lower.contains('timetable') ||
        lower.contains('schedule') ||
        lower.contains('period') ||
        lower.contains('periods');

    if (!hasClassOrLecture) return false;

    // Actions must never be classified as read-only schedule queries
    if (_isTimetableAction(lower) || _isRecordingAction(lower)) {
      return false;
    }

    // Reject if it's purely about an assignment for a class (e.g. "Data Structures class assignment")
    if (_hasTaskVocabulary(lower) || _hasDeadlineVocabulary(lower)) {
      // If it contains "when is my next class" or "classes today", it's a schedule query
      final asksForClassDirectly = lower.contains('next class') ||
          lower.contains('next lecture') ||
          lower.contains('class today') ||
          lower.contains('classes today') ||
          lower.contains('class tomorrow') ||
          lower.contains('classes tomorrow') ||
          lower.contains('schedule today') ||
          lower.contains('today\'s schedule') ||
          lower.contains('todays schedule') ||
          lower.contains('my schedule') ||
          lower.contains('my timetable');
      return asksForClassDirectly;
    }

    return true;
  }

  static bool _isRecordingAction(String lower) {
    return lower.contains('record it') ||
        lower.contains('schedule recording') ||
        lower.contains('record my') ||
        lower.contains('start recording') ||
        lower.contains('record class') ||
        lower.contains('record lecture') ||
        lower.contains('and record');
  }

  static bool _isTimetableAction(String lower) {
    final clean = lower
        .replaceFirst(
            RegExp(
                r'^(?:(?:hey|hi|a|ok|he)?\s*(?:pal|paul|hebbal|apple|bell)|hebbal|apple)[,\s]*',
                caseSensitive: false),
            '')
        .trim();

    // Strictly exclude task, deadline, assignment, and reminder commands
    if (clean.contains('deadline') ||
        clean.contains('assignment') ||
        clean.contains('homework') ||
        clean.contains('task') ||
        clean.contains('submission') ||
        clean.contains('submit') ||
        clean.contains('remind') ||
        clean.contains('reminder') ||
        clean.contains('project') ||
        clean.contains('todo') ||
        (clean.contains('due') &&
            !clean.contains('class') &&
            !clean.contains('lecture'))) {
      return false;
    }

    // Exclude read-only schedule queries like "what classes do i have", "when is my next class"
    if (clean.startsWith('what') ||
        clean.startsWith('when') ||
        clean.startsWith('which') ||
        clean.startsWith('do i have') ||
        clean.startsWith('are there') ||
        clean.startsWith('show') ||
        clean.startsWith('view') ||
        clean.contains('what class') ||
        clean.contains('what are my') ||
        clean.contains('next class') ||
        clean.contains('next lecture')) {
      return false;
    }

    final hasActionVerb = RegExp(
            r'\b(?:create|add|schedule|put|book|set\s+up|move|reschedule|change|delete|remove)\b',
            caseSensitive: false)
        .hasMatch(clean);

    final hasTimetableEntity = RegExp(
            r'\b(?:class|classes|lecture|lectures|period|periods|session|timetable)\b',
            caseSensitive: false)
        .hasMatch(clean);

    final hasAcademicSubject = RegExp(
            r'\b(?:data\s+structures?|data\s+stitches|operating\s+systems?|computer\s+networks?|discrete\s+math(?:ematics)?|engineering\s+physics|physics|artificial\s+intelligence|database\s+systems?|dsa|ai|os|dbms)\b',
            caseSensitive: false)
        .hasMatch(clean);

    final hasTimeOrDay = RegExp(
            r'\b(?:today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun|\d{1,2}(?::\d{2})?\s*(?:am|pm)?|from|to|at)\b',
            caseSensitive: false)
        .hasMatch(clean);

    return hasActionVerb &&
        (hasTimetableEntity || (hasAcademicSubject && hasTimeOrDay));
  }

  static bool _isTaskAction(String lower) {
    final clean = lower
        .replaceFirst(
            RegExp(
                r'^(?:(?:hey|hi|a|ok|he)?\s*(?:pal|paul|hebbal|apple|bell)|hebbal|apple)[,\s]*',
                caseSensitive: false),
            '')
        .trim();

    // Query prompts must not be treated as creation actions
    if (clean.startsWith('what') ||
        clean.startsWith('when') ||
        clean.startsWith('which') ||
        clean.startsWith('do i have') ||
        clean.startsWith('are there') ||
        clean.startsWith('show') ||
        clean.startsWith('view') ||
        clean.startsWith('list') ||
        clean.startsWith('find') ||
        clean.contains('what are my') ||
        clean.contains('what assignments') ||
        clean.contains('what deadlines')) {
      return false;
    }

    final hasActionVerb = RegExp(
            r'\b(?:add|create|new|remind|set|put|schedule|make|post)\b',
            caseSensitive: false)
        .hasMatch(clean);

    final hasTaskEntity =
        RegExp(r'\b(?:deadline|deadlines|assignment|assignments|homework|task|tasks|submission|submissions|reminder|reminders|project|todo|todos)\b',
                    caseSensitive: false)
                .hasMatch(clean) ||
            clean.contains('remind me') ||
            (clean.contains('due') &&
                !clean.contains('class') &&
                !clean.contains('lecture'));

    return hasActionVerb && hasTaskEntity;
  }

  static bool _isHolidayQuery(String lower) {
    return lower.contains('holiday') ||
        lower.contains('holidays') ||
        lower.contains('vacation') ||
        lower.contains('day off') ||
        lower.contains('days off') ||
        lower.contains('college off');
  }

  static bool _isMessQuery(String lower) {
    return lower.contains('mess') ||
        lower.contains('canteen') ||
        lower.contains('lunch') ||
        lower.contains('dinner') ||
        lower.contains('breakfast') ||
        lower.contains('food menu');
  }

  static bool _isAcademicCalendarQuery(String lower) {
    return lower.contains('academic calendar') ||
        lower.contains('exam date') ||
        lower.contains('exam dates') ||
        lower.contains('midsem') ||
        lower.contains('endsem') ||
        lower.contains('semester calendar') ||
        lower.contains('semester start') ||
        lower.contains('convocation');
  }

  static bool _isLectureQuery(String lower) {
    return lower.contains('recent lecture') ||
        lower.contains('recent lectures') ||
        lower.contains('recorded lecture') ||
        lower.contains('recorded lectures') ||
        lower.contains('my recordings') ||
        lower.contains('lecture recordings');
  }

  static bool _isVaultSearch(String lower) {
    return lower.contains('search vault') ||
        lower.contains('search notes') ||
        lower.contains('in my notes') ||
        lower.contains('study vault');
  }
}
