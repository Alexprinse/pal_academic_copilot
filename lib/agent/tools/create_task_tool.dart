import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../models/deadline.dart';
import '../../services/deadline_service.dart';

class CreateTaskTool extends AgentTool {
  final DeadlineService _deadlineService;

  CreateTaskTool({DeadlineService? deadlineService})
      : _deadlineService = deadlineService ?? DeadlineService.instance,
        super(
          name: 'create_task',
          description:
              'Create a new academic task, assignment reminder, or study todo.',
          isReadOnly: false,
          parameters: const [
            AgentParameter(
              name: 'title',
              type: AgentParameterType.string,
              description:
                  'Title of the task or assignment (e.g. "Submit OS assignment", "Study for Math Quiz").',
              required: true,
            ),
            AgentParameter(
              name: 'dueDate',
              type: AgentParameterType.string,
              description:
                  'When the task is due (e.g. "September 15", "tomorrow", "in 3 days", "2026-09-15").',
              required: true,
            ),
            AgentParameter(
              name: 'course',
              type: AgentParameterType.string,
              description:
                  'Associated course or subject (e.g. "Operating Systems", "Mathematics"). Optional.',
              required: false,
            ),
            AgentParameter(
              name: 'priority',
              type: AgentParameterType.string,
              description:
                  'Priority level: "high", "medium", or "low". Defaults to "medium".',
              required: false,
              defaultValue: 'medium',
            ),
          ],
        );

  static const Map<String, int> _months = {
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sep': 9,
    'sept': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  }) async {
    final title = (arguments['title'] as String? ?? '').trim();
    if (title.isEmpty) {
      return AgentToolResult.validationError(
        tool: name,
        error: 'Task title is required.',
      );
    }

    final rawDueDate = (arguments['dueDate'] as String? ?? '').trim();
    if (rawDueDate.isEmpty) {
      return AgentToolResult.validationError(
        tool: name,
        error: 'Due date is required to set a task reminder.',
      );
    }

    final now = context?.currentDateTime ?? DateTime.now();
    final parsedDate = _parseDueDate(rawDueDate, now);

    if (parsedDate == null) {
      return AgentToolResult.failure(
        tool: name,
        message:
            'Could not understand due date "$rawDueDate". Please provide a date like "September 15" or "tomorrow".',
        error: 'INVALID_DATE_FORMAT',
      );
    }

    // Determine course
    String course = (arguments['course'] as String? ?? '').trim();
    if (course.isEmpty) {
      course = _inferCourse(title);
    }

    // Determine priority
    final rawPriority =
        (arguments['priority'] as String? ?? 'medium').toLowerCase();
    TaskPriority priority = TaskPriority.medium;
    if (rawPriority.contains('high') ||
        rawPriority.contains('urgent') ||
        rawPriority.contains('crit')) {
      priority = TaskPriority.high;
    } else if (rawPriority.contains('low')) {
      priority = TaskPriority.low;
    }

    final newId = 'dl_${DateTime.now().millisecondsSinceEpoch}';
    final deadline = Deadline(
      id: newId,
      title: title,
      course: course,
      dueDate: parsedDate,
      priority: priority,
    );

    _deadlineService.addDeadline(deadline);

    final formattedDate = _formatDate(parsedDate);

    return AgentToolResult.success(
      tool: name,
      message:
          'Created task "$title" for $course due on $formattedDate with ${priority.name} priority.',
      data: {
        'id': deadline.id,
        'title': deadline.title,
        'course': deadline.course,
        'dueDate': deadline.dueDate.toIso8601String(),
        'priority': deadline.priority.name,
        'formattedDate': formattedDate,
        'action': 'create_task',
        'undoable': true,
      },
    );
  }

  DateTime? _parseDueDate(String raw, DateTime reference) {
    final lower = raw.toLowerCase().trim();

    if (lower == 'today') {
      return DateTime(reference.year, reference.month, reference.day, 23, 59);
    }
    if (lower == 'tomorrow') {
      final tom = reference.add(const Duration(days: 1));
      return DateTime(tom.year, tom.month, tom.day, 23, 59);
    }

    // "in X days"
    final inDaysMatch = RegExp(r'in\s+(\d+)\s+days?').firstMatch(lower);
    if (inDaysMatch != null) {
      final days = int.parse(inDaysMatch.group(1)!);
      final target = reference.add(Duration(days: days));
      return DateTime(target.year, target.month, target.day, 23, 59);
    }

    // Try ISO format
    final tryIso = DateTime.tryParse(raw);
    if (tryIso != null) return tryIso;

    // "Month Day" e.g. "September 15" or "Sep 15" or "15 September"
    for (final monthEntry in _months.entries) {
      final monthName = monthEntry.key;
      final monthNum = monthEntry.value;

      // Pattern 1: "September 15"
      final p1 = RegExp('$monthName\\s+(\\d{1,2})(?:st|nd|rd|th)?',
              caseSensitive: false)
          .firstMatch(lower);
      if (p1 != null) {
        final day = int.parse(p1.group(1)!);
        int year = reference.year;
        var date = DateTime(year, monthNum, day, 23, 59);
        if (date.isBefore(reference.subtract(const Duration(days: 1)))) {
          date = DateTime(year + 1, monthNum, day, 23, 59);
        }
        return date;
      }

      // Pattern 2: "15 September"
      final p2 = RegExp('(\\d{1,2})(?:st|nd|rd|th)?\\s+$monthName',
              caseSensitive: false)
          .firstMatch(lower);
      if (p2 != null) {
        final day = int.parse(p2.group(1)!);
        int year = reference.year;
        var date = DateTime(year, monthNum, day, 23, 59);
        if (date.isBefore(reference.subtract(const Duration(days: 1)))) {
          date = DateTime(year + 1, monthNum, day, 23, 59);
        }
        return date;
      }
    }

    return null;
  }

  String _inferCourse(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('os') || lower.contains('operating system')) {
      return 'Operating Systems';
    }
    if (lower.contains('ai') || lower.contains('artificial intelligence')) {
      return 'Artificial Intelligence';
    }
    if (lower.contains('math') ||
        lower.contains('calculus') ||
        lower.contains('discrete')) {
      return 'Mathematics';
    }
    if (lower.contains('physic') || lower.contains('optics')) {
      return 'Engineering Physics';
    }
    if (lower.contains('network')) {
      return 'Computer Networks';
    }
    if (lower.contains('database') || lower.contains('sql')) {
      return 'Database Systems';
    }
    if (lower.contains('english') ||
        lower.contains('writing') ||
        lower.contains('presentation')) {
      return 'English';
    }
    return 'General';
  }

  String _formatDate(DateTime dt) {
    const monthNames = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${monthNames[dt.month]} ${dt.day}, ${dt.year}';
  }
}
