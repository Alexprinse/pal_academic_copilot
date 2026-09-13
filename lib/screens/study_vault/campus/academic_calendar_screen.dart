import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../models/campus_vault.dart';
import '../../../services/campus_vault_service.dart';
import '../../../theme/app_theme.dart';
import '../vault_breadcrumbs.dart';

class AcademicCalendarScreen extends StatefulWidget {
  const AcademicCalendarScreen({super.key});

  @override
  State<AcademicCalendarScreen> createState() => _AcademicCalendarScreenState();
}

class _AcademicCalendarScreenState extends State<AcademicCalendarScreen> {
  final CampusVaultService _campusService = CampusVaultService.instance;

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

  Future<void> _uploadCalendarDoc() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;
        final item = AcademicCalendarItem(
          id: 'cal-doc-${DateTime.now().millisecondsSinceEpoch}',
          title: 'Official Academic Schedule ($name)',
          startDate: DateTime.now(),
          eventType: CalendarEventType.semester,
          description: 'Uploaded official calendar document',
          originalDocPath: path,
        );
        await _campusService.addCalendarItem(item);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Uploaded "$name" to Academic Calendar.'),
              backgroundColor: AppTheme.darkSurface,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  void _showAddMilestoneDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime startDate = DateTime.now().add(const Duration(days: 14));
    DateTime? endDate;
    CalendarEventType eventType = CalendarEventType.exam;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add Academic Milestone',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Milestone Title',
                  hintText: 'e.g. End-Term Project Presentation',
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
                controller: descCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'e.g. Mandatory attendance; project viva',
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
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppTheme.cardBorder),
                      ),
                      title: const Text('Start Date',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary)),
                      subtitle: Text(
                        '${startDate.month}/${startDate.day}/${startDate.year}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary),
                      ),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: DateTime(2025),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setDialogState(() => startDate = date);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppTheme.cardBorder),
                      ),
                      title: const Text('End Date (Opt)',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary)),
                      subtitle: Text(
                        endDate != null
                            ? '${endDate!.month}/${endDate!.day}/${endDate!.year}'
                            : 'None',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary),
                      ),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: endDate ?? startDate,
                          firstDate: startDate,
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setDialogState(() => endDate = date);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CalendarEventType>(
                initialValue: eventType,
                decoration: InputDecoration(
                  labelText: 'Event Type',
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
                items: CalendarEventType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.displayName,
                        style: const TextStyle(fontSize: 13.5)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => eventType = val);
                },
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    if (title.isNotEmpty) {
                      final item = AcademicCalendarItem(
                        id: 'cal-${DateTime.now().millisecondsSinceEpoch}',
                        title: title,
                        startDate: startDate,
                        endDate: endDate,
                        eventType: eventType,
                        description: descCtrl.text.trim().isNotEmpty
                            ? descCtrl.text.trim()
                            : null,
                      );
                      await _campusService.addCalendarItem(item);
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
                  child: const Text('Add Milestone',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _viewOriginalDoc(AcademicCalendarItem item) {
    if (item.originalDocPath == null ||
        !File(item.originalDocPath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document file not found on device.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.file(
                  File(item.originalDocPath!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text('Cannot preview document file',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              left: 16,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _campusService.calendarItems;
    final nextMilestone = _campusService.getNextMilestone();

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
          'Academic Calendar',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_outlined,
                color: AppTheme.primaryAccent, size: 21),
            tooltip: 'Upload official calendar',
            onPressed: _uploadCalendarDoc,
          ),
          IconButton(
            icon:
                const Icon(Icons.add, color: AppTheme.primaryAccent, size: 23),
            tooltip: 'Add milestone',
            onPressed: _showAddMilestoneDialog,
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
              const BreadcrumbItem(label: 'Academic Calendar'),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Next Milestone Hero
                if (nextMilestone != null) ...[
                  _buildNextMilestoneHero(nextMilestone),
                  const SizedBox(height: 20),
                ],

                const Text(
                  'SEMESTER TIMELINE & KEY DATES',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),

                if (items.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'No academic calendar items recorded.',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                  )
                else
                  ...items.map((item) => _buildTimelineCard(item)),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextMilestoneHero(AcademicCalendarItem item) {
    final days = item.daysUntil();
    String countdown;
    if (days < 0) {
      countdown = 'In progress';
    } else if (days == 0) {
      countdown = 'Starts Today!';
    } else if (days == 1) {
      countdown = 'Starts Tomorrow';
    } else {
      countdown = '$days days away';
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _getEventColor(item.eventType).withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: _getEventColor(item.eventType).withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getEventColor(item.eventType).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'NEXT ACADEMIC MILESTONE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: _getEventColor(item.eventType),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.neutralPillFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  countdown,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.date_range,
                  size: 14, color: _getEventColor(item.eventType)),
              const SizedBox(width: 6),
              Text(
                _formatDateRange(item.startDate, item.endDate),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '•  ${item.eventType.displayName}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          if (item.description != null && item.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              item.description!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineCard(AcademicCalendarItem item) {
    final color = _getEventColor(item.eventType);
    final hasDoc = item.originalDocPath != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_getEventIcon(item.eventType), color: color, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                item.eventType.displayName,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatDateRange(item.startDate, item.endDate),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (item.description != null && item.description!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasDoc)
              IconButton(
                icon: const Icon(Icons.attachment,
                    size: 20, color: AppTheme.primaryAccent),
                tooltip: 'View Document',
                onPressed: () => _viewOriginalDoc(item),
              ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18,
                  color: AppTheme.textSecondary.withValues(alpha: 0.6)),
              onPressed: () => _campusService.removeCalendarItem(item.id),
            ),
          ],
        ),
      ),
    );
  }

  Color _getEventColor(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.exam:
        return Colors.red.shade700;
      case CalendarEventType.registration:
        return Colors.blue.shade700;
      case CalendarEventType.semester:
        return AppTheme.primaryAccent;
      case CalendarEventType.holidayBreak:
        return Colors.green.shade700;
      case CalendarEventType.event:
        return Colors.purple.shade700;
    }
  }

  IconData _getEventIcon(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.exam:
        return Icons.edit_note;
      case CalendarEventType.registration:
        return Icons.assignment_turned_in_outlined;
      case CalendarEventType.semester:
        return Icons.school_outlined;
      case CalendarEventType.holidayBreak:
        return Icons.beach_access_outlined;
      case CalendarEventType.event:
        return Icons.event_available_outlined;
    }
  }

  String _formatDateRange(DateTime start, DateTime? end) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final startStr = '${months[start.month - 1]} ${start.day}, ${start.year}';
    if (end == null ||
        (start.year == end.year &&
            start.month == end.month &&
            start.day == end.day)) {
      return startStr;
    }
    final endStr = '${months[end.month - 1]} ${end.day}, ${end.year}';
    return '$startStr – $endStr';
  }
}
