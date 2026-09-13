import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/agent/agent_context.dart';
import 'package:pal_academic_copilot/agent/agent_service.dart';
import 'package:pal_academic_copilot/agent/tools/get_academic_calendar_tool.dart';
import 'package:pal_academic_copilot/agent/tools/get_holidays_tool.dart';
import 'package:pal_academic_copilot/agent/tools/get_id_card_tool.dart';
import 'package:pal_academic_copilot/agent/tools/get_mess_menu_tool.dart';
import 'package:pal_academic_copilot/agent/tools/get_notices_tool.dart';
import 'package:pal_academic_copilot/models/campus_vault.dart';
import 'package:pal_academic_copilot/services/campus_vault_service.dart';
import 'package:pal_academic_copilot/services/rag_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CampusVaultService campusService;

  setUp(() {
    CampusVaultService.resetInstanceForTesting();
    AgentService.resetInstanceForTesting();
    RagService.instance.restoreDefaultSubjects();
    campusService = CampusVaultService.instance;
  });

  group('Personal Student Vault — Data Models & Persistence', () {
    test('CampusVaultService initializes with default seed data', () {
      expect(campusService.idCard.studentName, 'Alex Prinse');
      expect(campusService.idCard.rollNumber, 'CS22B1045');
      expect(campusService.messMenu.days.containsKey('Monday'), isTrue);
      expect(campusService.messMenu.days.containsKey('Sunday'), isTrue);
      expect(campusService.holidays.isNotEmpty, isTrue);
      expect(campusService.calendarItems.isNotEmpty, isTrue);
      expect(campusService.notices.isNotEmpty, isTrue);
    });

    test('ID Card update and delete preserves privacy on device', () async {
      final updated = campusService.idCard.copyWith(
        studentName: 'Jane Doe',
        rollNumber: 'CS23B2001',
      );
      await campusService.saveIdCard(updated);
      expect(campusService.idCard.studentName, 'Jane Doe');
      expect(campusService.idCard.rollNumber, 'CS23B2001');

      await campusService.deleteIdCard();
      expect(campusService.idCard.studentName, isEmpty);
      expect(campusService.idCard.studentId, isEmpty);
    });

    test('Mess Menu meal update and day retrieval', () async {
      final monday = campusService.getMenuForDayName('Monday');
      expect(monday, isNotNull);
      expect(monday!.breakfast.items.isNotEmpty, isTrue);

      await campusService.updateMeal(
        dayOfWeek: 'Monday',
        mealName: 'Lunch',
        items: ['Special Thali', 'Gulab Jamun'],
      );

      final updatedMonday = campusService.getMenuForDayName('Monday');
      expect(updatedMonday!.lunch.items, ['Special Thali', 'Gulab Jamun']);

      // Reset
      await campusService.resetMessMenuToDefault();
      final resetMonday = campusService.getMenuForDayName('Monday');
      expect(resetMonday!.lunch.items.contains('Paneer Butter Masala'), isTrue);
    });

    test('Campus Holiday countdown and next holiday lookup', () {
      final testDate = DateTime(2026, 10, 1);
      final next = campusService.getNextHoliday(from: testDate);
      expect(next, isNotNull);
      expect(next!.name, 'Gandhi Jayanti');
      expect(next.daysUntil(from: testDate), 1);
    });

    test('Academic Calendar milestones and countdown', () {
      final testDate = DateTime(2026, 10, 1);
      final milestone = campusService.getNextMilestone(from: testDate);
      expect(milestone, isNotNull);
      expect(milestone!.title, 'Mid-Term Examinations');
      expect(milestone.daysUntil(from: testDate), 13);
    });

    test('Campus Notices CRUD and search', () async {
      final newNotice = CampusNotice(
        id: 'test-notice-99',
        title: 'Robotics Workshop Registration',
        date: DateTime(2026, 9, 13),
        category: NoticeCategory.events,
        extractedText: 'Hands-on ROS workshop in Seminar Hall 3.',
        summary: 'Robotics workshop registration open.',
      );

      await campusService.addNotice(newNotice);
      expect(campusService.notices.first.id, 'test-notice-99');

      final searchResults = campusService.searchCampus('robotics');
      expect(searchResults.isNotEmpty, isTrue);
      expect(searchResults.first['title'], 'Robotics Workshop Registration');

      await campusService.removeNotice('test-notice-99');
      expect(
          campusService.notices.any((n) => n.id == 'test-notice-99'), isFalse);
    });
  });

  group('Personal Student Vault — Agent Tools Integration', () {
    test('GetMessMenuTool answers today lunch and tomorrow dinner', () async {
      final tool = GetMessMenuTool(campusService: campusService);
      final mockContext = AgentContext(
        currentDateTime: DateTime(2026, 9, 14, 12, 0), // A Monday
      );

      // Query Lunch Today
      final resultLunch = await tool.execute(
        {'day': 'today', 'meal': 'lunch'},
        context: mockContext,
      );
      expect(resultLunch.success, isTrue);
      expect(resultLunch.message.contains('Paneer Butter Masala'), isTrue);

      // Query Dinner Tomorrow (Tuesday)
      final resultDinner = await tool.execute(
        {'day': 'tomorrow', 'meal': 'dinner'},
        context: mockContext,
      );
      expect(resultDinner.success, isTrue);
      expect(resultDinner.message.contains('Tuesday'), isTrue);
      expect(resultDinner.message.contains('Palak Paneer'), isTrue);
    });

    test('GetHolidaysTool answers next holiday and check_tomorrow', () async {
      final tool = GetHolidaysTool(campusService: campusService);
      final mockContext = AgentContext(
        currentDateTime: DateTime(2026, 10, 1),
      );

      final resultNext = await tool.execute(
        {'queryType': 'next'},
        context: mockContext,
      );
      expect(resultNext.success, isTrue);
      expect(resultNext.message.contains('Gandhi Jayanti'), isTrue);

      final resultTomorrow = await tool.execute(
        {'queryType': 'check_tomorrow'},
        context: mockContext,
      );
      expect(resultTomorrow.success, isTrue);
      expect(resultTomorrow.message.contains('Yes! Tomorrow is a holiday'),
          isTrue);
    });

    test('GetIdCardTool answers roll number and student ID on-device',
        () async {
      final tool = GetIdCardTool(campusService: campusService);

      final resultRoll = await tool.execute({'field': 'roll_number'});
      expect(resultRoll.success, isTrue);
      expect(resultRoll.message.contains('CS22B1045'), isTrue);

      final resultAll = await tool.execute({'field': 'all'});
      expect(resultAll.success, isTrue);
      expect(resultAll.message.contains('Alex Prinse'), isTrue);
      expect(resultAll.message.contains('Computer Science'), isTrue);
    });

    test('GetAcademicCalendarTool retrieves exam schedules', () async {
      final tool = GetAcademicCalendarTool(campusService: campusService);
      final mockContext = AgentContext(
        currentDateTime: DateTime(2026, 9, 15),
      );

      final result = await tool.execute(
        {'eventType': 'exam'},
        context: mockContext,
      );
      expect(result.success, isTrue);
      expect(result.message.contains('Mid-Term Examinations'), isTrue);
      expect(result.message.contains('End-Term Theory Examinations'), isTrue);
    });

    test('GetNoticesTool retrieves circulars by category', () async {
      final tool = GetNoticesTool(campusService: campusService);

      final resultExams = await tool.execute({'category': 'exams'});
      expect(resultExams.success, isTrue);
      expect(resultExams.message.contains('Mid-Term Exam Schedule'), isTrue);

      final resultPlacement = await tool.execute({'category': 'placement'});
      expect(resultPlacement.success, isTrue);
      expect(resultPlacement.message.contains('Campus Placement Registration'),
          isTrue);
    });
  });

  group('Personal Student Vault — Agent Routing Isolation', () {
    test('Campus queries route directly to campus tools and do NOT trigger RAG',
        () {
      final agent = AgentService.instance;

      // 1. Mess menu query
      final messCalls = agent.determineToolCalls("What is for lunch today?");
      expect(messCalls.length, 1);
      expect(messCalls.first.tool, 'get_mess_menu');

      // 2. Holiday query
      final holidayCalls = agent.determineToolCalls("Is tomorrow a holiday?");
      expect(holidayCalls.length, 1);
      expect(holidayCalls.first.tool, 'get_holidays');

      // 3. ID Card query
      final idCalls = agent.determineToolCalls("What is my roll number?");
      expect(idCalls.length, 1);
      expect(idCalls.first.tool, 'get_id_card');

      // 4. Academic Calendar query
      final calCalls = agent.determineToolCalls("When are end-term exams?");
      expect(calCalls.length, 1);
      expect(calCalls.first.tool, 'get_academic_calendar');

      // 5. Notice query
      final noticeCalls =
          agent.determineToolCalls("Any new notices about exams?");
      expect(noticeCalls.length, 1);
      expect(noticeCalls.first.tool, 'get_notices');

      // 6. Academic query routes to RAG (search_knowledge), NOT campus
      final ragCalls = agent.determineToolCalls(
          "What do my notes say about Peterson's algorithm?");
      expect(ragCalls.length, 1);
      expect(ragCalls.first.tool, 'search_knowledge');
    });

    test('Vault search covers both Academic and Campus content', () {
      final ragService = RagService.instance;

      // Academic search
      final osResults = ragService.searchVault('Operating Systems');
      expect(osResults.any((r) => r.type == 'subject'), isTrue);

      // Campus search
      final foodResults = campusService.searchCampus('Paneer');
      expect(foodResults.any((r) => r['category'] == 'Mess Menu'), isTrue);

      final holidayResults = campusService.searchCampus('Gandhi');
      expect(holidayResults.any((r) => r['category'] == 'Holidays'), isTrue);
    });
  });
}
