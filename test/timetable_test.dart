import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/parsed_timetable_entry.dart';
import 'package:pal_academic_copilot/models/timetable_entry.dart';
import 'package:pal_academic_copilot/screens/add_class_wizard_screen.dart';
import 'package:pal_academic_copilot/screens/class_details_modal.dart';
import 'package:pal_academic_copilot/screens/dashboard_screen.dart';
import 'package:pal_academic_copilot/screens/timetable_screen.dart';
import 'package:pal_academic_copilot/screens/timetable_verification_screen.dart';
import 'package:pal_academic_copilot/services/timetable_parser.dart';
import 'package:pal_academic_copilot/services/timetable_service.dart';
import 'package:pal_academic_copilot/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      },
    );
  });

  group('TimetableEntry Model Tests', () {
    test('Calculates duration string correctly', () {
      const entry1 = TimetableEntry(
        id: 't1',
        subject: 'Algorithms',
        dayOfWeek: 'Mon',
        startTime: '09:00 AM',
        endTime: '10:00 AM',
      );
      expect(entry1.durationString, '1 hour');
      expect(entry1.startHourDouble, 9.0);
      expect(entry1.endHourDouble, 10.0);

      const entry2 = TimetableEntry(
        id: 't2',
        subject: 'OS Lab',
        dayOfWeek: 'Tue',
        startTime: '11:00 AM',
        endTime: '12:30 PM',
      );
      expect(entry2.durationString, '1 hr 30 min');
      expect(entry2.startHourDouble, 11.0);
      expect(entry2.endHourDouble, 12.5);
    });

    test('Serializes to and from JSON correctly', () {
      const original = TimetableEntry(
        id: 't-test',
        subject: 'Computer Networks',
        dayOfWeek: 'Wed',
        startTime: '02:00 PM',
        endTime: '03:30 PM',
        room: 'Room 301',
        professor: 'Prof. Mehta',
        notes: 'Bring laptop',
        repeatWeekly: true,
        type: 'Lecture',
      );

      final json = original.toJson();
      final revived = TimetableEntry.fromJson(json);

      expect(revived.id, original.id);
      expect(revived.subject, original.subject);
      expect(revived.dayOfWeek, original.dayOfWeek);
      expect(revived.startTime, original.startTime);
      expect(revived.endTime, original.endTime);
      expect(revived.room, original.room);
      expect(revived.professor, original.professor);
      expect(revived.notes, original.notes);
      expect(revived.repeatWeekly, isTrue);
      expect(revived.type, 'Lecture');
    });
  });

  group('TimetableService CRUD & Query Tests', () {
    final service = TimetableService.instance;

    setUp(() async {
      await service.resetToDefaultSeed(saveToDisk: false);
    });

    test('Initializes with default academic seed classes', () {
      expect(service.entries.isNotEmpty, isTrue);
      final monClasses = service.getEntriesForDay('Mon');
      expect(monClasses.any((c) => c.subject == 'Data Structures'), isTrue);
      expect(monClasses.any((c) => c.subject == 'Operating Systems'), isTrue);
    });

    test('Adds and deletes timetable entries', () async {
      const newClass = TimetableEntry(
        id: 'custom-1',
        subject: 'Quantum Computing',
        dayOfWeek: 'Mon',
        startTime: '08:00 AM',
        endTime: '09:00 AM',
        room: 'Hall Q',
      );

      await service.addEntry(newClass);
      expect(service.entries.any((e) => e.id == 'custom-1'), isTrue);

      final monClasses = service.getEntriesForDay('Mon');
      expect(monClasses.any((e) => e.subject == 'Quantum Computing'), isTrue);

      await service.deleteEntry('custom-1');
      expect(service.entries.any((e) => e.id == 'custom-1'), isFalse);
    });

    test('Updates existing timetable entry', () async {
      final first = service.entries.first;
      final updated = first.copyWith(room: 'New Room 999');

      await service.updateEntry(updated);
      final fetched = service.entries.firstWhere((e) => e.id == first.id);
      expect(fetched.room, 'New Room 999');
    });

    test('Provides recent and suggested subjects', () {
      final subjects = service.getRecentSubjects();
      expect(subjects.isNotEmpty, isTrue);
      expect(subjects.contains('Operating Systems'), isTrue);
    });

    test('Architectural queries for Pal integration execute safely', () {
      expect(service.getTodayDayOfWeek(), isNotNull);
      final todayClasses = service.getTodayClasses();
      expect(todayClasses, isA<List<TimetableEntry>>());
      // getCurrentClass and getNextClass should run without throwing
      service.getCurrentClass();
      service.getNextClass();
    });
  });

  group('Timetable UI & Navigation Widget Tests', () {
    testWidgets(
        'Dashboard replaces Vault shortcut with Timetable icon and navigates to TimetableScreen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await TimetableService.instance.resetToDefaultSeed(saveToDisk: false);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: DashboardScreen(onNavigateTab: (_) {}),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Timetable icon exists on top right of Home screen
      final timetableBtn = find.byIcon(Icons.calendar_month_outlined);
      expect(timetableBtn, findsOneWidget);

      // Verify top button has Weekly Timetable tooltip
      expect(find.byTooltip('Weekly Timetable'), findsOneWidget);

      // Tap Timetable button
      await tester.tap(timetableBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Timetable screen is displayed
      expect(find.text('Timetable'), findsOneWidget);
      expect(find.text('Plan your week, your way.'), findsOneWidget);
      expect(find.text('Add Class'), findsWidgets);

      // Pop back to Home
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    });

    testWidgets('Weekly view displays classes and opens Class Details modal',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await TimetableService.instance.resetToDefaultSeed(saveToDisk: false);

      await tester.pumpWidget(
        const MaterialApp(
          home: TimetableScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Select Monday
      await tester.tap(find.text('Mon'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Monday class cards are visible
      expect(find.text('Data Structures'), findsOneWidget);
      expect(find.text('Operating Systems'), findsOneWidget);
    });

    testWidgets('Add Class Wizard steps 1 through 5 work and create a class',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: AddClassWizardScreen(initialDay: 'Mon'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Step 1: Day
      expect(find.text("Let's add a class"), findsOneWidget);
      expect(find.text('First, select the day(s).'), findsOneWidget);

      // Tap Next ->
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Step 2: Time
      expect(find.text('What time is it?'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('1 hour'), findsOneWidget);

      // Tap Next ->
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Step 3: Subject
      expect(find.text('What are you studying?'), findsOneWidget);
      // Select quick chip "Algorithms"
      await tester.tap(find.text('Algorithms'));
      await tester.pump();

      // Tap Next ->
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Step 4: Details
      expect(find.text('Add details (optional)'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. Room 204'), 'Room 505');
      await tester.enterText(find.byType(TextField).first, 'Room 505');
      await tester.pump();

      // Tap Next ->
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Step 5: Repeat
      expect(find.text('Repeat this class?'), findsOneWidget);
      expect(find.text('Repeat every week'), findsOneWidget);

      // Complete Add Class
      await tester.tap(find.text('Add Class'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify class was added to service
      expect(
        TimetableService.instance.entries
            .any((e) => e.subject == 'Algorithms' && e.room == 'Room 505'),
        isTrue,
      );
    });

    testWidgets('Empty State is displayed when timetable has no entries',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await TimetableService.instance.clearAll(saveToDisk: false);

      await tester.pumpWidget(
        const MaterialApp(
          home: TimetableScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Screen 9 Empty State is rendered
      expect(find.text('Your week is waiting'), findsOneWidget);
      expect(find.text('Add Your First Class'), findsOneWidget);
      expect(find.text('Import Timetable Image'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month), findsOneWidget);

      // Restore seed data
      await TimetableService.instance.resetToDefaultSeed(saveToDisk: false);
    });

    testWidgets(
        'TimetableVerificationScreen renders extracted classes and review badges',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dummyResult = ParsedTimetableResult(
        entries: [
          ParsedTimetableEntry(
            id: 'mock-1',
            subject: 'Computer Architecture',
            dayOfWeek: 'Mon',
            startTime: '09:00 AM',
            endTime: '10:00 AM',
            room: 'Room 303',
            type: 'Lecture',
            confidence: 0.95,
            requiresReview: false,
          ),
          ParsedTimetableEntry(
            id: 'mock-2',
            subject: 'Cloud Computing Lab',
            dayOfWeek: 'Mon',
            startTime: '10:00 AM',
            endTime: '11:00 AM',
            room: 'Lab 4',
            type: 'Lab',
            confidence: 0.65,
            requiresReview: true,
            reviewReason: 'Time inferred from Period II',
          ),
        ],
        layoutDescription: 'Grid: Days as Columns, Times as Rows',
        dayHeaders: [],
        timeHeaders: [],
        contentItems: [],
        cellRects: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: TimetableVerificationScreen(
            parsedResult: dummyResult,
            imagePath: '/tmp/test_timetable.png',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Check header and privacy message
      expect(find.text('Review Timetable'), findsOneWidget);
      expect(find.text('Found 2 classes'), findsOneWidget);
      expect(find.text('Processed privately on your device · 100% Offline'),
          findsOneWidget);
      expect(find.text('1 review'), findsOneWidget);

      // Check class cards
      expect(find.text('Computer Architecture'), findsOneWidget);
      expect(find.text('Room 303'), findsOneWidget);
      expect(find.text('Cloud Computing Lab'), findsOneWidget);
      expect(find.text('Time inferred from Period II'), findsOneWidget);

      // Tap to edit class
      await tester.tap(find.text('Computer Architecture'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Modal is open
      expect(find.text('Edit Class'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Computer Architecture'),
          'Advanced Architecture');
      await tester.pump();

      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify edited text appears
      expect(find.text('Advanced Architecture'), findsOneWidget);
    });

    testWidgets('ClassDetailsModal allows editing class time and details',
        (tester) async {
      const entry = TimetableEntry(
        id: 'edit-test-1',
        subject: 'Microprocessors',
        dayOfWeek: 'Tue',
        startTime: '09:00 AM',
        endTime: '10:00 AM',
        room: 'Lab 2',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const ClassDetailsModal(entry: entry),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Microprocessors'), findsOneWidget);
      expect(find.text('09:00 AM – 10:00 AM (1 hour)'), findsOneWidget);

      // Tap Edit button
      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Edit Class Details'), findsOneWidget);
      expect(find.text('Start Time'), findsOneWidget);
      expect(find.text('End Time'), findsOneWidget);

      // Verify start and end times are displayed
      expect(find.text('09:00 AM'), findsOneWidget);
      expect(find.text('10:00 AM'), findsOneWidget);

      // Save changes
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Class updated successfully'), findsOneWidget);
    });
  });
}
