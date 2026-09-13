import 'package:flutter/material.dart';
import '../../../models/campus_vault.dart';
import '../../../models/deadline.dart';
import '../../../services/campus_vault_service.dart';
import '../../../services/deadline_service.dart';
import '../../../theme/app_theme.dart';
import '../vault_breadcrumbs.dart';

class NoticesScreen extends StatefulWidget {
  final Function(int,
      {String? initialQuery,
      String? filterSubject,
      String? filterUnit})? onNavigateToBrain;

  const NoticesScreen({super.key, this.onNavigateToBrain});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  final CampusVaultService _campusService = CampusVaultService.instance;
  final DeadlineService _deadlineService = DeadlineService.instance;
  String _selectedCategory =
      'all'; // 'all', 'exams', 'placement', 'events', 'administration', 'general'

  @override
  void initState() {
    super.initState();
    _campusService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _campusService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _showNoticeDetail(CampusNotice notice) {
    _campusService.markNoticeAsRead(notice.id);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            // Category & Date Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getCategoryColor(notice.category)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    notice.category.displayName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: _getCategoryColor(notice.category),
                    ),
                  ),
                ),
                Text(
                  '${notice.date.year}-${notice.date.month.toString().padLeft(2, "0")}-${notice.date.day.toString().padLeft(2, "0")}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              notice.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),

            if (notice.issuingAuthority != null) ...[
              Row(
                children: [
                  const Icon(Icons.verified_user_outlined,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Issued by: ${notice.issuingAuthority}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            const Divider(color: AppTheme.cardBorder),
            const SizedBox(height: 8),

            // Summary Card (if present)
            if (notice.summary != null && notice.summary!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.detectedPillFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.detectedPillText.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 18, color: AppTheme.detectedPillText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Quick Takeaways',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.detectedPillText,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            notice.summary!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textPrimary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Notice Full Text
            const Text(
              'CIRCULAR CONTENT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.neutralPillFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Text(
                notice.extractedText,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                  height: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Action 1: Ask Pal about this Notice
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                if (widget.onNavigateToBrain != null) {
                  widget.onNavigateToBrain!(
                    1,
                    initialQuery:
                        'Explain the campus notice: "${notice.title}". Key points: ${notice.extractedText}',
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Open Pal Brain tab to ask questions about this notice.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 17),
              label: const Text('Ask Pal About This Notice'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.darkSurface,
                foregroundColor: AppTheme.canvasBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),

            const SizedBox(height: 8),

            // Action 2: Create Task / Reminder from Deadline
            if (notice.deadline != null) ...[
              OutlinedButton.icon(
                onPressed: () {
                  final dl = Deadline(
                    id: 'dl-notice-${DateTime.now().millisecondsSinceEpoch}',
                    title: 'Notice Deadline: ${notice.title}',
                    course: 'Campus Circular',
                    dueDate: notice.deadline!,
                    priority: TaskPriority.high,
                  );
                  _deadlineService.addDeadline(dl);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Created task for ${notice.deadline!.month}/${notice.deadline!.day}!'),
                      backgroundColor: AppTheme.darkSurface,
                    ),
                  );
                },
                icon: const Icon(Icons.alarm_add_outlined,
                    size: 17, color: AppTheme.primaryAccent),
                label: Text(
                  'Add Deadline Task (${notice.deadline!.month}/${notice.deadline!.day})',
                  style: const TextStyle(
                      color: AppTheme.primaryAccent,
                      fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.cardBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showAddNoticeDialog() {
    final titleCtrl = TextEditingController();
    final authCtrl = TextEditingController(text: 'Academic Affairs');
    final textCtrl = TextEditingController();
    final summaryCtrl = TextEditingController();
    DateTime pickedDate = DateTime.now();
    DateTime? deadlineDate;
    NoticeCategory category = NoticeCategory.general;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Add Campus Notice',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: AppTheme.textSecondary),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Notice Title',
                    hintText: 'e.g. End Semester Exam Seating Plan',
                    filled: true,
                    fillColor: AppTheme.neutralPillFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: authCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Issuing Authority',
                    hintText: 'e.g. Controller of Examinations',
                    filled: true,
                    fillColor: AppTheme.neutralPillFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: textCtrl,
                  maxLines: 4,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Notice Text / Details',
                    hintText: 'Paste circular announcement text here...',
                    filled: true,
                    fillColor: AppTheme.neutralPillFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: summaryCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Brief Summary (Optional)',
                    hintText: 'e.g. Report to hall at 09:30 AM with ID card.',
                    filled: true,
                    fillColor: AppTheme.neutralPillFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<NoticeCategory>(
                  initialValue: category,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    filled: true,
                    fillColor: AppTheme.neutralPillFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                  items: NoticeCategory.values.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(cat.displayName,
                          style: const TextStyle(fontSize: 13.5)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => category = val);
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  title: const Text('Action Deadline (Optional)',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                  subtitle: Text(
                    deadlineDate != null
                        ? '${deadlineDate!.month}/${deadlineDate!.day}/${deadlineDate!.year}'
                        : 'No deadline attached',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary),
                  ),
                  trailing: const Icon(Icons.event, size: 18),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2030),
                    );
                    if (date != null) {
                      setDialogState(() => deadlineDate = date);
                    }
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final title = titleCtrl.text.trim();
                      final text = textCtrl.text.trim();
                      if (title.isNotEmpty && text.isNotEmpty) {
                        final notice = CampusNotice(
                          id: 'not-${DateTime.now().millisecondsSinceEpoch}',
                          title: title,
                          date: pickedDate,
                          category: category,
                          issuingAuthority: authCtrl.text.trim().isNotEmpty
                              ? authCtrl.text.trim()
                              : null,
                          extractedText: text,
                          summary: summaryCtrl.text.trim().isNotEmpty
                              ? summaryCtrl.text.trim()
                              : null,
                          deadline: deadlineDate,
                          isRead: true,
                        );
                        await _campusService.addNotice(notice);
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.darkSurface,
                      foregroundColor: AppTheme.canvasBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Add Notice',
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allNotices = _campusService.notices;

    final filteredNotices = allNotices.where((n) {
      if (_selectedCategory == 'all') return true;
      return n.category.name.toLowerCase() == _selectedCategory;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Campus Notices',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.add, color: AppTheme.primaryAccent, size: 23),
            tooltip: 'Add notice',
            onPressed: _showAddNoticeDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          VaultBreadcrumbs(
            items: [
              BreadcrumbItem(
                label: 'Vault',
                onTap: () => Navigator.pop(context),
              ),
              BreadcrumbItem(
                label: 'Campus',
                onTap: () => Navigator.pop(context),
              ),
              const BreadcrumbItem(label: 'Notices'),
            ],
          ),

          // Category filter pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterPill('all', 'All (${allNotices.length})'),
                const SizedBox(width: 8),
                _buildFilterPill('exams', 'Examinations'),
                const SizedBox(width: 8),
                _buildFilterPill('placement', 'Placements'),
                const SizedBox(width: 8),
                _buildFilterPill('events', 'Events'),
                const SizedBox(width: 8),
                _buildFilterPill('administration', 'Admin'),
              ],
            ),
          ),

          const Divider(height: 1, color: AppTheme.cardBorder),

          Expanded(
            child: filteredNotices.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'No notices found under this category.',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredNotices.length,
                    itemBuilder: (_, idx) =>
                        _buildNoticeCard(filteredNotices[idx]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String key, String label) {
    final isSelected = _selectedCategory == key;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = key),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.darkSurface : AppTheme.neutralPillFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.darkSurface : AppTheme.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppTheme.canvasBg : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildNoticeCard(CampusNotice notice) {
    final color = _getCategoryColor(notice.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        onTap: () => _showNoticeDetail(notice),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child:
              Icon(_getCategoryIcon(notice.category), color: color, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                notice.title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${notice.date.month}/${notice.date.day}/${notice.date.year}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (notice.issuingAuthority != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '•  ${notice.issuingAuthority}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (notice.summary != null) ...[
                const SizedBox(height: 4),
                Text(
                  notice.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right,
            color: AppTheme.textSecondary, size: 18),
      ),
    );
  }

  Color _getCategoryColor(NoticeCategory cat) {
    switch (cat) {
      case NoticeCategory.exams:
        return Colors.red.shade700;
      case NoticeCategory.placement:
        return Colors.teal.shade700;
      case NoticeCategory.events:
        return Colors.purple.shade700;
      case NoticeCategory.administration:
        return Colors.blue.shade700;
      case NoticeCategory.general:
        return AppTheme.primaryAccent;
    }
  }

  IconData _getCategoryIcon(NoticeCategory cat) {
    switch (cat) {
      case NoticeCategory.exams:
        return Icons.quiz_outlined;
      case NoticeCategory.placement:
        return Icons.work_outline;
      case NoticeCategory.events:
        return Icons.celebration_outlined;
      case NoticeCategory.administration:
        return Icons.apartment_outlined;
      case NoticeCategory.general:
        return Icons.campaign_outlined;
    }
  }
}
