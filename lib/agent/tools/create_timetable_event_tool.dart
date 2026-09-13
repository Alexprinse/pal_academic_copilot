import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../models/timetable_entry.dart';
import '../../services/timetable_service.dart';

class CreateTimetableEventTool extends AgentTool {
  final TimetableService _timetableService;

  CreateTimetableEventTool({TimetableService? timetableService})
      : _timetableService = timetableService ?? TimetableService.instance,
        super(
          name: 'create_timetable_event',
          description: 'Create a new class or lecture event in the timetable.',
          isReadOnly: false,
          parameters: const [
            AgentParameter(
              name: 'subject',
              type: AgentParameterType.string,
              description:
                  'The name of the course or subject (e.g. "Artificial Intelligence", "Operating Systems").',
              required: true,
            ),
            AgentParameter(
              name: 'day',
              type: AgentParameterType.string,
              description:
                  'The day for the class (e.g. "tomorrow", "Mon", "Tuesday", or 3-letter weekday).',
              required: true,
            ),
            AgentParameter(
              name: 'startTime',
              type: AgentParameterType.string,
              description:
                  'Class start time (e.g. "10:00 AM", "10:00", "10am").',
              required: true,
            ),
            AgentParameter(
              name: 'endTime',
              type: AgentParameterType.string,
              description: 'Class end time (e.g. "11:00 AM", "11:00", "11am").',
              required: false,
            ),
            AgentParameter(
              name: 'room',
              type: AgentParameterType.string,
              description:
                  'Optional classroom or lecture hall (e.g. "Room 204", "Lab 2").',
              required: false,
              defaultValue: 'Room TBD',
            ),
            AgentParameter(
              name: 'professor',
              type: AgentParameterType.string,
              description: 'Optional professor or instructor name.',
              required: false,
              defaultValue: 'Professor TBD',
            ),
            AgentParameter(
              name: 'type',
              type: AgentParameterType.string,
              description:
                  'Type of session: "Lecture", "Lab", "Tutorial", or "Seminar".',
              required: false,
              defaultValue: 'Lecture',
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
    final rawSubject = (arguments['subject'] as String? ?? '').trim();
    if (rawSubject.isEmpty) {
      return AgentToolResult.validationError(
        tool: name,
        error: 'Course subject name is required.',
      );
    }

    final now = context?.currentDateTime ?? DateTime.now();
    final rawDay = (arguments['day'] as String? ?? '').trim();
    if (rawDay.isEmpty) {
      return AgentToolResult.validationError(
        tool: name,
        error: 'Please specify what day this class is on.',
      );
    }

    final resolvedDay = _resolveDay(rawDay, now);

    final rawStart = (arguments['startTime'] as String? ?? '').trim();
    if (rawStart.isEmpty) {
      return AgentToolResult.validationError(
        tool: name,
        error: 'What time does the class start and end?',
      );
    }

    final normalizedStart = _normalizeTime(rawStart);
    final rawEnd = (arguments['endTime'] as String? ?? '').trim();
    final normalizedEnd = rawEnd.isNotEmpty
        ? _normalizeTime(rawEnd)
        : _computeDefaultEndTime(normalizedStart);

    final room = (arguments['room'] as String? ?? 'Room TBD').trim();
    final professor =
        (arguments['professor'] as String? ?? 'Professor TBD').trim();
    final type = (arguments['type'] as String? ?? 'Lecture').trim();

    // Duplicate verification
    final existingEntries = _timetableService.entries;
    final isDuplicate = existingEntries.any((e) =>
        e.dayOfWeek.toLowerCase() == resolvedDay.toLowerCase() &&
        e.startTime.toLowerCase() == normalizedStart.toLowerCase() &&
        (e.subject.toLowerCase() == rawSubject.toLowerCase() ||
            _isFuzzyMatch(rawSubject.toLowerCase(), e.subject.toLowerCase())));

    if (isDuplicate) {
      return AgentToolResult.failure(
        tool: name,
        message:
            'A class for "$rawSubject" is already scheduled on $resolvedDay at $normalizedStart.',
        error: 'DUPLICATE_EVENT',
        data: {'isDuplicate': true},
      );
    }

    final newId = 'tt_${DateTime.now().millisecondsSinceEpoch}';
    final entry = TimetableEntry(
      id: newId,
      subject: rawSubject,
      dayOfWeek: resolvedDay,
      startTime: normalizedStart,
      endTime: normalizedEnd,
      room: room,
      professor: professor,
      type: type,
      repeatWeekly: true,
    );

    try {
      await _timetableService.addEntry(entry);
    } catch (e) {
      return AgentToolResult.failure(
        tool: name,
        message: "I couldn't add that class to your timetable: $e",
        error: e.toString(),
      );
    }

    return AgentToolResult.success(
      tool: name,
      message:
          '✓ Added $rawSubject on $resolvedDay, $normalizedStart–$normalizedEnd ($room).',
      data: {
        'id': entry.id,
        'subject': entry.subject,
        'day': entry.dayOfWeek,
        'startTime': entry.startTime,
        'endTime': entry.endTime,
        'room': entry.room,
        'professor': entry.professor,
        'canUndo': true,
        'undoId': entry.id,
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

    // Remove AM/PM for numerical parsing
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
      // Heuristic: academic classes from 1 to 7 are usually PM, 8 to 11 are AM
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
