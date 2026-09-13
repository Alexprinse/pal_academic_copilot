import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../models/timetable_entry.dart';
import '../../services/timetable_service.dart';

class UpdateTimetableEventTool extends AgentTool {
  final TimetableService _timetableService;

  UpdateTimetableEventTool({TimetableService? timetableService})
      : _timetableService = timetableService ?? TimetableService.instance,
        super(
          name: 'update_timetable_event',
          description:
              'Move or update an existing timetable class (e.g. change start time, end time, day, or room).',
          isReadOnly: false,
          parameters: const [
            AgentParameter(
              name: 'subject',
              type: AgentParameterType.string,
              description:
                  'The subject name of the class to update (e.g. "AI", "Operating Systems").',
              required: true,
            ),
            AgentParameter(
              name: 'newStartTime',
              type: AgentParameterType.string,
              description:
                  'The new start time for the class (e.g. "11:00 AM", "11am", "14:00").',
              required: true,
            ),
            AgentParameter(
              name: 'newEndTime',
              type: AgentParameterType.string,
              description:
                  'Optional new end time. Defaults to 1 hour after new start time.',
              required: false,
            ),
            AgentParameter(
              name: 'currentDay',
              type: AgentParameterType.string,
              description:
                  'Optional current day of the class to disambiguate (e.g. "tomorrow", "Mon", "Wednesday").',
              required: false,
            ),
            AgentParameter(
              name: 'newDay',
              type: AgentParameterType.string,
              description: 'Optional new day if moving class to another day.',
              required: false,
            ),
            AgentParameter(
              name: 'newRoom',
              type: AgentParameterType.string,
              description: 'Optional updated room or lecture hall.',
              required: false,
            ),
            AgentParameter(
              name: 'id',
              type: AgentParameterType.string,
              description: 'Optional exact entry ID if already known.',
              required: false,
            ),
          ],
        );

  static const Map<int, String> _weekdayMap = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  }) async {
    final rawSubject =
        (arguments['subject'] as String? ?? '').trim().toLowerCase();
    if (rawSubject.isEmpty) {
      return AgentToolResult.validationError(
        tool: name,
        error: 'Subject name is required to identify which class to update.',
      );
    }

    final newStartTimeRaw = (arguments['newStartTime'] as String? ?? '').trim();
    if (newStartTimeRaw.isEmpty) {
      return AgentToolResult.validationError(
        tool: name,
        error: 'Please specify the new start time for the class.',
      );
    }

    final now = context?.currentDateTime ?? DateTime.now();
    final allEntries = _timetableService.entries;
    final exactId = arguments['id'] as String?;

    List<TimetableEntry> candidates = [];

    if (exactId != null && exactId.isNotEmpty) {
      candidates = allEntries.where((e) => e.id == exactId).toList();
    } else {
      final rawCurrentDay = (arguments['currentDay'] as String? ?? '').trim();
      final currentDayResolved =
          rawCurrentDay.isNotEmpty ? _resolveDay(rawCurrentDay, now) : null;

      candidates = allEntries.where((e) {
        final entrySub = e.subject.toLowerCase();
        final matchSubject = entrySub.contains(rawSubject) ||
            rawSubject.contains(entrySub) ||
            _isFuzzyMatch(rawSubject, entrySub);
        if (!matchSubject) return false;
        if (currentDayResolved != null) {
          return e.dayOfWeek.toLowerCase() == currentDayResolved.toLowerCase();
        }
        return true;
      }).toList();
    }

    // 1. Zero matches
    if (candidates.isEmpty) {
      final dayHint = arguments['currentDay'] != null
          ? ' on ${arguments["currentDay"]}'
          : '';
      return AgentToolResult.failure(
        tool: name,
        message:
            'No class found matching "$rawSubject"$dayHint in your timetable.',
        error: 'ENTRY_NOT_FOUND',
        data: {'matchCount': 0},
      );
    }

    // 2. Multiple matches: ASK the user, do not guess
    if (candidates.length > 1) {
      final candidateDescriptions = candidates
          .map((c) =>
              '• ${c.subject} on ${c.dayOfWeek} at ${c.startTime} (${c.room ?? "Room TBD"}) [ID: ${c.id}]')
          .join('\n');

      return AgentToolResult.failure(
        tool: name,
        message:
            'Multiple classes found matching "$rawSubject":\n$candidateDescriptions\n\nWhich class would you like to move?',
        error: 'AMBIGUOUS_MATCH',
        data: {
          'requiresClarification': true,
          'matchCount': candidates.length,
          'candidates': candidates
              .map((c) => {
                    'id': c.id,
                    'subject': c.subject,
                    'day': c.dayOfWeek,
                    'startTime': c.startTime,
                  })
              .toList(),
        },
      );
    }

    // 3. Exactly 1 match: proceed to update
    final target = candidates.first;
    final normalizedStart = _normalizeTime(newStartTimeRaw);
    final rawEnd = (arguments['newEndTime'] as String? ?? '').trim();
    final normalizedEnd = rawEnd.isNotEmpty
        ? _normalizeTime(rawEnd)
        : _computeDefaultEndTime(normalizedStart);

    final rawNewDay = (arguments['newDay'] as String? ?? '').trim();
    final resolvedDay =
        rawNewDay.isNotEmpty ? _resolveDay(rawNewDay, now) : target.dayOfWeek;

    final newRoom = (arguments['newRoom'] as String? ?? '').trim();

    final updatedEntry = TimetableEntry(
      id: target.id,
      subject: target.subject,
      dayOfWeek: resolvedDay,
      startTime: normalizedStart,
      endTime: normalizedEnd,
      room: newRoom.isNotEmpty ? newRoom : target.room,
      professor: target.professor,
      notes: target.notes,
      type: target.type,
      repeatWeekly: target.repeatWeekly,
    );

    try {
      await _timetableService.updateEntry(updatedEntry);
    } catch (e) {
      return AgentToolResult.failure(
        tool: name,
        message: "I couldn't update that class in your timetable: $e",
        error: e.toString(),
      );
    }

    return AgentToolResult.success(
      tool: name,
      message:
          '✓ Moved ${target.subject} from ${target.startTime} to $normalizedStart on $resolvedDay.',
      data: {
        'id': updatedEntry.id,
        'subject': updatedEntry.subject,
        'previousStart': target.startTime,
        'previousEnd': target.endTime,
        'newStart': updatedEntry.startTime,
        'newEnd': updatedEntry.endTime,
        'day': updatedEntry.dayOfWeek,
        'room': updatedEntry.room,
        'canUndo': true,
        'undoEntry': target.toJson(),
      },
    );
  }

  String _resolveDay(String dayInput, DateTime now) {
    final lower = dayInput.toLowerCase().trim();
    if (lower == 'tomorrow') {
      final tomorrowWeekday = now.weekday % 7 + 1;
      return _weekdayMap[tomorrowWeekday] ?? 'Mon';
    }
    if (lower == 'today') {
      return _weekdayMap[now.weekday] ?? 'Mon';
    }
    if (lower.startsWith('mon')) return 'Mon';
    if (lower.startsWith('tue')) return 'Tue';
    if (lower.startsWith('wed')) return 'Wed';
    if (lower.startsWith('thu')) return 'Thu';
    if (lower.startsWith('fri')) return 'Fri';
    if (lower.startsWith('sat')) return 'Sat';
    if (lower.startsWith('sun')) return 'Sun';

    return 'Mon';
  }

  String _normalizeTime(String raw) {
    var s = raw.trim().toUpperCase();
    final hasAm = s.contains('AM');
    final hasPm = s.contains('PM');
    s = s.replaceAll('AM', '').replaceAll('PM', '').trim();

    int hour = 9;
    int minute = 0;

    if (s.contains(':')) {
      final parts = s.split(':');
      hour = int.tryParse(parts[0]) ?? 9;
      minute = int.tryParse(parts[1]) ?? 0;
    } else {
      hour = int.tryParse(s) ?? 9;
    }

    String period = 'AM';
    if (hasPm) {
      period = 'PM';
    } else if (hasAm) {
      period = 'AM';
    } else {
      if (hour >= 1 && hour <= 7) {
        period = 'PM';
      } else {
        period = 'AM';
      }
    }

    if (hour > 12) {
      hour -= 12;
      period = 'PM';
    } else if (hour == 0) {
      hour = 12;
    }

    final hStr = hour.toString().padLeft(2, '0');
    final mStr = minute.toString().padLeft(2, '0');
    return '$hStr:$mStr $period';
  }

  String _computeDefaultEndTime(String startTime) {
    final parts = startTime.split(' ');
    final timeParts = parts[0].split(':');
    var hour = int.tryParse(timeParts[0]) ?? 9;
    final minute = timeParts[1];
    var period = parts.length > 1 ? parts[1] : 'AM';

    hour += 1;
    if (hour == 12 && period == 'AM') {
      period = 'PM';
    } else if (hour > 12) {
      hour = 1;
    }

    final hStr = hour.toString().padLeft(2, '0');
    return '$hStr:$minute $period';
  }

  bool _isFuzzyMatch(String a, String b) {
    if (a == b) return true;
    if (a == 'ai' &&
        (b.contains('artificial intelligence') || b.contains('ai'))) {
      return true;
    }
    if (b == 'ai' &&
        (a.contains('artificial intelligence') || a.contains('ai'))) {
      return true;
    }
    if (a == 'os' && (b.contains('operating system') || b.contains('os'))) {
      return true;
    }
    if (b == 'os' && (a.contains('operating system') || a.contains('os'))) {
      return true;
    }
    return false;
  }
}
