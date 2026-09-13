import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/rag_scope.dart';
import '../../models/vault_item.dart';
import '../../services/conversation_service.dart';
import '../../services/rag_service.dart';
import '../../theme/app_theme.dart';
import '../ocr_scanner_screen.dart';
import 'vault_breadcrumbs.dart';
import 'vault_source_detail_screen.dart';

class VaultUnitScreen extends StatefulWidget {
  final VaultSubject subject;
  final VaultUnit unit;
  final Function(int,
      {String? initialQuery,
      String? filterSubject,
      String? filterUnit}) onNavigateToBrain;

  const VaultUnitScreen({
    super.key,
    required this.subject,
    required this.unit,
    required this.onNavigateToBrain,
  });

  @override
  State<VaultUnitScreen> createState() => _VaultUnitScreenState();
}

class _VaultUnitScreenState extends State<VaultUnitScreen> {
  final RagService _ragService = RagService.instance;
  final ConversationService _conversationService = ConversationService.instance;

  late VaultSubject _subject;
  late VaultUnit _unit;

  @override
  void initState() {
    super.initState();
    _subject = widget.subject;
    _unit = widget.unit;
    _ragService.addListener(_onRagUpdate);
  }

  @override
  void dispose() {
    _ragService.removeListener(_onRagUpdate);
    super.dispose();
  }

  void _onRagUpdate() {
    if (!mounted) return;
    final s = _ragService.subjects.firstWhere(
      (sub) => sub.id == _subject.id,
      orElse: () => _subject,
    );
    final u = s.units.firstWhere(
      (un) => un.id == _unit.id,
      orElse: () => _unit,
    );
    setState(() {
      _subject = s;
      _unit = u;
    });
  }

  void _openChatWithPrompt(String prompt, {String? title}) async {
    final scope = RagScope.subjectUnit(
      subjectName: _subject.name,
      subjectId: _subject.id,
      unitName: _unit.name,
      unitId: _unit.id,
    );

    await _conversationService.createConversation(
      initialTitle: title ?? '${_subject.name} · ${_unit.name}',
      initialRagScope: scope.displayLabel,
      subjectId: _subject.id,
      subjectName: _subject.name,
      unitId: _unit.id,
      unitName: _unit.name,
      ragScopeType: scope.type.name,
      ragScope: scope,
    );

    if (!mounted) return;
    widget.onNavigateToBrain(
      2, // Brain chat tab
      initialQuery: prompt,
      filterSubject: _subject.name,
      filterUnit: _unit.name,
    );
  }

  Future<void> _pickAndIndexPdf() async {
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
                ],
              ),
            );
          },
        ),
      );

      try {
        await _ragService.indexHybridPdfFile(
          filePath: path,
          fileName: name,
          subjectName: _subject.name,
          unitName: _unit.name,
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
              content: Text(
                'Added "$name" to ${_unit.name}!',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
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
              content: Text('Failed to import PDF: $e'),
            ),
          );
        }
      }
    }
  }

  void _showAddSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Text(
                'Add Study Material to ${_unit.name}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.detectedPillFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.upload_file,
                      color: AppTheme.primaryAccent, size: 22),
                ),
                title: const Text('Upload PDF Notes',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600)),
                subtitle: const Text('Native text & hybrid OCR processing',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndIndexPdf();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.trustPillFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.document_scanner,
                      color: AppTheme.trustPillText, size: 22),
                ),
                title: const Text('Scan Handwritten / Textbook',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600)),
                subtitle: const Text('Capture page photo with on-device OCR',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OcrScannerScreen(
                        onNavigateToBrain: widget.onNavigateToBrain,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteUnit() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text(
          'Delete Unit?',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${_unit.name}" from ${_subject.name}? This will remove ${_unit.documents.length} sources and their indexed notes.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
              _ragService.deleteUnit(_subject.id, _unit.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.cardSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  content: Text('Deleted "${_unit.name}"',
                      style: const TextStyle(color: AppTheme.textPrimary)),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSource(VaultDocument doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text('Delete Source?',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete "${doc.name}"?',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
              _ragService.deleteSource(sourceId: doc.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.cardSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  content: Text('Deleted "${doc.name}"',
                      style: const TextStyle(color: AppTheme.textPrimary)),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final breadcrumbs = [
      BreadcrumbItem(
        label: 'Study Vault',
        onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
      ),
      BreadcrumbItem(
        label: _subject.name,
        onTap: () => Navigator.of(context).pop(),
      ),
      BreadcrumbItem(label: _unit.name),
    ];

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _unit.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_subject.name} · ${_unit.documents.length} Sources',
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 20, color: AppTheme.textSecondary),
            tooltip: 'Delete Unit',
            onPressed: _confirmDeleteUnit,
          ),
        ],
      ),
      body: ListView(
        children: [
          VaultBreadcrumbs(items: breadcrumbs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Action Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.add,
                          size: 14, color: AppTheme.primaryAccent),
                      label: const Text('Add Source'),
                      onPressed: _showAddSourcePicker,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.auto_awesome,
                          size: 14, color: AppTheme.primaryAccent),
                      label: const Text('Ask Pal'),
                      onPressed: () => _openChatWithPrompt(
                        'Explain the core principles and critical concepts in ${_unit.name}.',
                        title: '${_subject.name} · ${_unit.name}',
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.summarize_outlined,
                          size: 14, color: AppTheme.detectedPillText),
                      label: const Text('Summarize Unit'),
                      onPressed: () => _openChatWithPrompt(
                        'Provide a comprehensive summary of ${_unit.name} with key takeaways and definitions.',
                        title: 'Summary: ${_unit.name}',
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.quiz_outlined,
                          size: 14, color: AppTheme.trustPillText),
                      label: const Text('Quiz Me'),
                      onPressed: () => _openChatWithPrompt(
                        'Generate 5 practice exam questions with detailed answers based on ${_unit.name}.',
                        title: 'Quiz: ${_unit.name}',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Text(
                  'SOURCES (${_unit.documents.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.textSecondary,
                  ),
                ),

                const SizedBox(height: 10),

                if (_unit.documents.isEmpty)
                  _buildEmptySourcesState()
                else
                  ..._unit.documents.map((doc) => _buildSourceItem(doc)),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceItem(VaultDocument doc) {
    IconData icon = Icons.picture_as_pdf;
    Color iconColor = AppTheme.detectedPillText;
    Color bgColor = AppTheme.detectedPillFill;

    if (doc.isAudio) {
      icon = Icons.mic;
      iconColor = AppTheme.trustPillText;
      bgColor = AppTheme.trustPillFill;
    } else if (doc.isHandwritten) {
      icon = Icons.draw_outlined;
      iconColor = AppTheme.primaryAccent;
      bgColor = AppTheme.primaryAccent.withValues(alpha: 0.12);
    } else if (doc.hasOcr) {
      icon = Icons.document_scanner;
      iconColor = AppTheme.trustPillText;
      bgColor = AppTheme.trustPillFill;
    }

    final metaText = doc.isAudio
        ? (doc.formattedDuration.isNotEmpty
            ? doc.formattedDuration
            : 'Audio Lecture')
        : '${doc.pageCount} pages';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        title: Text(
          doc.name,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(
              metaText,
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: AppTheme.neutralPillFill,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                doc.typeLabel,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: AppTheme.textSecondary),
              tooltip: 'Delete Source',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _confirmDeleteSource(doc),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppTheme.textSecondary),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VaultSourceDetailScreen(
                subject: _subject,
                unit: _unit,
                source: doc,
                onNavigateToBrain: widget.onNavigateToBrain,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptySourcesState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Icon(Icons.folder_open_outlined,
              size: 40, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          const Text(
            'No study material here yet.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Upload PDF notes or scan handwritten pages.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _showAddSourcePicker,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Source'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.darkSurface,
              foregroundColor: AppTheme.canvasBg,
            ),
          ),
        ],
      ),
    );
  }
}
