import 'package:flutter/material.dart';
import '../models/vault_item.dart';
import '../services/campus_vault_service.dart';
import '../services/rag_service.dart';
import '../theme/app_theme.dart';
import 'study_vault/campus/academic_calendar_screen.dart';
import 'study_vault/campus/holidays_screen.dart';
import 'study_vault/campus/id_card_screen.dart';
import 'study_vault/campus/mess_menu_screen.dart';
import 'study_vault/campus/notices_screen.dart';
import 'study_vault/vault_search_sheet.dart';
import 'study_vault/vault_subject_screen.dart';
import 'study_vault/vault_unorganized_screen.dart';

class StudyVaultScreen extends StatefulWidget {
  final Function(int,
      {String? initialQuery,
      String? filterSubject,
      String? filterUnit}) onNavigateToBrain;

  const StudyVaultScreen({super.key, required this.onNavigateToBrain});

  @override
  State<StudyVaultScreen> createState() => _StudyVaultScreenState();
}

class _StudyVaultScreenState extends State<StudyVaultScreen> {
  final RagService _ragService = RagService.instance;
  final CampusVaultService _campusService = CampusVaultService.instance;

  @override
  void initState() {
    super.initState();
    _ragService.addListener(_onUpdate);
    _campusService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _ragService.removeListener(_onUpdate);
    _campusService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          VaultSearchSheet(onNavigateToBrain: widget.onNavigateToBrain),
    );
  }

  void _showAddSubjectDialog() {
    final subjectCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final unitCtrl =
        TextEditingController(text: 'Unit 1: Introduction & Fundamentals');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
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
                  'Add New Subject',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textInactive),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: subjectCtrl,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Subject Name',
                hintText: 'e.g., Computer Networks, Linear Algebra',
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
              controller: codeCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Course Code (Optional)',
                hintText: 'e.g., CS301',
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
              controller: unitCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'First Unit Name',
                hintText: 'e.g., Unit 1: Physical Layer',
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
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  final name = subjectCtrl.text.trim();
                  final code = codeCtrl.text.trim();
                  final unit = unitCtrl.text.trim();
                  if (name.isNotEmpty) {
                    _ragService.addSubject(
                      name,
                      code: code.isNotEmpty ? code : null,
                      iconCode: 'school',
                      initialUnits: unit.isNotEmpty ? [unit] : null,
                    );
                    Navigator.pop(ctx);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.darkSurface,
                  foregroundColor: AppTheme.canvasBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Add Subject',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _restoreDefaults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text('Restore Default Subjects?'),
        content: const Text(
          'This will reset your academic subjects to default curriculum. Your sources will be preserved.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _ragService.restoreDefaultSubjects();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _ragService.subjects;
    final unorganizedCount = _ragService.totalUnorganizedSources;
    final idCard = _campusService.idCard;
    final nextHoliday = _campusService.getNextHoliday();
    final nextMilestone = _campusService.getNextMilestone();
    final notices = _campusService.notices;

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personal Student Vault',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'Academic & Campus Knowledge Hub',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search,
                color: AppTheme.primaryAccent, size: 22),
            tooltip: 'Search Vault',
            onPressed: _openSearch,
          ),
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.neutralPillFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Row(
              children: [
                const Text('📚', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Text(
                  '${_ragService.totalSources} Sources',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.neutralPillText,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                size: 20, color: AppTheme.textSecondary),
            color: AppTheme.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.cardBorder),
            ),
            onSelected: (val) {
              if (val == 'restore') _restoreDefaults();
              if (val == 'reset_mess') {
                _campusService.resetMessMenuToDefault();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'restore',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt,
                        size: 18, color: AppTheme.textSecondary),
                    SizedBox(width: 8),
                    Text('Restore Default Subjects',
                        style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'reset_mess',
                child: Row(
                  children: [
                    Icon(Icons.restaurant,
                        size: 18, color: AppTheme.textSecondary),
                    SizedBox(width: 8),
                    Text('Reset Mess Menu', style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.cardDecoration,
            child: const Row(
              children: [
                Icon(Icons.account_balance_outlined,
                    color: AppTheme.primaryAccent, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Personal Student Vault',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Academics hierarchy & campus life essentials. 100% on-device.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // ==================== SECTION 1: ACADEMICS ====================
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'ACADEMICS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: AppTheme.neutralPillFill,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${subjects.length}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _showAddSubjectDialog,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.detectedPillFill,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.detectedPillText.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add,
                          size: 13, color: AppTheme.detectedPillText),
                      SizedBox(width: 4),
                      Text(
                        'Add Subject',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.detectedPillText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          if (subjects.isEmpty)
            _buildEmptySubjectsState()
          else
            ...subjects.map((subject) => _buildSubjectCard(subject)),

          const SizedBox(height: 24),

          // ==================== SECTION 2: CAMPUS LIFE ====================
          Row(
            children: [
              const Text(
                'CAMPUS LIFE & ESSENTIALS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppTheme.detectedPillFill,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '5 Hubs',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.detectedPillText,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Campus Card 1: ID Card
          _buildCampusCard(
            title: 'Student ID Card',
            subtitle: idCard.studentName.isNotEmpty
                ? '${idCard.studentName} · Roll: ${idCard.rollNumber ?? idCard.studentId}'
                : 'Upload or verify your student ID card',
            badge: idCard.hasImages ? 'Verified' : 'Active',
            icon: Icons.badge_outlined,
            iconColor: Colors.indigo.shade600,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IdCardScreen()),
              );
            },
          ),

          // Campus Card 2: Mess Menu
          _buildCampusCard(
            title: 'Mess Menu',
            subtitle: _getTodayMealSnippet(),
            badge: 'Today',
            icon: Icons.restaurant_outlined,
            iconColor: Colors.orange.shade700,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MessMenuScreen()),
              );
            },
          ),

          // Campus Card 3: Holidays
          _buildCampusCard(
            title: 'Campus Holidays',
            subtitle: nextHoliday != null
                ? 'Next: ${nextHoliday.name} · ${_formatDate(nextHoliday.date)} (${nextHoliday.daysUntil()}d left)'
                : 'View official campus holidays and breaks',
            badge:
                nextHoliday != null ? '${nextHoliday.daysUntil()}d left' : null,
            icon: Icons.celebration_outlined,
            iconColor: Colors.purple.shade600,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HolidaysScreen()),
              );
            },
          ),

          // Campus Card 4: Academic Calendar
          _buildCampusCard(
            title: 'Academic Calendar',
            subtitle: nextMilestone != null
                ? 'Next: ${nextMilestone.title} (${_formatDate(nextMilestone.startDate)})'
                : 'Semester timeline, exam dates & key deadlines',
            badge: nextMilestone?.eventType.displayName,
            icon: Icons.calendar_month_outlined,
            iconColor: Colors.blue.shade700,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AcademicCalendarScreen()),
              );
            },
          ),

          // Campus Card 5: Notices
          _buildCampusCard(
            title: 'Campus Notices',
            subtitle: notices.isNotEmpty
                ? '${notices.length} circulars · Latest: "${notices.first.title}"'
                : 'Official announcements and examination circulars',
            badge: '${notices.length} Notices',
            icon: Icons.campaign_outlined,
            iconColor: Colors.teal.shade700,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NoticesScreen(
                    onNavigateToBrain: widget.onNavigateToBrain,
                  ),
                ),
              );
            },
          ),

          // ==================== SECTION 3: UNORGANIZED ====================
          if (unorganizedCount > 0) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Text(
                  'UNORGANIZED MATERIAL',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$unorganizedCount',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.amber.shade300,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildUnorganizedCard(unorganizedCount),
          ],

          const SizedBox(height: 24),

          // Add Another Subject Button
          InkWell(
            onTap: _showAddSubjectDialog,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.neutralPillFill.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.cardBorder,
                  width: 1.2,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline,
                      size: 18, color: AppTheme.primaryAccent),
                  SizedBox(width: 8),
                  Text(
                    'Add Another Academic Subject',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildCampusCard({
    required String title,
    required String subtitle,
    String? badge,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.neutralPillFill,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
            ),
          ),
          trailing: const Icon(Icons.arrow_forward_ios,
              size: 14, color: AppTheme.textSecondary),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildSubjectCard(VaultSubject subject) {
    IconData icon = Icons.school_outlined;
    if (subject.iconCode == 'computer') icon = Icons.computer;
    if (subject.iconCode == 'language') icon = Icons.language;
    if (subject.iconCode == 'psychology') icon = Icons.psychology;
    if (subject.iconCode == 'science') icon = Icons.science;
    if (subject.iconCode == 'functions') icon = Icons.functions;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.detectedPillFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.detectedPillText, size: 22),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  subject.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subject.code != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppTheme.neutralPillFill,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    subject.code!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${subject.units.length} units · ${subject.totalSources} sources',
              style:
                  const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
            ),
          ),
          trailing: const Icon(Icons.arrow_forward_ios,
              size: 14, color: AppTheme.textSecondary),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VaultSubjectScreen(
                  subject: subject,
                  onNavigateToBrain: widget.onNavigateToBrain,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildUnorganizedCard(int count) {
    return Material(
      color: AppTheme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.amber.shade700.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade900.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.inbox_outlined,
              color: Colors.amberAccent, size: 22),
        ),
        title: const Text(
          'Unorganized Sources',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
            color: AppTheme.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '$count source(s) awaiting subject or campus assignment',
            style:
                const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios,
            size: 14, color: AppTheme.textSecondary),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VaultUnorganizedScreen(
                onNavigateToBrain: widget.onNavigateToBrain,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptySubjectsState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Icon(Icons.folder_open_outlined,
              size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text(
            "Let's organize your study material.",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add your academic subjects and units to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showAddSubjectDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Subject'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.darkSurface,
              foregroundColor: AppTheme.canvasBg,
            ),
          ),
        ],
      ),
    );
  }

  String _getTodayMealSnippet() {
    final dayMenu = _campusService.getMenuForDate(DateTime.now());
    final lunchItems = dayMenu.lunch.items;
    if (lunchItems.isNotEmpty) {
      return 'Lunch: ${lunchItems.take(2).join(", ")} & more';
    }
    return 'View weekly breakfast, lunch, snacks & dinner';
  }

  String _formatDate(DateTime d) {
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
    return '${months[d.month - 1]} ${d.day}';
  }
}
