import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../services/llm_service.dart';
import '../services/timetable_service.dart';
import 'agent_context.dart';
import 'agent_intent.dart';
import 'agent_response.dart';
import 'agent_tool_call.dart';
import 'agent_tool_registry.dart';
import 'agent_tool_result.dart';
import 'planner/agent_plan.dart';
import 'planner/agent_plan_executor.dart';
import 'planner/agent_planner.dart';
import 'tools/create_task_tool.dart';
import 'tools/create_timetable_event_tool.dart';
import 'tools/delete_timetable_event_tool.dart';
import 'tools/get_academic_calendar_tool.dart';
import 'tools/get_holidays_tool.dart';
import 'tools/get_id_card_tool.dart';
import 'tools/get_mess_menu_tool.dart';
import 'tools/get_notices_tool.dart';
import 'tools/get_recent_lectures_tool.dart';
import 'tools/get_today_schedule_tool.dart';
import 'tools/get_upcoming_classes_tool.dart';
import 'tools/get_upcoming_tasks_tool.dart';
import 'tools/schedule_recording_tool.dart';
import 'tools/search_knowledge_tool.dart';
import 'tools/update_timetable_event_tool.dart';

class AgentService {
  static AgentService? _instance;
  static AgentService get instance => _instance ??= AgentService();

  @visibleForTesting
  static void resetInstanceForTesting() {
    _instance?._pendingConfirmationCall = null;
    _instance = null;
  }

  final AgentToolRegistry registry;
  final LlmService llmService;
  late final AgentPlanner planner;
  late final AgentPlanExecutor planExecutor;
  AgentToolCall? _pendingConfirmationCall;

  AgentService({
    AgentToolRegistry? registry,
    LlmService? llmService,
    AgentPlanner? planner,
    AgentPlanExecutor? planExecutor,
  })  : registry = registry ?? _createDefaultRegistry(),
        llmService = llmService ?? LlmService.instance {
    this.planner = planner ?? AgentPlanner();
    this.planExecutor =
        planExecutor ?? AgentPlanExecutor(registry: this.registry);
  }

  static AgentToolRegistry _createDefaultRegistry() {
    return AgentToolRegistry([
      GetTodayScheduleTool(),
      GetUpcomingClassesTool(),
      GetUpcomingTasksTool(),
      SearchKnowledgeTool(),
      GetRecentLecturesTool(),
      CreateTimetableEventTool(),
      UpdateTimetableEventTool(),
      DeleteTimetableEventTool(),
      CreateTaskTool(),
      ScheduleRecordingTool(),
      GetMessMenuTool(),
      GetHolidaysTool(),
      GetIdCardTool(),
      GetAcademicCalendarTool(),
      GetNoticesTool(),
    ]);
  }

  /// Analyzes the user prompt and determines all on-device tool calls to invoke.
  /// Supports single and multi-tool execution pipelines.
  List<AgentToolCall> determineToolCalls(
    String input, {
    List<AcademicChatMessage>? conversationHistory,
  }) {
    final clean = input.trim();
    if (clean.isEmpty) return [];

    // 1. Direct structured JSON tool call check
    final directCall = AgentToolCall.tryParse(clean);
    if (directCall != null) {
      return [directCall];
    }

    final lower = clean.toLowerCase();

    // 2. Multi-step Planner Integration
    final plan = planner.createPlan(clean);
    if (plan.isBlockedOnMissingInfo) {
      return [];
    }
    if (plan.steps.length > 1) {
      return plan.steps
          .map((s) => AgentToolCall(tool: s.tool, arguments: s.arguments))
          .toList();
    }

    // 3. Multi-tool pattern fallback: "Add AI tomorrow at 10 and record it"
    final multiToolCalls = _parseMultiToolCalls(clean, lower);
    if (multiToolCalls.isNotEmpty) {
      return multiToolCalls;
    }

    // 3. Confirming a previous destructive action (e.g. "Yes, delete it" or "Confirm delete")
    if (_isConfirmationPrompt(lower)) {
      if (_pendingConfirmationCall != null) {
        final call = _pendingConfirmationCall!;
        _pendingConfirmationCall = null;
        return [call];
      }
      final deleteCall =
          _parseConfirmedDelete(clean, lower, conversationHistory);
      if (deleteCall != null) return [deleteCall];
    }

    // 4. Delete timetable event
    if (_isDeleteRequest(lower)) {
      final deleteCall = _parseDeleteTimetableCall(clean, lower);
      if (deleteCall != null) return [deleteCall];
    }

    // 5. Update / Move timetable event
    if (_isUpdateRequest(lower)) {
      final updateCall = _parseUpdateTimetableCall(clean, lower);
      if (updateCall != null) return [updateCall];
    }

    // 6. Create task / deadline reminder (Priority: task before timetable)
    if (_isCreateTaskRequest(lower)) {
      final taskCall = _parseCreateTaskCall(clean, lower);
      if (taskCall != null) return [taskCall];
    }

    // 7. Create timetable event
    if (_isCreateTimetableRequest(lower)) {
      final createCall = _parseCreateTimetableCall(clean, lower);
      if (createCall != null) return [createCall];
    }

    // 8. Schedule recording
    if (_isScheduleRecordingRequest(lower)) {
      final recCall = _parseScheduleRecordingCall(clean, lower);
      if (recCall != null) return [recCall];
    }

    // 9. Intent-driven routing & entity disambiguation
    final intents = AgentIntent.detectIntents(clean);

    // Multi-intent handling: e.g. "What is my next class and what assignments are due today?"
    if (intents.length > 1) {
      final calls = <AgentToolCall>[];
      final clauses = clean.split(RegExp(
          r'(?:\s+(?:and|&|also)\s+|[;?]\s*(?:also\s+)?)',
          caseSensitive: false));
      for (final intent in intents) {
        String relevantClause = clean;
        for (final clause in clauses) {
          if (AgentIntent.detectPrimaryIntent(clause) == intent) {
            relevantClause = clause;
            break;
          }
        }
        final call = _toolCallForIntent(
            intent, relevantClause, relevantClause.toLowerCase());
        if (call != null && !calls.any((c) => c.tool == call.tool)) {
          calls.add(call);
        }
      }
      if (calls.isNotEmpty) {
        return calls;
      }
    }

    // Explicit entity-first priority for task actions:
    final primaryIntent = intents.first;
    if (primaryIntent == AgentIntent.taskAction) {
      final taskCall = _parseCreateTaskCall(clean, lower);
      if (taskCall != null) return [taskCall];
    }

    // Explicit entity-first priority for timetable actions:
    if (primaryIntent == AgentIntent.timetableAction) {
      final createCall = _parseCreateTimetableCall(clean, lower);
      if (createCall != null) return [createCall];
    }

    // Explicit entity-first priority for deadline / task queries:
    // Guarantees queries like "Find my upcoming assignment deadlines", "What is due this week?",
    // "When is my Data Structures assignment due?" NEVER fall through to timetable/classes.
    if (primaryIntent == AgentIntent.deadlineQuery ||
        primaryIntent == AgentIntent.taskQuery) {
      final taskCall = _toolCallForIntent(primaryIntent, clean, lower);
      if (taskCall != null) return [taskCall];
    }

    // 10. Read-only tools from Phase 2
    final readOnlyCall = _parseReadOnlyCall(clean, lower);
    if (readOnlyCall != null) return [readOnlyCall];

    // 11. Fallback to primary intent mapping
    final fallbackCall = _toolCallForIntent(primaryIntent, clean, lower);
    if (fallbackCall != null) return [fallbackCall];

    return [];
  }

  AgentToolCall? _toolCallForIntent(
    AgentIntent intent,
    String clean,
    String lower,
  ) {
    switch (intent) {
      case AgentIntent.deadlineQuery:
      case AgentIntent.taskQuery:
        String filter = 'pending';
        if (lower.contains('tomorrow')) {
          filter = 'tomorrow';
        } else if (lower.contains('today')) {
          filter = 'today';
        } else if (lower.contains('week')) {
          filter = 'this_week';
        } else if (lower.contains('overdue')) {
          filter = 'overdue';
        } else if (lower.contains('all')) {
          filter = 'all';
        }
        final subject = _extractSubject(lower);
        return AgentToolCall(
          tool: 'get_upcoming_tasks',
          arguments: {
            'filter': filter,
            'limit': 5,
            if (subject != null) 'query': subject,
          },
        );

      case AgentIntent.scheduleQuery:
        if (lower.contains('next class') ||
            lower.contains('next lecture') ||
            lower.contains('when is my next') ||
            lower.contains('what is my next') ||
            (lower.contains('next') && !lower.contains('classes today'))) {
          final subject = _extractSubject(lower);
          return AgentToolCall(
            tool: 'get_upcoming_classes',
            arguments: {
              'target': 'next',
              'limit': 3,
              if (subject != null) 'subject': subject,
            },
          );
        }
        if ((lower.contains('class') && lower.contains('today')) ||
            lower.contains('classes today') ||
            lower.contains('schedule today') ||
            lower.contains('today\'s schedule') ||
            lower.contains('todays schedule') ||
            lower.trim() == 'schedule' ||
            lower.trim() == 'timetable') {
          return const AgentToolCall(
            tool: 'get_today_schedule',
            arguments: {},
          );
        }
        String target = 'all';
        if (lower.contains('tomorrow')) {
          target = 'tomorrow';
        } else if (lower.contains('today')) {
          target = 'today';
        }
        final subject = _extractSubject(lower);
        return AgentToolCall(
          tool: 'get_upcoming_classes',
          arguments: {
            'target': target,
            'limit': 5,
            if (subject != null) 'subject': subject,
          },
        );

      case AgentIntent.holidayQuery:
        String queryType = 'next';
        if (lower.contains('tomorrow')) {
          queryType = 'check_tomorrow';
        } else if (lower.contains('today')) {
          queryType = 'check_today';
        } else if (lower.contains('upcoming') ||
            lower.contains('list') ||
            lower.contains('all')) {
          queryType = 'upcoming';
        }
        return AgentToolCall(
          tool: 'get_holidays',
          arguments: {'queryType': queryType},
        );

      case AgentIntent.messQuery:
        String day = 'today';
        if (lower.contains('tomorrow')) day = 'tomorrow';
        String meal = 'all';
        if (lower.contains('lunch')) {
          meal = 'lunch';
        } else if (lower.contains('dinner')) {
          meal = 'dinner';
        } else if (lower.contains('breakfast')) {
          meal = 'breakfast';
        } else if (lower.contains('snack') || lower.contains('tea')) {
          meal = 'snacks';
        }
        return AgentToolCall(
          tool: 'get_mess_menu',
          arguments: {'day': day, 'meal': meal},
        );

      case AgentIntent.academicCalendarQuery:
        return const AgentToolCall(
          tool: 'get_academic_calendar',
          arguments: {'queryType': 'upcoming_events'},
        );

      case AgentIntent.lectureQuery:
        return const AgentToolCall(
          tool: 'get_recent_lectures',
          arguments: {'limit': 5, 'filter': 'all'},
        );

      case AgentIntent.vaultSearch:
        final query = clean
            .replaceAll(
                RegExp(
                    r'(?:search vault for|search notes for|search vault|search notes|in my notes)',
                    caseSensitive: false),
                '')
            .trim();
        return AgentToolCall(
          tool: 'search_knowledge',
          arguments: {'query': query.isNotEmpty ? query : clean},
        );

      case AgentIntent.timetableAction:
        if (_isDeleteRequest(lower)) {
          return _parseDeleteTimetableCall(clean, lower);
        } else if (_isUpdateRequest(lower)) {
          return _parseUpdateTimetableCall(clean, lower);
        } else {
          return _parseCreateTimetableCall(clean, lower);
        }

      case AgentIntent.taskAction:
        return _parseCreateTaskCall(clean, lower);

      case AgentIntent.recordingAction:
        return _parseScheduleRecordingCall(clean, lower);

      default:
        return null;
    }
  }

  static String? _extractSubject(String lower) {
    const knownSubjects = [
      'data structures',
      'operating systems',
      'discrete math',
      'discrete mathematics',
      'wave optics',
      'engineering physics',
      'computer networks',
      'physics',
      'math',
      'mathematics',
      'os',
      'ai',
      'artificial intelligence',
      'dbms',
      'database',
    ];
    for (final s in knownSubjects) {
      final pattern = RegExp('\\b${RegExp.escape(s)}\\b', caseSensitive: false);
      if (pattern.hasMatch(lower)) {
        return s;
      }
    }
    return null;
  }

  /// Backward-compatible single tool lookup
  AgentToolCall? determineToolCall(String input) {
    final calls = determineToolCalls(input);
    return calls.isNotEmpty ? calls.first : null;
  }

  // ==================== MULTI-TOOL PARSER ====================

  List<AgentToolCall> _parseMultiToolCalls(String clean, String lower) {
    // Check for "add/create ... and record ..." pattern
    final isAddAndRecord =
        (lower.contains('add') || lower.contains('create')) &&
            (lower.contains('and record') ||
                lower.contains('and schedule record') ||
                lower.contains('& record'));

    if (isAddAndRecord) {
      // Split or parse the event creation part
      final createPart = clean
          .replaceAll(
              RegExp(r'\s*(?:and|&)\s*(?:schedule\s+)?record.*$',
                  caseSensitive: false),
              '')
          .trim();
      final createCall =
          _parseCreateTimetableCall(createPart, createPart.toLowerCase());

      if (createCall != null) {
        final args = createCall.arguments;
        final recCall = AgentToolCall(
          tool: 'schedule_recording',
          arguments: {
            'subject': args['subject'],
            'day': args['day'],
            'startTime': args['startTime'],
            if (args.containsKey('endTime')) 'endTime': args['endTime'],
          },
        );
        return [createCall, recCall];
      }
    }

    return [];
  }

  // ==================== ACTION TOOL PARSERS ====================

  bool _isConfirmationPrompt(String lower) {
    return lower == 'yes' ||
        lower == 'yes please' ||
        lower == 'yes, delete it' ||
        lower == 'yes delete it' ||
        lower == 'yes, delete' ||
        lower == 'yes delete' ||
        lower == 'confirm delete' ||
        lower == 'confirm' ||
        lower == 'yes remove it' ||
        lower == 'yes, remove it';
  }

  AgentToolCall? _parseConfirmedDelete(
    String clean,
    String lower,
    List<AcademicChatMessage>? conversationHistory,
  ) {
    String? subject;
    String? day;

    // Scan recent messages for subject / day context
    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      for (final msg in conversationHistory.reversed) {
        final text = msg.text.toLowerCase();
        if (text.contains('remove') || text.contains('delete')) {
          if (text.contains('ai')) {
            subject = 'AI';
          }
          if (text.contains('os') || text.contains('operating system')) {
            subject = 'Operating Systems';
          }
          if (text.contains('math')) {
            subject = 'Mathematics';
          }
          if (text.contains('physics')) {
            subject = 'Engineering Physics';
          }
          if (text.contains('network')) {
            subject = 'Computer Networks';
          }

          for (final d in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']) {
            if (text.contains(d)) {
              day = d;
              break;
            }
          }
          if (subject != null) {
            break;
          }
        }
      }
    }

    return AgentToolCall(
      tool: 'delete_timetable_event',
      arguments: {
        if (subject != null) 'subject': subject,
        if (day != null) 'day': day,
        'confirmed': true,
      },
    );
  }

  bool _isDeleteRequest(String lower) {
    return (lower.startsWith('delete') ||
            lower.startsWith('remove') ||
            lower.contains('delete my') ||
            lower.contains('remove my')) &&
        (lower.contains('class') ||
            lower.contains('lecture') ||
            lower.contains('event') ||
            lower.contains('timetable') ||
            lower.contains('ai') ||
            lower.contains('os') ||
            lower.contains('math') ||
            lower.contains('physics') ||
            lower.contains('network'));
  }

  AgentToolCall? _parseDeleteTimetableCall(String clean, String lower) {
    final confirmed = lower.contains('confirm') || lower.contains('force');

    // Extract subject
    String subject = '';
    if (lower.contains('ai') || lower.contains('artificial intelligence')) {
      subject = 'AI';
    } else if (lower.contains('os') || lower.contains('operating system')) {
      subject = 'Operating Systems';
    } else if (lower.contains('math')) {
      subject = 'Mathematics';
    } else if (lower.contains('physics')) {
      subject = 'Engineering Physics';
    } else if (lower.contains('network')) {
      subject = 'Computer Networks';
    } else {
      // Regex subject extraction
      final subMatch = RegExp(
              r'(?:delete|remove)\s+(?:my\s+)?([a-zA-Z\s]+?)(?:\s+class|\s+lecture|\s+on|\s+from|$)',
              caseSensitive: false)
          .firstMatch(clean);
      if (subMatch != null) {
        subject = subMatch.group(1)!.trim();
      }
    }

    // Extract day
    String? day;
    if (lower.contains('tomorrow')) {
      day = 'tomorrow';
    } else if (lower.contains('today')) {
      day = 'today';
    } else {
      final dayMatch = RegExp(
              r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\b',
              caseSensitive: false)
          .firstMatch(clean);
      if (dayMatch != null) {
        day = dayMatch.group(1);
      }
    }

    return AgentToolCall(
      tool: 'delete_timetable_event',
      arguments: {
        if (subject.isNotEmpty) 'subject': subject,
        if (day != null) 'day': day,
        'confirmed': confirmed,
      },
    );
  }

  bool _isUpdateRequest(String lower) {
    return (lower.startsWith('move') ||
            lower.startsWith('reschedule') ||
            lower.startsWith('change') ||
            lower.startsWith('shift') ||
            lower.contains('move tomorrow') ||
            lower.contains('move my')) &&
        (lower.contains('to') || lower.contains('from'));
  }

  AgentToolCall? _parseUpdateTimetableCall(String clean, String lower) {
    // Extract subject
    String subject = '';
    if (lower.contains('ai') || lower.contains('artificial intelligence')) {
      subject = 'AI';
    } else if (lower.contains('os') || lower.contains('operating system')) {
      subject = 'Operating Systems';
    } else if (lower.contains('math')) {
      subject = 'Mathematics';
    } else if (lower.contains('physics')) {
      subject = 'Engineering Physics';
    } else if (lower.contains('network')) {
      subject = 'Computer Networks';
    } else {
      final subMatch = RegExp(
              r'(?:move|reschedule|change|shift)\s+(?:tomorrow(?:\x27s|\s+)?|my\s+)?([a-zA-Z\s]+?)(?:\s+class|\s+lecture|\s+from|\s+to)',
              caseSensitive: false)
          .firstMatch(clean);
      if (subMatch != null) {
        subject = subMatch.group(1)!.trim();
      }
    }

    // Extract current day
    String? currentDay;
    if (lower.contains('tomorrow')) {
      currentDay = 'tomorrow';
    } else if (lower.contains('today')) {
      currentDay = 'today';
    } else {
      final dayMatch = RegExp(
              r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\b',
              caseSensitive: false)
          .firstMatch(clean);
      if (dayMatch != null) {
        currentDay = dayMatch.group(1);
      }
    }

    // Extract new time: "to 11", "to 11:00 AM", "from 10 to 11", "to 10 to 11"
    String? newStartTime;
    String? newEndTime;

    final toRangeMatch = RegExp(
            r'to\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*(?:-|to)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)',
            caseSensitive: false)
        .firstMatch(clean);
    if (toRangeMatch != null) {
      newStartTime = toRangeMatch.group(1)!.trim();
      newEndTime = toRangeMatch.group(2)!.trim();
    } else {
      final fromToMatch = RegExp(
              r'from\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s+(?:to|-)\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)',
              caseSensitive: false)
          .firstMatch(clean);
      if (fromToMatch != null) {
        newStartTime = fromToMatch.group(2)!.trim();
      } else {
        final toMatch = RegExp(r'to\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)',
                caseSensitive: false)
            .firstMatch(clean);
        if (toMatch != null) {
          newStartTime = toMatch.group(1)!.trim();
        }
      }
    }

    if (newStartTime == null) {
      // Fallback: look for last time mentioned
      final timeMatch =
          RegExp(r'(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)', caseSensitive: false)
              .allMatches(clean)
              .toList();
      if (timeMatch.isNotEmpty) {
        newStartTime = timeMatch.last.group(1)!.trim();
      }
    }

    return AgentToolCall(
      tool: 'update_timetable_event',
      arguments: {
        'subject': subject.isNotEmpty ? subject : 'AI',
        'newStartTime': newStartTime ?? '11:00 AM',
        if (newEndTime != null) 'newEndTime': newEndTime,
        if (currentDay != null) 'currentDay': currentDay,
      },
    );
  }

  bool _isCreateTimetableRequest(String lower) {
    if (lower.contains('remind') ||
        lower.contains('task') ||
        lower.contains('assignment') ||
        lower.contains('deadline') ||
        lower.contains('deadlines') ||
        lower.contains('homework') ||
        lower.contains('submission') ||
        lower.contains('submit') ||
        lower.contains('todo') ||
        lower.contains('project') ||
        (lower.contains('due') &&
            !lower.contains('class') &&
            !lower.contains('lecture')) ||
        lower.contains('record') ||
        lower.startsWith('what') ||
        lower.startsWith('when') ||
        lower.startsWith('which') ||
        lower.startsWith('do i have') ||
        lower.startsWith('are there') ||
        lower.startsWith('show') ||
        lower.startsWith('view') ||
        lower.contains('what class') ||
        lower.contains('next class') ||
        lower.contains('next lecture')) {
      return false;
    }
    final clean = lower
        .replaceFirst(
            RegExp(
                r'^(?:(?:hey|hi|a|ok|he)?\s*(?:pal|paul|hebbal|apple|bell)|hebbal|apple)[,\s]*',
                caseSensitive: false),
            '')
        .trim();

    final hasActionVerb = RegExp(
            r'\b(?:create|add|schedule|put|book|set\s+up)\b',
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

  static String _formatTimeStr(String raw, {String? defaultPeriod}) {
    var t = raw.trim();
    // Strip dots in a.m. / p.m.
    t = t.replaceAll(RegExp(r'a\.m\.?', caseSensitive: false), 'AM');
    t = t.replaceAll(RegExp(r'p\.m\.?', caseSensitive: false), 'PM');

    final amPmMatch =
        RegExp(r'^(.*?)\s*(am|pm)$', caseSensitive: false).firstMatch(t);
    String mainPart = t;
    String? amPm;
    if (amPmMatch != null) {
      mainPart = amPmMatch.group(1)!.trim();
      amPm = amPmMatch.group(2)!.toUpperCase();
    }

    final parts = mainPart.split(':');
    final hour = int.tryParse(parts[0]);
    if (hour == null) return t.toUpperCase();
    final minute = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';

    if (amPm != null) {
      return '$hour:$minute $amPm';
    }

    if (defaultPeriod != null && defaultPeriod.isNotEmpty) {
      return '$hour:$minute ${defaultPeriod.toUpperCase()}';
    }

    if (hour >= 8 && hour <= 11) {
      return '$hour:$minute AM';
    } else if (hour == 12 || (hour >= 1 && hour <= 7)) {
      return '$hour:$minute PM';
    } else {
      return '$hour:$minute';
    }
  }

  AgentToolCall? _parseCreateTimetableCall(String clean, String lower) {
    // 0. Pre-clean text:
    var workingText = clean
        .replaceFirst(
            RegExp(
                r'^(?:(?:hey|hi|a|ok|he)?\s*(?:pal|paul|hebbal|apple|bell)|hebbal|apple)[,\s]*',
                caseSensitive: false),
            '')
        .trim();
    // Normalize a.m. / p.m.
    workingText =
        workingText.replaceAll(RegExp(r'a\.m\.?', caseSensitive: false), 'AM');
    workingText =
        workingText.replaceAll(RegExp(r'p\.m\.?', caseSensitive: false), 'PM');

    final workingLower = workingText.toLowerCase();

    // 1. Subject extraction:
    String subject = '';
    if (workingLower.contains('data structure') ||
        workingLower.contains('data structures') ||
        workingLower.contains('data stitches') ||
        workingLower.contains('dsa')) {
      subject = 'Data Structures';
    } else if (workingLower.contains('operating system') ||
        workingLower.contains('operating systems') ||
        RegExp(r'\bos\b', caseSensitive: false).hasMatch(workingText)) {
      subject = 'Operating Systems';
    } else if (workingLower.contains('computer network') ||
        workingLower.contains('computer networks') ||
        workingLower.contains('network') ||
        workingLower.contains('networking')) {
      subject = 'Computer Networks';
    } else if (workingLower.contains('artificial intelligence') ||
        RegExp(r'\bai\b', caseSensitive: false).hasMatch(workingText)) {
      subject = 'Artificial Intelligence';
    } else if (workingLower.contains('discrete') ||
        workingLower.contains('discrete math') ||
        workingLower.contains('discrete mathematics')) {
      subject = 'Discrete Mathematics';
    } else if (workingLower.contains('physics') ||
        workingLower.contains('engineering physics')) {
      subject = 'Engineering Physics';
    } else if (workingLower.contains('dbms') ||
        workingLower.contains('database')) {
      subject = 'Database Systems';
    } else if (workingLower.contains('math') ||
        workingLower.contains('mathematics')) {
      subject = 'Mathematics';
    } else {
      // Check user timetable entries for matching subject names
      for (final entry in TimetableService.instance.entries) {
        if (entry.subject.trim().isNotEmpty &&
            workingLower.contains(entry.subject.trim().toLowerCase())) {
          subject = entry.subject.trim();
          break;
        }
      }
    }

    if (subject.isEmpty) {
      // Look for: "create/add/schedule/put ... [subject] class/lecture"
      final verbSubMatch = RegExp(
              r'(?:create|add|schedule|put|book)\s+(?:a\s+|an\s+)?([a-zA-Z\s]+?)\s+(?:class|lecture|period|session)\b',
              caseSensitive: false)
          .firstMatch(workingText);
      if (verbSubMatch != null && verbSubMatch.group(1)!.trim().isNotEmpty) {
        final candidate = verbSubMatch.group(1)!.trim();
        if (candidate.toLowerCase() != 'new' &&
            candidate.toLowerCase() != 'my') {
          subject = candidate;
        }
      }
    }

    if (subject.isEmpty) {
      // Look for: "on <subject>" or "for <subject>" (strictly excluding "for me")
      final onMatch = RegExp(
              r'\b(?:on|(?:for\s+(?!me\b)))\s+([a-zA-Z\s]+?)(?:\s+at|\s+from|\s+tomorrow|\s+today|$|[.,;])',
              caseSensitive: false)
          .firstMatch(workingText);
      if (onMatch != null && onMatch.group(1)!.trim().isNotEmpty) {
        subject = onMatch.group(1)!.trim();
      } else {
        final subMatch = RegExp(
                r'(?:add|create|schedule|put)\s+(?:a\s+|an\s+)?(?:class\s+)?([a-zA-Z\s]+?)(?:\s+tomorrow|\s+today|\s+on|\s+at|\s+from|$|[.,;])',
                caseSensitive: false)
            .firstMatch(workingText);
        if (subMatch != null) {
          final s = subMatch.group(1)!.trim();
          if (s.toLowerCase() != 'me' && s.toLowerCase() != 'for me') {
            subject = s;
          }
        }
      }
    }

    // Day
    String day = 'tomorrow';
    if (workingLower.contains('today')) {
      day = 'today';
    } else if (workingLower.contains('tomorrow')) {
      day = 'tomorrow';
    } else {
      final dayMatch = RegExp(
              r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\b',
              caseSensitive: false)
          .firstMatch(workingText);
      if (dayMatch != null) {
        day = dayMatch.group(1)!;
      }
    }

    // Times: "from 10:00 AM to 11", "from 10 to 11", "at 10 to 11", "at 10", "10 to 11"
    String startTime = '10:00 AM';
    String? endTime;

    final fromToMatch = RegExp(
            r'(?:from|at)\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*(?:to|-)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)',
            caseSensitive: false)
        .firstMatch(workingText);
    if (fromToMatch != null) {
      final rawStart = fromToMatch.group(1)!.trim();
      final rawEnd = fromToMatch.group(2)!.trim();
      startTime = _formatTimeStr(rawStart);
      String? startPeriod;
      if (startTime.toUpperCase().contains('AM')) startPeriod = 'AM';
      if (startTime.toUpperCase().contains('PM')) startPeriod = 'PM';
      endTime = _formatTimeStr(rawEnd, defaultPeriod: startPeriod);
    } else {
      final directRangeMatch = RegExp(
              r'\b(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*(?:to|-)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\b',
              caseSensitive: false)
          .firstMatch(workingText);
      if (directRangeMatch != null) {
        final rawStart = directRangeMatch.group(1)!.trim();
        final rawEnd = directRangeMatch.group(2)!.trim();
        startTime = _formatTimeStr(rawStart);
        String? startPeriod;
        if (startTime.toUpperCase().contains('AM')) startPeriod = 'AM';
        if (startTime.toUpperCase().contains('PM')) startPeriod = 'PM';
        endTime = _formatTimeStr(rawEnd, defaultPeriod: startPeriod);
      } else {
        final atMatch = RegExp(
                r'(?:at|from)\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)',
                caseSensitive: false)
            .firstMatch(workingText);
        if (atMatch != null) {
          startTime = _formatTimeStr(atMatch.group(1)!.trim());
        }
      }
    }

    return AgentToolCall(
      tool: 'create_timetable_event',
      arguments: {
        'subject': subject.isNotEmpty ? subject : 'Academic Class',
        'day': day,
        'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
      },
    );
  }

  bool _isScheduleRecordingRequest(String lower) {
    if (lower.contains('what did') ||
        lower.contains('recent') ||
        lower.contains('recorded today') ||
        lower.contains('how many')) {
      return false;
    }
    return lower.startsWith('record') ||
        lower.contains('schedule recording') ||
        lower.contains('record my') ||
        lower.contains('auto record') ||
        lower.contains('record class');
  }

  AgentToolCall? _parseScheduleRecordingCall(String clean, String lower) {
    // E.g. "Record my networking class tomorrow from 2 to 3"
    String subject = 'Networking';
    if (lower.contains('networking') || lower.contains('network')) {
      subject = 'Computer Networks';
    } else if (lower.contains('ai') ||
        lower.contains('artificial intelligence')) {
      subject = 'Artificial Intelligence';
    } else if (lower.contains('os') || lower.contains('operating system')) {
      subject = 'Operating Systems';
    } else if (lower.contains('math')) {
      subject = 'Mathematics';
    } else if (lower.contains('physics')) {
      subject = 'Engineering Physics';
    } else {
      final subMatch = RegExp(
              r'(?:record\s+my|record|schedule\s+recording\s+for)\s+([a-zA-Z\s]+?)(?:\s+class|\s+tomorrow|\s+on|\s+from|$)',
              caseSensitive: false)
          .firstMatch(clean);
      if (subMatch != null) {
        subject = subMatch.group(1)!.trim();
      }
    }

    // Day
    String day = 'tomorrow';
    if (lower.contains('today')) {
      day = 'today';
    } else {
      final dayMatch = RegExp(
              r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\b',
              caseSensitive: false)
          .firstMatch(clean);
      if (dayMatch != null) {
        day = dayMatch.group(1)!;
      }
    }

    // Times
    String? startTime;
    String? endTime;
    final fromToMatch = RegExp(
            r'(?:from|at)\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*(?:to|-)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)',
            caseSensitive: false)
        .firstMatch(clean);
    if (fromToMatch != null) {
      startTime = fromToMatch.group(1)!.trim();
      endTime = fromToMatch.group(2)!.trim();
    } else {
      final atMatch = RegExp(r'(?:at|from)\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)',
              caseSensitive: false)
          .firstMatch(clean);
      if (atMatch != null) {
        startTime = atMatch.group(1)!.trim();
      }
    }

    return AgentToolCall(
      tool: 'schedule_recording',
      arguments: {
        'subject': subject,
        'day': day,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
      },
    );
  }

  bool _isCreateTaskRequest(String lower) {
    final clean = lower
        .replaceFirst(
            RegExp(
                r'^(?:(?:hey|hi|a|ok|he)?\s*(?:pal|paul|hebbal|apple|bell)|hebbal|apple)[,\s]*',
                caseSensitive: false),
            '')
        .trim();

    // Query prompts must not be treated as task creation actions
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

  AgentToolCall? _parseCreateTaskCall(String clean, String lower) {
    // E.g. "Remind me to submit my OS assignment on September 15"
    // E.g. "Create task study for Math quiz due tomorrow"
    // E.g. "add a physics deadline to me today"
    // E.g. "add my physics assignment due today"
    var workingText = clean
        .replaceFirst(
            RegExp(
                r'^(?:(?:hey|hi|a|ok|he)?\s*(?:pal|paul|hebbal|apple|bell)|hebbal|apple)[,\s]*',
                caseSensitive: false),
            '')
        .trim();
    // Strip colloquial fillers
    workingText = workingText.replaceAll(
        RegExp(r'\b(?:to|for)\s+me\b|\bplease\b|\bcan you\b|\bcould you\b',
            caseSensitive: false),
        '');

    final workingLower = workingText.toLowerCase();

    // Subject resolution using timetable entries and suggested subjects
    final displaySubject =
        AgentPlanner.extractDisplaySubject(workingLower, clean);
    final course =
        AgentPlanner.resolveCourseSubject(workingLower, clean, displaySubject);

    // Due date
    String dueDate = 'tomorrow';
    if (workingLower.contains('today')) {
      dueDate = 'today';
    } else if (workingLower.contains('tomorrow')) {
      dueDate = 'tomorrow';
    } else {
      final dueMatch = RegExp(r'(?:on|by|due|for)\s+([a-zA-Z0-9\s]+?)$',
              caseSensitive: false)
          .firstMatch(workingText);
      if (dueMatch != null) {
        dueDate = dueMatch.group(1)!.trim();
      }
    }

    // Title
    final title = AgentPlanner.extractTaskTitle(
        workingText, workingLower, displaySubject);

    return AgentToolCall(
      tool: 'create_task',
      arguments: {
        'title': title,
        'dueDate': dueDate,
        if (course.isNotEmpty) 'course': course,
      },
    );
  }

  // ==================== READ-ONLY TOOLS (PHASE 2) ====================

  AgentToolCall? _parseReadOnlyCall(String clean, String lower) {
    // 1. Next class / upcoming lecture questions
    if (lower.contains('next class') ||
        lower.contains('next lecture') ||
        (lower.contains('class') && lower.contains('next')) ||
        (lower.contains('lecture') && lower.contains('next'))) {
      final subject = _extractSubject(lower);
      return AgentToolCall(
        tool: 'get_upcoming_classes',
        arguments: {
          'target': 'next',
          'limit': 3,
          if (subject != null) 'subject': subject,
        },
      );
    }

    // 2. Tomorrow's schedule
    if ((lower.contains('tomorrow') &&
            (lower.contains('class') ||
                lower.contains('schedule') ||
                lower.contains('timetable') ||
                lower.contains('lecture'))) ||
        lower.contains('what class do i have tomorrow')) {
      final subject = _extractSubject(lower);
      return AgentToolCall(
        tool: 'get_upcoming_classes',
        arguments: {
          'target': 'tomorrow',
          'limit': 5,
          if (subject != null) 'subject': subject,
        },
      );
    }

    // 3. Today's schedule / classes / general schedule
    if ((lower.contains('class') && lower.contains('today')) ||
        lower.contains('classes today') ||
        lower.contains('schedule today') ||
        lower.contains('classes do i have today') ||
        lower.contains('what classes do i have today') ||
        lower.contains('my classes today') ||
        lower.contains('today\'s schedule') ||
        lower.contains('todays schedule') ||
        lower.contains('my schedule') ||
        lower.contains('check my schedule') ||
        lower.contains('what is my schedule') ||
        lower.contains('what\'s my schedule') ||
        lower.contains('show schedule') ||
        lower.contains('view schedule') ||
        lower.trim() == 'schedule' ||
        lower.trim() == 'timetable') {
      return const AgentToolCall(
        tool: 'get_today_schedule',
        arguments: {},
      );
    }

    // 4. Tasks / assignments / deadlines (Checked before generic upcoming classes)
    if (lower.contains('assignment') ||
        lower.contains('deadline') ||
        lower.contains('due') ||
        lower.contains('homework') ||
        lower.contains('task')) {
      String filter = 'pending';
      if (lower.contains('tomorrow')) {
        filter = 'tomorrow';
      } else if (lower.contains('today')) {
        filter = 'today';
      } else if (lower.contains('week')) {
        filter = 'this_week';
      } else if (lower.contains('overdue')) {
        filter = 'overdue';
      } else if (lower.contains('all')) {
        filter = 'all';
      }
      final subject = _extractSubject(lower);
      return AgentToolCall(
        tool: 'get_upcoming_tasks',
        arguments: {
          'filter': filter,
          'limit': 5,
          if (subject != null) 'query': subject,
        },
      );
    }

    // 5. Upcoming classes / lectures / general schedule inquiries
    if (lower.contains('upcoming class') ||
        lower.contains('upcoming classes') ||
        lower.contains('classes are coming up') ||
        lower.contains('classes coming up') ||
        lower.contains('what are my classes') ||
        lower.contains('what classes do i have') ||
        lower.contains('classes do i have') ||
        lower.contains('show my classes') ||
        lower.contains('check my classes') ||
        lower.contains('list my classes') ||
        lower.contains('any classes')) {
      final subject = _extractSubject(lower);
      return AgentToolCall(
        tool: 'get_upcoming_classes',
        arguments: {
          'target': 'all',
          'limit': 5,
          if (subject != null) 'subject': subject,
        },
      );
    }

    // 6. Recent lectures / recorded audio
    if (lower.contains('recorded today') ||
        lower.contains('last lecture') ||
        lower.contains('recent lecture') ||
        lower.contains('recent recording') ||
        lower.contains('yesterday\'s lecture discuss') ||
        lower.contains('yesterdays lecture discuss') ||
        lower.contains('what did yesterday\'s lecture') ||
        lower.contains('what did yesterdays lecture') ||
        lower.contains('lectures did i record')) {
      return const AgentToolCall(
        tool: 'get_recent_lectures',
        arguments: {'limit': 5, 'filter': 'all'},
      );
    }

    // 7. Campus: Mess Menu queries
    if (lower.contains('mess') ||
        lower.contains('lunch') ||
        lower.contains('dinner') ||
        lower.contains('breakfast') ||
        lower.contains('snacks') ||
        lower.contains('food today') ||
        lower.contains('menu today')) {
      String day = 'today';
      if (lower.contains('tomorrow')) day = 'tomorrow';
      String meal = 'all';
      if (lower.contains('lunch')) {
        meal = 'lunch';
      } else if (lower.contains('dinner')) {
        meal = 'dinner';
      } else if (lower.contains('breakfast')) {
        meal = 'breakfast';
      } else if (lower.contains('snack') || lower.contains('tea')) {
        meal = 'snacks';
      }
      return AgentToolCall(
        tool: 'get_mess_menu',
        arguments: {'day': day, 'meal': meal},
      );
    }

    // 8. Campus: Holidays queries
    if (lower.contains('holiday') ||
        lower.contains('holidays') ||
        lower.contains('next break') ||
        lower.contains('vacation')) {
      String queryType = 'next';
      if (lower.contains('tomorrow')) {
        queryType = 'check_tomorrow';
      } else if (lower.contains('today')) {
        queryType = 'check_today';
      } else if (lower.contains('upcoming') ||
          lower.contains('list') ||
          lower.contains('all')) {
        queryType = 'upcoming';
      }
      return AgentToolCall(
        tool: 'get_holidays',
        arguments: {'queryType': queryType},
      );
    }

    // 9. Campus: Student ID Card queries
    if (lower.contains('student id') ||
        lower.contains('roll number') ||
        lower.contains('roll no') ||
        lower.contains('my roll') ||
        lower.contains('id card') ||
        lower.contains('show my id') ||
        lower.contains('my id')) {
      String field = 'all';
      if (lower.contains('roll')) {
        field = 'roll_number';
      } else if (lower.contains('id') && !lower.contains('card')) {
        field = 'id';
      } else if (lower.contains('department') || lower.contains('branch')) {
        field = 'department';
      }
      return AgentToolCall(
        tool: 'get_id_card',
        arguments: {'field': field},
      );
    }

    // 10. Campus: Academic Calendar queries
    if (lower.contains('academic calendar') ||
        lower.contains('exam date') ||
        lower.contains('exam schedule') ||
        lower.contains('when are exams') ||
        lower.contains('when are my exams') ||
        lower.contains('end-term') ||
        lower.contains('end term') ||
        lower.contains('mid-term') ||
        lower.contains('mid term') ||
        lower.contains('semester end') ||
        lower.contains('fee deadline') ||
        lower.contains('registration deadline')) {
      String eventType = 'all';
      if (lower.contains('exam') || lower.contains('term')) {
        eventType = 'exam';
      } else if (lower.contains('reg') || lower.contains('fee')) {
        eventType = 'registration';
      }
      return AgentToolCall(
        tool: 'get_academic_calendar',
        arguments: {'eventType': eventType, 'query': clean},
      );
    }

    // 11. Campus: Notices & Circulars
    if (lower.contains('notice') ||
        lower.contains('notices') ||
        lower.contains('circular') ||
        lower.contains('announcement') ||
        lower.contains('placement circular')) {
      String category = 'all';
      if (lower.contains('exam')) {
        category = 'exams';
      } else if (lower.contains('place') || lower.contains('intern')) {
        category = 'placement';
      } else if (lower.contains('event')) {
        category = 'events';
      } else if (lower.contains('admin')) {
        category = 'administration';
      }
      return AgentToolCall(
        tool: 'get_notices',
        arguments: {'category': category, 'query': clean},
      );
    }

    // 12. Knowledge / Notes / PDF / Concept Search
    if ((lower.contains('what did my') && lower.contains('say')) ||
        lower.contains('lecture say') ||
        lower.contains('notes say') ||
        lower.contains('what do my notes say') ||
        lower.contains('in my notes') ||
        lower.contains('search notes') ||
        lower.contains('search vault') ||
        lower.contains('find in lecture') ||
        lower.contains('process scheduling') ||
        lower.contains('scheduling') ||
        lower.contains('peterson')) {
      String query = clean;
      final match = RegExp(
              r'(?:about|say about|discuss|regarding|explain|notes on|lecture on)\s+(.*)',
              caseSensitive: false)
          .firstMatch(clean);
      if (match != null && match.group(1) != null) {
        query = match.group(1)!.trim().replaceAll(RegExp(r'[?.]+$'), '');
      }

      return AgentToolCall(
        tool: 'search_knowledge',
        arguments: {'query': query, 'limit': 3},
      );
    }

    return null;
  }

  // ==================== PROCESS PIPELINE ====================

  static const int maxToolIterations = 5;

  /// Processes user input through the on-device Agent pipeline:
  /// Processes user input through the on-device Agent pipeline:
  /// User input -> Determine intent -> Safe tool execution -> Grounded synthesis
  Future<AgentResponse> process({
    required String prompt,
    AgentContext? context,
    List<AcademicChatMessage>? conversationHistory,
  }) async {
    final ctx = context ?? AgentContext();
    debugPrint('[PAL-AGENT] User input: $prompt');
    debugPrint('[AGENT] User query: $prompt');

    final detectedIntents = AgentIntent.detectIntents(prompt);
    debugPrint(
        '[PAL-AGENT] Detected intent: ${detectedIntents.map((i) => i.code).join(', ')}');

    // 1. Multi-Step Planner Integration
    final plan = planner.createPlan(prompt, context: ctx);

    // Validation before execution: if required information is missing, halt and ask user
    if (plan.isBlockedOnMissingInfo) {
      final question = plan.missingInformationQuestion!;
      debugPrint('[PAL-AGENT] Plan missing info: $question');
      debugPrint('[AGENT] Plan missing info: $question');
      return AgentResponse(
        text: question,
        toolCalls: [],
        toolResults: [],
        rawLlmOutput: question,
      );
    }

    // If multi-step plan, execute sequentially through AgentPlanExecutor
    if (plan.steps.length > 1) {
      debugPrint(
          '[AGENT] Multi-step plan executing: ${plan.steps.length} steps');
      final executedPlan = await planExecutor.execute(plan, context: ctx);
      final toolCalls = executedPlan.steps
          .map((s) => AgentToolCall(tool: s.tool, arguments: s.arguments))
          .toList();
      final toolResults = executedPlan.steps
          .where((s) => s.result != null)
          .map((s) => s.result!)
          .toList();

      for (var i = 0; i < toolCalls.length; i++) {
        debugPrint('[PAL-AGENT] Selected tool: ${toolCalls[i].tool}');
        debugPrint('[PAL-AGENT] Tool arguments: ${toolCalls[i].arguments}');
        debugPrint('[AGENT] Selected tool: ${toolCalls[i].tool}');
        debugPrint('[AGENT] Tool arguments: ${toolCalls[i].arguments}');
        if (i < toolResults.length) {
          debugPrint(
              '[PAL-AGENT] Tool result: ${toolResults[i].toLlmContextString()}');
          debugPrint(
              '[AGENT] Tool result: ${toolResults[i].toLlmContextString()}');
        }
      }

      final responseText = _synthesizeMultiStepPlanAnswer(executedPlan);
      debugPrint('[PAL-AGENT] Final response: $responseText');
      debugPrint('[AGENT] Final grounded response: $responseText');

      return AgentResponse(
        text: responseText,
        toolCalls: toolCalls,
        toolResults: toolResults,
        rawLlmOutput: executedPlan.formatProgressSummary(),
      );
    }

    // 2. Identify Tool Calls (Deterministic first, then dynamic LLM decision if loaded)
    List<AgentToolCall> toolCalls =
        determineToolCalls(prompt, conversationHistory: conversationHistory);

    if (toolCalls.isEmpty && llmService.isModelLoaded) {
      debugPrint('[AGENT] Attempting dynamic LLM tool decision pass...');
      final toolDecisionPrompt = registry.buildSystemPrompt();
      final llmDecision = await _generateLlmResponse(
        prompt: prompt,
        systemPrompt: toolDecisionPrompt,
        history: conversationHistory,
        maxTokens: 256,
      );

      final extractedCalls = AgentToolCall.extractCalls(llmDecision);
      if (extractedCalls.isNotEmpty) {
        toolCalls = extractedCalls;
        debugPrint(
            '[AGENT] Dynamic LLM selected ${extractedCalls.length} tool(s)');
      } else {
        // LLM decided no tool is needed (e.g. general conversation)
        final cleanAnswer = _cleanLlmResponse(llmDecision);
        debugPrint('[PAL-AGENT] Final response: $cleanAnswer');
        debugPrint('[AGENT] Final grounded response: $cleanAnswer');
        return AgentResponse(
          text: cleanAnswer,
          toolCalls: [],
          toolResults: [],
          rawLlmOutput: llmDecision,
        );
      }
    }

    if (toolCalls.isEmpty) {
      // Direct conversational response without tool invocation
      final directAnswer =
          await _generateDirectAnswer(prompt, ctx, conversationHistory);
      debugPrint('[PAL-AGENT] Final response: $directAnswer');
      debugPrint('[AGENT] Final grounded response: $directAnswer');
      return AgentResponse(
        text: directAnswer,
        toolCalls: [],
        toolResults: [],
        rawLlmOutput: directAnswer,
      );
    }

    // Section 9: Tool Routing Mismatch Guard
    // If user's intent is deadline or task query, NEVER allow timetable or class tools.
    // For single-intent queries, ensure tool selection did not drift into the wrong domain.
    if (detectedIntents.length == 1) {
      final primaryIntent = detectedIntents.first;
      for (int i = 0; i < toolCalls.length; i++) {
        final call = toolCalls[i];
        if (primaryIntent == AgentIntent.taskAction &&
            call.tool != 'create_task') {
          debugPrint('[PAL-AGENT] WARNING: Tool routing mismatch detected! '
              'Intent was ${primaryIntent.code} but selected tool was ${call.tool}. '
              'Rerouting to create_task.');
          final rerouted = _parseCreateTaskCall(prompt, prompt.toLowerCase());
          if (rerouted != null) {
            toolCalls[i] = rerouted;
          }
        } else if (primaryIntent == AgentIntent.timetableAction &&
            call.tool == 'create_task') {
          debugPrint('[PAL-AGENT] WARNING: Tool routing mismatch detected! '
              'Intent was ${primaryIntent.code} but selected tool was ${call.tool}. '
              'Rerouting to create_timetable_event.');
          final rerouted =
              _parseCreateTimetableCall(prompt, prompt.toLowerCase());
          if (rerouted != null) {
            toolCalls[i] = rerouted;
          }
        } else if ((primaryIntent == AgentIntent.deadlineQuery ||
                primaryIntent == AgentIntent.taskQuery) &&
            (call.tool == 'get_upcoming_classes' ||
                call.tool == 'get_today_schedule')) {
          debugPrint('[PAL-AGENT] WARNING: Tool routing mismatch detected! '
              'Intent was ${primaryIntent.code} but selected tool was ${call.tool}. '
              'Rerouting to get_upcoming_tasks.');
          toolCalls[i] =
              _toolCallForIntent(primaryIntent, prompt, prompt.toLowerCase()) ??
                  AgentToolCall(
                    tool: 'get_upcoming_tasks',
                    arguments: {
                      'filter': prompt.toLowerCase().contains('tomorrow')
                          ? 'tomorrow'
                          : (prompt.toLowerCase().contains('week')
                              ? 'this_week'
                              : 'pending'),
                      'limit': 5,
                    },
                  );
        } else if (primaryIntent == AgentIntent.scheduleQuery &&
            call.tool == 'get_upcoming_tasks') {
          debugPrint('[PAL-AGENT] WARNING: Tool routing mismatch detected! '
              'Intent was ${primaryIntent.code} but selected tool was ${call.tool}. '
              'Rerouting to get_upcoming_classes.');
          toolCalls[i] =
              _toolCallForIntent(primaryIntent, prompt, prompt.toLowerCase()) ??
                  const AgentToolCall(
                    tool: 'get_upcoming_classes',
                    arguments: {'target': 'next', 'limit': 3},
                  );
        }
      }
    }

    // 3. Safe sequential execution through tool registry (capped at maxToolIterations)
    final toolResults = <AgentToolResult>[];
    final callsToExecute = toolCalls.take(maxToolIterations).toList();

    for (final call in callsToExecute) {
      debugPrint('[PAL-AGENT] Selected tool: ${call.tool}');
      debugPrint('[PAL-AGENT] Tool arguments: ${call.arguments}');
      debugPrint('[AGENT] Selected tool: ${call.tool}');
      debugPrint('[AGENT] Tool arguments: ${call.arguments}');

      final result = await registry.executeTool(call, context: ctx);
      toolResults.add(result);
      debugPrint('[PAL-AGENT] Tool result: ${result.toLlmContextString()}');
      debugPrint('[AGENT] Tool result: ${result.toLlmContextString()}');

      if (result.requiresConfirmation) {
        final data = result.data;
        final targetId = (data is Map && data.containsKey('id'))
            ? data['id'] as String?
            : null;
        _pendingConfirmationCall = AgentToolCall(
          tool: call.tool,
          arguments: {
            ...call.arguments,
            if (targetId != null) 'id': targetId,
            'confirmed': true,
          },
        );
      }
    }

    // 4. Grounded Synthesis (Second Pass)
    String synthesizedText;
    final isPureAction = callsToExecute.isNotEmpty &&
        callsToExecute.every((c) =>
            c.tool == 'create_timetable_event' ||
            c.tool == 'update_timetable_event' ||
            c.tool == 'delete_timetable_event' ||
            c.tool == 'create_task' ||
            c.tool == 'schedule_recording');

    if (isPureAction && toolResults.every((r) => r.success)) {
      synthesizedText = toolResults.map((r) => r.message).join('\n');
    } else if (llmService.isModelLoaded) {
      final synthesisSystemPrompt =
          'You are Pal, the user\'s personal academic copilot running on-device.\n'
          'Answer the student\'s question based ONLY on the verified on-device tool results below.\n'
          'RULES:\n'
          '1. Answer accurately using ONLY the data in the tool results.\n'
          '2. If the tool result says no classes, tasks, or recordings were found, state that clearly to the student.\n'
          '3. Do NOT invent, assume, or hallucinate classes, timings, or tasks.\n'
          '4. Under NO circumstances should you mention class schedules or timetable data for an assignment or deadline question. If there are no assignments, state: "You don\'t have any upcoming assignment deadlines."\n'
          '5. Do NOT output any XML tags, <tool_call> tags, or raw JSON in your response.\n'
          '6. Be concise, clear, and helpful.';

      final synthesisPrompt = 'User Question: $prompt\n\n'
          'On-Device Tool Results:\n'
          '${toolResults.map((r) => r.toLlmContextString()).join('\n\n')}\n\n'
          'Grounded answer:';

      final llmSynthesized = await _generateLlmResponse(
        prompt: synthesisPrompt,
        systemPrompt: synthesisSystemPrompt,
        maxTokens: 512,
      );
      final cleaned = _cleanLlmResponse(llmSynthesized);
      synthesizedText = cleaned.isNotEmpty
          ? cleaned
          : _synthesizeGroundedAnswer(
              prompt: prompt,
              toolCalls: callsToExecute,
              results: toolResults,
              context: ctx,
            );
    } else {
      synthesizedText = _synthesizeGroundedAnswer(
        prompt: prompt,
        toolCalls: callsToExecute,
        results: toolResults,
        context: ctx,
      );
    }

    // Final consistency check: If tool is create_timetable_event, ensure response
    // strictly pertains to timetable addition and NEVER mentions assignments, deadlines, or holidays
    final hasCreateTimetable =
        callsToExecute.any((c) => c.tool == 'create_timetable_event');
    if (hasCreateTimetable) {
      final ttResult =
          toolResults.firstWhere((r) => r.tool == 'create_timetable_event');
      if (ttResult.success) {
        synthesizedText = ttResult.message;
      }
    }

    final hasCreateTask = callsToExecute.any((c) => c.tool == 'create_task');
    if (hasCreateTask) {
      final taskResult = toolResults.firstWhere((r) => r.tool == 'create_task');
      if (taskResult.success) {
        synthesizedText = taskResult.message;
      }
    }

    debugPrint('[PAL-AGENT] Final response: $synthesizedText');
    debugPrint('[AGENT] Final grounded response: $synthesizedText');

    return AgentResponse(
      text: synthesizedText,
      toolCalls: callsToExecute,
      toolResults: toolResults,
      rawLlmOutput: toolResults.map((r) => r.toLlmContextString()).join('\n\n'),
    );
  }

  Future<String> _generateLlmResponse({
    required String prompt,
    String? systemPrompt,
    int maxTokens = 512,
    List<AcademicChatMessage>? history,
  }) async {
    try {
      final stream = llmService.generateStreaming(
        prompt: prompt,
        systemPrompt: systemPrompt,
        maxTokens: maxTokens,
        conversationHistory: history,
      );
      final buffer = StringBuffer();
      await for (final token in stream) {
        buffer.write(token);
      }
      return buffer.toString().trim();
    } catch (e) {
      debugPrint('[AGENT] LLM generation error: $e');
      return '';
    }
  }

  String _cleanLlmResponse(String raw) {
    var cleaned =
        raw.replaceAll(RegExp(r'<tool_call>[\s\S]*?</tool_call>'), '').trim();
    cleaned = cleaned
        .replaceAll(RegExp(r'```(?:tool_call|json)[\s\S]*?```'), '')
        .trim();
    return cleaned;
  }

  Future<String> _generateDirectAnswer(
    String prompt,
    AgentContext context,
    List<AcademicChatMessage>? history,
  ) async {
    final stream = llmService.generateStreaming(
      prompt: prompt,
      systemPrompt:
          "You are Pal, the user's on-device personal academic copilot. Be concise, calm, intelligent, and accurate.",
      maxTokens: 256,
      conversationHistory: history,
    );

    final buffer = StringBuffer();
    await for (final token in stream) {
      buffer.write(token);
    }
    return buffer.toString().trim();
  }

  String _synthesizeMultiStepPlanAnswer(AgentPlan plan) {
    // 1. Partial failure or any step failure
    if (plan.status == AgentPlanStatus.partialSuccess ||
        (plan.completedSteps.isNotEmpty && plan.hasFailures)) {
      final completedTools = plan.completedSteps.map((s) => s.tool).toSet();
      final failedStep = plan.failedSteps.first;

      if (completedTools.contains('create_timetable_event') &&
          failedStep.tool == 'schedule_recording') {
        return "The class was added to your timetable, but I couldn't enable automatic recording.";
      }
      if (completedTools.contains('create_timetable_event') &&
          failedStep.tool == 'create_task') {
        return "The class was added to your timetable, but I couldn't set the reminder.";
      }
      return "The initial step was completed, but I couldn't complete ${failedStep.description}: ${failedStep.result?.message ?? ''}";
    }

    // 2. Complete failure
    if (plan.status == AgentPlanStatus.failed || plan.completedSteps.isEmpty) {
      if (plan.failedSteps.isNotEmpty) {
        return "I couldn't complete that request: ${plan.failedSteps.first.result?.message ?? 'Action failed.'}";
      }
      return "I couldn't complete that request.";
    }

    // 3. Complete success - Scenario-tailored synthesis
    final completedTools = plan.completedSteps.map((s) => s.tool).toList();

    // Scenario 1: create_timetable_event + schedule_recording
    if (completedTools.contains('create_timetable_event') &&
        completedTools.contains('schedule_recording')) {
      final eventStep =
          plan.steps.firstWhere((s) => s.tool == 'create_timetable_event');
      final eventData = eventStep.result?.data as Map<String, dynamic>?;
      final subject =
          eventData?['subject'] ?? eventStep.arguments['subject'] ?? 'Class';
      final day = eventData?['day'] ?? eventStep.arguments['day'] ?? 'tomorrow';
      final start =
          eventData?['startTime'] ?? eventStep.arguments['startTime'] ?? '';
      final end = eventData?['endTime'] ?? eventStep.arguments['endTime'] ?? '';
      final room = eventData?['room'] ?? 'Room TBD';

      return "Added **$subject** on **$day** from **$start** to **$end** ($room) to your timetable and scheduled automatic recording.";
    }

    // Scenario 2: create_timetable_event + create_task
    if (completedTools.contains('create_timetable_event') &&
        completedTools.contains('create_task')) {
      final eventStep =
          plan.steps.firstWhere((s) => s.tool == 'create_timetable_event');
      final taskStep = plan.steps.firstWhere((s) => s.tool == 'create_task');
      final eventData = eventStep.result?.data as Map<String, dynamic>?;
      final taskData = taskStep.result?.data as Map<String, dynamic>?;

      final subject =
          eventData?['subject'] ?? eventStep.arguments['subject'] ?? 'Class';
      final day = eventData?['day'] ?? eventStep.arguments['day'] ?? 'tomorrow';
      final start =
          eventData?['startTime'] ?? eventStep.arguments['startTime'] ?? '';
      final end = eventData?['endTime'] ?? eventStep.arguments['endTime'] ?? '';

      return "Added **$subject** on **$day** from **$start** to **$end** and created reminder \"${taskData?['title'] ?? taskStep.arguments['title']}\".";
    }

    // Scenario 3: get_upcoming_classes + update_timetable_event
    if (completedTools.contains('get_upcoming_classes') &&
        completedTools.contains('update_timetable_event')) {
      final updateStep =
          plan.steps.firstWhere((s) => s.tool == 'update_timetable_event');
      final updateData = updateStep.result?.data as Map<String, dynamic>?;
      final subject =
          updateData?['subject'] ?? updateStep.arguments['subject'] ?? 'Class';
      final day =
          updateData?['day'] ?? updateStep.arguments['currentDay'] ?? '';
      final newStart = updateData?['startTime'] ??
          updateStep.arguments['newStartTime'] ??
          '';
      final newEnd = updateData?['endTime'] ?? '';

      return "Identified your next class (**$subject** on **$day**) and moved it to **$newStart**${newEnd.isNotEmpty ? ' - **$newEnd**' : ''}.";
    }

    // Scenario 4: search_knowledge + create_task
    if (completedTools.contains('search_knowledge') &&
        completedTools.contains('create_task')) {
      final taskStep = plan.steps.firstWhere((s) => s.tool == 'create_task');
      final taskData = taskStep.result?.data as Map<String, dynamic>?;
      final title = taskData?['title'] ?? taskStep.arguments['title'] ?? 'Task';
      final date =
          taskData?['formattedDate'] ?? taskStep.arguments['dueDate'] ?? '';

      return "Found the assignment in your lecture materials and created task \"**$title**\" (due $date).";
    }

    // Generic multi-step success
    final buffer = StringBuffer();
    buffer.writeln("Completed all planned actions:\n");
    for (final s in plan.completedSteps) {
      buffer.writeln("• ${s.result?.message ?? s.description}");
    }
    return buffer.toString().trim();
  }

  String _synthesizeGroundedAnswer({
    required String prompt,
    required List<AgentToolCall> toolCalls,
    required List<AgentToolResult> results,
    required AgentContext context,
  }) {
    if (results.length == 1) {
      return _synthesizeSingleToolAnswer(toolCalls.first, results.first);
    }

    // Multi-tool response synthesis
    final buffer = StringBuffer();
    final anyRequiresConfirmation = results.any((r) => r.requiresConfirmation);

    if (anyRequiresConfirmation) {
      buffer.writeln('⚠️ **Confirmation Required**\n');
    }

    for (var i = 0; i < results.length; i++) {
      final call = toolCalls[i];
      final r = results[i];
      if (i > 0) buffer.writeln('\n');
      buffer.write(_synthesizeSingleToolAnswer(call, r));
    }

    return buffer.toString().trim();
  }

  String _synthesizeSingleToolAnswer(
      AgentToolCall toolCall, AgentToolResult result) {
    if (!result.success) {
      if (result.error == 'TOOL_NOT_FOUND') {
        return 'Unknown tool: "${result.tool}". This action cannot be executed.';
      }
      return 'I couldn\'t complete that request: ${result.message}';
    }

    if (result.requiresConfirmation) {
      return '⚠️ **Confirmation Required**\n\n${result.message}';
    }

    final data = result.data;
    if (data is! Map<String, dynamic>) {
      return result.message;
    }

    // Grounded synthesis for each tool type
    switch (toolCall.tool) {
      case 'create_timetable_event':
        return 'Added **${data["subject"]}** on **${data["day"]}** from **${data["startTime"]}** to **${data["endTime"]}** (${data["room"]}) to your timetable.';

      case 'update_timetable_event':
        return 'Moved **${data["subject"]}** on **${data["day"]}** to **${data["startTime"]}** - **${data["endTime"]}**.';

      case 'delete_timetable_event':
        return result.message;

      case 'create_task':
        return 'Created task "**${data["title"]}**" for **${data["course"]}** due on **${data["formattedDate"]}** [Priority: ${data["priority"]?.toString().toUpperCase()}].';

      case 'schedule_recording':
        return result.message;

      case 'get_today_schedule':
        final classes = (data['classes'] as List?) ?? [];
        final day = data['day'] ?? 'today';
        if (classes.isEmpty) {
          return 'You have no classes scheduled for $day. Enjoy your free time or use it for focused study!';
        }
        final buffer = StringBuffer();
        buffer.writeln('Here is your class schedule for **$day**:');
        for (var i = 0; i < classes.length; i++) {
          final c = classes[i];
          buffer.writeln(
              '${i + 1}. **${c["subject"]}** · ${c["start"]} - ${c["end"]} (${c["room"] ?? "Room TBD"}, ${c["professor"] ?? "Professor TBD"})');
        }
        return buffer.toString().trim();

      case 'get_upcoming_classes':
        final classes = (data['classes'] as List?) ?? [];
        if (classes.isEmpty) {
          final sub = data['subject'];
          if (sub != null && sub.toString().isNotEmpty) {
            return "You don't have any upcoming classes for \"$sub\".";
          }
          return "Your timetable doesn't contain any upcoming classes.";
        }
        final first = classes.first;
        final buffer = StringBuffer();
        buffer.writeln(
            'Your next class is **${first["subject"]}** at **${first["start"]}** (${first["day"]}, ${first["room"]}).');
        if (classes.length > 1) {
          buffer.writeln('\nFollowing classes:');
          for (var i = 1; i < classes.length; i++) {
            final c = classes[i];
            buffer.writeln(
                '• **${c["subject"]}** (${c["day"]} at ${c["start"]}, ${c["room"]})');
          }
        }
        return buffer.toString().trim();

      case 'get_upcoming_tasks':
        final tasks = (data['tasks'] as List?) ?? [];
        if (tasks.isEmpty) {
          final q = data['query'];
          if (q != null && q.toString().isNotEmpty) {
            return "You don't have any upcoming assignment deadlines for \"$q\".";
          }
          return "You don't have any upcoming assignment deadlines.";
        }
        final buffer = StringBuffer();
        buffer.writeln('Here are your upcoming assignment deadlines:');
        for (final t in tasks) {
          final priority = t['priority']?.toString().toUpperCase() ?? 'MEDIUM';
          final timeLeft = t['timeLeft'] ?? '';
          buffer.writeln(
              '• **${t["title"]}** (${t["course"]}) — Due: $timeLeft [Priority: $priority]');
        }
        return buffer.toString().trim();

      case 'search_knowledge':
        final matches = (data['matches'] as List?) ?? [];
        final query = data['query'] ?? '';
        if (matches.isEmpty) {
          return 'I searched your Study Vault, but found no matching notes or lecture excerpts for "$query".';
        }
        final buffer = StringBuffer();
        buffer.writeln(
            'Here is what your course materials say about **$query**:');
        for (var i = 0; i < matches.length; i++) {
          final m = matches[i];
          final location = m['isAudio'] == true
              ? '${m["documentName"]} at ${m["timestamp"] ?? "00:00"}'
              : '${m["documentName"]}, p. ${m["pageNumber"]} (${m["extractionType"]})';
          buffer.writeln('\n**Source ${i + 1}: $location**');
          buffer.writeln('${m["text"]}');
        }
        return buffer.toString().trim();

      case 'get_recent_lectures':
        final recordings = (data['recordings'] as List?) ?? [];
        if (recordings.isEmpty) {
          return 'No recorded lectures found.';
        }
        final buffer = StringBuffer();
        buffer.writeln('Here are your recent lecture recordings:');
        for (final r in recordings) {
          final status =
              r['status'] == 'completed' ? 'Transcribed' : 'Processing';
          buffer.writeln(
              '• **${r["title"]}** · ${r["durationFormatted"]} ($status)');
          final points = (r['keyPoints'] as List?) ?? [];
          if (points.isNotEmpty) {
            buffer.writeln('  - *Key takeaway: ${points.first}*');
          }
        }
        return buffer.toString().trim();

      default:
        return result.message;
    }
  }
}
