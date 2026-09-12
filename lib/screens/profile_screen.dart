import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../services/deadline_service.dart';
import '../services/rag_service.dart';
import '../services/llm_service.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  final Function(int)? onNavigateTab;

  const ProfileScreen({super.key, this.onNavigateTab});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileService _profileService = ProfileService.instance;
  final DeadlineService _deadlineService = DeadlineService.instance;
  final RagService _ragService = RagService.instance;
  final LlmService _llmService = LlmService.instance;

  @override
  void initState() {
    super.initState();
    _profileService.addListener(_onUpdate);
    _deadlineService.addListener(_onUpdate);
    _ragService.addListener(_onUpdate);
    _llmService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _profileService.removeListener(_onUpdate);
    _deadlineService.removeListener(_onUpdate);
    _ragService.removeListener(_onUpdate);
    _llmService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _showEditProfileDialog() {
    final profile = _profileService.profile;
    final nameCtrl = TextEditingController(text: profile.name);
    final idCtrl = TextEditingController(text: profile.studentId);
    final majorCtrl = TextEditingController(text: profile.major);
    final uniCtrl = TextEditingController(text: profile.university);
    final gpaCtrl = TextEditingController(text: profile.gpa.toString());
    final goalCtrl =
        TextEditingController(text: profile.dailyGoalHours.toString());

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
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
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
                    'Edit Student Profile',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
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
              const SizedBox(height: 16),
              _buildTextField('Full Name', nameCtrl, Icons.person_outline),
              const SizedBox(height: 12),
              _buildTextField('Student ID', idCtrl, Icons.badge_outlined),
              const SizedBox(height: 12),
              _buildTextField(
                  'Major / Specialization', majorCtrl, Icons.school_outlined),
              const SizedBox(height: 12),
              _buildTextField('University / Institution', uniCtrl,
                  Icons.account_balance_outlined),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                        'GPA (4.0 Scale)', gpaCtrl, Icons.grade_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                        'Daily Goal (Hrs)', goalCtrl, Icons.timer_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  final parsedGpa =
                      double.tryParse(gpaCtrl.text.trim()) ?? profile.gpa;
                  final parsedGoal = double.tryParse(goalCtrl.text.trim()) ??
                      profile.dailyGoalHours;

                  _profileService.updateProfile(
                    name: nameCtrl.text.trim().isNotEmpty
                        ? nameCtrl.text.trim()
                        : profile.name,
                    studentId: idCtrl.text.trim().isNotEmpty
                        ? idCtrl.text.trim()
                        : profile.studentId,
                    major: majorCtrl.text.trim().isNotEmpty
                        ? majorCtrl.text.trim()
                        : profile.major,
                    university: uniCtrl.text.trim().isNotEmpty
                        ? uniCtrl.text.trim()
                        : profile.university,
                    gpa: parsedGpa,
                    dailyGoalHours: parsedGoal,
                  );

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.cardSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppTheme.cardBorder),
                      ),
                      content: const Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: AppTheme.trustPillText, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Profile details updated successfully!',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.darkSurface,
                  foregroundColor: AppTheme.canvasBg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Save Changes',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddCourseDialog() {
    final codeCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final profCtrl = TextEditingController();
    final creditsCtrl = TextEditingController(text: '3');
    final roomCtrl = TextEditingController();
    final scheduleCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Add Enrolled Course',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField('Course Code (e.g. CS 450)', codeCtrl, Icons.tag),
              const SizedBox(height: 10),
              _buildTextField('Course Title', titleCtrl, Icons.book_outlined),
              const SizedBox(height: 10),
              _buildTextField(
                  'Professor / Instructor', profCtrl, Icons.person_outline),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                        'Credits', creditsCtrl, Icons.star_outline,
                        keyboardType: TextInputType.number),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child:
                        _buildTextField('Room', roomCtrl, Icons.room_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildTextField('Schedule (e.g. Mon 2 PM)', scheduleCtrl,
                  Icons.schedule_outlined),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (codeCtrl.text.trim().isNotEmpty &&
                  titleCtrl.text.trim().isNotEmpty) {
                _profileService.addCourse(
                  EnrolledCourse(
                    code: codeCtrl.text.trim().toUpperCase(),
                    title: titleCtrl.text.trim(),
                    instructor: profCtrl.text.trim().isEmpty
                        ? 'TBA'
                        : profCtrl.text.trim(),
                    credits: int.tryParse(creditsCtrl.text.trim()) ?? 3,
                    schedule: scheduleCtrl.text.trim().isEmpty
                        ? 'TBA'
                        : scheduleCtrl.text.trim(),
                    room: roomCtrl.text.trim().isEmpty
                        ? 'Campus'
                        : roomCtrl.text.trim(),
                  ),
                );
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Add Course'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog() {
    final exportJson = _profileService.exportAcademicSummary();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.ios_share, color: AppTheme.primaryAccent, size: 22),
            SizedBox(width: 10),
            Text(
              'Academic Data Export',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 280),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.neutralPillFill.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: SingleChildScrollView(
            child: Text(
              exportJson,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: exportJson));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.cardSurface,
                  content: const Text(
                    'Academic record copied to clipboard!',
                    style: TextStyle(color: AppTheme.textPrimary),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy JSON'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.darkSurface,
              foregroundColor: AppTheme.canvasBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        prefixIcon: Icon(icon, size: 18, color: AppTheme.textSecondary),
        filled: true,
        fillColor: AppTheme.neutralPillFill.withValues(alpha: 0.3),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppTheme.primaryAccent, width: 1.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profileService.profile;
    final completedDeadlines = _deadlineService.completedCount;
    final totalDeadlines = _deadlineService.totalCount;
    final vaultChunks = _ragService.totalIndexedChunks;
    final activePresetName = _llmService.activePreset?.name ?? 'SmolLM2 135M';

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.cardSurface,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.cardBorder),
                boxShadow: AppTheme.cardShadow,
              ),
              child: const Icon(Icons.arrow_back,
                  size: 18, color: AppTheme.textPrimary),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Student Profile',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'On-Device Academic Identity',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: InkWell(
              onTap: _showEditProfileDialog,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorder),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_outlined,
                        size: 14, color: AppTheme.primaryAccent),
                    SizedBox(width: 5),
                    Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Identity & Student Hero Card
            _buildHeroCard(profile),

            const SizedBox(height: 18),

            // 2. Academic Performance & Stats Metric Grid
            _buildAcademicStatsGrid(
              profile: profile,
              completedDeadlines: completedDeadlines,
              totalDeadlines: totalDeadlines,
              vaultChunks: vaultChunks,
            ),

            const SizedBox(height: 24),

            // 3. Enrolled Courses Section
            _buildEnrolledCoursesSection(profile),

            const SizedBox(height: 24),

            // 4. On-Device Copilot & Privacy Preferences
            _buildAiPreferencesSection(profile, activePresetName),

            const SizedBox(height: 24),

            // 5. Hardware & Storage Health
            _buildStorageSection(),

            const SizedBox(height: 24),

            // 6. Action Buttons (Export & Sign Out / Reset)
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(UserProfile profile) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder, width: 1.5),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Large Avatar with Monogram & Gold Accent Ring
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppTheme.canvasBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primaryAccent,
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      profile.initials,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryAccent,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.darkSurface,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: AppTheme.cardSurface, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.school,
                      size: 12,
                      color: AppTheme.primaryAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Student Name & Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            profile.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.major,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.university,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.neutralPillFill,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Text(
                        'ID: ${profile.studentId}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppTheme.cardBorder),
          const SizedBox(height: 12),
          // Academic Term & Trust Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 13, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    '${profile.semester} • ${profile.academicYear}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.trustPillFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 12, color: AppTheme.trustPillText),
                    SizedBox(width: 4),
                    Text(
                      '100% On-Device',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.trustPillText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicStatsGrid({
    required UserProfile profile,
    required int completedDeadlines,
    required int totalDeadlines,
    required int vaultChunks,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Academic Metrics',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Cumulative GPA',
                value: profile.gpa.toStringAsFixed(2),
                subtitle: 'Top 5% Tier',
                icon: Icons.workspace_premium,
                accentColor: AppTheme.primaryAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                title: 'Study Streak',
                value: '${profile.streakDays} Days',
                subtitle: 'Daily Goal: ${profile.dailyGoalHours.toInt()}h',
                icon: Icons.local_fire_department,
                accentColor: const Color(0xFFE65100),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Tasks Finished',
                value: '$completedDeadlines / $totalDeadlines',
                subtitle: 'On-time completions',
                icon: Icons.check_circle_outline,
                accentColor: AppTheme.trustPillText,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                title: 'RAG Knowledge',
                value: '$vaultChunks Chunks',
                subtitle: 'Textbooks & Slides',
                icon: Icons.auto_stories_outlined,
                accentColor: const Color(0xFF1E88E5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              Icon(icon, size: 16, color: accentColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnrolledCoursesSection(UserProfile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  'Enrolled Courses',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.neutralPillFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${profile.courses.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: _showAddCourseDialog,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.neutralPillFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add, size: 13, color: AppTheme.primaryAccent),
                    SizedBox(width: 4),
                    Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...profile.courses.map((course) => _buildCourseCard(course)),
      ],
    );
  }

  Widget _buildCourseCard(EnrolledCourse course) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.highlightBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              course.code,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryAccent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${course.instructor} • ${course.credits} Credits',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.schedule,
                        size: 11, color: AppTheme.textInactive),
                    const SizedBox(width: 4),
                    Text(
                      course.schedule,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.room_outlined,
                        size: 11, color: AppTheme.textInactive),
                    const SizedBox(width: 3),
                    Text(
                      course.room,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                size: 18, color: AppTheme.textSecondary),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'delete') {
                _profileService.removeCourse(course.code);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline,
                        size: 16, color: AppTheme.overduePillText),
                    SizedBox(width: 8),
                    Text('Remove Course',
                        style: TextStyle(color: AppTheme.overduePillText)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAiPreferencesSection(
      UserProfile profile, String activePresetName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'On-Device Copilot & Privacy',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Material(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(18),
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Active Model Information
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppTheme.highlightBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.psychology,
                        color: AppTheme.primaryAccent, size: 20),
                  ),
                  title: const Text(
                    'Active Reasoning Engine',
                    style:
                        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '$activePresetName (Hardware NPU)',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary),
                  ),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.trustPillFill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.trustPillText,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppTheme.cardBorder),

                // Strict Privacy Toggle
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  activeThumbColor: AppTheme.primaryAccent,
                  title: const Text(
                    'Strict Offline Privacy Mode',
                    style:
                        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Zero data leaves your phone. Audio, RAG, and LLM run 100% locally.',
                    style:
                        TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  value: profile.offlineStrictPrivacy,
                  onChanged: (val) {
                    _profileService.updatePrivacyAndAiSettings(
                        offlineStrictPrivacy: val);
                  },
                ),
                const Divider(height: 1, color: AppTheme.cardBorder),

                // Auto Extract Deadlines Toggle
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  activeThumbColor: AppTheme.primaryAccent,
                  title: const Text(
                    'Automatic Deadline Extractor',
                    style:
                        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Detect assignments, quizzes, and project due dates from audio lectures.',
                    style:
                        TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  value: profile.autoExtractDeadlines,
                  onChanged: (val) {
                    _profileService.updatePrivacyAndAiSettings(
                        autoExtractDeadlines: val);
                  },
                ),
                const Divider(height: 1, color: AppTheme.cardBorder),

                // Smart Audio Summaries Toggle
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  activeThumbColor: AppTheme.primaryAccent,
                  title: const Text(
                    'Smart Lecture Audio Summaries',
                    style:
                        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Generate key takeaways and flashcard citations post recording.',
                    style:
                        TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  value: profile.smartAudioSummaries,
                  onChanged: (val) {
                    _profileService.updatePrivacyAndAiSettings(
                        smartAudioSummaries: val);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStorageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hardware & Local Sandbox',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.cardBorder),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Device NPU Accelerator',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.neutralPillFill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Snapdragon 8 Elite',
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Local Model Cache',
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  Text(
                    '490 MB (Qwen 2.5 INT4)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Study Vault Vector Store',
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  Text(
                    '18.4 MB (Local Chunks)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Lecture Audio Sandbox',
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  Text(
                    '34.2 MB (WAV Cache)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.cardSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppTheme.cardBorder),
                      ),
                      content: const Text(
                        'Temporary audio and OCR cache cleared safely.',
                        style: TextStyle(color: AppTheme.textPrimary),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.cleaning_services_outlined, size: 15),
                label: const Text('Clear Temporary Cache (34.2 MB)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: const BorderSide(color: AppTheme.cardBorder),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size(double.infinity, 38),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _showExportDialog,
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('Export Academic Record & Summary'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.darkSurface,
            foregroundColor: AppTheme.canvasBg,
            minimumSize: const Size(double.infinity, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'PAL Academic Copilot v1.0.0 • 100% Private On-Device',
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
