import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../models/deadline.dart';
import '../../services/deadline_service.dart';

class GetUpcomingTasksTool extends AgentTool {
  final DeadlineService _deadlineService;

  GetUpcomingTasksTool({DeadlineService? deadlineService})
      : _deadlineService = deadlineService ?? DeadlineService.instance,
        super(
          name: 'get_upcoming_tasks',
          description:
              'Use when the user asks about assignments, homework, tasks, submissions, due dates, deadlines, or work that needs to be completed.',
          isReadOnly: true,
          parameters: const [
            AgentParameter(
              name: 'filter',
              type: AgentParameterType.string,
              description:
                  'Filter criteria: "pending" (default), "all", "this_week", "tomorrow", or "overdue".',
              required: false,
              defaultValue: 'pending',
              allowedValues: [
                'pending',
                'all',
                'today',
                'this_week',
                'tomorrow',
                'overdue'
              ],
            ),
            AgentParameter(
              name: 'limit',
              type: AgentParameterType.integer,
              description: 'Maximum number of tasks to return (default 5).',
              required: false,
              defaultValue: 5,
            ),
            AgentParameter(
              name: 'query',
              type: AgentParameterType.string,
              description:
                  'Optional subject or course name to filter tasks by (e.g. "Data Structures", "OS", "TCP").',
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
    final filter = (arguments['filter'] as String? ?? 'pending').toLowerCase();
    final limit = (arguments['limit'] as num? ?? 5).toInt();
    final query =
        (arguments['query'] as String? ?? arguments['subject'] as String?)
            ?.toLowerCase()
            .trim();

    final allDeadlines = _deadlineService.deadlines;

    List<Deadline> filtered = [];
    switch (filter) {
      case 'all':
        filtered = List.from(allDeadlines);
        break;
      case 'overdue':
        filtered = allDeadlines
            .where((d) => !d.isCompleted && d.dueDate.isBefore(now))
            .toList();
        break;
      case 'today':
        final todayStart = DateTime(now.year, now.month, now.day);
        final todayEnd = DateTime(now.year, now.month, now.day + 1);
        filtered = allDeadlines
            .where((d) =>
                !d.isCompleted &&
                d.dueDate.isAfter(todayStart) &&
                d.dueDate.isBefore(todayEnd))
            .toList();
        break;
      case 'tomorrow':
        final tomorrowStart = DateTime(now.year, now.month, now.day + 1);
        final tomorrowEnd = DateTime(now.year, now.month, now.day + 2);
        filtered = allDeadlines
            .where((d) =>
                !d.isCompleted &&
                d.dueDate.isAfter(tomorrowStart) &&
                d.dueDate.isBefore(tomorrowEnd))
            .toList();
        break;
      case 'this_week':
        final endOfWeek = now.add(Duration(days: 7 - now.weekday + 1));
        filtered = allDeadlines
            .where((d) =>
                !d.isCompleted &&
                d.dueDate.isAfter(now) &&
                d.dueDate.isBefore(endOfWeek))
            .toList();
        break;
      case 'pending':
      default:
        filtered = allDeadlines.where((d) => !d.isCompleted).toList();
        break;
    }

    if (query != null && query.isNotEmpty) {
      filtered = filtered.where((d) {
        final title = d.title.toLowerCase();
        final course = d.course.toLowerCase();
        return title.contains(query) || course.contains(query);
      }).toList();
    }

    // Sort chronologically by dueDate
    filtered.sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final selected = filtered.take(limit).toList();
    final taskList = selected.map((d) {
      return {
        'id': d.id,
        'title': d.title,
        'course': d.course,
        'dueDate': d.dueDate.toIso8601String(),
        'priority': d.priority.name,
        'isCompleted': d.isCompleted,
        'timeLeft': d.countdownString,
      };
    }).toList();

    if (taskList.isEmpty) {
      final subjectMsg =
          query != null && query.isNotEmpty ? ' for "$query"' : '';
      return AgentToolResult.success(
        tool: name,
        message:
            'You do not have any upcoming assignment deadlines$subjectMsg.',
        data: {
          'filter': filter,
          if (query != null) 'query': query,
          'taskCount': 0,
          'tasks': [],
        },
      );
    }

    return AgentToolResult.success(
      tool: name,
      message:
          'Found ${taskList.length} upcoming ${taskList.length == 1 ? "task" : "tasks"}.',
      data: {
        'filter': filter,
        'taskCount': taskList.length,
        'tasks': taskList,
      },
    );
  }
}
