import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/vault_item.dart';
import '../services/rag_service.dart';
import '../theme/app_theme.dart';
import 'ocr_document_review_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _ragService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _ragService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _pickAndIndexPdf(String subjectName, String unitName) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;

      if (!mounted) return;

      int currentPage = 1;
      int totalPages = 1;
      String statusMessage = 'Analyzing document structure...';
      void Function(void Function())? updateDialogState;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (context, setDialogState) {
            updateDialogState = setDialogState;
            final progress = totalPages > 0
                ? (currentPage / totalPages).clamp(0.0, 1.0)
                : 0.0;
            return AlertDialog(
              backgroundColor: AppTheme.cardSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppTheme.cardBorder),
              ),
              title: Row(
                children: [
                  const Icon(Icons.document_scanner,
                      color: AppTheme.primaryAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Indexing "$name"',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppTheme.neutralPillFill,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryAccent),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Page $currentPage of $totalPages',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusMessage,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Icon(Icons.security,
                          size: 12, color: AppTheme.trustPillText),
                      SizedBox(width: 4),
                      Text(
                        '100% On-Device • Zero Cloud Calls',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.trustPillText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );

      try {
        final doc = await _ragService.indexHybridPdfFile(
          filePath: path,
          fileName: name,
          subjectName: subjectName,
          unitName: unitName,
          onProgress: (cur, tot, status) {
            currentPage = cur;
            totalPages = tot;
            statusMessage = status;
            updateDialogState?.call(() {});
          },
        );

        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.cardSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.cardBorder),
              ),
              content: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: AppTheme.trustPillText, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Indexed ${doc.chunkCount} chunks across ${doc.pageCount} pages (${doc.ocrPageCount} OCR)!',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'Review OCR',
                textColor: AppTheme.primaryAccent,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OcrDocumentReviewScreen(
                        document: doc,
                        onNavigateToBrain: widget.onNavigateToBrain,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade900,
              content: Text('Failed to index PDF: $e'),
            ),
          );
        }
      }
    }
  }

  void _showAddSubjectDialog() {
    final subjectCtrl = TextEditingController();
    final unitCtrl =
        TextEditingController(text: 'Unit 1: Introduction & Fundamentals');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
            const SizedBox(height: 12),
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
                  final unit = unitCtrl.text.trim();
                  if (name.isNotEmpty) {
                    _ragService.addSubject(
                      name,
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

  void _showAddUnitDialog(String subjectName) {
    final unitCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add Unit to $subjectName',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: TextField(
          controller: unitCtrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Unit 3: Memory Management',
            filled: true,
            fillColor: AppTheme.neutralPillFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.cardBorder),
            ),
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
              final unitName = unitCtrl.text.trim();
              if (unitName.isNotEmpty) {
                _ragService.addUnit(subjectName, unitName);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add Unit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              'Study Vault',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'Subject & Unit RAG Knowledge Base',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.neutralPillFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Row(
              children: [
                const Text('📚', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text(
                  '${_ragService.totalIndexedChunks} Chunks',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.neutralPillText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // RAG In-Memory Status Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.cardDecoration,
            child: const Row(
              children: [
                Icon(Icons.bolt, color: AppTheme.primaryAccent, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'In-Memory BM25 Lexical Retriever',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Zero-NDK collision, <5ms retrieval latency, 100% offline.',
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

          const SizedBox(height: 18),

          // Enrolled Subjects Header + "+ Add Subject" Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Enrolled Subjects',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              InkWell(
                onTap: _showAddSubjectDialog,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                          size: 14, color: AppTheme.detectedPillText),
                      SizedBox(width: 4),
                      Text(
                        'Add Subject',
                        style: TextStyle(
                          fontSize: 11.5,
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

          const SizedBox(height: 12),

          ..._ragService.subjects.map((subject) => _buildSubjectCard(subject)),

          const SizedBox(height: 20),

          // Large Add Subject Card button at the bottom
          InkWell(
            onTap: _showAddSubjectDialog,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
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
                      size: 20, color: AppTheme.primaryAccent),
                  SizedBox(width: 8),
                  Text(
                    'Add Another Subject',
                    style: TextStyle(
                      fontSize: 14,
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

  Widget _buildSubjectCard(VaultSubject subject) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: AppTheme.cardDecoration,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.detectedPillFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.school_outlined,
                color: AppTheme.detectedPillText, size: 20),
          ),
          title: Text(
            subject.name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: Text(
            '${subject.units.length} Units • ${subject.totalDocuments} PDFs • ${subject.totalChunks} Chunks',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          trailing: IconButton(
            icon:
                const Icon(Icons.add, size: 20, color: AppTheme.primaryAccent),
            tooltip: 'Add Unit',
            onPressed: () => _showAddUnitDialog(subject.name),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
              child: Column(
                children: [
                  ...subject.units.map((unit) => _buildUnitItem(subject, unit)),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => _showAddUnitDialog(subject.name),
                    icon: const Icon(Icons.add,
                        size: 15, color: AppTheme.primaryAccent),
                    label: Text(
                      'Add Unit to ${subject.name}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitItem(VaultSubject subject, VaultUnit unit) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.canvasBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  unit.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.upload_file_outlined,
                    size: 18, color: AppTheme.primaryAccent),
                tooltip: 'Add PDF Notes',
                onPressed: () => _pickAndIndexPdf(subject.name, unit.name),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${unit.documents.length} PDF Notes uploaded (${unit.totalChunks} Chunks indexed)',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          if (unit.documents.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...unit.documents
                .map((doc) => _buildDocumentItem(subject, unit, doc)),
          ],
          const SizedBox(height: 12),
          // Quick Action Chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                avatar: const Icon(Icons.auto_awesome,
                    size: 13, color: AppTheme.primaryAccent),
                label: const Text('Ask Pal from Unit'),
                onPressed: () {
                  widget.onNavigateToBrain(
                    2, // Ask tab
                    initialQuery:
                        'Summarize the core principles of ${unit.name}',
                    filterSubject: subject.name,
                    filterUnit: unit.name,
                  );
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.quiz_outlined,
                    size: 13, color: AppTheme.detectedPillText),
                label: const Text('Generate 3 Quiz Qs'),
                onPressed: () {
                  widget.onNavigateToBrain(
                    2, // Ask tab
                    initialQuery:
                        'Generate 3 practice exam questions with detailed answers based on ${unit.name}',
                    filterSubject: subject.name,
                    filterUnit: unit.name,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentItem(
      VaultSubject subject, VaultUnit unit, VaultDocument doc) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorder.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: doc.hasOcr
                  ? AppTheme.trustPillFill
                  : AppTheme.detectedPillFill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              doc.hasOcr ? Icons.document_scanner : Icons.picture_as_pdf,
              size: 16,
              color: doc.hasOcr
                  ? AppTheme.trustPillText
                  : AppTheme.detectedPillText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.name,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${doc.pageCount} pages • ${doc.chunkCount} chunks',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (doc.hasOcr) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.trustPillFill,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'OCR (${doc.ocrPageCount}p)',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.trustPillText,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_note,
                size: 20, color: AppTheme.primaryAccent),
            tooltip: 'Review & Edit OCR Text',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OcrDocumentReviewScreen(
                    document: doc,
                    onNavigateToBrain: widget.onNavigateToBrain,
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
