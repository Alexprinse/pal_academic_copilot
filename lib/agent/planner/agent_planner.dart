import '../../services/timetable_service.dart';
import '../agent_context.dart';
import '../agent_tool_call.dart';
import 'agent_plan.dart';
import 'agent_plan_step.dart';

class AgentPlanner {
  static const int maxPlanSteps = 6;

  AgentPlan createPlan(
    String request, {
    AgentContext? context,
  }) {
    final clean = request.trim();
    final lower = clean.toLowerCase();
    final planId = 'plan_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Event + Auto-record ("Add AI tomorrow 10-11 and record it", "I have OS tomorrow from 10 to 11. Add it to my timetable and record it automatically.")
    if ((lower.contains('and record') ||
            lower.contains('record it') ||
            lower.contains('record automatically')) &&
        (lower.contains('add') ||
            lower.contains('have') ||
            lower.contains('schedule'))) {
      return _buildEventAndRecordPlan(planId, clean, lower);
    }

    // 2. Event + Reminder ("Add my AI class tomorrow at 2 and remind me 30 minutes before")
    if ((lower.contains('remind me') || lower.contains('set a reminder')) &&
        (lower.contains('add') ||
            lower.contains('have') ||
            lower.contains('class'))) {
      return _buildEventAndReminderPlan(planId, clean, lower);
    }

    // 3. Read + Write ("What is my next class? Move it to 11", "Tell me my next class and move it one hour later")
    if ((lower.contains('next class') || lower.contains('next lecture')) &&
        (lower.contains('move') ||
            lower.contains('reschedule') ||
            lower.contains('change') ||
            lower.contains('later'))) {
      return _buildReadAndMoveClassPlan(planId, clean, lower);
    }

    // 4. Knowledge + Action ("Find the assignment mentioned in yesterday's lecture and add it to my tasks", "Find the assignment from yesterday's lecture and add it")
    if ((lower.contains('assignment') || lower.contains('homework')) &&
        (lower.contains('lecture') || lower.contains('notes')) &&
        (lower.contains('add') || lower.contains('task'))) {
      return _buildKnowledgeAndTaskPlan(planId, clean, lower);
    }

    // Default: generate single-step plan
    return _buildSingleStepPlan(planId, clean, lower);
  }

  AgentPlan _buildEventAndRecordPlan(
      String planId, String clean, String lower) {
    // Subject
    String subject = _extractSubject(lower, clean);

    // Day
    String day = _extractDay(lower);

    // Times
    final times = _extractStartAndEndTime(clean);
    final startTime = times['startTime'];
    final endTime = times['endTime'];

    // Validation: Missing critical information
    if (startTime == null) {
      return AgentPlan(
        planId: planId,
        originalRequest: clean,
        steps: [],
        missingInformationQuestion:
            'I can add and record that class. What time does your $subject class start and end?',
      );
    }

    final step1 = AgentPlanStep(
      id: 'step_1',
      tool: 'create_timetable_event',
      arguments: {
        'subject': subject,
        'day': day,
        'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
      },
      description: 'Add $subject to timetable ($day · $startTime)',
    );

    final step2 = AgentPlanStep(
      id: 'step_2',
      tool: 'schedule_recording',
      arguments: {
        'subject': subject,
        'day': day,
        'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
      },
      dependsOnPrevious: true,
      dependencyKey: 'timetable_event',
      description: 'Enable automatic recording for $subject',
    );

    return AgentPlan(
      planId: planId,
      originalRequest: clean,
      steps: [step1, step2],
    );
  }

  AgentPlan _buildEventAndReminderPlan(
      String planId, String clean, String lower) {
    String subject = _extractSubject(lower, clean);
    String day = _extractDay(lower);

    final times = _extractStartAndEndTime(clean);
    final startTime = times['startTime'];
    final endTime = times['endTime'];

    if (startTime == null) {
      return AgentPlan(
        planId: planId,
        originalRequest: clean,
        steps: [],
        missingInformationQuestion:
            'I can set that up. What time does your $subject class start?',
      );
    }

    // Extract reminder offset (default 30 mins)
    int offsetMinutes = 30;
    final offsetMatch = RegExp(r'(\d+)\s*(?:min|minute)', caseSensitive: false)
        .firstMatch(clean);
    if (offsetMatch != null) {
      offsetMinutes = int.tryParse(offsetMatch.group(1)!) ?? 30;
    }

    final step1 = AgentPlanStep(
      id: 'step_1',
      tool: 'create_timetable_event',
      arguments: {
        'subject': subject,
        'day': day,
        'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
      },
      description: 'Add $subject to timetable ($day at $startTime)',
    );

    final step2 = AgentPlanStep(
      id: 'step_2',
      tool: 'create_task',
      arguments: {
        'title': 'Attend $subject ($offsetMinutes mins before)',
        'dueDate': day,
        'course': subject,
        'priority': 'medium',
      },
      dependsOnPrevious: true,
      dependencyKey: 'event_reminder',
      description: 'Set $offsetMinutes-minute reminder for $subject',
    );

    return AgentPlan(
      planId: planId,
      originalRequest: clean,
      steps: [step1, step2],
    );
  }

  AgentPlan _buildReadAndMoveClassPlan(
      String planId, String clean, String lower) {
    // Look for new time: "to 11", "one hour later", "to 11:00 AM"
    String? newStartTime;
    final toMatch =
        RegExp(r'to\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)', caseSensitive: false)
            .firstMatch(clean);
    if (toMatch != null) {
      newStartTime = toMatch.group(1)!.trim();
    } else if (lower.contains('one hour later') ||
        lower.contains('1 hour later')) {
      newStartTime = 'OFFSET_+1H';
    } else {
      newStartTime = '11:00 AM';
    }

    final step1 = AgentPlanStep(
      id: 'step_1',
      tool: 'get_upcoming_classes',
      arguments: {'target': 'next', 'limit': 1},
      description: 'Find your next scheduled class',
    );

    final step2 = AgentPlanStep(
      id: 'step_2',
      tool: 'update_timetable_event',
      arguments: {
        'newStartTime': newStartTime,
      },
      dependsOnPrevious: true,
      dependencyKey: 'next_class_target',
      description: 'Move class to $newStartTime',
    );

    return AgentPlan(
      planId: planId,
      originalRequest: clean,
      steps: [step1, step2],
    );
  }

  AgentPlan _buildKnowledgeAndTaskPlan(
      String planId, String clean, String lower) {
    final step1 = AgentPlanStep(
      id: 'step_1',
      tool: 'search_knowledge',
      arguments: {
        'query': 'assignment homework project due submission',
        'limit': 3,
      },
      description: 'Search lecture notes for assignment mentions',
    );

    final step2 = AgentPlanStep(
      id: 'step_2',
      tool: 'create_task',
      arguments: {
        'title': 'Lecture Assignment',
        'dueDate': 'in 3 days',
        'priority': 'high',
      },
      dependsOnPrevious: true,
      dependencyKey: 'extracted_assignment',
      description: 'Create task from lecture findings',
    );

    return AgentPlan(
      planId: planId,
      originalRequest: clean,
      steps: [step1, step2],
    );
  }

  AgentPlan _buildSingleStepPlan(String planId, String clean, String lower) {
    // Single tool fallback
    AgentToolCall? singleCall;

    if (lower.contains('next class')) {
      singleCall = const AgentToolCall(
        tool: 'get_upcoming_classes',
        arguments: {'target': 'next', 'limit': 3},
      );
    } else if (lower.contains('classes today') ||
        lower.contains('today\'s schedule')) {
      singleCall = const AgentToolCall(
        tool: 'get_today_schedule',
        arguments: {},
      );
    } else if (lower.startsWith('add') ||
        lower.startsWith('create') ||
        lower.startsWith('schedule') ||
        lower.startsWith('put') ||
        lower.startsWith('set') ||
        lower.startsWith('remind')) {
      final isTaskOrDeadline = lower.contains('deadline') ||
          lower.contains('assignment') ||
          lower.contains('homework') ||
          lower.contains('task') ||
          lower.contains('submission') ||
          lower.contains('remind') ||
          lower.contains('project') ||
          lower.contains('todo') ||
          (lower.contains('due') &&
              !lower.contains('class') &&
              !lower.contains('lecture'));

      if (isTaskOrDeadline) {
        final displaySubject = extractDisplaySubject(lower, clean);
        final subject = resolveCourseSubject(lower, clean, displaySubject);
        final day = _extractDay(lower);

        // Check if user specified a concrete title beyond just "deadline" / "a physics deadline"
        final isVagueDeadline = lower.contains('deadline') &&
            !lower.contains('assignment') &&
            !lower.contains('homework') &&
            !lower.contains('report') &&
            !lower.contains('project') &&
            !lower.contains('quiz') &&
            !lower.contains('test') &&
            !lower.contains('numerical') &&
            !lower.contains('chapter') &&
            !lower.contains('lab');

        if (isVagueDeadline) {
          return AgentPlan(
            planId: planId,
            originalRequest: clean,
            steps: [],
            missingInformationQuestion:
                'What should I call this $displaySubject deadline?',
          );
        }

        final title = extractTaskTitle(clean, lower, displaySubject);
        singleCall = AgentToolCall(
          tool: 'create_task',
          arguments: {
            'title': title,
            'dueDate': day,
            if (subject.isNotEmpty) 'course': subject,
          },
        );
      } else {
        final subject = _extractSubject(lower, clean);
        final day = _extractDay(lower);
        final times = _extractStartAndEndTime(clean);
        final startTime = times['startTime'];
        final endTime = times['endTime'];

        if (startTime == null) {
          return AgentPlan(
            planId: planId,
            originalRequest: clean,
            steps: [],
            missingInformationQuestion:
                'What time does your $subject class start and end?',
          );
        }

        singleCall = AgentToolCall(
          tool: 'create_timetable_event',
          arguments: {
            'subject': subject,
            'day': day,
            'startTime': startTime,
            if (endTime != null) 'endTime': endTime,
          },
        );
      }
    }

    if (singleCall != null) {
      final step = AgentPlanStep(
        id: 'step_1',
        tool: singleCall.tool,
        arguments: singleCall.arguments,
        description: 'Execute ${singleCall.tool}',
      );
      return AgentPlan(
        planId: planId,
        originalRequest: clean,
        steps: [step],
      );
    }

    return AgentPlan(
      planId: planId,
      originalRequest: clean,
      steps: [],
    );
  }

  static String extractDisplaySubject(String lower, String clean) {
    if (lower.contains('physics')) return 'Physics';
    if (lower.contains('operating system') ||
        RegExp(r'\bos\b').hasMatch(lower)) {
      return 'Operating Systems';
    }
    if (lower.contains('data structure') ||
        lower.contains('data stitches') ||
        RegExp(r'\bdsa\b').hasMatch(lower)) {
      return 'Data Structures';
    }
    if (lower.contains('network') || lower.contains('networking')) {
      return 'Computer Networks';
    }
    if (lower.contains('artificial intelligence') ||
        RegExp(r'\bai\b').hasMatch(lower)) {
      return 'Artificial Intelligence';
    }
    if (lower.contains('math') || lower.contains('mathematics')) {
      return 'Mathematics';
    }
    if (lower.contains('database') || lower.contains('dbms')) {
      return 'Database Systems';
    }

    final match = RegExp(
            r'(?:add|create|new|for|about)\s+(?:a\s+|an\s+|my\s+)?([a-zA-Z]+?)(?:\s+deadline|\s+assignment|\s+task|\s+class|\s+today|\s+tomorrow|$)',
            caseSensitive: false)
        .firstMatch(clean);
    if (match != null && match.group(1)!.trim().isNotEmpty) {
      final s = match.group(1)!.trim();
      return s[0].toUpperCase() + s.substring(1);
    }
    return 'Academic';
  }

  static String resolveCourseSubject(
      String lower, String clean, String displaySubject) {
    // 1. Check user's actual timetable database first
    for (final entry in TimetableService.instance.entries) {
      final sub = entry.subject.trim();
      if (sub.isEmpty) continue;
      final subLower = sub.toLowerCase();
      if (lower.contains(subLower)) return sub;
      if (lower.contains('physics') && subLower.contains('physics')) return sub;
      if (lower.contains('operating system') &&
          subLower.contains('operating system')) return sub;
      if (lower.contains('data structure') &&
          subLower.contains('data structure')) return sub;
      if (lower.contains('network') && subLower.contains('network')) return sub;
      if (lower.contains('math') && subLower.contains('math')) return sub;
      if (lower.contains('ai') && subLower.contains('ai')) return sub;
    }

    // 2. Check suggested subjects
    for (final sub in TimetableService.suggestedSubjects) {
      final subLower = sub.toLowerCase();
      if (lower.contains(subLower)) return sub;
      if (lower.contains('physics') && subLower.contains('physics')) return sub;
      if (lower.contains('operating system') &&
          subLower.contains('operating system')) return sub;
      if (lower.contains('data structure') &&
          subLower.contains('data structure')) return sub;
      if (lower.contains('network') && subLower.contains('network')) return sub;
      if (lower.contains('math') && subLower.contains('math')) return sub;
    }

    // 3. Fallback to known academic curriculum courses
    if (lower.contains('physics')) return 'Engineering Physics';
    if (lower.contains('os') || lower.contains('operating system')) {
      return 'Operating Systems';
    }
    if (lower.contains('data structure') ||
        lower.contains('data stitches') ||
        lower.contains('dsa')) {
      return 'Data Structures';
    }
    if (lower.contains('network') || lower.contains('networking')) {
      return 'Computer Networks';
    }
    if (lower.contains('ai') || lower.contains('artificial intelligence')) {
      return 'Artificial Intelligence';
    }
    if (lower.contains('discrete') || lower.contains('math')) {
      return 'Mathematics';
    }
    if (lower.contains('dbms') || lower.contains('database')) {
      return 'Database Systems';
    }

    return displaySubject;
  }

  static String extractTaskTitle(
      String clean, String lower, String displaySubject) {
    var t = clean;
    t = t.replaceFirst(
        RegExp(
            r'^(?:(?:hey|hi|a|ok|he)?\s*(?:pal|paul|hebbal|apple|bell)|hebbal|apple)[,\s]*',
            caseSensitive: false),
        '');
    t = t.replaceFirst(
        RegExp(
            r'^(?:remind\s+me\s+to|remind\s+me\s+about|create\s+task|add\s+task|new\s+task|add|create|set|put)\s+(?:a\s+|an\s+|my\s+)?',
            caseSensitive: false),
        '');
    t = t.replaceAll(
        RegExp(
            r'\s+(?:due\s+)?(?:today|tomorrow|in\s+\d+\s+days?|on\s+[a-zA-Z0-9\s]+?|by\s+[a-zA-Z0-9\s]+?)$',
            caseSensitive: false),
        '');
    t = t.replaceAll(RegExp(r'\b(?:to|for)\s+me\b', caseSensitive: false), '');
    t = t.trim();

    if (t.isEmpty ||
        t.toLowerCase() == 'deadline' ||
        t.toLowerCase() == 'task' ||
        t.toLowerCase() == 'assignment' ||
        t.toLowerCase() == 'homework' ||
        t.toLowerCase() == 'reminder') {
      return '$displaySubject ${t.isEmpty ? "Deadline" : (t[0].toUpperCase() + t.substring(1))}';
    }

    if (t.toLowerCase() == '${displaySubject.toLowerCase()} deadline' ||
        t.toLowerCase() == '${displaySubject.toLowerCase()} assignment' ||
        t.toLowerCase() == '${displaySubject.toLowerCase()} task') {
      final lastWord = t.split(' ').last;
      return '$displaySubject ${lastWord[0].toUpperCase() + lastWord.substring(1)}';
    }

    return t[0].toUpperCase() + t.substring(1);
  }

  String _extractSubject(String lower, String clean) {
    if (RegExp(r'\bai\b', caseSensitive: false).hasMatch(clean) ||
        lower.contains('artificial intelligence')) {
      return 'Artificial Intelligence';
    }
    if (RegExp(r'\bos\b', caseSensitive: false).hasMatch(clean) ||
        lower.contains('operating system')) {
      return 'Operating Systems';
    }
    if (RegExp(r'\bmath\b', caseSensitive: false).hasMatch(clean) ||
        lower.contains('mathematics') ||
        lower.contains('discrete')) {
      return 'Mathematics';
    }
    if (lower.contains('physics')) {
      return 'Engineering Physics';
    }
    if (lower.contains('network')) {
      return 'Computer Networks';
    }

    final match = RegExp(
            r'(?:add|have|class|course)\s+(?:my\s+)?([a-zA-Z\s]+?)(?:\s+tomorrow|\s+today|\s+at|\s+from|$)',
            caseSensitive: false)
        .firstMatch(clean);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return 'Academic Class';
  }

  String _extractDay(String lower) {
    if (lower.contains('today')) return 'today';
    if (lower.contains('tomorrow')) return 'tomorrow';
    for (final d in [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
      'mon',
      'tue',
      'wed',
      'thu',
      'fri',
      'sat',
      'sun'
    ]) {
      if (lower.contains(d)) return d;
    }
    return 'tomorrow';
  }

  Map<String, String?> _extractStartAndEndTime(String clean) {
    String? startTime;
    String? endTime;

    // Pattern 1: "from 10 to 11", "at 10 to 11", "10 to 11", "10–11", "10-11"
    final rangeMatch = RegExp(
            r'(?:from\s+|at\s+)?(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*(?:to|-|–)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)',
            caseSensitive: false)
        .firstMatch(clean);
    if (rangeMatch != null) {
      startTime = rangeMatch.group(1)!.trim();
      endTime = rangeMatch.group(2)!.trim();
      return {'startTime': startTime, 'endTime': endTime};
    }

    // Pattern 2: "at 2", "at 10am"
    final atMatch =
        RegExp(r'at\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)', caseSensitive: false)
            .firstMatch(clean);
    if (atMatch != null) {
      startTime = atMatch.group(1)!.trim();
      return {'startTime': startTime, 'endTime': null};
    }

    return {'startTime': null, 'endTime': null};
  }
}
