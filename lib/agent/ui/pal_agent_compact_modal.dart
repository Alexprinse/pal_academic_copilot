import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../agent_activity_service.dart';
import '../agent_service.dart';
import 'agent_action_preview_sheet.dart';

class PalAgentCompactModal extends StatefulWidget {
  final VoidCallback? onVoiceRecordRequested;

  const PalAgentCompactModal({
    super.key,
    this.onVoiceRecordRequested,
  });

  static Future<void> show(BuildContext context,
      {VoidCallback? onVoiceRecordRequested}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PalAgentCompactModal(
        onVoiceRecordRequested: onVoiceRecordRequested,
      ),
    );
  }

  @override
  State<PalAgentCompactModal> createState() => _PalAgentCompactModalState();
}

class _PalAgentCompactModalState extends State<PalAgentCompactModal> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _showHistory = false;

  final List<String> _suggestedCommands = [
    'Add a class',
    'Schedule a recording',
    'Check my schedule',
    'Ask my notes',
  ];

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSelectSuggestion(String suggestion) {
    switch (suggestion) {
      case 'Add a class':
        _textController.text = 'Add Artificial Intelligence tomorrow from 10 to 11';
        break;
      case 'Schedule a recording':
        _textController.text = 'Schedule recording for Artificial Intelligence';
        break;
      case 'Check my schedule':
        _submitPrompt('What is my schedule today?');
        return;
      case 'Ask my notes':
        _textController.text = 'Find assignment in yesterday\'s lecture notes';
        break;
      default:
        _textController.text = suggestion;
    }
    _focusNode.requestFocus();
    setState(() {});
  }

  void _submitPrompt(String prompt) {
    final clean = prompt.trim();
    if (clean.isEmpty) return;

    Navigator.of(context).pop();

    final toolCalls = AgentService.instance.determineToolCalls(clean);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgentActionPreviewSheet(
        transcript: clean,
        toolCalls: toolCalls,
        onCancel: () {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
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

            // Header: ✦ Pal + Subtitle + Action History Toggle + Close
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      '✦',
                      style: TextStyle(
                        color: AppTheme.primaryAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pal',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        _showHistory
                            ? 'Recent Activity History'
                            : 'What can I help you do?',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _showHistory ? 'Commands' : 'Recent Actions',
                  icon: Icon(
                    _showHistory
                        ? Icons.chat_bubble_outline_rounded
                        : Icons.history_rounded,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () => setState(() => _showHistory = !_showHistory),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Mode 1: Activity History
            if (_showHistory) ...[
              _buildHistoryView(),
            ] else ...[
              // Mode 2: Suggested Commands Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _suggestedCommands.map((cmd) {
                  return InkWell(
                    onTap: () => _onSelectSuggestion(cmd),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.canvasBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Text(
                        cmd,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // Text Input Box + Mic + Send
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.canvasBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.cardBorder,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        style: const TextStyle(
                          fontSize: 14.5,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Tell Pal what you need...',
                          hintStyle: TextStyle(
                            fontSize: 14.5,
                            color: AppTheme.textInactive,
                          ),
                          border: InputBorder.none,
                        ),
                        onSubmitted: _submitPrompt,
                      ),
                    ),
                    // Mic Button
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onVoiceRecordRequested?.call();
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color:
                              AppTheme.primaryAccent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.mic_rounded,
                          color: AppTheme.primaryAccent,
                          size: 20,
                        ),
                      ),
                    ),
                    // Send Button
                    InkWell(
                      onTap: () => _submitPrompt(_textController.text),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_upward_rounded,
                          color: Color(0xFF1E1D19),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryView() {
    final activities = AgentActivityService.instance.activities;
    if (activities.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: const Center(
          child: Text(
            'No recent agent actions yet.\nTry asking Pal to add a class or schedule a recording.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TODAY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: activities.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final act = activities[index];
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.canvasBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      act.isSuccess
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      size: 18,
                      color: act.isSuccess
                          ? const Color(0xFF2E7D32)
                          : Colors.redAccent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            act.title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            act.subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (act.isReversible && !act.isUndone)
                      TextButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await AgentActivityService.instance
                              .undoActivity(act.id);
                          if (ok && mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Action undone.'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            setState(() {});
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Undo',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      )
                    else if (act.isUndone)
                      const Text(
                        'Undone',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
