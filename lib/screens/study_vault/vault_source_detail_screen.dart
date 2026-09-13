import 'package:flutter/material.dart';
import '../../models/extracted_page_content.dart';
import '../../models/rag_scope.dart';
import '../../models/vault_item.dart';
import '../../services/conversation_service.dart';
import '../../services/rag_service.dart';
import '../../theme/app_theme.dart';
import '../ocr_document_review_screen.dart';
import 'vault_breadcrumbs.dart';

class VaultSourceDetailScreen extends StatefulWidget {
  final VaultSubject? subject;
  final VaultUnit? unit;
  final VaultDocument source;
  final Function(int,
      {String? initialQuery,
      String? filterSubject,
      String? filterUnit}) onNavigateToBrain;

  const VaultSourceDetailScreen({
    super.key,
    this.subject,
    this.unit,
    required this.source,
    required this.onNavigateToBrain,
  });

  @override
  State<VaultSourceDetailScreen> createState() =>
      _VaultSourceDetailScreenState();
}

class _VaultSourceDetailScreenState extends State<VaultSourceDetailScreen> {
  final RagService _ragService = RagService.instance;
  final ConversationService _conversationService = ConversationService.instance;

  late VaultDocument _source;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _ragService.addListener(_onRagUpdate);
  }

  @override
  void dispose() {
    _ragService.removeListener(_onRagUpdate);
    super.dispose();
  }

  void _onRagUpdate() {
    if (mounted) setState(() {});
  }

  void _openChatWithPrompt(String prompt, {String? title}) async {
    final subName = widget.subject?.name ?? _source.subjectName;
    final uName = widget.unit?.name ?? _source.unitName;

    final RagScope scope = _source.isAudio
        ? RagScope.lecture(
            lectureId: _source.id,
            lectureTitle: _source.name,
            subjectId: widget.subject?.id ?? _source.subjectId,
            subjectName: subName,
            unitId: widget.unit?.id ?? _source.unitId,
            unitName: uName,
          )
        : RagScope.document(
            documentId: _source.id,
            documentName: _source.name,
            subjectId: widget.subject?.id ?? _source.subjectId,
            subjectName: subName,
            unitId: widget.unit?.id ?? _source.unitId,
            unitName: uName,
          );

    await _conversationService.createConversation(
      initialTitle: title ?? _source.name,
      initialRagScope: scope.displayLabel,
      documentId: _source.id,
      documentTitle: _source.name,
      sourceType: _source.sourceType,
      ragScope: scope,
      ragScopeType: scope.type.name,
      subjectId: widget.subject?.id ?? _source.subjectId,
      subjectName: subName,
      unitId: widget.unit?.id ?? _source.unitId,
      unitName: uName,
    );

    if (!mounted) return;
    widget.onNavigateToBrain(
      2, // Brain chat tab
      initialQuery: prompt,
      filterSubject: subName,
      filterUnit: uName,
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text(
          'Delete Source?',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${_source.name}"? All associated indexed notes and search data will be permanently removed.',
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
              _ragService.deleteSource(sourceId: _source.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.cardSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  content: Text('Deleted "${_source.name}"',
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

  void _showPageTextModal(int pageNumber, String text) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.75,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Page $pageNumber — ${_source.name}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      size: 18, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(color: AppTheme.cardBorder),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: AppTheme.textPrimary,
                  ),
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
    final pages = _ragService.getExtractedPages(_source.name);
    final isAudio = _source.isAudio;
    final isHandwritten = _source.isHandwritten;

    IconData typeIcon = Icons.picture_as_pdf;
    Color iconColor = AppTheme.primaryAccent;
    if (isAudio) {
      typeIcon = Icons.mic;
      iconColor = AppTheme.trustPillText;
    } else if (isHandwritten) {
      typeIcon = Icons.draw_outlined;
      iconColor = AppTheme.detectedPillText;
    } else if (_source.hasOcr) {
      typeIcon = Icons.document_scanner;
      iconColor = AppTheme.detectedPillText;
    }

    final breadcrumbs = [
      BreadcrumbItem(
        label: 'Study Vault',
        onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
      ),
      if (widget.subject != null)
        BreadcrumbItem(
          label: widget.subject!.name,
          onTap: () {
            Navigator.of(context).pop();
            if (widget.unit != null) Navigator.of(context).pop();
          },
        ),
      if (widget.unit != null)
        BreadcrumbItem(
          label: widget.unit!.name,
          onTap: () => Navigator.of(context).pop(),
        ),
      BreadcrumbItem(label: _source.name),
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
        title: Text(
          _source.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 20, color: AppTheme.textSecondary),
            tooltip: 'Delete Source',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: ListView(
        children: [
          VaultBreadcrumbs(items: breadcrumbs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(typeIcon, size: 28, color: iconColor),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _source.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.subject?.name ?? _source.subjectName} · ${widget.unit?.name ?? _source.unitName}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.neutralPillFill,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _source.typeLabel,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                if (_source.formattedDuration.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.trustPillFill,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _source.formattedDuration,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.trustPillText,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.detectedPillFill,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${_source.pageCount} pages',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.detectedPillText,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Primary Action Buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.auto_awesome,
                          size: 14, color: AppTheme.primaryAccent),
                      label: const Text('Ask Pal'),
                      onPressed: () => _openChatWithPrompt(
                        'What are the core ideas and principles covered in ${_source.name}?',
                        title: 'Ask Pal: ${_source.name}',
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.summarize_outlined,
                          size: 14, color: AppTheme.detectedPillText),
                      label: const Text('Summarize'),
                      onPressed: () => _openChatWithPrompt(
                        'Please provide an executive summary and key takeaways of ${_source.name}.',
                        title: 'Summary: ${_source.name}',
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.quiz_outlined,
                          size: 14, color: AppTheme.trustPillText),
                      label: const Text('Create Quiz'),
                      onPressed: () => _openChatWithPrompt(
                        'Generate 5 practice exam questions with detailed answers based strictly on ${_source.name}.',
                        title: 'Quiz: ${_source.name}',
                      ),
                    ),
                    if (!isAudio)
                      ActionChip(
                        avatar: const Icon(Icons.edit_note,
                            size: 14, color: AppTheme.primaryAccent),
                        label: const Text('Review Text'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OcrDocumentReviewScreen(
                                document: _source,
                                onNavigateToBrain: widget.onNavigateToBrain,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // Pages or Transcript Section
                Text(
                  isAudio ? 'TRANSCRIPT SECTIONS' : 'DOCUMENT PAGES',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),

                if (pages.isNotEmpty)
                  ...pages.map((p) => _buildPageItem(p))
                else
                  _buildPlaceholderPages(),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageItem(ExtractedPageContent page) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.neutralPillFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'P${page.pageNumber}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        title: Text(
          'Page ${page.pageNumber}',
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          page.text.trim().replaceAll(RegExp(r'\s+'), ' '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right,
            size: 16, color: AppTheme.textSecondary),
        onTap: () => _showPageTextModal(page.pageNumber, page.text),
      ),
    );
  }

  Widget _buildPlaceholderPages() {
    final count = _source.pageCount > 0 ? _source.pageCount : 1;
    return Column(
      children: List.generate(count, (index) {
        final pageNum = index + 1;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.neutralPillFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'P$pageNum',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            title: Text(
              'Page $pageNum',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            subtitle: const Text(
              'Tap to view text content',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            trailing: const Icon(Icons.chevron_right,
                size: 16, color: AppTheme.textSecondary),
            onTap: () => _showPageTextModal(pageNum,
                'Content for page $pageNum of ${_source.name}.\n\nIndexed in on-device RAG knowledge base for Pal.'),
          ),
        );
      }),
    );
  }
}
