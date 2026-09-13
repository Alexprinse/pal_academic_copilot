import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../services/timetable_service.dart';

class GetTodayScheduleTool extends AgentTool {
  final TimetableService _timetableService;

  GetTodayScheduleTool({TimetableService? timetableService})
      : _timetableService = timetableService ?? TimetableService.instance,
        super(
          name: 'get_today_schedule',
          description:
              "Retrieve the student's scheduled classes and lectures for today.",
          isReadOnly: true,
          parameters: const [
            AgentParameter(
              name: 'day',
              type: AgentParameterType.string,
              description:
                  'Optional 3-letter weekday abbreviation (Mon, Tue, Wed, Thu, Fri, Sat, Sun). Defaults to today.',
              required: false,
              allowedValues: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
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
    final todayAbbr = _weekdayMap[now.weekday] ?? 'Mon';
    final targetDay = arguments['day'] as String? ?? todayAbbr;

    final allEntries = _timetableService.entries;
    final todayClasses = allEntries
        .where((e) => e.dayOfWeek.toLowerCase() == targetDay.toLowerCase())
        .toList();

    // Sort chronologically by start time
    todayClasses.sort((a, b) => a.startHourDouble.compareTo(b.startHourDouble));

    final classList = todayClasses.map((e) {
      return {
        'id': e.id,
        'subject': e.subject,
        'start': e.startTime,
        'end': e.endTime,
        'room': e.room ?? 'Not specified',
        'professor': e.professor ?? 'Not specified',
        'type': e.type,
      };
    }).toList();

    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}';

    if (classList.isEmpty) {
      return AgentToolResult.success(
        tool: name,
        message: 'No classes scheduled for $targetDay.',
        data: {
          'date': dateStr,
          'day': targetDay,
          'classCount': 0,
          'classes': [],
        },
      );
    }

    return AgentToolResult.success(
      tool: name,
      message:
          'Found ${classList.length} ${classList.length == 1 ? "class" : "classes"} scheduled for $targetDay.',
      data: {
        'date': dateStr,
        'day': targetDay,
        'classCount': classList.length,
        'classes': classList,
      },
    );
  }
}
