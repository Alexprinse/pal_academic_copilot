import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../models/campus_vault.dart';
import '../../services/campus_vault_service.dart';

class GetNoticesTool extends AgentTool {
  final CampusVaultService _campusService;

  GetNoticesTool({CampusVaultService? campusService})
      : _campusService = campusService ?? CampusVaultService.instance,
        super(
          name: 'get_notices',
          description:
              "Retrieve campus notices, circulars, announcements, and administrative deadlines.",
          isReadOnly: true,
          parameters: const [
            AgentParameter(
              name: 'category',
              type: AgentParameterType.string,
              description:
                  'Filter by category: "exams", "placement", "events", "administration", or "all". Defaults to "all".',
              required: false,
              allowedValues: [
                'exams',
                'placement',
                'events',
                'administration',
                'all'
              ],
              defaultValue: 'all',
            ),
            AgentParameter(
              name: 'query',
              type: AgentParameterType.string,
              description:
                  'Search keyword (e.g. "exam", "placement", "fee", "hall ticket"). Optional.',
              required: false,
            ),
            AgentParameter(
              name: 'limit',
              type: AgentParameterType.number,
              description: 'Maximum notices to retrieve (1-10). Defaults to 3.',
              required: false,
              defaultValue: 3,
            ),
          ],
        );

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  }) async {
    final categoryArg =
        (arguments['category'] as String? ?? 'all').toLowerCase();
    final query = (arguments['query'] as String?)?.trim().toLowerCase();
    final limit = (arguments['limit'] as num?)?.toInt() ?? 3;

    var notices = _campusService.notices;

    if (categoryArg != 'all' && categoryArg.isNotEmpty) {
      final cat = NoticeCategory.fromString(categoryArg);
      notices = notices.where((n) => n.category == cat).toList();
    }

    if (query != null && query.isNotEmpty) {
      notices = notices.where((n) {
        return n.title.toLowerCase().contains(query) ||
            n.extractedText.toLowerCase().contains(query) ||
            (n.summary?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    if (notices.isEmpty) {
      return AgentToolResult.success(
        tool: name,
        message: 'No campus notices matching your criteria were found.',
        data: {'count': 0, 'notices': []},
      );
    }

    final topNotices = notices.take(limit).toList();
    final summaryList = topNotices.map((n) {
      final dateStr =
          '${n.date.year}-${n.date.month.toString().padLeft(2, "0")}-${n.date.day.toString().padLeft(2, "0")}';
      final dlStr = n.deadline != null
          ? ' [Deadline: ${n.deadline!.month}/${n.deadline!.day}]'
          : '';
      final snippet = n.summary ??
          (n.extractedText.length > 100
              ? '${n.extractedText.substring(0, 100)}...'
              : n.extractedText);
      return '• [${n.category.displayName}] ${n.title} ($dateStr)$dlStr\n  Details: $snippet';
    }).join('\n\n');

    return AgentToolResult.success(
      tool: name,
      message: 'Found ${notices.length} campus notice(s):\n\n$summaryList',
      data: {
        'totalCount': notices.length,
        'retrievedCount': topNotices.length,
        'notices': topNotices.map((n) => n.toMap()).toList(),
      },
    );
  }
}
