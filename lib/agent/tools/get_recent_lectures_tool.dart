import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../models/lecture_recording.dart';
import '../../services/lecture_recording_service.dart';

class GetRecentLecturesTool extends AgentTool {
  final LectureRecordingService _recordingService;

  GetRecentLecturesTool({LectureRecordingService? recordingService})
      : _recordingService =
            recordingService ?? LectureRecordingService.instance,
        super(
          name: 'get_recent_lectures',
          description:
              'Retrieve recently recorded lectures and live captures, including transcription status and summaries.',
          isReadOnly: true,
          parameters: const [
            AgentParameter(
              name: 'limit',
              type: AgentParameterType.integer,
              description:
                  'Maximum number of recordings to return (default 5).',
              required: false,
              defaultValue: 5,
            ),
            AgentParameter(
              name: 'filter',
              type: AgentParameterType.string,
              description: 'Filter scope: "all" (default) or "today".',
              required: false,
              defaultValue: 'all',
              allowedValues: ['all', 'today'],
            ),
          ],
        );

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  }) async {
    final now = context?.currentDateTime ?? DateTime.now();
    final limit = (arguments['limit'] as num? ?? 5).toInt();
    final filter = (arguments['filter'] as String? ?? 'all').toLowerCase();

    final allRecordings = _recordingService.recordings;

    List<LectureRecording> filtered = List.from(allRecordings);
    if (filter == 'today') {
      filtered = filtered
          .where((r) =>
              r.date.year == now.year &&
              r.date.month == now.month &&
              r.date.day == now.day)
          .toList();
    }

    filtered.sort((a, b) => b.date.compareTo(a.date));

    final selected = filtered.take(limit).toList();
    final recordingsList = selected.map((r) {
      return {
        'id': r.id,
        'title': r.displayTitle,
        'subject': r.subject,
        'date': r.date.toIso8601String(),
        'durationSeconds': r.durationSeconds,
        'durationFormatted': r.formattedDuration,
        'isLiveCapture': r.isLiveCapture,
        'status': r.transcriptionStatus,
        'hasTranscript': r.transcriptText.trim().isNotEmpty,
        'keyPoints': r.summary?.keyPoints ?? [],
      };
    }).toList();

    if (recordingsList.isEmpty) {
      final msg = filter == 'today'
          ? 'No lectures recorded today.'
          : 'No lecture recordings found.';
      return AgentToolResult.success(
        tool: name,
        message: msg,
        data: {'recordings': [], 'filter': filter},
      );
    }

    return AgentToolResult.success(
      tool: name,
      message:
          'Found ${recordingsList.length} lecture ${recordingsList.length == 1 ? "recording" : "recordings"}.',
      data: {
        'filter': filter,
        'count': recordingsList.length,
        'recordings': recordingsList,
      },
    );
  }
}
