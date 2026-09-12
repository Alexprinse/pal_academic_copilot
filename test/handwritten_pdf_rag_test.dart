import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/extracted_page_content.dart';
import 'package:pal_academic_copilot/models/vault_item.dart';
import 'package:pal_academic_copilot/screens/ocr_document_review_screen.dart';
import 'package:pal_academic_copilot/services/rag_service.dart';
import 'package:pal_academic_copilot/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.iqoo.pal/pdf_renderer'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getPdfPageCount') {
          return 2;
        }
        if (methodCall.method == 'renderPdfPage') {
          return '/tmp/mock_pdf_page_${methodCall.arguments['pageIndex']}.png';
        }
        if (methodCall.method == 'cleanupPdfCache') {
          return true;
        }
        return null;
      },
    );
  });

  group('ExtractedPageContent & TextChunk Models', () {
    test('ExtractionType enum flags isOcr correctly', () {
      expect(ExtractionType.nativePdf.isOcr, isFalse);
      expect(ExtractionType.printedOcr.isOcr, isTrue);
      expect(ExtractionType.handwrittenOcr.isOcr, isTrue);
      expect(ExtractionType.userCorrected.isOcr, isTrue);

      expect(ExtractionType.nativePdf.label, 'Digital PDF');
      expect(ExtractionType.printedOcr.label, 'Printed OCR');
      expect(ExtractionType.handwrittenOcr.label, 'Handwritten OCR');
      expect(ExtractionType.userCorrected.label, 'User Corrected');
    });

    test('TextChunk preserves extractionType and isOcr flag', () {
      final nativeChunk = TextChunk(
        id: 'chunk_1',
        subject: 'OS',
        unit: 'Unit 1',
        documentName: 'textbook.pdf',
        pageNumber: 5,
        text: 'Process synchronization basics',
        wordCount: 3,
        extractionType: ExtractionType.nativePdf,
      );
      expect(nativeChunk.isOcr, isFalse);

      final ocrChunk = TextChunk(
        id: 'chunk_2',
        subject: 'OS',
        unit: 'Unit 1',
        documentName: 'notes.pdf',
        pageNumber: 7,
        text: 'Handwritten notes on semaphore wait and signal',
        wordCount: 7,
        extractionType: ExtractionType.handwrittenOcr,
        confidence: 0.85,
      );
      expect(ocrChunk.isOcr, isTrue);
      expect(ocrChunk.confidence, 0.85);

      final map = ocrChunk.toMap();
      final reconstructed = TextChunk.fromMap(map);
      expect(reconstructed.id, ocrChunk.id);
      expect(reconstructed.pageNumber, 7);
      expect(reconstructed.extractionType, ExtractionType.handwrittenOcr);
      expect(reconstructed.isOcr, isTrue);
      expect(reconstructed.confidence, 0.85);
    });

    test('VaultDocument tracks OCR vs Native page counts', () {
      final doc = VaultDocument(
        id: 'doc_1',
        name: 'Lecture_Handwritten.pdf',
        path: '/path/Lecture_Handwritten.pdf',
        subject: 'OS',
        unit: 'Unit 1',
        chunkCount: 4,
        pageCount: 4,
        addedAt: DateTime.now(),
        ocrPageCount: 3,
        nativePageCount: 1,
      );
      expect(doc.hasOcr, isTrue);
      expect(doc.ocrPageCount, 3);
      expect(doc.nativePageCount, 1);

      final map = doc.toMap();
      final parsed = VaultDocument.fromMap(map);
      expect(parsed.hasOcr, isTrue);
      expect(parsed.ocrPageCount, 3);
      expect(parsed.nativePageCount, 1);
    });

    test('ExtractedPageContent serialization and copyWith', () {
      final page = ExtractedPageContent(
        documentName: 'notes.pdf',
        pageNumber: 3,
        text: 'Original OCR text with errors',
        extractionType: ExtractionType.handwrittenOcr,
        confidence: 0.72,
        isLowQuality: true,
        warningMessage: 'Unclear cursive handwriting',
      );

      final updated = page.copyWith(
        text: 'Corrected text by student',
        extractionType: ExtractionType.userCorrected,
        confidence: 1.0,
        isLowQuality: false,
        warningMessage: null,
      );

      expect(updated.text, 'Corrected text by student');
      expect(updated.extractionType, ExtractionType.userCorrected);
      expect(updated.confidence, 1.0);
      expect(updated.isLowQuality, isFalse);
      expect(updated.warningMessage, isNull);

      final map = page.toMap();
      final fromMap = ExtractedPageContent.fromMap(map);
      expect(fromMap.pageNumber, 3);
      expect(fromMap.extractionType, ExtractionType.handwrittenOcr);
      expect(fromMap.isLowQuality, isTrue);
    });
  });

  group('RagService On-Device OCR & Hybrid Indexing', () {
    late RagService ragService;

    setUp(() async {
      ragService = RagService.instance;
      await ragService.init();
    });

    test('Seed data includes handwritten document with OCR tags', () {
      final pages = ragService
          .getExtractedPages('Lecture_Notes_Process_Sync_Handwritten.pdf');
      expect(pages.isNotEmpty, isTrue);
      expect(pages.length, 2);
      expect(pages[0].extractionType, ExtractionType.handwrittenOcr);
      expect(pages[0].pageNumber, 1);
      expect(pages[0].isLowQuality, isTrue);
    });

    test('BM25 retrieves handwritten OCR chunks with exact page citations', () {
      final results = ragService.search(
        query: 'Atomic TAS Test-and-Set hardware support',
        filterSubject: 'Operating Systems',
        topK: 3,
      );

      expect(results.isNotEmpty, isTrue);
      final topMatch = results.first;
      expect(topMatch.chunk.documentName,
          'Lecture_Notes_Process_Sync_Handwritten.pdf');
      expect(topMatch.chunk.pageNumber, 1);
      expect(topMatch.chunk.isOcr, isTrue);
      expect(topMatch.chunk.extractionType, ExtractionType.handwrittenOcr);
    });

    test('User correction via reindexPageText updates chunks and BM25 search',
        () async {
      const docName = 'Lecture_Notes_Process_Sync_Handwritten.pdf';
      const newCorrectedText =
          'SpecializedQuantumMutex: A custom synchronization primitive designed for quantum spinlocks.';

      // Re-index page 2 with corrected text
      await ragService.reindexPageText(
        documentName: docName,
        pageNumber: 2,
        newText: newCorrectedText,
      );

      // Verify cached page updated
      final pages = ragService.getExtractedPages(docName);
      final page2 = pages.firstWhere((p) => p.pageNumber == 2);
      expect(page2.text, newCorrectedText);
      expect(page2.extractionType, ExtractionType.userCorrected);
      expect(page2.isLowQuality, isFalse);

      // Verify BM25 immediately retrieves the new term
      final searchMatches = ragService.search(
        query: 'SpecializedQuantumMutex',
        filterSubject: 'Operating Systems',
      );

      expect(searchMatches.isNotEmpty, isTrue);
      expect(searchMatches.first.chunk.pageNumber, 2);
      expect(searchMatches.first.chunk.extractionType,
          ExtractionType.userCorrected);
      expect(searchMatches.first.chunk.text, contains('quantum spinlocks'));
    });
  });

  group('OcrDocumentReviewScreen Widget Tests', () {
    testWidgets('Renders page carousel, OCR badges, and edits text',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final rag = RagService.instance;
      await rag.init();

      final doc = VaultDocument(
        id: 'doc_test_1',
        name: 'Lecture_Notes_Process_Sync_Handwritten.pdf',
        path: '/mock/path.pdf',
        subject: 'Operating Systems',
        unit: 'Unit 1',
        chunkCount: 2,
        pageCount: 2,
        addedAt: DateTime.now(),
        ocrPageCount: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: OcrDocumentReviewScreen(document: doc),
        ),
      );

      await tester.pumpAndSettle();

      // Check header and 100% On-Device OCR indicator
      expect(find.text('Lecture_Notes_Process_Sync_Handwritten.pdf'),
          findsOneWidget);
      expect(find.text('100% On-Device OCR • Knowledge Base Review'),
          findsOneWidget);

      // Check page choice chips
      expect(find.text('p.1'), findsOneWidget);
      expect(find.text('p.2'), findsOneWidget);

      // Check Extracted Text Header and Save button
      expect(find.text('EXTRACTED TEXT (RAG GROUNDING)'), findsOneWidget);
      expect(find.text('Save Correction & Sync RAG'), findsOneWidget);

      // Switch to page 2
      await tester.tap(find.text('p.2'));
      await tester.pumpAndSettle();

      // Enter new text in editor
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      await tester.enterText(
          textField, 'Updated via widget test user correction');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Save
      final saveBtn = find.text('Save Correction & Sync RAG');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify page 2 updated
      final updatedPages = rag.getExtractedPages(doc.name);
      expect(updatedPages.firstWhere((p) => p.pageNumber == 2).text,
          'Updated via widget test user correction');
    });
  });
}
