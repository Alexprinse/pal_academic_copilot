import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/extracted_page_content.dart';
import '../models/vault_item.dart';
import 'ocr_service.dart';
import 'pdf_page_renderer_service.dart';

class RagService extends ChangeNotifier {
  static final RagService instance = RagService._();
  RagService._();

  final List<VaultSubject> _subjects = [];
  List<VaultSubject> get subjects => _subjects;

  final List<TextChunk> _allChunks = [];
  List<TextChunk> get allChunks => _allChunks;

  final Map<String, List<ExtractedPageContent>> _extractedPages = {};

  final PdfPageRendererService _pdfRenderer = PdfPageRendererService();
  final OcrService _ocrService = OcrService.instance;

  bool _isIndexing = false;
  bool get isIndexing => _isIndexing;

  int get totalIndexedChunks => _allChunks.length;

  List<ExtractedPageContent> getExtractedPages(String docName) {
    return List.unmodifiable(_extractedPages[docName] ?? []);
  }

  Future<void> init() async {
    await _loadPageCache();
    if (_subjects.isEmpty) {
      _populateSeedData();
    }
  }

  void addSubject(String subjectName,
      {String iconCode = 'school', List<String>? initialUnits}) {
    final cleanName = subjectName.trim();
    if (cleanName.isEmpty) return;

    final existing = _subjects.any(
      (s) => s.name.toLowerCase() == cleanName.toLowerCase(),
    );
    if (existing) return;

    final units = <VaultUnit>[];
    if (initialUnits != null && initialUnits.isNotEmpty) {
      for (var i = 0; i < initialUnits.length; i++) {
        final uName = initialUnits[i].trim();
        if (uName.isNotEmpty) {
          units.add(VaultUnit(
            id: 'unit_${DateTime.now().millisecondsSinceEpoch}_$i',
            name: uName,
            subjectName: cleanName,
          ));
        }
      }
    } else {
      units.add(VaultUnit(
        id: 'unit_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Unit 1: Introduction & Fundamentals',
        subjectName: cleanName,
      ));
    }

    _subjects.add(VaultSubject(
      name: cleanName,
      iconCode: iconCode,
      units: units,
    ));
    notifyListeners();
  }

  void addUnit(String subjectName, String unitName) {
    final cleanUnit = unitName.trim();
    if (cleanUnit.isEmpty) return;

    final subject = _subjects.firstWhere(
      (s) => s.name.toLowerCase() == subjectName.trim().toLowerCase(),
      orElse: () {
        final newSub =
            VaultSubject(name: subjectName.trim(), iconCode: 'school');
        _subjects.add(newSub);
        return newSub;
      },
    );

    final exists = subject.units.any(
      (u) => u.name.toLowerCase() == cleanUnit.toLowerCase(),
    );
    if (!exists) {
      subject.units.add(VaultUnit(
        id: 'unit_${DateTime.now().millisecondsSinceEpoch}',
        name: cleanUnit,
        subjectName: subject.name,
      ));
      notifyListeners();
    }
  }

  void _populateSeedData() {
    // Seed Subject 1: Operating Systems
    final osUnit1 = VaultUnit(
      id: 'os-unit-1',
      name: 'Unit 1: Process Synchronization & Concurrency',
      subjectName: 'Operating Systems',
    );
    final osUnit2 = VaultUnit(
      id: 'os-unit-2',
      name: 'Unit 2: CPU Scheduling & Deadlocks',
      subjectName: 'Operating Systems',
    );

    final osSubject = VaultSubject(
      name: 'Operating Systems',
      iconCode: 'computer',
      units: [osUnit1, osUnit2],
    );

    // Seed Subject 2: Engineering Physics
    final physUnit1 = VaultUnit(
      id: 'phys-unit-1',
      name: 'Unit 1: Quantum Mechanics & Wave Optics',
      subjectName: 'Engineering Physics',
    );
    final physSubject = VaultSubject(
      name: 'Engineering Physics',
      iconCode: 'science',
      units: [physUnit1],
    );

    // Seed Subject 3: Discrete Mathematics
    final mathUnit1 = VaultUnit(
      id: 'math-unit-1',
      name: 'Unit 1: Graph Theory & Recurrence Relations',
      subjectName: 'Discrete Mathematics',
    );
    final mathSubject = VaultSubject(
      name: 'Discrete Mathematics',
      iconCode: 'functions',
      units: [mathUnit1],
    );

    _subjects.addAll([osSubject, physSubject, mathSubject]);

    // Document 1: Digital PDF (Silberschatz OS Ch5)
    final osDoc1 = VaultDocument(
      id: 'doc-os-1',
      name: 'Silberschatz_OS_Ch5_Sync.pdf',
      path: '/vault/Silberschatz_OS_Ch5_Sync.pdf',
      subject: 'Operating Systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      chunkCount: 3,
      pageCount: 3,
      addedAt: DateTime.now().subtract(const Duration(days: 3)),
      nativePageCount: 3,
      ocrPageCount: 0,
    );
    osUnit1.documents.add(osDoc1);

    const doc1Page1Text =
        'Process Synchronization deals with mechanisms ensuring orderly execution of cooperating processes. '
        'The Critical Section Problem requires three criteria: 1. Mutual Exclusion: If process Pi is executing in its critical section, '
        'no other processes can execute in their critical sections. 2. Progress: If no process is executing in its critical section and some '
        'processes wish to enter, selection cannot be postponed indefinitely. 3. Bounded Waiting: There must be a bound on the number of times '
        'other processes are allowed to enter their critical sections after a process has made a request to enter.';

    const doc1Page2Text =
        'Peterson\'s Solution is a classic software-based solution to the critical-section problem for two processes. '
        'It uses two shared variables: int turn; boolean flag[2]; '
        'The variable turn indicates whose turn it is to enter the critical section. The flag array is used to indicate '
        'if a process is ready to enter. Peterson\'s algorithm satisfies mutual exclusion, progress, and bounded waiting requirements '
        'on single-core architectures, though modern multi-threaded architectures require memory barriers or atomic hardware instructions '
        'like Test-and-Set and Compare-and-Swap (CAS).';

    const doc1Page3Text =
        'Semaphores are synchronization tools introduced by Dijkstra. A semaphore S is an integer variable accessed only through '
        'two standard atomic operations: wait() and signal(), historically called P() and V(). '
        'A counting semaphore can range over an unrestricted domain, whereas a binary semaphore (mutex lock) ranges only between 0 and 1. '
        'Spinlocks avoid context switches but cause busy waiting, wasting CPU cycles unless wait times are very short.';

    _indexRawText(
      subject: 'Operating Systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      docName: 'Silberschatz_OS_Ch5_Sync.pdf',
      pageNumber: 1,
      text: doc1Page1Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );
    _indexRawText(
      subject: 'Operating Systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      docName: 'Silberschatz_OS_Ch5_Sync.pdf',
      pageNumber: 2,
      text: doc1Page2Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );
    _indexRawText(
      subject: 'Operating Systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      docName: 'Silberschatz_OS_Ch5_Sync.pdf',
      pageNumber: 3,
      text: doc1Page3Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );

    _extractedPages['Silberschatz_OS_Ch5_Sync.pdf'] = [
      ExtractedPageContent(
        documentName: 'Silberschatz_OS_Ch5_Sync.pdf',
        pageNumber: 1,
        text: doc1Page1Text,
        extractionType: ExtractionType.nativePdf,
      ),
      ExtractedPageContent(
        documentName: 'Silberschatz_OS_Ch5_Sync.pdf',
        pageNumber: 2,
        text: doc1Page2Text,
        extractionType: ExtractionType.nativePdf,
      ),
      ExtractedPageContent(
        documentName: 'Silberschatz_OS_Ch5_Sync.pdf',
        pageNumber: 3,
        text: doc1Page3Text,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    // Document 2: Deadlocks
    final osDoc2 = VaultDocument(
      id: 'doc-os-2',
      name: 'Silberschatz_OS_Ch7_Deadlocks.pdf',
      path: '/vault/Silberschatz_OS_Ch7_Deadlocks.pdf',
      subject: 'Operating Systems',
      unit: 'Unit 2: CPU Scheduling & Deadlocks',
      chunkCount: 1,
      pageCount: 1,
      addedAt: DateTime.now().subtract(const Duration(days: 2)),
      nativePageCount: 1,
      ocrPageCount: 0,
    );
    osUnit2.documents.add(osDoc2);

    const doc2Page1Text =
        'A deadlock occurs when a set of blocked processes each holding a resource and waiting to acquire a resource held by another process. '
        'Four Coffman conditions must hold simultaneously for deadlock: 1. Mutual Exclusion, 2. Hold and Wait, '
        '3. No Preemption, 4. Circular Wait. Dijkstra\'s Banker\'s Algorithm is used for deadlock avoidance in multi-instance resource systems.';

    _indexRawText(
      subject: 'Operating Systems',
      unit: 'Unit 2: CPU Scheduling & Deadlocks',
      docName: 'Silberschatz_OS_Ch7_Deadlocks.pdf',
      pageNumber: 1,
      text: doc2Page1Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );

    _extractedPages['Silberschatz_OS_Ch7_Deadlocks.pdf'] = [
      ExtractedPageContent(
        documentName: 'Silberschatz_OS_Ch7_Deadlocks.pdf',
        pageNumber: 1,
        text: doc2Page1Text,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    // Document 3: Handwritten Lecture Notes (demonstrating on-device OCR intelligence)
    final osHandwrittenDoc = VaultDocument(
      id: 'doc-os-hw-1',
      name: 'Lecture_Notes_Process_Sync_Handwritten.pdf',
      path: '/vault/Lecture_Notes_Process_Sync_Handwritten.pdf',
      subject: 'Operating Systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      chunkCount: 2,
      pageCount: 2,
      addedAt: DateTime.now().subtract(const Duration(days: 1)),
      nativePageCount: 0,
      ocrPageCount: 2,
    );
    osUnit1.documents.add(osHandwrittenDoc);

    const hwPage1Text =
        'Critical Section Problem notes from lecture: 1) Mutual Exclusion: only 1 process in CS at any time. '
        '2) Progress: if no process is in CS, who enters cannot be delayed forever. '
        '3) Bounded wait: limit on turns before waiting process gets in. Hardware support includes Atomic TAS (Test-and-Set).';

    const hwPage2Text =
        'Semaphores summary: wait(S) decrements, signal(S) increments. If S <= 0, process blocks. '
        'Classic problems: Producer-Consumer (bounded buffer), Dining Philosophers, Readers-Writers.';

    _indexRawText(
      subject: 'Operating Systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      docName: 'Lecture_Notes_Process_Sync_Handwritten.pdf',
      pageNumber: 1,
      text: hwPage1Text,
      extractionType: ExtractionType.handwrittenOcr,
      confidence: 0.82,
    );

    _indexRawText(
      subject: 'Operating Systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      docName: 'Lecture_Notes_Process_Sync_Handwritten.pdf',
      pageNumber: 2,
      text: hwPage2Text,
      extractionType: ExtractionType.handwrittenOcr,
      confidence: 0.88,
    );

    _extractedPages['Lecture_Notes_Process_Sync_Handwritten.pdf'] = [
      ExtractedPageContent(
        documentName: 'Lecture_Notes_Process_Sync_Handwritten.pdf',
        pageNumber: 1,
        text: hwPage1Text,
        extractionType: ExtractionType.handwrittenOcr,
        confidence: 0.82,
        isLowQuality: true,
        warningMessage:
            'Handwritten notes detected. Some characters were transcribed via on-device ML.',
      ),
      ExtractedPageContent(
        documentName: 'Lecture_Notes_Process_Sync_Handwritten.pdf',
        pageNumber: 2,
        text: hwPage2Text,
        extractionType: ExtractionType.handwrittenOcr,
        confidence: 0.88,
        isLowQuality: false,
      ),
    ];

    notifyListeners();
  }

  void _indexRawText({
    required String subject,
    required String unit,
    required String docName,
    required int pageNumber,
    required String text,
    ExtractionType extractionType = ExtractionType.nativePdf,
    double confidence = 1.0,
  }) {
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    const chunkSize = 250;
    const overlap = 35;

    if (words.length <= chunkSize) {
      _allChunks.add(TextChunk(
        id: '${docName}_p${pageNumber}_c0',
        subject: subject,
        unit: unit,
        documentName: docName,
        pageNumber: pageNumber,
        text: text,
        wordCount: words.length,
        extractionType: extractionType,
        confidence: confidence,
      ));
    } else {
      int start = 0;
      int chunkIdx = 0;
      while (start < words.length) {
        final end = min(start + chunkSize, words.length);
        final chunkText = words.sublist(start, end).join(' ');
        _allChunks.add(TextChunk(
          id: '${docName}_p${pageNumber}_c$chunkIdx',
          subject: subject,
          unit: unit,
          documentName: docName,
          pageNumber: pageNumber,
          text: chunkText,
          wordCount: end - start,
          extractionType: extractionType,
          confidence: confidence,
        ));
        chunkIdx++;
        if (end == words.length) break;
        start += (chunkSize - overlap);
      }
    }
  }

  /// Backward-compatible entrypoint: delegates to indexHybridPdfFile
  Future<VaultDocument> indexPdfFile({
    required String filePath,
    required String fileName,
    required String subjectName,
    required String unitName,
    void Function(int currentPage, int totalPages, String statusText)?
        onProgress,
  }) async {
    return indexHybridPdfFile(
      filePath: filePath,
      fileName: fileName,
      subjectName: subjectName,
      unitName: unitName,
      onProgress: onProgress,
    );
  }

  /// Complete On-Device Hybrid PDF Indexer:
  /// 1. Tries digital text extraction per page.
  /// 2. If < 15 words or image-only, renders page raster and runs on-device OCR.
  /// 3. Detects handwriting characteristics and flags low-confidence pages.
  /// 4. Preserves exact page boundaries for verified citations.
  Future<VaultDocument> indexHybridPdfFile({
    required String filePath,
    required String fileName,
    required String subjectName,
    required String unitName,
    void Function(int currentPage, int totalPages, String statusText)?
        onProgress,
  }) async {
    _isIndexing = true;
    notifyListeners();

    try {
      final fileBytes = await File(filePath).readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: fileBytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final int pageCount = document.pages.count;
      int createdChunks = 0;
      int nativePages = 0;
      int ocrPages = 0;
      final List<ExtractedPageContent> extractedPages = [];

      for (int i = 0; i < pageCount; i++) {
        final int pageNum = i + 1;
        onProgress?.call(
            pageNum, pageCount, 'Analyzing page $pageNum of $pageCount...');

        final String rawPageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );

        final digitalWords = rawPageText
            .split(RegExp(r'\s+'))
            .where((w) => w.trim().isNotEmpty)
            .toList();

        // Check if page has readable digital text: >= 15 coherent words
        final bool hasDigitalText = digitalWords.length >= 15 &&
            RegExp(r'[a-zA-Z]{2,}').hasMatch(rawPageText);

        if (hasDigitalText) {
          // Native digital PDF extraction
          _indexRawText(
            subject: subjectName,
            unit: unitName,
            docName: fileName,
            pageNumber: pageNum,
            text: rawPageText,
            extractionType: ExtractionType.nativePdf,
            confidence: 1.0,
          );
          createdChunks++;
          nativePages++;

          extractedPages.add(ExtractedPageContent(
            documentName: fileName,
            pageNumber: pageNum,
            text: rawPageText.trim(),
            extractionType: ExtractionType.nativePdf,
            confidence: 1.0,
            isLowQuality: false,
          ));
        } else {
          // Scanned, photographed or handwritten page - run on-device OCR fallback
          onProgress?.call(pageNum, pageCount,
              'Scanning page $pageNum with on-device OCR...');

          String? imagePath;
          try {
            imagePath =
                await _pdfRenderer.renderPdfPage(filePath, i, scale: 2.0);
          } catch (e) {
            debugPrint('[RagService] Native page render error: $e');
          }

          if (imagePath != null && File(imagePath).existsSync()) {
            final ocrResult = await _ocrService.processImageFile(imagePath);
            final ocrText = ocrResult.text.trim();

            if (ocrText.isNotEmpty) {
              final bool isHandwritten = _detectLikelyHandwritten(ocrText);
              final extType = isHandwritten
                  ? ExtractionType.handwrittenOcr
                  : ExtractionType.printedOcr;
              final conf = isHandwritten ? 0.80 : 0.95;

              _indexRawText(
                subject: subjectName,
                unit: unitName,
                docName: fileName,
                pageNumber: pageNum,
                text: ocrText,
                extractionType: extType,
                confidence: conf,
              );
              createdChunks++;
              ocrPages++;

              extractedPages.add(ExtractedPageContent(
                documentName: fileName,
                pageNumber: pageNum,
                text: ocrText,
                extractionType: extType,
                confidence: conf,
                isLowQuality: isHandwritten,
                warningMessage: isHandwritten
                    ? 'Handwritten notes detected. Some characters may need user review.'
                    : null,
                imagePath: imagePath,
              ));
            } else {
              // OCR produced no text; keep whatever raw text there was
              if (rawPageText.trim().isNotEmpty) {
                _indexRawText(
                  subject: subjectName,
                  unit: unitName,
                  docName: fileName,
                  pageNumber: pageNum,
                  text: rawPageText,
                  extractionType: ExtractionType.printedOcr,
                  confidence: 0.60,
                );
                createdChunks++;
                ocrPages++;
              }
              extractedPages.add(ExtractedPageContent(
                documentName: fileName,
                pageNumber: pageNum,
                text: rawPageText.trim(),
                extractionType: ExtractionType.printedOcr,
                confidence: 0.50,
                isLowQuality: true,
                warningMessage:
                    'Page image has low contrast or illegible handwriting.',
                imagePath: imagePath,
              ));
            }
          } else {
            // Renderer not available or failed; fallback to raw text if present
            if (rawPageText.trim().isNotEmpty) {
              _indexRawText(
                subject: subjectName,
                unit: unitName,
                docName: fileName,
                pageNumber: pageNum,
                text: rawPageText,
                extractionType: ExtractionType.nativePdf,
                confidence: 0.70,
              );
              createdChunks++;
              nativePages++;
            }
            extractedPages.add(ExtractedPageContent(
              documentName: fileName,
              pageNumber: pageNum,
              text: rawPageText.trim(),
              extractionType: ExtractionType.nativePdf,
              confidence: 0.70,
              isLowQuality: rawPageText.trim().isEmpty,
              warningMessage: rawPageText.trim().isEmpty
                  ? 'No legible text detected on this page.'
                  : null,
            ));
          }
        }
      }

      document.dispose();

      _extractedPages[fileName] = extractedPages;
      await _savePageCache();

      final vaultDoc = VaultDocument(
        id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
        name: fileName,
        path: filePath,
        subject: subjectName,
        unit: unitName,
        chunkCount: createdChunks,
        pageCount: pageCount,
        addedAt: DateTime.now(),
        ocrPageCount: ocrPages,
        nativePageCount: nativePages,
      );

      var subject = _subjects.firstWhere(
        (s) => s.name.toLowerCase() == subjectName.toLowerCase(),
        orElse: () {
          final newSub = VaultSubject(name: subjectName, iconCode: 'book');
          _subjects.add(newSub);
          return newSub;
        },
      );

      var unit = subject.units.firstWhere(
        (u) => u.name.toLowerCase() == unitName.toLowerCase(),
        orElse: () {
          final newUnit = VaultUnit(
            id: 'unit_${DateTime.now().millisecondsSinceEpoch}',
            name: unitName,
            subjectName: subjectName,
          );
          subject.units.add(newUnit);
          return newUnit;
        },
      );

      unit.documents.add(vaultDoc);
      return vaultDoc;
    } finally {
      _isIndexing = false;
      notifyListeners();
    }
  }

  bool _detectLikelyHandwritten(String text) {
    if (text.isEmpty) return false;
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return false;

    final totalChars = words.fold(0, (sum, w) => sum + w.length);
    final avgLen = totalChars / words.length;

    final nonAlpha = RegExp(r'[^a-zA-Z0-9\s]').allMatches(text).length;
    final noiseRatio = nonAlpha / text.length;

    return avgLen < 3.2 || noiseRatio > 0.16;
  }

  /// Re-indexes page text after user manual review/correction.
  /// Automatically updates in-memory BM25 chunks and cached page models.
  Future<void> reindexPageText({
    required String documentName,
    required int pageNumber,
    required String newText,
  }) async {
    VaultDocument? targetDoc;
    VaultUnit? targetUnit;
    String subjectName = '';
    String unitName = '';

    for (final s in _subjects) {
      for (final u in s.units) {
        for (final d in u.documents) {
          if (d.name == documentName) {
            targetDoc = d;
            targetUnit = u;
            subjectName = s.name;
            unitName = u.name;
            break;
          }
        }
      }
    }

    // 1. Remove previous chunks for this exact page
    _allChunks.removeWhere(
      (c) => c.documentName == documentName && c.pageNumber == pageNumber,
    );

    // 2. Re-chunk and index new text
    if (newText.trim().isNotEmpty) {
      _indexRawText(
        subject: subjectName.isNotEmpty ? subjectName : 'General',
        unit: unitName.isNotEmpty ? unitName : 'General',
        docName: documentName,
        pageNumber: pageNumber,
        text: newText.trim(),
        extractionType: ExtractionType.userCorrected,
        confidence: 1.0,
      );
    }

    // 3. Update cached ExtractedPageContent
    final pages = _extractedPages[documentName];
    if (pages != null) {
      final index = pages.indexWhere((p) => p.pageNumber == pageNumber);
      if (index != -1) {
        pages[index] = pages[index].copyWith(
          text: newText.trim(),
          extractionType: ExtractionType.userCorrected,
          confidence: 1.0,
          isLowQuality: false,
          warningMessage: null,
        );
      } else {
        pages.add(ExtractedPageContent(
          documentName: documentName,
          pageNumber: pageNumber,
          text: newText.trim(),
          extractionType: ExtractionType.userCorrected,
          confidence: 1.0,
          isLowQuality: false,
        ));
        pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
      }
    } else {
      _extractedPages[documentName] = [
        ExtractedPageContent(
          documentName: documentName,
          pageNumber: pageNumber,
          text: newText.trim(),
          extractionType: ExtractionType.userCorrected,
          confidence: 1.0,
          isLowQuality: false,
        ),
      ];
    }

    // 4. Update chunk count in document
    if (targetDoc != null && targetUnit != null) {
      final totalDocChunks =
          _allChunks.where((c) => c.documentName == documentName).length;
      final docIdx = targetUnit.documents.indexOf(targetDoc);
      if (docIdx != -1) {
        targetUnit.documents[docIdx] = VaultDocument(
          id: targetDoc.id,
          name: targetDoc.name,
          path: targetDoc.path,
          subject: targetDoc.subject,
          unit: targetDoc.unit,
          chunkCount: totalDocChunks,
          pageCount: targetDoc.pageCount,
          addedAt: targetDoc.addedAt,
          ocrPageCount: targetDoc.ocrPageCount,
          nativePageCount: targetDoc.nativePageCount,
        );
      }
    }

    await _savePageCache();
    notifyListeners();
  }

  /// Reprocesses a specific page with OCR if the user requests it.
  Future<ExtractedPageContent?> reprocessPageWithOcr({
    required String documentName,
    required int pageNumber,
  }) async {
    VaultDocument? targetDoc;
    for (final s in _subjects) {
      for (final u in s.units) {
        for (final d in u.documents) {
          if (d.name == documentName) {
            targetDoc = d;
            break;
          }
        }
      }
    }
    if (targetDoc == null) return null;

    final imagePath = await _pdfRenderer.renderPdfPage(
      targetDoc.path,
      pageNumber - 1,
      scale: 2.0,
    );
    if (imagePath == null) return null;

    final ocrResult = await _ocrService.processImageFile(imagePath);
    final newText = ocrResult.text.trim();

    await reindexPageText(
      documentName: documentName,
      pageNumber: pageNumber,
      newText: newText,
    );

    final pages = _extractedPages[documentName];
    if (pages == null) return null;
    final idx = pages.indexWhere((p) => p.pageNumber == pageNumber);
    return idx != -1 ? pages[idx] : null;
  }

  Future<File?> _getCacheFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/pal_extracted_pages.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePageCache() async {
    try {
      final file = await _getCacheFile();
      if (file == null) return;
      final Map<String, dynamic> data = {};
      for (final entry in _extractedPages.entries) {
        data[entry.key] = entry.value.map((p) => p.toMap()).toList();
      }
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('[RagService] Failed to save page cache: $e');
    }
  }

  Future<void> _loadPageCache() async {
    try {
      final file = await _getCacheFile();
      if (file == null || !file.existsSync()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final Map<String, dynamic> decoded = jsonDecode(raw);
      for (final entry in decoded.entries) {
        final list = (entry.value as List<dynamic>)
            .map((item) =>
                ExtractedPageContent.fromMap(item as Map<String, dynamic>))
            .toList();
        _extractedPages[entry.key] = list;
      }
    } catch (e) {
      debugPrint('[RagService] Failed to load page cache: $e');
    }
  }

  /// High-speed In-Memory BM25 Lexical-Semantic Search (< 5ms, 0 MB extra model RAM)
  List<ChunkMatch> search({
    required String query,
    String? filterSubject,
    String? filterUnit,
    int topK = 3,
  }) {
    if (query.trim().isEmpty || _allChunks.isEmpty) return [];

    final queryTerms = _tokenize(query);
    if (queryTerms.isEmpty) return [];

    List<TextChunk> candidateChunks = _allChunks;
    if (filterSubject != null && filterSubject != 'All Notes') {
      candidateChunks = candidateChunks
          .where((c) => c.subject.toLowerCase() == filterSubject.toLowerCase())
          .toList();
    }
    if (filterUnit != null &&
        filterUnit.isNotEmpty &&
        filterUnit != 'All Units') {
      candidateChunks = candidateChunks
          .where((c) => c.unit.toLowerCase().contains(filterUnit.toLowerCase()))
          .toList();
    }

    if (candidateChunks.isEmpty) return [];

    final int n = candidateChunks.length;
    final double totalWords =
        candidateChunks.fold(0, (sum, c) => sum + c.wordCount);
    final double avgdl = totalWords / (n > 0 ? n : 1);

    // Compute document frequency (df) for each query term in candidate set
    final Map<String, int> docFreq = {};
    for (final term in queryTerms) {
      docFreq[term] =
          candidateChunks.where((c) => _tokenize(c.text).contains(term)).length;
    }

    const double k1 = 1.2;
    const double b = 0.75;

    final List<ChunkMatch> matches = [];

    for (final chunk in candidateChunks) {
      final chunkTokens = _tokenize(chunk.text);
      final Map<String, int> termFreq = {};
      for (final t in chunkTokens) {
        termFreq[t] = (termFreq[t] ?? 0) + 1;
      }

      double score = 0.0;
      final int dl = chunk.wordCount;

      for (final term in queryTerms) {
        final tf = termFreq[term] ?? 0;
        if (tf == 0) continue;

        final df = docFreq[term] ?? 0;
        final idf = log(1.0 + (n - df + 0.5) / (df + 0.5));
        final tfComponent = (tf * (k1 + 1.0)) /
            (tf + k1 * (1.0 - b + b * (dl / (avgdl > 0 ? avgdl : 1))));

        score += idf * tfComponent;
      }

      if (score > 0.1) {
        matches.add(ChunkMatch(chunk: chunk, score: score));
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.take(topK).toList();
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2)
        .toList();
  }
}
