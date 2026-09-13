import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/ocr_document_context.dart';
import '../services/ocr_service.dart';
import '../theme/app_theme.dart';
import 'pal_brain_screen.dart';
import 'study_vault/save_to_vault_dialog.dart';

class OcrScannerScreen extends StatefulWidget {
  final Function(int, {String? initialQuery}) onNavigateToBrain;

  const OcrScannerScreen({super.key, required this.onNavigateToBrain});

  @override
  State<OcrScannerScreen> createState() => _OcrScannerScreenState();
}

class _OcrScannerScreenState extends State<OcrScannerScreen> {
  final OcrService _ocrService = OcrService.instance;
  final TextEditingController _textController = TextEditingController();
  String? _currentDocumentTitle;

  @visibleForTesting
  void setDocumentTitleForTesting(String? title) {
    setState(() => _currentDocumentTitle = title);
  }

  final List<Map<String, String>> _recentScans = [
    {
      'title': 'Operating Systems — Notes',
      'meta': 'Today · 2 pages',
      'sampleText':
          'Operating Systems: Peterson\'s Algorithm for mutual exclusion in process synchronization. What are the shared variables and how does bounded waiting hold?\n\nPeterson\'s solution is a software-based algorithm restricted to two processes that alternate execution between critical section and remainder section.',
    },
    {
      'title': 'Assignment 1 — Questions',
      'meta': 'Yesterday · 1 page',
      'sampleText':
          'Question 2: Define semaphore. Differentiate between Counting Semaphore and Binary Semaphore (Mutex) with execution timing diagrams.',
    },
    {
      'title': 'Chapter 3 — Process Scheduling',
      'meta': 'Sep 8 · 4 pages',
      'sampleText':
          'Round Robin (RR) Scheduling Algorithm: Each process gets a small unit of CPU time (time quantum q), usually 10-100 milliseconds. After this time has elapsed, the process is preempted and added to the end of the ready queue.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _ocrService.addListener(_onOcrUpdate);
    if (_ocrService.lastResult != null) {
      _textController.text = _ocrService.lastResult!.text;
    }
  }

  @override
  void dispose() {
    _ocrService.removeListener(_onOcrUpdate);
    _textController.dispose();
    super.dispose();
  }

  void _onOcrUpdate() {
    if (mounted) {
      if (_ocrService.lastResult != null) {
        _textController.text = _ocrService.lastResult!.text;
      }
      setState(() {});
    }
  }

  Future<void> _capture(ImageSource source) async {
    try {
      final res = await _ocrService.scanImage(source);
      if (res != null && mounted) {
        _textController.text = res.text;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.cardSurface,
          content: Text(
            'OCR Error: $e',
            style: const TextStyle(color: AppTheme.overduePillText),
          ),
        ),
      );
    }
  }

  void _copyExtractedText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recognized text copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _loadRecentScan(Map<String, String> item) {
    setState(() {
      _currentDocumentTitle = item['title'];
      _textController.text = item['sampleText'] ?? '';
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded "${item['title']}" into OCR workspace'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showOcrInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.visibility_outlined,
                color: AppTheme.primaryAccent, size: 22),
            SizedBox(width: 8),
            Text(
              'On-Device Vision',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        content: const Text(
          'Pal uses Google ML Kit running 100% locally on your device hardware. Your textbook pages and handwritten notes are processed on-device with zero cloud telemetry or image uploading.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'GOT IT',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lastResult = _ocrService.lastResult;
    final hasText = _textController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header
              _buildHeader(context),

              // 2. Hardware / Status Card
              _buildStatusCard(lastResult),

              // 3. Scan & Extract Zone (Capabilities + Buttons)
              _buildHeroScanZone(),

              // 4. Output Area (Empty State or Result Card)
              _buildOcrResultArea(lastResult, hasText),

              // 5. AI Actions Section
              _buildAiActionsArea(hasText),

              // 6. Recent Scans
              _buildRecentScansArea(),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                if (Navigator.canPop(context)) ...[
                  InkWell(
                    onTap: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.arrow_back,
                        color: AppTheme.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'Textbook & Notes OCR',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Extract text from your study materials',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            color: AppTheme.textSecondary,
            tooltip: 'On-Device Privacy & Vision Info',
            onPressed: () => _showOcrInfoDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(OcrResult? lastResult) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.trustPillText,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'On-Device OCR',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.trustPillFill,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '● Ready',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.trustPillText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            lastResult != null
                ? '${lastResult.processingTimeMs}ms · ${lastResult.blockCount} blocks'
                : 'Works offline · Zero cloud',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroScanZone() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Scan & extract',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Turn textbook pages, handwritten notes, equations and worksheets into usable study material.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 14),

          // 4 Capability Pills
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildCapabilityChip(Icons.menu_book_outlined, 'Textbook Pages'),
              _buildCapabilityChip(Icons.edit_note, 'Handwritten Notes'),
              _buildCapabilityChip(Icons.functions, 'Equations'),
              _buildCapabilityChip(Icons.assignment_outlined, 'Worksheets'),
            ],
          ),
          const SizedBox(height: 18),

          // Action Buttons: Camera & Photo
          Row(
            children: [
              Expanded(
                flex: 6,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _capture(ImageSource.camera),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.camera_alt_rounded, size: 18),
                        SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Camera Scan',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Scan a page or note',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: const BorderSide(color: AppTheme.cardBorder),
                    backgroundColor: AppTheme.canvasBg,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _capture(ImageSource.gallery),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.photo_library_outlined,
                            size: 18, color: AppTheme.primaryAccent),
                        SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Choose Photo',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Select from gallery',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.neutralPillFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.primaryAccent),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOcrResultArea(OcrResult? lastResult, bool hasText) {
    if (!hasText) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.cardBorder),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Center(
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.highlightBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.document_scanner_outlined,
                  color: AppTheme.primaryAccent,
                  size: 24,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ready to scan',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap Camera Scan above to capture textbook pages, questions, or handwritten lecture notes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final charCount = _textController.text.length;
    final wordCount = _textController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Result Header Bar
          Row(
            children: [
              const Icon(Icons.check_circle,
                  color: AppTheme.trustPillText, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Recognized Text',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (_currentDocumentTitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _currentDocumentTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                iconSize: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.bookmark_add_outlined,
                    color: AppTheme.primaryAccent),
                tooltip: 'Save to Study Vault',
                onPressed: _showSaveToVaultDialog,
              ),
              const SizedBox(width: 4),
              IconButton(
                iconSize: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.copy_rounded,
                    color: AppTheme.primaryAccent),
                tooltip: 'Copy recognized text',
                onPressed: _copyExtractedText,
              ),
              const SizedBox(width: 4),
              IconButton(
                iconSize: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.clear, color: AppTheme.overduePillText),
                tooltip: 'Clear workspace',
                onPressed: () {
                  _ocrService.clear();
                  _textController.clear();
                  _currentDocumentTitle = null;
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Metadata badge row
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.neutralPillFill,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$wordCount words · $charCount chars',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          // Optional Image Preview Thumbnail
          if (lastResult?.imagePath != null &&
              File(lastResult!.imagePath!).existsSync()) ...[
            const SizedBox(height: 12),
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(lastResult.imagePath!),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: AppTheme.cardBorder),
          const SizedBox(height: 10),

          // Scrollable editable text box
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.neutralPillFill.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: TextField(
              controller: _textController,
              maxLines: null,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: AppTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiActionsArea(bool hasText) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome, size: 16, color: AppTheme.primaryAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'What would you like to do?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Instantly route recognized notes and questions to Pal Brain on-device AI.',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 14),

          // 3 AI Action Buttons
          _buildAiActionTile(
            icon: Icons.calculate_outlined,
            title: 'Explain & Solve',
            subtitle: 'Step-by-step explanation with proofs & formulas',
            isEnabled: hasText,
            isPrimary: true,
            onTap: () => _handleAiAction('explain'),
          ),
          const SizedBox(height: 8),
          _buildAiActionTile(
            icon: Icons.summarize_outlined,
            title: 'Summarize',
            subtitle: 'Create concise study notes and key takeaways',
            isEnabled: hasText,
            isPrimary: false,
            onTap: () => _handleAiAction('summarize'),
          ),
          const SizedBox(height: 8),
          _buildAiActionTile(
            icon: Icons.quiz_outlined,
            title: 'Create Quiz',
            subtitle: 'Generate 3 exam practice questions with answers',
            isEnabled: hasText,
            isPrimary: false,
            onTap: () => _handleAiAction('quiz'),
          ),
          const SizedBox(height: 8),
          _buildAiActionTile(
            icon: Icons.folder_special_outlined,
            title: 'Save to Study Vault',
            subtitle: 'Index into Subject & Unit, or save to Unorganized',
            isEnabled: hasText,
            isPrimary: false,
            onTap: _showSaveToVaultDialog,
          ),
        ],
      ),
    );
  }

  static String _formatShortDate(DateTime dt) {
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
    return '${months[dt.month - 1]} ${dt.day}';
  }

  void _handleAiAction(String actionType) {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No readable text was found.'),
          backgroundColor: AppTheme.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final docTitle = (_currentDocumentTitle != null &&
            _currentDocumentTitle!.trim().isNotEmpty)
        ? _currentDocumentTitle!.trim()
        : 'Notes · ${_formatShortDate(now)}';

    final docId = 'ocr_${now.millisecondsSinceEpoch}';

    final ocrContext = OcrDocumentContext(
      id: docId,
      title: docTitle,
      text: text,
      pageCount: 1,
      actionType: actionType,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PalBrainScreen(
          ocrDocument: ocrContext,
        ),
      ),
    );
  }

  void _showSaveToVaultDialog() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No recognized text to save.'),
          backgroundColor: AppTheme.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SaveToVaultDialog(
        text: text,
        initialTitle: _currentDocumentTitle,
      ),
    );
  }

  Widget _buildAiActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isEnabled,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isEnabled
                ? (isPrimary ? AppTheme.highlightBg : AppTheme.cardSurface)
                : AppTheme.neutralPillFill.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isEnabled
                  ? (isPrimary
                      ? AppTheme.primaryAccent.withValues(alpha: 0.4)
                      : AppTheme.cardBorder)
                  : AppTheme.cardBorder.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? AppTheme.primaryAccent.withValues(alpha: 0.15)
                      : AppTheme.neutralPillFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isEnabled
                      ? AppTheme.primaryAccent
                      : AppTheme.textInactive,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isEnabled
                            ? AppTheme.textPrimary
                            : AppTheme.textInactive,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isEnabled
                            ? AppTheme.textSecondary
                            : AppTheme.textInactive,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 13,
                color: isEnabled
                    ? (isPrimary
                        ? AppTheme.primaryAccent
                        : AppTheme.textSecondary)
                    : AppTheme.textInactive,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentScansArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.history, size: 16, color: AppTheme.primaryAccent),
              SizedBox(width: 8),
              Text(
                'Recent Scans',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentScans.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 16, color: AppTheme.cardBorder),
            itemBuilder: (context, index) {
              final scan = _recentScans[index];
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _loadRecentScan(scan),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.neutralPillFill,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          size: 18,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              scan['title']!,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              scan['meta']!,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppTheme.textInactive,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
