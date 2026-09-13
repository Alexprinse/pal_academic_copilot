import 'package:flutter/material.dart';
import '../../screens/timetable_screen.dart';
import '../../services/deadline_service.dart';
import '../../services/timetable_service.dart';
import '../../theme/app_theme.dart';
import '../agent_activity_service.dart';
import '../agent_response.dart';
import '../agent_service.dart';
import '../agent_tool_call.dart';

class AgentActionPreviewSheet extends StatefulWidget {
  final String transcript;
  final List<AgentToolCall> toolCalls;
  final VoidCallback onCancel;
  final Function(AgentResponse response)? onExecuted;
  final AgentService? agentService;

  const AgentActionPreviewSheet({
    super.key,
    required this.transcript,
    required this.toolCalls,
    required this.onCancel,
    this.onExecuted,
    this.agentService,
  });

  @override
  State<AgentActionPreviewSheet> createState() =>
      _AgentActionPreviewSheetState();
}

class _AgentActionPreviewSheetState extends State<AgentActionPreviewSheet> {
  bool _isExecuting = false;
  int _executingStepIndex = 0;
  AgentResponse? _response;
  String? _executionError;
  bool _isUndone = false;
  String? _createdTimetableId;
  String? _createdTaskId;

  bool get _isAction => widget.toolCalls.any((call) {
        final t = call.tool;
        return t == 'create_timetable_event' ||
            t == 'update_timetable_event' ||
            t == 'delete_timetable_event' ||
            t == 'create_task' ||
            t == 'schedule_recording';
      });

  @override
  void initState() {
    super.initState();
    // If it's a direct question (read-only query), execute immediately to show Pal's answer!
    if (!_isAction) {
      _executeNow();
    }
  }

  Future<void> _executeNow() async {
    setState(() {
      _isExecuting = true;
      _executionError = null;
      _executingStepIndex = 0;
    });

    try {
      final service = widget.agentService ?? AgentService.instance;
      final res = await service.process(prompt: widget.transcript);

      // Track created resource IDs for undo support
      for (final tr in res.toolResults) {
        if (tr.success && tr.data is Map) {
          final data = tr.data as Map;
          if (tr.tool == 'create_timetable_event') {
            _createdTimetableId = data['id'] as String?;
          } else if (tr.tool == 'create_task') {
            _createdTaskId = data['id'] as String?;
          }
        }
      }

      // Record in lightweight Agent Activity History
      if (res.toolResults.isNotEmpty && res.toolResults.any((r) => r.success)) {
        final firstSuccess = res.toolResults.firstWhere((r) => r.success);
        AgentActivityService.instance.recordActivity(
          title: _getActionTitle(firstSuccess.tool),
          subtitle: firstSuccess.message,
          isSuccess: res.toolResults.every((r) => r.success),
          isReversible: _createdTimetableId != null || _createdTaskId != null,
          undoCallback: _performUndo,
        );
      }

      if (mounted) {
        setState(() {
          _isExecuting = false;
          _response = res;
        });
        widget.onExecuted?.call(res);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExecuting = false;
          _executionError = 'Couldn\'t complete everything: ${e.toString()}';
        });
      }
    }
  }

  Future<bool> _performUndo() async {
    if (_isUndone) return false;

    bool undone = false;
    if (_createdTimetableId != null) {
      TimetableService.instance.deleteEntry(_createdTimetableId!);
      undone = true;
    }
    if (_createdTaskId != null) {
      DeadlineService.instance.deleteDeadline(_createdTaskId!);
      undone = true;
    }

    if (mounted) {
      setState(() => _isUndone = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Action undone successfully.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    return undone;
  }

  String _getActionTitle(String tool) {
    switch (tool) {
      case 'create_timetable_event':
        return 'Added class to timetable';
      case 'update_timetable_event':
        return 'Updated timetable class';
      case 'schedule_recording':
        return 'Scheduled automated recording';
      case 'create_task':
        return 'Created task reminder';
      case 'delete_timetable_event':
        return 'Removed timetable class';
      default:
        return 'Agent action completed';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppTheme.cardBorder, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 1. "You said" transcript box
            const Text(
              'YOU SAID',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.canvasBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Text(
                '"${widget.transcript}"',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 2. Multi-state rendering: Loading -> Success/Error -> Preview
            if (_isExecuting) ...[
              _buildExecutionProgress(),
            ] else if (_response != null) ...[
              if (!_isAction)
                _buildQuestionAnswer(_response!)
              else if (_response!.toolResults.every((r) => r.success))
                _buildSuccessState(_response!)
              else
                _buildErrorState(_response!),
            ] else ...[
              _buildActionPreview(),
            ],
          ],
        ),
      ),
    );
  }

  // ==================== EXECUTION PROGRESS ====================

  Widget _buildExecutionProgress() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EXECUTING...',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryAccent,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        ...widget.toolCalls.asMap().entries.map((entry) {
          final idx = entry.key;
          final call = entry.value;
          final isDone = idx < _executingStepIndex;
          final isRunning = idx == _executingStepIndex;

          String stepLabel;
          switch (call.tool) {
            case 'create_timetable_event':
              stepLabel = isDone ? 'Class added' : 'Adding class...';
              break;
            case 'schedule_recording':
              stepLabel = isDone
                  ? 'Automatic recording enabled'
                  : 'Enabling recording...';
              break;
            case 'create_task':
              stepLabel = isDone ? 'Reminder created' : 'Setting reminder...';
              break;
            case 'update_timetable_event':
              stepLabel =
                  isDone ? 'Class rescheduled' : 'Rescheduling class...';
              break;
            default:
              stepLabel = isDone ? 'Action completed' : 'Processing...';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.canvasBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isRunning
                    ? AppTheme.primaryAccent.withValues(alpha: 0.5)
                    : AppTheme.cardBorder,
              ),
            ),
            child: Row(
              children: [
                if (isDone)
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF2E7D32), size: 20)
                else if (isRunning)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppTheme.primaryAccent),
                    ),
                  )
                else
                  const Icon(Icons.radio_button_unchecked_rounded,
                      color: AppTheme.textSecondary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stepLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isRunning ? FontWeight.w700 : FontWeight.w500,
                      color: isRunning
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ==================== SUCCESS STATE ====================

  Widget _buildSuccessState(AgentResponse response) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF2E7D32),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _cleanMarkdown(response.text),
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Action Buttons: [View Class] [Undo] [Done]
        Row(
          children: [
            if (_createdTimetableId != null) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TimetableScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: const Text('View Class'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: const BorderSide(color: AppTheme.cardBorder),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (_createdTimetableId != null || _createdTaskId != null) ...[
              OutlinedButton.icon(
                onPressed: _isUndone ? null : _performUndo,
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: Text(_isUndone ? 'Undone' : 'Undo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      _isUndone ? AppTheme.textSecondary : Colors.redAccent,
                  side: BorderSide(
                    color: _isUndone
                        ? AppTheme.cardBorder
                        : Colors.redAccent.withValues(alpha: 0.5),
                  ),
                  padding:
                      const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent,
                  foregroundColor: const Color(0xFF1E1D19),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== ERROR STATE ====================

  Widget _buildErrorState(AgentResponse response) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Couldn\'t complete everything.',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.redAccent,
          ),
        ),
        const SizedBox(height: 10),

        // Authoritative Step breakdown
        ...response.toolResults.map((result) {
          final isSuccess = result.success;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSuccess
                  ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                  : Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: isSuccess ? const Color(0xFF2E7D32) : Colors.redAccent,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isSuccess
                        ? (result.tool == 'create_timetable_event'
                            ? 'Class added'
                            : result.message)
                        : (result.tool == 'schedule_recording'
                            ? 'Automatic recording couldn\'t be enabled'
                            : result.message),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSuccess
                          ? AppTheme.textPrimary
                          : Colors.redAccent.shade100,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _executeNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent,
                  foregroundColor: const Color(0xFF1E1D19),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== QUESTION MODE ====================

  Widget _buildQuestionAnswer(AgentResponse response) {
    // Extract subtle source citation if present
    String? sourceCitation;
    for (final tr in response.toolResults) {
      if (tr.tool == 'search_knowledge' && tr.data is Map) {
        final matches = (tr.data['matches'] as List?) ?? [];
        if (matches.isNotEmpty) {
          final first = matches.first as Map;
          final doc = first['documentName'] ?? 'Lecture Notes';
          final p = first['pageNumber'];
          final ts = first['timestamp'];
          if (ts != null) {
            sourceCitation = 'Based on: $doc · $ts';
          } else if (p != null) {
            sourceCitation = 'Sources: $doc · p. $p';
          } else {
            sourceCitation = 'Based on: $doc';
          }
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PAL',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryAccent,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.trustPillFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primaryAccent.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            _cleanMarkdown(response.text),
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textPrimary,
              height: 1.4,
            ),
          ),
        ),
        if (sourceCitation != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.menu_book_rounded,
                  size: 13, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                sourceCitation,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: const Color(0xFF1E1D19),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Done',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== ACTION PREVIEW ====================

  Widget _buildActionPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PAL WILL',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryAccent,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),

        ...widget.toolCalls.asMap().entries.map((entry) => _buildActionCard(
            entry.value,
            stepIndex: widget.toolCalls.length > 1 ? entry.key + 1 : null)),

        if (_executionError != null) ...[
          const SizedBox(height: 8),
          Text(
            _executionError!,
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 20),

        // [Cancel] [Do it] Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  widget.onCancel();
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _executeNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent,
                  foregroundColor: const Color(0xFF1E1D19),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Do it',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(AgentToolCall call, {int? stepIndex}) {
    IconData icon;
    String title;
    String subtitle;
    Color iconBg;

    final args = call.arguments;

    switch (call.tool) {
      case 'create_timetable_event':
        icon = Icons.add_rounded;
        iconBg = const Color(0xFF2E7D32).withValues(alpha: 0.2);
        final subject = args['subject'] ?? 'New Class';
        final day = args['day'] ?? 'Tomorrow';
        final start = args['startTime'] ?? '';
        final end = args['endTime'] != null ? ' – ${args["endTime"]}' : '';
        title = '✓ Add $subject';
        subtitle = '$day · $start$end';
        break;

      case 'update_timetable_event':
        icon = Icons.edit_calendar_rounded;
        iconBg = AppTheme.primaryAccent.withValues(alpha: 0.2);
        final subject = args['subject'] ?? 'Class';
        final newStart = args['newStartTime'] ?? '';
        final newEnd =
            args['newEndTime'] != null ? ' – ${args["newEndTime"]}' : '';
        title = '✓ Move $subject';
        subtitle = 'New time: $newStart$newEnd';
        break;

      case 'delete_timetable_event':
        icon = Icons.delete_outline_rounded;
        iconBg = Colors.redAccent.withValues(alpha: 0.2);
        final subject = args['subject'] ?? 'Class';
        final day = args['day'] != null ? ' on ${args["day"]}' : '';
        title = '✓ Remove $subject';
        subtitle = 'Will delete from timetable$day';
        break;

      case 'create_task':
        icon = Icons.check_circle_outline_rounded;
        iconBg = Colors.amber.withValues(alpha: 0.2);
        final taskTitle = args['title'] ?? 'Task';
        final due = args['dueDate'] ?? 'Tomorrow';
        title = '✓ Create task: $taskTitle';
        subtitle = 'Due: $due';
        break;

      case 'schedule_recording':
        icon = Icons.mic_none_rounded;
        iconBg = Colors.blueAccent.withValues(alpha: 0.2);
        final subject = args['subject'] ?? 'Lecture';
        final day = args['day'] ?? 'Tomorrow';
        final start =
            args['startTime'] != null ? ' at ${args["startTime"]}' : '';
        title = '✓ Enable automatic recording';
        subtitle = '$subject · $day$start';
        break;

      default:
        icon = Icons.bolt_rounded;
        iconBg = AppTheme.cardBorder;
        title = '✓ ${call.tool}';
        subtitle = args.toString();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.canvasBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: AppTheme.primaryAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (stepIndex != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'STEP $stepIndex',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryAccent,
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _cleanMarkdown(String text) {
    // Remove technical markdown bold markers for cleaner UI display if needed
    return text.replaceAll('**', '');
  }
}
