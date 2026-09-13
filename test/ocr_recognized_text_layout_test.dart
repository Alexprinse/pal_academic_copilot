import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/screens/ocr_scanner_screen.dart';
import 'package:pal_academic_copilot/services/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    OcrService.instance.clear();
  });

  testWidgets(
      'OCR Recognized Text card renders horizontally without vertical character wrapping on compact screens',
      (WidgetTester tester) async {
    // Set a compact mobile screen constraint (width 360, similar to standard mobile)
    tester.view.physicalSize = const Size(360 * 2, 740 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const sampleOcrText =
        'Operating Systems: Peterson\'s Algorithm for mutual exclusion in process synchronization. '
        'What are the shared variables and how does bounded waiting hold?';

    OcrService.instance.setLastResultForTest(
      OcrResult(
        text: sampleOcrText,
        blockCount: 1,
        processingTimeMs: 120,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OcrScannerScreen(
            onNavigateToBrain: (tab, {initialQuery}) {},
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Find the 'Recognized Text' text widget
    final recognizedTextFinder = find.text('Recognized Text');
    expect(recognizedTextFinder, findsOneWidget);

    // Verify its rendered dimensions:
    // When wrapped vertically letter-by-letter, height was > 200px and width was < 25px.
    // When properly laid out horizontally, width is > 100px and height is <= 30px.
    final renderBox = tester.renderObject<RenderBox>(recognizedTextFinder);
    expect(renderBox.size.width, greaterThan(100.0));
    expect(renderBox.size.height, lessThan(35.0));

    // Verify word and char count pill is rendered
    expect(find.textContaining('words ·'), findsOneWidget);
    expect(find.textContaining('chars'), findsOneWidget);

    // Verify action buttons are present
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);

    // Verify NO RenderFlex overflows
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'OCR Recognized Text card renders without overflow on narrow 320px screen with document title',
      (WidgetTester tester) async {
    // Test on extra narrow screen (320 logical width)
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const sampleOcrText =
        'Operating Systems: Peterson\'s Algorithm for mutual exclusion in process synchronization.';

    OcrService.instance.setLastResultForTest(
      OcrResult(
        text: sampleOcrText,
        blockCount: 1,
        processingTimeMs: 95,
      ),
    );

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OcrScannerScreen(
            key: key,
            onNavigateToBrain: (tab, {initialQuery}) {},
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Recognized Text renders as a single horizontal line (< 35px height, never vertical column)
    final recognizedTextFinder = find.text('Recognized Text');
    expect(recognizedTextFinder, findsOneWidget);
    final renderBox = tester.renderObject<RenderBox>(recognizedTextFinder);
    expect(renderBox.size.height, lessThan(35.0));

    expect(tester.takeException(), isNull);
  });
}
