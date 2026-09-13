import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../services/campus_vault_service.dart';

class GetHolidaysTool extends AgentTool {
  final CampusVaultService _campusService;

  GetHolidaysTool({CampusVaultService? campusService})
      : _campusService = campusService ?? CampusVaultService.instance,
        super(
          name: 'get_holidays',
          description:
              "Retrieve upcoming campus holidays, check if today/tomorrow is a holiday, or lookup the next official break.",
          isReadOnly: true,
          parameters: const [
            AgentParameter(
              name: 'queryType',
              type: AgentParameterType.string,
              description:
                  'Query type: "next" (next holiday), "check_tomorrow", "check_today", or "upcoming" (all upcoming). Defaults to "next".',
              required: false,
              allowedValues: [
                'next',
                'check_tomorrow',
                'check_today',
                'upcoming'
              ],
              defaultValue: 'next',
            ),
            AgentParameter(
              name: 'month',
              type: AgentParameterType.number,
              description: 'Optional month number (1-12) to filter holidays.',
              required: false,
            ),
          ],
        );

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  }) async {
    final now = context?.currentDateTime ?? DateTime.now();
    final queryType =
        (arguments['queryType'] as String? ?? 'next').toLowerCase();
    final monthFilter = arguments['month'] as int?;

    final allHolidays = _campusService.holidays;

    if (queryType == 'check_today') {
      final todayHolidays = allHolidays
          .where((h) =>
              h.date.year == now.year &&
              h.date.month == now.month &&
              h.date.day == now.day)
          .toList();

      if (todayHolidays.isNotEmpty) {
        final h = todayHolidays.first;
        return AgentToolResult.success(
          tool: name,
          message:
              'Yes! Today is a holiday: ${h.name} (${h.type.displayName}).',
          data: {'isHoliday': true, 'holiday': h.toMap()},
        );
      } else {
        return AgentToolResult.success(
          tool: name,
          message: 'No, today is not a campus holiday.',
          data: {'isHoliday': false},
        );
      }
    }

    if (queryType == 'check_tomorrow') {
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowHolidays = allHolidays
          .where((h) =>
              h.date.year == tomorrow.year &&
              h.date.month == tomorrow.month &&
              h.date.day == tomorrow.day)
          .toList();

      if (tomorrowHolidays.isNotEmpty) {
        final h = tomorrowHolidays.first;
        return AgentToolResult.success(
          tool: name,
          message:
              'Yes! Tomorrow is a holiday: ${h.name} (${h.type.displayName}).',
          data: {'isHoliday': true, 'holiday': h.toMap()},
        );
      } else {
        return AgentToolResult.success(
          tool: name,
          message: 'No, tomorrow is not a campus holiday.',
          data: {'isHoliday': false},
        );
      }
    }

    if (queryType == 'next') {
      final next = _campusService.getNextHoliday(from: now);
      if (next == null) {
        return AgentToolResult.success(
          tool: name,
          message: 'No upcoming holidays found in the campus calendar.',
          data: {'nextHoliday': null},
        );
      }

      final daysUntil = next.daysUntil(from: now);
      String whenStr = daysUntil == 0
          ? 'today'
          : (daysUntil == 1 ? 'tomorrow' : 'in $daysUntil days');

      final dateStr =
          '${next.date.year}-${next.date.month.toString().padLeft(2, "0")}-${next.date.day.toString().padLeft(2, "0")}';

      return AgentToolResult.success(
        tool: name,
        message:
            'The next holiday is ${next.name} ($dateStr, $whenStr). Type: ${next.type.displayName}.',
        data: {
          'nextHoliday': next.toMap(),
          'daysUntil': daysUntil,
          'formattedDate': dateStr,
        },
      );
    }

    // upcoming / month filter
    var list = _campusService.getUpcomingHolidays(from: now);
    if (monthFilter != null) {
      list = list.where((h) => h.date.month == monthFilter).toList();
    }

    return AgentToolResult.success(
      tool: name,
      message: 'Found ${list.length} upcoming holiday(s).',
      data: {
        'count': list.length,
        'holidays': list.map((h) => h.toMap()).toList(),
      },
    );
  }
}
