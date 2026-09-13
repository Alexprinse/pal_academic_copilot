import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../services/campus_vault_service.dart';

class GetMessMenuTool extends AgentTool {
  final CampusVaultService _campusService;

  GetMessMenuTool({CampusVaultService? campusService})
      : _campusService = campusService ?? CampusVaultService.instance,
        super(
          name: 'get_mess_menu',
          description:
              "Retrieve the student's campus dining/mess menu for a specific day or meal (e.g. lunch today, dinner tomorrow).",
          isReadOnly: true,
          parameters: const [
            AgentParameter(
              name: 'day',
              type: AgentParameterType.string,
              description:
                  'The day to query: "today", "tomorrow", or day of week ("Monday", "Tuesday", etc.). Defaults to today.',
              required: false,
              defaultValue: 'today',
            ),
            AgentParameter(
              name: 'meal',
              type: AgentParameterType.string,
              description:
                  'Specific meal: "breakfast", "lunch", "snacks", or "dinner". If omitted, returns all meals for the day.',
              required: false,
              allowedValues: ['breakfast', 'lunch', 'snacks', 'dinner', 'all'],
              defaultValue: 'all',
            ),
          ],
        );

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  }) async {
    final now = context?.currentDateTime ?? DateTime.now();
    final dayArg =
        (arguments['day'] as String? ?? 'today').trim().toLowerCase();
    final mealArg =
        (arguments['meal'] as String? ?? 'all').trim().toLowerCase();

    DateTime targetDate = now;
    String targetDayName;

    if (dayArg == 'tomorrow') {
      targetDate = now.add(const Duration(days: 1));
      targetDayName = _weekdays[targetDate.weekday - 1];
    } else if (dayArg == 'today') {
      targetDayName = _weekdays[now.weekday - 1];
    } else {
      // Find matching weekday name
      final match = _weekdays.firstWhere(
        (w) => w.toLowerCase().startsWith(dayArg.substring(0, 3)),
        orElse: () => _weekdays[now.weekday - 1],
      );
      targetDayName = match;
    }

    final dayMenu = _campusService.getMenuForDayName(targetDayName);
    if (dayMenu == null) {
      return AgentToolResult.failure(
        tool: name,
        message: 'No dining menu found for $targetDayName.',
      );
    }

    if (mealArg != 'all' && mealArg.isNotEmpty) {
      final meal = dayMenu.getMeal(mealArg);
      final itemsStr =
          meal.items.isNotEmpty ? meal.items.join(', ') : 'No items listed';
      return AgentToolResult.success(
        tool: name,
        message:
            '$targetDayName ${meal.mealName} (${meal.timings}): $itemsStr.',
        data: {
          'day': targetDayName,
          'meal': meal.mealName,
          'timings': meal.timings,
          'items': meal.items,
          'messName': _campusService.messMenu.messName,
        },
      );
    }

    // All meals
    final mealsData = {
      'breakfast': {
        'timings': dayMenu.breakfast.timings,
        'items': dayMenu.breakfast.items,
      },
      'lunch': {
        'timings': dayMenu.lunch.timings,
        'items': dayMenu.lunch.items,
      },
      'snacks': {
        'timings': dayMenu.snacks.timings,
        'items': dayMenu.snacks.items,
      },
      'dinner': {
        'timings': dayMenu.dinner.timings,
        'items': dayMenu.dinner.items,
      },
    };

    final summary = '$targetDayName Menu: '
        'Breakfast: ${dayMenu.breakfast.items.join(", ")}; '
        'Lunch: ${dayMenu.lunch.items.join(", ")}; '
        'Snacks: ${dayMenu.snacks.items.join(", ")}; '
        'Dinner: ${dayMenu.dinner.items.join(", ")}.';

    return AgentToolResult.success(
      tool: name,
      message: summary,
      data: {
        'day': targetDayName,
        'messName': _campusService.messMenu.messName,
        'meals': mealsData,
      },
    );
  }
}
