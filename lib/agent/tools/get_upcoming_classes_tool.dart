import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../models/timetable_entry.dart';
import '../../services/timetable_service.dart';

class GetUpcomingClassesTool extends AgentTool {
  final TimetableService _timetableService;

  GetUpcomingClassesTool({TimetableService? timetableService})
      : _timetableService = timetableService ?? TimetableService.instance,
        super(
          name: 'get_upcoming_classes',
          description:
              'Use ONLY when the user asks about classes, lectures, timetable entries, class times, classrooms, or their academic schedule.',
          isReadOnly: true,
          parameters: const [
            AgentParameter(
              name: 'target',
              type: AgentParameterType.string,
              description:
                  'Target scope: "next" (next upcoming class from now), "tomorrow", "today", or a specific day (e.g. "Monday", "Tue"). Defaults to "next".',
              required: false,
              defaultValue: 'next',
            ),
            AgentParameter(
              name: 'limit',
              type: AgentParameterType.integer,
              description: 'Maximum number of classes to retrieve (default 3).',
              required: false,
              defaultValue: 3,
            ),
            AgentParameter(
              name: 'subject',
              type: AgentParameterType.string,
              description:
                  'Optional subject or course name to filter classes by (e.g. "Data Structures", "OS").',
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
    final now = context?.currentDateTime ?? DateTime.now();
    final target =
        (arguments['target'] as String? ?? 'next').toLowerCase().trim();
    final limit = (arguments['limit'] as num? ?? 3).toInt();
    final subject =
        (arguments['subject'] as String? ?? arguments['query'] as String?)
            ?.toLowerCase()
            .trim();

    var allEntries = _timetableService.entries;
    if (subject != null && subject.isNotEmpty) {
      allEntries = allEntries
          .where((e) => e.subject.toLowerCase().contains(subject))
          .toList();
    }

    if (allEntries.isEmpty) {
      final subjectMsg =
          subject != null && subject.isNotEmpty ? ' for "$subject"' : '';
      return AgentToolResult.success(
        tool: name,
        message: 'No classes found in the timetable$subjectMsg.',
        data: {
          'classes': [],
          'scope': target,
          if (subject != null) 'subject': subject
        },
      );
    }

    final todayAbbr = _weekdayMap[now.weekday] ?? 'Mon';
    final currentHourDouble = now.hour + (now.minute / 60.0);

    List<TimetableEntry> matching = [];
    String resolvedScope = target;

    if (target == 'tomorrow') {
      final tomorrowWeekday = now.weekday % 7 + 1;
      final tomorrowAbbr = _weekdayMap[tomorrowWeekday] ?? 'Mon';
      resolvedScope = 'tomorrow ($tomorrowAbbr)';
      matching = allEntries
          .where((e) => e.dayOfWeek.toLowerCase() == tomorrowAbbr.toLowerCase())
          .toList()
        ..sort((a, b) => a.startHourDouble.compareTo(b.startHourDouble));
    } else if (target == 'today') {
      resolvedScope = 'today ($todayAbbr)';
      matching = allEntries
          .where((e) => e.dayOfWeek.toLowerCase() == todayAbbr.toLowerCase())
          .toList()
        ..sort((a, b) => a.startHourDouble.compareTo(b.startHourDouble));
    } else if (_isWeekday(target)) {
      final abbr = _normalizeWeekday(target);
      resolvedScope = abbr;
      matching = allEntries
          .where((e) => e.dayOfWeek.toLowerCase() == abbr.toLowerCase())
          .toList()
        ..sort((a, b) => a.startHourDouble.compareTo(b.startHourDouble));
    } else {
      // Default: 'next' -> Look for upcoming classes today after current hour
      resolvedScope = 'next upcoming';
      final remainingToday = allEntries
          .where((e) =>
              e.dayOfWeek.toLowerCase() == todayAbbr.toLowerCase() &&
              e.startHourDouble >= currentHourDouble)
          .toList()
        ..sort((a, b) => a.startHourDouble.compareTo(b.startHourDouble));

      if (remainingToday.isNotEmpty) {
        matching = remainingToday;
      } else {
        // Find next day with scheduled classes across the upcoming 7 days
        for (var i = 1; i <= 7; i++) {
          final nextDayIndex = (now.weekday - 1 + i) % 7 + 1;
          final nextDayAbbr = _weekdayMap[nextDayIndex] ?? 'Mon';
          final nextDayClasses = allEntries
              .where(
                  (e) => e.dayOfWeek.toLowerCase() == nextDayAbbr.toLowerCase())
              .toList()
            ..sort((a, b) => a.startHourDouble.compareTo(b.startHourDouble));

          if (nextDayClasses.isNotEmpty) {
            matching = nextDayClasses;
            resolvedScope = 'upcoming on $nextDayAbbr';
            break;
          }
        }
      }
    }

    final selected = matching.take(limit).toList();
    final classList = selected.map((e) {
      return {
        'id': e.id,
        'subject': e.subject,
        'day': e.dayOfWeek,
        'start': e.startTime,
        'end': e.endTime,
        'room': e.room ?? 'Not specified',
        'professor': e.professor ?? 'Not specified',
        'type': e.type,
      };
    }).toList();

    if (classList.isEmpty) {
      return AgentToolResult.success(
        tool: name,
        message: 'No upcoming classes found for $resolvedScope.',
        data: {'classes': [], 'scope': resolvedScope},
      );
    }

    final first = classList.first;
    final summaryMessage =
        'Next class is ${first["subject"]} at ${first["start"]} (${first["day"]}, ${first["room"]}).';

    return AgentToolResult.success(
      tool: name,
      message: summaryMessage,
      data: {
        'scope': resolvedScope,
        'count': classList.length,
        'classes': classList,
      },
    );
  }

  bool _isWeekday(String input) {
    final lower = input.toLowerCase();
    return lower.startsWith('mon') ||
        lower.startsWith('tue') ||
        lower.startsWith('wed') ||
        lower.startsWith('thu') ||
        lower.startsWith('fri') ||
        lower.startsWith('sat') ||
        lower.startsWith('sun');
  }

  String _normalizeWeekday(String input) {
    final lower = input.toLowerCase();
    if (lower.startsWith('mon')) return 'Mon';
    if (lower.startsWith('tue')) return 'Tue';
    if (lower.startsWith('wed')) return 'Wed';
    if (lower.startsWith('thu')) return 'Thu';
    if (lower.startsWith('fri')) return 'Fri';
    if (lower.startsWith('sat')) return 'Sat';
    if (lower.startsWith('sun')) return 'Sun';
    return 'Mon';
  }
}
