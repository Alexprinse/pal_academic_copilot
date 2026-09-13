import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../services/campus_vault_service.dart';

class GetAcademicCalendarTool extends AgentTool {
  final CampusVaultService _campusService;

  GetAcademicCalendarTool({CampusVaultService? campusService})
      : _campusService = campusService ?? CampusVaultService.instance,
        super(
          name: 'get_academic_calendar',
          description:
              "Retrieve upcoming academic milestones, exam schedules, registration deadlines, or semester timeline from the campus calendar.",
          isReadOnly: true,
          parameters: const [
            AgentParameter(
              name: 'eventType',
              type: AgentParameterType.string,
              description:
                  'Filter by event type: "exam", "registration", "semester", "break", or "all". Defaults to "all".',
              required: false,
              allowedValues: [
                'exam',
                'registration',
                'semester',
                'break',
                'all'
              ],
              defaultValue: 'all',
            ),
            AgentParameter(
              name: 'query',
              type: AgentParameterType.string,
              description:
                  'Specific search term (e.g. "mid-term", "end-term", "fee"). Optional.',
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
    final eventType =
        (arguments['eventType'] as String? ?? 'all').toLowerCase();
    final query = (arguments['query'] as String?)?.trim().toLowerCase();

    var items = _campusService.getUpcomingCalendarItems(from: now);

    if (eventType != 'all' && eventType.isNotEmpty) {
      items = items.where((item) {
        final name = item.eventType.name.toLowerCase();
        if (eventType == 'exam') return name.contains('exam');
        if (eventType == 'break') return name.contains('break');
        if (eventType == 'registration') return name.contains('registration');
        if (eventType == 'semester') return name.contains('semester');
        return true;
      }).toList();
    }

    if (query != null && query.isNotEmpty) {
      items = items.where((item) {
        return item.title.toLowerCase().contains(query) ||
            (item.description?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    if (items.isEmpty) {
      return AgentToolResult.success(
        tool: name,
        message: 'No upcoming academic milestones matching your criteria.',
        data: {'count': 0, 'items': []},
      );
    }

    final formattedList = items.take(5).map((item) {
      final startStr =
          '${item.startDate.year}-${item.startDate.month.toString().padLeft(2, "0")}-${item.startDate.day.toString().padLeft(2, "0")}';
      final endStr = item.endDate != null
          ? ' to ${item.endDate!.year}-${item.endDate!.month.toString().padLeft(2, "0")}-${item.endDate!.day.toString().padLeft(2, "0")}'
          : '';
      final days = item.daysUntil(from: now);
      final timing = days == 0
          ? 'starts today'
          : (days > 0 ? 'in $days days' : 'in progress');

      return '• ${item.title} ($startStr$endStr, $timing) [${item.eventType.displayName}]';
    }).join('\n');

    return AgentToolResult.success(
      tool: name,
      message: 'Upcoming Academic Calendar Milestones:\n$formattedList',
      data: {
        'count': items.length,
        'items': items.map((i) => i.toMap()).toList(),
      },
    );
  }
}
