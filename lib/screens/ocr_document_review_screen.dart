import 'dart:io';
import 'package:flutter/material.dart';
import '../models/extracted_page_content.dart';
import '../models/vault_item.dart';
import '../services/rag_service.dart';
import '../theme/app_theme.dart';

class OcrDocumentReviewScreen extends StatefulWidget {
  final VaultDocument document;
  final int initialPageNumber;
  final void Function(int tabIndex,
      {String? initialQuery,
      String? filterSubject,
      String? filterUnit})? onNavigateToBrain;

  const OcrDocumentReviewScreen({
    super.key,
    required this.document,
    this.initialPageNumber = 1,
    this.onNavigateToBrain,
  });

  @override
  State<OcrDocumentReviewScreen> createState() =>
      _OcrDocumentReviewScreenState();
}

class _OcrDocumentReviewScreenState extends State<OcrDocumentReviewScreen> {
  final RagService _ragService = RagService.instance;
  late int _selectedPageIndex;
  late TextEditingController _textController;
  bool _isSaving = false;
  bool _isReprocessing = false;
  bool _showImagePreview = false;

  @override
  void initState() {
    super.initState();
    _selectedPageIndex = (widget.initialPageNumber - 1).clamp(0, 9999);
    _textController = TextEditingController();
    _updateTextForCurrentPage();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  List<ExtractedPageContent> _getPages() {
    final pages = _ragService.getExtractedPages(widget.document.name);
    if (pages.isNotEmpty) return pages;

    // Fallback placeholder if opened before pages populated
    return List.generate(
      widget.document.pageCount,
      (i) => ExtractedPageContent(
        documentName: widget.document.name,
        pageNumber: i + 1,
        text: 'Page ${i + 1} content',
        extractionType: ExtractionType.nativePdf,
      ),
    );
  }

  void _updateTextForCurrentPage() {
    final pages = _getPages();
    if (_selectedPageIndex >= 0 && _selectedPageIndex < pages.length) {
      _textController.text = pages[_selectedPageIndex].text;
    }
  }

  Future<void> _saveCurrentPageCorrection() async {
    final pages = _getPages();
    if (_selectedPageIndex < 0 || _selectedPageIndex >= pages.length) return;
    final page = pages[_selectedPageIndex];

    setState(() => _isSaving = true);
    await _ragService.reindexPageText(
      documentName: widget.document.name,
      pageNumber: page.pageNumber,
      newText: _textController.text,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

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
                'Page ${page.pageNumber} updated! RAG index synchronized.',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reprocessCurrentPage() async {
    final pages = _getPages();
    if (_selectedPageIndex < 0 || _selectedPageIndex >= pages.length) return;
    final page = pages[_selectedPageIndex];

    setState(() => _isReprocessing = true);
    final updated = await _ragService.reprocessPageWithOcr(
      documentName: widget.document.name,
      pageNumber: page.pageNumber,
    );
    if (!mounted) return;
    setState(() => _isReprocessing = false);

    if (updated != null) {
      _textController.text = updated.text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.cardSurface,
          content: Text(
            'Page ${page.pageNumber} reprocessed via on-device OCR!',
            style: const TextStyle(color: AppTheme.textPrimary),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _getPages();
    final currentPage = (_selectedPageIndex < pages.length)
        ? pages[_selectedPageIndex]
        : pages.first;

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.document.name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                const Icon(Icons.security,
                    size: 11, color: AppTheme.trustPillText),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    '100% On-Device OCR • Knowledge Base Review',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.trustPillText,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryAccent),
            tooltip: 'Reprocess Page with OCR',
            onPressed: _isReprocessing ? null : _reprocessCurrentPage,
          ),
        ],
      ),
      body: Column(
        children: [
          // Horizontal Page Carousel Selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppTheme.neutralPillFill.withValues(alpha: 0.35),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(pages.length, (idx) {
                  final p = pages[idx];
                  final isSelected = idx == _selectedPageIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: isSelected,
                      selectedColor:
                          AppTheme.primaryAccent.withValues(alpha: 0.2),
                      backgroundColor: AppTheme.cardSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected
                              ? AppTheme.primaryAccent
                              : (p.isLowQuality
                                  ? Colors.orange.withValues(alpha: 0.6)
                                  : AppTheme.cardBorder),
                        ),
                      ),
                      avatar: Icon(
                        p.extractionType == ExtractionType.nativePdf
                            ? Icons.article_outlined
                            : (p.extractionType == ExtractionType.handwrittenOcr
                                ? Icons.draw_outlined
                                : (p.extractionType ==
                                        ExtractionType.userCorrected
                                    ? Icons.check_circle_outline
                                    : Icons.document_scanner_outlined)),
                        size: 14,
                        color: isSelected
                            ? AppTheme.primaryAccent
                            : AppTheme.textSecondary,
                      ),
                      label: Text(
                        'p.${p.pageNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primaryAccent
                              : AppTheme.textPrimary,
                        ),
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _selectedPageIndex = idx;
                            _updateTextForCurrentPage();
                          });
                        }
                      },
                    ),
                  );
                }),
              ),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Page Header with Type Badge and Quality indicator
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: currentPage.extractionType.isOcr
                            ? AppTheme.trustPillFill
                            : AppTheme.detectedPillFill,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            currentPage.extractionType.isOcr
                                ? Icons.document_scanner
                                : Icons.text_snippet,
                            size: 13,
                            color: currentPage.extractionType.isOcr
                                ? AppTheme.trustPillText
                                : AppTheme.detectedPillText,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            currentPage.extractionType.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: currentPage.extractionType.isOcr
                                  ? AppTheme.trustPillText
                                  : AppTheme.detectedPillText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.neutralPillFill,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Text(
                        'Confidence: ${(currentPage.confidence * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (currentPage.imagePath != null &&
                        File(currentPage.imagePath!).existsSync())
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showImagePreview = !_showImagePreview;
                          });
                        },
                        icon: Icon(
                          _showImagePreview
                              ? Icons.visibility_off_outlined
                              : Icons.image_outlined,
                          size: 14,
                          color: AppTheme.primaryAccent,
                        ),
                        label: Text(
                          _showImagePreview ? 'Hide Scan' : 'View Scan',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryAccent,
                          ),
                        ),
                      ),
                  ],
                ),

                // Low Quality / Handwriting Warning
                if (currentPage.isLowQuality ||
                    currentPage.warningMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.amber, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            currentPage.warningMessage ??
                                'Handwritten text detected. Check for any unclear symbols and edit directly below.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textPrimary,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Optional Image Preview of Rendered Scan
                if (_showImagePreview &&
                    currentPage.imagePath != null &&
                    File(currentPage.imagePath!).existsSync()) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.cardBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: Image.file(
                        File(currentPage.imagePath!),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Extracted Text Card / Editor
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'EXTRACTED TEXT (RAG GROUNDING)',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            '${_textController.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} Words',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textInactive,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _textController,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText:
                              'No text extracted on this page yet. Type or paste your notes here...',
                          hintStyle: TextStyle(
                            color: AppTheme.textInactive,
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed:
                            _isSaving ? null : _saveCurrentPageCorrection,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: Text(
                          _isSaving
                              ? 'Saving...'
                              : 'Save Correction & Sync RAG',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (widget.onNavigateToBrain != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryAccent,
                      side: const BorderSide(color: AppTheme.cardBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onNavigateToBrain!(
                        2,
                        initialQuery:
                            'Explain the concepts from ${widget.document.name} page ${currentPage.pageNumber}',
                        filterSubject: widget.document.subject,
                        filterUnit: widget.document.unit,
                      );
                    },
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: Text(
                      'Ask Pal About Page ${currentPage.pageNumber}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
