import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../models/timetable_entry.dart';
import '../../services/timetable_service.dart';

class DeleteTimetableEventTool extends AgentTool {
  final TimetableService _timetableService;

  DeleteTimetableEventTool({TimetableService? timetableService})
      : _timetableService = timetableService ?? TimetableService.instance,
        super(
          name: 'delete_timetable_event',
          description:
              'Delete a class or lecture event from the timetable. Destructive action that requires confirmation.',
          isReadOnly: false,
          parameters: const [
            AgentParameter(
              name: 'subject',
              type: AgentParameterType.string,
              description:
                  'The subject name of the class to delete (e.g. "AI", "Operating Systems").',
              required: false,
            ),
            AgentParameter(
              name: 'day',
              type: AgentParameterType.string,
              description:
                  'The day of the class (e.g. "Monday", "Mon", "tomorrow").',
              required: false,
            ),
            AgentParameter(
              name: 'id',
              type: AgentParameterType.string,
              description:
                  'The exact entry ID to delete if already identified.',
              required: false,
            ),
            AgentParameter(
              name: 'confirmed',
              type: AgentParameterType.boolean,
              description:
                  'Set to true once the user has explicitly confirmed the deletion.',
              required: false,
              defaultValue: false,
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
    final exactId = arguments['id'] as String?;
    final rawSubject =
        (arguments['subject'] as String? ?? '').trim().toLowerCase();
    final rawDay = (arguments['day'] as String? ?? '').trim();
    final confirmed = arguments['confirmed'] == true ||
        arguments['confirmed'] == 'true' ||
        arguments['confirmed'] == 1;

    final allEntries = _timetableService.entries;
    final now = context?.currentDateTime ?? DateTime.now();

    List<TimetableEntry> candidates = [];

    if (exactId != null && exactId.isNotEmpty) {
      candidates = allEntries.where((e) => e.id == exactId).toList();
    } else {
      if (rawSubject.isEmpty && rawDay.isEmpty) {
        return AgentToolResult.validationError(
          tool: name,
          error: 'Please specify the class subject or day to delete.',
        );
      }

      String? targetDay;
      if (rawDay.isNotEmpty) {
        targetDay = _resolveDay(rawDay, now);
      }

      candidates = allEntries.where((entry) {
        if (rawSubject.isNotEmpty) {
          final entrySub = entry.subject.toLowerCase();
          final matchesSubject = entrySub.contains(rawSubject) ||
              rawSubject.contains(entrySub) ||
              _isFuzzyMatch(rawSubject, entrySub);
          if (!matchesSubject) return false;
        }

        if (targetDay != null) {
          if (entry.dayOfWeek.toLowerCase() != targetDay.toLowerCase()) {
            return false;
          }
        }

        return true;
      }).toList();
    }

    if (candidates.isEmpty) {
      final desc = [
        if (rawSubject.isNotEmpty) 'for "$rawSubject"',
        if (rawDay.isNotEmpty) 'on $rawDay',
      ].join(' ');
      return AgentToolResult.failure(
        tool: name,
        message: 'No matching class found in your timetable $desc to delete.',
        error: 'ENTRY_NOT_FOUND',
      );
    }

    if (candidates.length > 1 && !confirmed) {
      final listStr = candidates
          .map((c) =>
              '• ${c.dayOfWeek} at ${c.startTime} - ${c.endTime} (${c.subject})')
          .join('\n');
      return AgentToolResult.failure(
        tool: name,
        message:
            'Multiple classes matched your request. Please specify which one you want to delete:\n$listStr',
        error: 'AMBIGUOUS_MATCH',
        data: {
          'candidateCount': candidates.length,
          'candidates': candidates.map((c) => c.toJson()).toList(),
        },
      );
    }

    final targetEntry = candidates.first;

    if (!confirmed) {
      return AgentToolResult.confirmationRequired(
        tool: name,
        message:
            'Are you sure you want to remove ${targetEntry.dayOfWeek}\'s ${targetEntry.subject} class (${targetEntry.startTime} - ${targetEntry.endTime}) from your timetable?',
        data: {
          'action': 'delete_timetable_event',
          'id': targetEntry.id,
          'subject': targetEntry.subject,
          'day': targetEntry.dayOfWeek,
          'startTime': targetEntry.startTime,
          'endTime': targetEntry.endTime,
          'requiresConfirmation': true,
        },
      );
    }

    // User confirmed! Execute deletion
    _timetableService.deleteEntry(targetEntry.id);

    return AgentToolResult.success(
      tool: name,
      message:
          'Removed ${targetEntry.dayOfWeek}\'s ${targetEntry.subject} class (${targetEntry.startTime} - ${targetEntry.endTime}) from your timetable.',
      data: {
        'action': 'delete',
        'deletedEntry': targetEntry.toJson(),
        'undoable': true,
      },
    );
  }

  String _resolveDay(String input, DateTime reference) {
    final lower = input.toLowerCase().trim();
    if (lower == 'today') {
      return _weekdayMap[reference.weekday] ?? 'Mon';
    }
    if (lower == 'tomorrow') {
      final tomorrow = reference.add(const Duration(days: 1));
      return _weekdayMap[tomorrow.weekday] ?? 'Mon';
    }
    if (lower == 'yesterday') {
      final yest = reference.subtract(const Duration(days: 1));
      return _weekdayMap[yest.weekday] ?? 'Mon';
    }
    for (final entry in _weekdayMap.entries) {
      if (lower.startsWith(entry.value.toLowerCase())) {
        return entry.value;
      }
    }
    final fullDays = {
      'monday': 'Mon',
      'tuesday': 'Tue',
      'wednesday': 'Wed',
      'thursday': 'Thu',
      'friday': 'Fri',
      'saturday': 'Sat',
      'sunday': 'Sun',
    };
    if (fullDays.containsKey(lower)) {
      return fullDays[lower]!;
    }
    return input;
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
