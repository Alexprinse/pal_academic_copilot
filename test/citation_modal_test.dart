import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/extracted_page_content.dart';
import 'package:pal_academic_copilot/models/rag_scope.dart';
import 'package:pal_academic_copilot/models/vault_item.dart';
import 'package:pal_academic_copilot/screens/pal_brain_screen.dart';
import 'package:pal_academic_copilot/services/conversation_service.dart';
import 'package:pal_academic_copilot/services/rag_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await RagService.instance.init();
    await ConversationService.instance.init();
  });

  testWidgets(
      'Citation excerpt modal bottom sheet renders large OCR text without overflow',
      (WidgetTester tester) async {
    // Generate a long OCR text chunk that would cause a 370px overflow if unconstrained
    final longOcrText =
        'Phone-First Format iROO HACKATHON -20 26 4 The iQOO device is the build surface '
        'and the demo surface: every entry must run and pitch on the phone. Your IQOO Device '
        'THE PLAYBOOK (1/2) RULES & GUIDELINES • A local or open-source model at the core earns '
        'brownie points, with the phone in the loop via Office Kit. . Office Kit bridges phone '
        'and laptop (screen mirror, clipboard, file transfer, remote control). Pairing instructions '
        'ship with the loaner and are covered in the Saturday 10:00 teach-in. On-device inference '
        'targets the Snapdragon NPU. AI credits for the weekend are free. • Stacks welcome: native '
        'Android, Flutter, React Native, or PWA. If it runs on the phone with a local or open-source '
        'model at the core, it qualifies. Kit scoring- • One flagship IQOO loaner phone per person, '
        'handed over at Saturday check-in with HackTracker preinstalled and Office Kit already configured. '
        'All work must be authored during the hackathon. Teams may consist of 1 to 4 participants. '
        'Submissions will be judged on innovation, UX, and technical execution on device.\n\n'
        'Additional criteria: Robustness against offline environments, battery consumption benchmarks, '
        'and UI fluidity under heavy on-device LLM generation.';

    final testChunk = TextChunk(
      id: 'chunk_test_1',
      documentId: 'doc_1',
      documentName: 'Notes · Sep 13',
      text: longOcrText,
      pageNumber: 1,
      wordCount: 150,
      extractionType: ExtractionType.printedOcr,
      subjectId: 'unorganized',
      subjectName: 'Unorganized',
      unitId: 'unorganized',
      unitName: 'Unorganized',
    );

    final match = ChunkMatch(chunk: testChunk, score: 0.23);

    final brainKey = GlobalKey<PalBrainScreenState>();

    // Test with compact mobile screen constraints
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PalBrainScreen(key: brainKey),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Open citation modal using the state helper
    final BuildContext context = brainKey.currentContext!;
    brainKey.currentState?.showCitationModalForTest(context, match);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify modal header renders
    expect(find.text('Notes · Sep 13'), findsWidgets);
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Printed OCR'), findsOneWidget);
    expect(find.text('VERIFIED SOURCE EXCERPT'), findsOneWidget);

    // Verify SingleChildScrollView is present to absorb any large height
    expect(find.byType(SingleChildScrollView), findsWidgets);

    // Verify "Copy Citation Excerpt" button is present
    expect(find.text('Copy Citation Excerpt'), findsOneWidget);

    // Verify NO RenderFlex overflow exception occurred
    expect(tester.takeException(), isNull);
  });
}
