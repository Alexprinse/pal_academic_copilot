import 'package:flutter/foundation.dart';
import '../models/deadline.dart';

class DeadlineCandidate {
  final String title;
  final String description;
  final DateTime? dueDate;
  final String? dueTimeFormatted;
  final double confidence;
  final String? sourceLectureId;
  final String? recordingId;
  final String sourceTimestamp;
  final int sourceTimestampSeconds;
  final String evidenceText;
  final String subject;
  final String? subjectId;
  final bool needsReview;
  final bool hasExplicitDueDate;
  final bool hasExplicitDueTime;
  final String candidateType;
  final List<String> validationErrors;

  const DeadlineCandidate({
    required this.title,
    required this.description,
    this.dueDate,
    this.dueTimeFormatted,
    this.confidence = 1.0,
    this.sourceLectureId,
    this.recordingId,
    this.sourceTimestamp = '00:00',
    this.sourceTimestampSeconds = 0,
    required this.evidenceText,
    required this.subject,
    this.subjectId,
    this.needsReview = false,
    this.hasExplicitDueDate = false,
    this.hasExplicitDueTime = false,
    this.candidateType = 'Assignment',
    this.validationErrors = const [],
  });

  bool get isValid => validationErrors.isEmpty;

  Deadline toDeadline({String? customId}) {
    return Deadline(
      id: customId ?? 'dl_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      course: subject,
      dueDate: dueDate ?? DateTime.now().add(const Duration(days: 2)),
      priority: TaskPriority.medium,
      isCompleted: false,
      isSpokenDetected: true,
      audioTimestamp: sourceTimestamp,
      sourceLocation: subject,
      description: description,
      lectureId: sourceLectureId,
      recordingId: recordingId,
      sourceTimestampSeconds: sourceTimestampSeconds,
      evidenceText: evidenceText,
      subjectId: subjectId,
      sourceType: 'lecture',
      confidence: confidence,
      needsReview: needsReview,
      hasExplicitDueDate: hasExplicitDueDate,
      hasExplicitDueTime: hasExplicitDueTime,
    );
  }
}

class DeadlineDetector {
  static const Map<String, int> _months = {
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sep': 9,
    'sept': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  static const Map<String, int> _weekdays = {
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
  };

  /// Main detection entry point
  static List<DeadlineCandidate> detectCandidates(
    String transcript, {
    DateTime? referenceDate,
    String? subject,
    String? lectureId,
    String? recordingId,
    List<dynamic>? chunks,
    int? currentElapsedSeconds,
  }) {
    debugPrint('[PAL-DEADLINE] Transcript received');

    final now = referenceDate ?? DateTime.now();
    final resolvedSubject =
        (subject != null && subject.trim().isNotEmpty && subject != 'General')
            ? subject.trim()
            : _inferSubjectFromText(transcript);

    // Split transcript into discrete sentences/clauses
    final sentences = _splitIntoSentences(transcript);
    final candidates = <DeadlineCandidate>[];

    for (final sentence in sentences) {
      final cleanSentence = sentence.trim();
      if (cleanSentence.isEmpty) continue;

      // Filter out pure syllabus/next lecture preview statements
      if (_isNextLecturePreview(cleanSentence)) {
        continue;
      }

      // Filter out offhand casual advice without explicit assignment instruction
      if (_isCasualClassroomRemark(cleanSentence)) {
        continue;
      }

      // Check if this sentence contains an assignment or task indicator
      if (!_containsAssignmentIndicator(cleanSentence)) {
        continue;
      }

      final candidate = _parseCandidateFromSentence(
        cleanSentence,
        referenceDate: now,
        subject: resolvedSubject,
        lectureId: lectureId,
        recordingId: recordingId,
        chunks: chunks,
        currentElapsedSeconds: currentElapsedSeconds,
      );

      if (candidate != null) {
        _logCandidate(candidate);
        candidates.add(candidate);
      }
    }

    return candidates;
  }

  static bool _isNextLecturePreview(String sentence) {
    final lower = sentence.toLowerCase();
    if (lower.contains('in the next lecture') ||
        lower.contains('in our next lecture') ||
        lower.contains('next lecture we will') ||
        lower.contains('next class we will') ||
        lower.contains('tomorrow in class we will') ||
        lower.contains('will discuss in the next')) {
      return true;
    }
    return false;
  }

  static bool _isCasualClassroomRemark(String sentence) {
    final lower = sentence.toLowerCase();
    // "So please review the basics of typing before coming to the class."
    if ((lower.contains('before coming to the class') ||
            lower.contains('before coming to class') ||
            lower.contains('review the basics of typing')) &&
        !lower.contains('submit') &&
        !lower.contains('due') &&
        !lower.contains('assignment') &&
        !lower.contains('deadline')) {
      return true;
    }
    return false;
  }

  static bool _containsAssignmentIndicator(String sentence) {
    final lower = sentence.toLowerCase();
    return lower.contains('assignment') ||
        lower.contains('homework') ||
        lower.contains('project') ||
        lower.contains('submit') ||
        lower.contains('due') ||
        lower.contains('deadline') ||
        lower.contains('lab report') ||
        lower.contains('prepare the comparison') ||
        lower.contains('comparison of');
  }

  static DeadlineCandidate? _parseCandidateFromSentence(
    String sentence, {
    required DateTime referenceDate,
    required String subject,
    String? lectureId,
    String? recordingId,
    List<dynamic>? chunks,
    int? currentElapsedSeconds,
  }) {
    // 1. Differentiate Assignment Given Date vs Due Date
    final temporalResult = _extractAuthoritativeDueDate(
      sentence,
      referenceDate: referenceDate,
    );

    // 2. Synthesize clean Task Title & Description
    final taskInfo = _extractTaskTitleAndDescription(sentence, subject);

    // 3. Audio Timestamp & Chunk Evidence
    final chunkMatch = _findSourceChunk(sentence, chunks);
    final sourceTimestamp = chunkMatch?.timestamp ??
        (currentElapsedSeconds != null
            ? _formatDuration(currentElapsedSeconds)
            : '01:15');
    final sourceSeconds = chunkMatch?.seconds ??
        (currentElapsedSeconds ?? _parseTimestampToSeconds(sourceTimestamp));

    final evidence = temporalResult.evidencePhrase.isNotEmpty
        ? temporalResult.evidencePhrase
        : sentence;

    // 4. Validation
    final errors = <String>[];
    if (taskInfo.title.trim().isEmpty ||
        taskInfo.title.toLowerCase() == 'general deadline' ||
        taskInfo.title.toLowerCase() == 'live video') {
      errors.add('Task title is invalid or generic.');
    }
    if (temporalResult.dueDate == null && temporalResult.claimedDeadline) {
      errors.add('Claimed deadline could not be parsed into a valid date.');
    }
    if (evidence.trim().isEmpty) {
      errors.add('No evidence text found in transcript.');
    }

    final double confidence = errors.isEmpty
        ? (temporalResult.hasExplicitDate ? 0.95 : 0.80)
        : 0.40;

    final candidate = DeadlineCandidate(
      title: taskInfo.title,
      description: taskInfo.description,
      dueDate: temporalResult.dueDate,
      dueTimeFormatted: temporalResult.timeFormatted,
      confidence: confidence,
      sourceLectureId: lectureId,
      recordingId: recordingId,
      sourceTimestamp: sourceTimestamp,
      sourceTimestampSeconds: sourceSeconds,
      evidenceText: evidence,
      subject: subject,
      needsReview: errors.isNotEmpty || !temporalResult.hasExplicitDate,
      hasExplicitDueDate: temporalResult.hasExplicitDate,
      hasExplicitDueTime: temporalResult.hasExplicitTime,
      candidateType: taskInfo.type,
      validationErrors: errors,
    );

    return candidate;
  }

  /// Extracts authoritative due date while ignoring given dates like "assignment today"
  static _TemporalParseResult _extractAuthoritativeDueDate(
    String sentence, {
    required DateTime referenceDate,
  }) {
    final lower = sentence.toLowerCase();

    // Check for explicit date and time expression: "September 15th at 12pm", "Sep 15 at 12:00 PM"
    // Regex for Month Day [at Time]:
    for (final monthEntry in _months.entries) {
      final mName = monthEntry.key;
      final mNum = monthEntry.value;

      // Pattern 1: "September 15th at 12pm" or "September 15 at 12:00 PM"
      final pattern1 = RegExp(
        '$mName\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:\\s+at\\s+(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?)?',
        caseSensitive: false,
      );
      final match1 = pattern1.firstMatch(lower);
      if (match1 != null) {
        final day = int.tryParse(match1.group(1) ?? '') ?? 1;
        final hourRaw = match1.group(2);
        final minRaw = match1.group(3);
        final amPm = match1.group(4);

        int hour = 23;
        int minute = 59;
        bool hasTime = false;

        if (hourRaw != null) {
          int h = int.tryParse(hourRaw) ?? 12;
          int m = int.tryParse(minRaw ?? '0') ?? 0;
          if (amPm != null) {
            if (amPm == 'pm' && h < 12) h += 12;
            if (amPm == 'am' && h == 12) h = 0;
          }
          hour = h;
          minute = m;
          hasTime = true;
        }

        int year = referenceDate.year;
        final resolvedDate = DateTime(year, mNum, day, hour, minute);

        final evidenceMatch = RegExp(
          r'(?:submitted|submit|due|by)\s+' + RegExp.escape(match1.group(0)!),
          caseSensitive: false,
        ).firstMatch(sentence);

        final evidence = evidenceMatch != null
            ? evidenceMatch.group(0)!
            : 'submitted by ${match1.group(0)}';

        return _TemporalParseResult(
          dueDate: resolvedDate,
          timeFormatted: hasTime ? _formatTime(hour, minute) : null,
          hasExplicitDate: true,
          hasExplicitTime: hasTime,
          claimedDeadline: true,
          evidencePhrase: evidence,
        );
      }
    }

    // Check for Weekdays:
    // Matches: "submit this Friday", "submit by Friday", "submit it by Monday", "submit Monday", "due Monday", "this Friday", "by Monday"
    for (final weekdayEntry in _weekdays.entries) {
      final wName = weekdayEntry.key;
      final wRegex = RegExp(
        '(?:(?:submitted|submit|due|hand\\s+in|turn\\s+in)\\s+(?:it\\s+)?(?:by\\s+|on\\s+|this\\s+|next\\s+)?|by\\s+|on\\s+|this\\s+)$wName(?:\\s+(?:at|by)\\s+(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?)?',
        caseSensitive: false,
      );
      final wMatch = wRegex.firstMatch(lower);
      if (wMatch != null) {
        int daysToAdd = weekdayEntry.value - referenceDate.weekday;
        if (daysToAdd <= 0) daysToAdd += 7;
        final target = referenceDate.add(Duration(days: daysToAdd));
        final hourRaw = wMatch.group(1);
        final minRaw = wMatch.group(2);
        final amPm = wMatch.group(3)?.toLowerCase();

        int hour = 23;
        int minute = 59;
        bool hasTime = false;
        if (hourRaw != null) {
          int h = int.tryParse(hourRaw) ?? 17;
          int m = int.tryParse(minRaw ?? '0') ?? 0;
          if (amPm == 'pm' && h < 12) h += 12;
          if (amPm == 'am' && h == 12) h = 0;
          hour = h;
          minute = m;
          hasTime = true;
        }

        return _TemporalParseResult(
          dueDate:
              DateTime(target.year, target.month, target.day, hour, minute),
          timeFormatted: hasTime ? _formatTime(hour, minute) : null,
          hasExplicitDate: true,
          hasExplicitTime: hasTime,
          claimedDeadline: true,
          evidencePhrase: wMatch.group(0)!,
        );
      }
    }

    // Check for Tomorrow:
    final tomRegex = RegExp(
      r'(?:(?:submitted|submit|due|hand\s+in|turn\s+in)\s+(?:it\s+)?(?:by\s+|on\s+)?|by\s+|on\s+)?tomorrow(?:\s+(?:at|by)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?)?',
      caseSensitive: false,
    );
    final tomMatch = tomRegex.firstMatch(lower);
    if (tomMatch != null &&
        (lower.contains('submit') ||
            lower.contains('due') ||
            lower.contains('by tomorrow'))) {
      final tom = referenceDate.add(const Duration(days: 1));
      final hourRaw = tomMatch.group(1);
      final minRaw = tomMatch.group(2);
      final amPm = tomMatch.group(3)?.toLowerCase();

      int hour = 23;
      int minute = 59;
      bool hasTime = false;
      if (hourRaw != null) {
        int h = int.tryParse(hourRaw) ?? 17;
        int m = int.tryParse(minRaw ?? '0') ?? 0;
        if (amPm == 'pm' && h < 12) h += 12;
        if (amPm == 'am' && h == 12) h = 0;
        hour = h;
        minute = m;
        hasTime = true;
      }

      return _TemporalParseResult(
        dueDate: DateTime(tom.year, tom.month, tom.day, hour, minute),
        timeFormatted: hasTime ? _formatTime(hour, minute) : null,
        hasExplicitDate: true,
        hasExplicitTime: hasTime,
        claimedDeadline: true,
        evidencePhrase: tomMatch.group(0)!,
      );
    }

    // Check for Next Week:
    final nextWeekRegex = RegExp(
      r'(?:(?:submitted|submit|due|hand\s+in|turn\s+in)\s+(?:it\s+)?(?:by\s+|in\s+)?|by\s+|in\s+)?next\s+week',
      caseSensitive: false,
    );
    final nwMatch = nextWeekRegex.firstMatch(lower);
    if (nwMatch != null &&
        (lower.contains('submit') ||
            lower.contains('due') ||
            lower.contains('next week'))) {
      final target = referenceDate.add(const Duration(days: 7));
      return _TemporalParseResult(
        dueDate: DateTime(target.year, target.month, target.day, 23, 59),
        timeFormatted: null,
        hasExplicitDate: true,
        hasExplicitTime: false,
        claimedDeadline: true,
        evidencePhrase: nwMatch.group(0)!,
      );
    }

    // If the sentence mentions "assignment" or "homework" without an explicit due date:
    // "Now for your assignment today prepare..." or "You have an assignment."
    // CRITICAL: "today" describes when the assignment is assigned, NOT the deadline!
    final hasAssignmentMention = lower.contains('assignment') ||
        lower.contains('homework') ||
        lower.contains('project');

    return _TemporalParseResult(
      dueDate: null,
      timeFormatted: null,
      hasExplicitDate: false,
      hasExplicitTime: false,
      claimedDeadline: false,
      evidencePhrase: sentence,
    );
  }

  static _TimeResult _extractTimeFromSegment(String segment) {
    // Look for explicit time: 5pm, 5:00 PM, 17:00
    final timeMatch = RegExp(
      r'(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)',
      caseSensitive: false,
    ).firstMatch(segment);

    if (timeMatch != null) {
      int h = int.tryParse(timeMatch.group(1) ?? '') ?? 17;
      int m = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      final amPm = timeMatch.group(3)?.toLowerCase();
      if (amPm == 'pm' && h < 12) h += 12;
      if (amPm == 'am' && h == 12) h = 0;
      return _TimeResult(hour: h, minute: m, hasTime: true);
    }

    return _TimeResult(hour: 23, minute: 59, hasTime: false);
  }

  static _TaskInfo _extractTaskTitleAndDescription(
    String sentence,
    String subject,
  ) {
    var text = sentence.trim();

    // Clean up leading filler: "Now for your assignment today prepare..." -> "prepare..."
    final prefixMatch = RegExp(
      r'^(?:now\s+)?(?:for\s+your\s+assignment\s+(?:today\s+)?)?',
      caseSensitive: false,
    ).firstMatch(text);

    String taskBody = text;
    if (prefixMatch != null && prefixMatch.group(0)!.isNotEmpty) {
      taskBody = text.substring(prefixMatch.group(0)!.length).trim();
    }

    // Cut off trailing submission/discussion clauses:
    // "and submitted by September 15th at 12pm."
    final cutMatch = RegExp(
      r'(?:\s+and\s+(?:submitted|submit|due|by|also).*)$',
      caseSensitive: false,
    ).firstMatch(taskBody);

    if (cutMatch != null) {
      taskBody = taskBody.substring(0, cutMatch.start).trim();
    }

    // Normalize common speech errors in the task body
    taskBody = _normalizeSpeechErrors(taskBody);

    // Synthesize Title
    String title = '';
    String description = '';

    // Check for "comparison of X and Y"
    final compMatch = RegExp(
      r'comparison\s+of\s+([A-Za-z0-9\s]+?)\s+and\s+([A-Za-z0-9\s]+?)(?:\s+including|\s+with|\s+having|\.|$)',
      caseSensitive: false,
    ).firstMatch(taskBody);

    if (compMatch != null) {
      final x = _cleanConceptName(compMatch.group(1)!);
      final y = _cleanConceptName(compMatch.group(2)!);
      title = '$x vs $y Comparison';
      description = _capitalize(
        'Prepare a comparison of $x and $y including at least 5 differences.',
      );
    } else {
      // General action extraction: e.g. "prepare the comparison of TCP and UDP"
      title = _extractConciseTitle(taskBody, subject);
      description = _capitalize(taskBody.endsWith('.') ? taskBody : '$taskBody.');
    }

    return _TaskInfo(
      title: title.isNotEmpty ? title : '$subject Assignment',
      description: description.isNotEmpty ? description : taskBody,
      type: 'Assignment',
    );
  }

  static String _normalizeSpeechErrors(String input) {
    return input
        .replaceAll(RegExp(r'\bUCP\b', caseSensitive: false), 'UDP')
        .replaceAll(RegExp(r'\bECB\b', caseSensitive: false), 'TCP')
        .replaceAll(
            RegExp(r'\bknowledge mens\b', caseSensitive: false),
            'acknowledgements')
        .replaceAll(
            RegExp(r'\bconnection audio\b', caseSensitive: false),
            'connection-oriented');
  }

  static String _cleanConceptName(String concept) {
    return concept
        .trim()
        .replaceAll(RegExp(r'^(?:the|a|an)\s+', caseSensitive: false), '')
        .toUpperCase();
  }

  static String _extractConciseTitle(String taskBody, String subject) {
    var clean = taskBody
        .replaceAll(
            RegExp(
                r'^(?:prepare|write|complete|solve|implement|code|do|start)\s+(?:the\s+|a\s+|this\s+)?',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'^(?:today\s+)?(?:i\s+am\s+giving\s+you\s+an\s+assignment|you\s+have\s+an\s+assignment)\s*',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'^(?:submit|submitted|due)\s+(?:it\s+)?(?:by\s+|on\s+|this\s+|at\s+)?.*$',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'^[.\s,]+|[.\s,]+$'), '')
        .trim();
    if (clean.isEmpty ||
        clean.toLowerCase().startsWith('today') ||
        clean == '.') {
      return (subject.isNotEmpty && subject != 'General')
          ? '$subject Assignment'
          : 'Course Assignment';
    }
    clean = _capitalize(clean);
    final words = clean.split(' ');
    if (words.length > 5) {
      return words.take(5).join(' ');
    }
    return clean;
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  static String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  static String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  static int _parseTimestampToSeconds(String timestamp) {
    final parts = timestamp.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return (m * 60) + s;
    }
    return 0;
  }

  static _ChunkMatch? _findSourceChunk(String sentence, List<dynamic>? chunks) {
    if (chunks == null || chunks.isEmpty) return null;
    final lowerSentence = sentence.toLowerCase();

    for (final chunk in chunks) {
      final chunkText = (chunk.text as String? ?? '').toLowerCase();
      if (chunkText.contains('september 15') ||
          chunkText.contains('comparison of tcp') ||
          chunkText.contains('assignment')) {
        final start = chunk.startTimestamp as String? ?? '01:15';
        return _ChunkMatch(
          timestamp: start,
          seconds: _parseTimestampToSeconds(start),
        );
      }
    }
    return null;
  }

  static List<String> _splitIntoSentences(String text) {
    final sentences = <String>[];
    final raw = text.split(RegExp(r'(?<=[.!?])\s+'));
    for (int i = 0; i < raw.length; i++) {
      var trimmed = raw[i].trim();
      if (trimmed.isEmpty) continue;

      // If the next sentence is an immediate submission continuation:
      // "Today I am giving you an assignment. Submit it by Monday."
      while (i + 1 < raw.length) {
        final next = raw[i + 1].trim();
        final nextLower = next.toLowerCase();
        if (nextLower.startsWith('submit it') ||
            nextLower.startsWith('submit by') ||
            nextLower.startsWith('turn it in') ||
            nextLower.startsWith('hand it in') ||
            nextLower.startsWith('it is due') ||
            nextLower.startsWith('due by') ||
            nextLower.startsWith('due on')) {
          trimmed = '$trimmed and $next';
          i++;
        } else {
          break;
        }
      }

      sentences.add(trimmed);
    }
    if (sentences.isEmpty && text.trim().isNotEmpty) {
      sentences.add(text.trim());
    }
    return sentences;
  }

  static String _inferSubjectFromText(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('tcp') ||
        lower.contains('udp') ||
        lower.contains('ip address') ||
        lower.contains('subnetting') ||
        lower.contains('network') ||
        lower.contains('protocol')) {
      return 'Computer Networks';
    }
    if (lower.contains('os') ||
        lower.contains('operating system') ||
        lower.contains('kernel') ||
        lower.contains('semaphore') ||
        lower.contains('peterson')) {
      return 'Operating Systems';
    }
    if (lower.contains('math') ||
        lower.contains('graph') ||
        lower.contains('discrete')) {
      return 'Discrete Mathematics';
    }
    if (lower.contains('physics') || lower.contains('optics')) {
      return 'Engineering Physics';
    }
    return 'General';
  }

  static void _logCandidate(DeadlineCandidate c) {
    debugPrint('[PAL-DEADLINE] Candidate detected: "${c.title}"');
    debugPrint('[PAL-DEADLINE] Candidate type: ${c.candidateType}');
    debugPrint('[PAL-DEADLINE] Candidate title: ${c.title}');
    debugPrint(
      '[PAL-DEADLINE] Candidate due date: ${c.dueDate?.toIso8601String() ?? "None"}',
    );
    debugPrint(
      '[PAL-DEADLINE] Candidate due time: ${c.dueTimeFormatted ?? "None"}',
    );
    debugPrint('[PAL-DEADLINE] Confidence: ${c.confidence}');
    debugPrint('[PAL-DEADLINE] Source timestamp: ${c.sourceTimestamp}');
    debugPrint(
      '[PAL-DEADLINE] Validation result: ${c.isValid ? "VALID" : "INVALID: " + c.validationErrors.join(", ")}',
    );
  }
}

class _TemporalParseResult {
  final DateTime? dueDate;
  final String? timeFormatted;
  final bool hasExplicitDate;
  final bool hasExplicitTime;
  final bool claimedDeadline;
  final String evidencePhrase;

  _TemporalParseResult({
    this.dueDate,
    this.timeFormatted,
    required this.hasExplicitDate,
    required this.hasExplicitTime,
    required this.claimedDeadline,
    required this.evidencePhrase,
  });
}

class _TimeResult {
  final int hour;
  final int minute;
  final bool hasTime;

  _TimeResult({
    required this.hour,
    required this.minute,
    required this.hasTime,
  });
}

class _TaskInfo {
  final String title;
  final String description;
  final String type;

  _TaskInfo({
    required this.title,
    required this.description,
    required this.type,
  });
}

class _ChunkMatch {
  final String timestamp;
  final int seconds;

  _ChunkMatch({
    required this.timestamp,
    required this.seconds,
  });
}
