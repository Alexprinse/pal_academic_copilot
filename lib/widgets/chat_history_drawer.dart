import 'package:flutter/material.dart';
import '../models/conversation_session.dart';
import '../services/conversation_service.dart';
import '../theme/app_theme.dart';

class ChatHistoryDrawer extends StatefulWidget {
  final String? activeConversationId;
  final Function(ConversationSession conversation) onSelectConversation;
  final VoidCallback onNewChat;

  const ChatHistoryDrawer({
    super.key,
    required this.activeConversationId,
    required this.onSelectConversation,
    required this.onNewChat,
  });

  @override
  State<ChatHistoryDrawer> createState() => _ChatHistoryDrawerState();
}

class _ChatHistoryDrawerState extends State<ChatHistoryDrawer> {
  final ConversationService _service = ConversationService.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final conversations = _searchQuery.trim().isEmpty
        ? _service.conversations
        : _service.searchConversations(_searchQuery);

    return Container(
      width: MediaQuery.of(context).size.width * 0.86,
      constraints: const BoxConstraints(maxWidth: 380),
      color: AppTheme.cardSurface,
      child: SafeArea(
        child: Column(
          children: [
            // 1. Header
            _buildHeader(context),

            // 2. Search Field
            _buildSearchBar(),

            const Divider(height: 1, color: AppTheme.cardBorder),

            // 3. Conversation List or Empty State
            Expanded(
              child: conversations.isEmpty
                  ? _buildEmptyState(context)
                  : _buildGroupedList(context, conversations),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.highlightBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.primaryAccent.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.forum_outlined,
              size: 17,
              color: AppTheme.primaryAccent,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Chat History',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
          // New Chat Button
          IconButton(
            tooltip: 'New Chat',
            icon: const Icon(Icons.add, color: AppTheme.textPrimary, size: 22),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onNewChat();
            },
          ),
          // Close Drawer
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close,
                color: AppTheme.textSecondary, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: AppTheme.neutralPillFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.cardBorder, width: 0.8),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 10, right: 6),
              child:
                  Icon(Icons.search, size: 17, color: AppTheme.textSecondary),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search conversations...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                },
              ),
            ),
            if (_searchQuery.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear,
                    size: 16, color: AppTheme.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_outlined,
                  size: 40, color: AppTheme.textSecondary),
              const SizedBox(height: 12),
              const Text(
                'No matching conversations',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Try searching for other keywords',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.highlightBg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 32,
                color: AppTheme.primaryAccent,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No conversations yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your study conversations will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onNewChat();
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Start a New Chat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAccent,
                foregroundColor: AppTheme.primaryButtonText,
                elevation: 0,
                shape: RoundedRectangleAppTheme(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedList(
      BuildContext context, List<ConversationSession> conversations) {
    // Separate pinned and date-grouped
    final pinned = conversations.where((c) => c.isPinned).toList();
    final nonPinned = conversations.where((c) => !c.isPinned).toList();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final pastWeek = today.subtract(const Duration(days: 7));

    final todayList = <ConversationSession>[];
    final yesterdayList = <ConversationSession>[];
    final weekList = <ConversationSession>[];
    final olderList = <ConversationSession>[];

    for (final c in nonPinned) {
      final date =
          DateTime(c.updatedAt.year, c.updatedAt.month, c.updatedAt.day);
      if (date.isAtSameMomentAs(today)) {
        todayList.add(c);
      } else if (date.isAtSameMomentAs(yesterday)) {
        yesterdayList.add(c);
      } else if (date.isAfter(pastWeek)) {
        weekList.add(c);
      } else {
        olderList.add(c);
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (pinned.isNotEmpty) ...[
          _buildSectionHeader('PINNED'),
          ...pinned.map((c) => _buildConversationTile(context, c)),
        ],
        if (todayList.isNotEmpty) ...[
          _buildSectionHeader('TODAY'),
          ...todayList.map((c) => _buildConversationTile(context, c)),
        ],
        if (yesterdayList.isNotEmpty) ...[
          _buildSectionHeader('YESTERDAY'),
          ...yesterdayList.map((c) => _buildConversationTile(context, c)),
        ],
        if (weekList.isNotEmpty) ...[
          _buildSectionHeader('PREVIOUS 7 DAYS'),
          ...weekList.map((c) => _buildConversationTile(context, c)),
        ],
        if (olderList.isNotEmpty) ...[
          _buildSectionHeader('OLDER'),
          ...olderList.map((c) => _buildConversationTile(context, c)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildConversationTile(
      BuildContext context, ConversationSession conversation) {
    final isActive = conversation.id == widget.activeConversationId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.of(context).pop();
          widget.onSelectConversation(conversation);
        },
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? AppTheme.highlightBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? AppTheme.primaryAccent.withValues(alpha: 0.4)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              if (conversation.isPinned)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.push_pin,
                      size: 13, color: AppTheme.primaryAccent),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive
                            ? AppTheme.primaryAccent
                            : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${conversation.selectedRagScope} · ${_formatTime(conversation.updatedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // More Actions Menu (⋮)
              _buildMoreMenu(context, conversation),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreMenu(
      BuildContext context, ConversationSession conversation) {
    return PopupMenuButton<String>(
      icon:
          const Icon(Icons.more_vert, size: 18, color: AppTheme.textSecondary),
      padding: EdgeInsets.zero,
      color: AppTheme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.cardBorder),
      ),
      onSelected: (action) {
        if (action == 'pin') {
          _service.togglePinConversation(conversation.id);
        } else if (action == 'rename') {
          _showRenameDialog(context, conversation);
        } else if (action == 'delete') {
          _showDeleteDialog(context, conversation);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'pin',
          height: 36,
          child: Row(
            children: [
              Icon(
                conversation.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
                size: 15,
                color: AppTheme.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                conversation.isPinned ? 'Unpin' : 'Pin conversation',
                style: const TextStyle(
                    fontSize: 12.5, color: AppTheme.textPrimary),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'rename',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 15, color: AppTheme.textPrimary),
              SizedBox(width: 8),
              Text(
                'Rename',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 15, color: AppTheme.redAccent),
              SizedBox(width: 8),
              Text(
                'Delete',
                style: TextStyle(fontSize: 12.5, color: AppTheme.redAccent),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showRenameDialog(
      BuildContext context, ConversationSession conversation) {
    final controller = TextEditingController(text: conversation.title);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text(
          'Rename Conversation',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Enter new title',
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            filled: true,
            fillColor: AppTheme.neutralPillFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primaryAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: AppTheme.primaryButtonText,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                _service.renameConversation(conversation.id, newTitle);
              }
              Navigator.of(dialogCtx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
      BuildContext context, ConversationSession conversation) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text(
          'Delete this conversation?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: const Text(
          'This cannot be undone. Your notes, vault files, and recordings will not be affected.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              _service.deleteConversation(conversation.id);
              Navigator.of(dialogCtx).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }
}

class RoundedRectangleAppTheme extends RoundedRectangleBorder {
  RoundedRectangleAppTheme()
      : super(
          borderRadius: BorderRadius.circular(8),
        );
}
