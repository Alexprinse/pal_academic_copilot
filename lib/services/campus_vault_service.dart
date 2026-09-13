import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/campus_vault.dart';

class CampusVaultService extends ChangeNotifier {
  static CampusVaultService? _instance;
  static CampusVaultService get instance =>
      _instance ??= CampusVaultService._();

  @visibleForTesting
  static void resetInstanceForTesting() {
    _instance = null;
  }

  CampusVaultService._() {
    _loadDefaults();
  }

  bool _initialized = false;
  bool get isInitialized => _initialized;

  late IdCardData _idCard;

  late MessMenuData _messMenu;
  final List<CampusHoliday> _holidays = [];
  final List<AcademicCalendarItem> _calendarItems = [];
  final List<CampusNotice> _notices = [];

  IdCardData get idCard => _idCard;
  MessMenuData get messMenu => _messMenu;
  List<CampusHoliday> get holidays => List.unmodifiable(_holidays);
  List<AcademicCalendarItem> get calendarItems =>
      List.unmodifiable(_calendarItems);
  List<CampusNotice> get notices => List.unmodifiable(_notices);

  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/campus_vault.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final Map<String, dynamic> data = jsonDecode(content);
          _fromMap(data);
          _initialized = true;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('Note: unable to load campus_vault.json: $e');
    }
    _initialized = true;
  }

  Future<void> _persist() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/campus_vault.json');
      await file.writeAsString(jsonEncode(_toMap()));
    } catch (e) {
      debugPrint('Note: unable to write campus_vault.json: $e');
    }
  }

  Map<String, dynamic> _toMap() {
    return {
      'idCard': _idCard.toMap(),
      'messMenu': _messMenu.toMap(),
      'holidays': _holidays.map((h) => h.toMap()).toList(),
      'calendarItems': _calendarItems.map((c) => c.toMap()).toList(),
      'notices': _notices.map((n) => n.toMap()).toList(),
    };
  }

  void _fromMap(Map<String, dynamic> data) {
    if (data['idCard'] != null) {
      _idCard = IdCardData.fromMap(data['idCard'] as Map<String, dynamic>);
    }
    if (data['messMenu'] != null) {
      _messMenu =
          MessMenuData.fromMap(data['messMenu'] as Map<String, dynamic>);
    }
    if (data['holidays'] != null) {
      _holidays.clear();
      final list = data['holidays'] as List<dynamic>;
      for (final item in list) {
        _holidays.add(CampusHoliday.fromMap(item as Map<String, dynamic>));
      }
    }
    if (data['calendarItems'] != null) {
      _calendarItems.clear();
      final list = data['calendarItems'] as List<dynamic>;
      for (final item in list) {
        _calendarItems
            .add(AcademicCalendarItem.fromMap(item as Map<String, dynamic>));
      }
    }
    if (data['notices'] != null) {
      _notices.clear();
      final list = data['notices'] as List<dynamic>;
      for (final item in list) {
        _notices.add(CampusNotice.fromMap(item as Map<String, dynamic>));
      }
    }
  }

  // ==================== ID CARD OPERATIONS ====================

  Future<void> saveIdCard(IdCardData newIdCard) async {
    _idCard = newIdCard;
    notifyListeners();
    await _persist();
  }

  Future<void> deleteIdCard() async {
    _idCard = IdCardData(
      studentName: '',
      studentId: '',
      department: '',
      institution: '',
      isExtracted: false,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _persist();
  }

  // ==================== MESS MENU OPERATIONS ====================

  DayMenu getMenuForDate(DateTime date) => _messMenu.getMenuForDate(date);

  DayMenu? getMenuForDayName(String day) => _messMenu.getMenuForDayName(day);

  Future<void> updateMeal({
    required String dayOfWeek,
    required String mealName,
    required List<String> items,
    String? timings,
  }) async {
    final existingDay = _messMenu.getMenuForDayName(dayOfWeek);
    if (existingDay == null) return;

    final lower = mealName.toLowerCase();
    DayMenu updatedDay;

    if (lower.contains('break')) {
      updatedDay = existingDay.copyWith(
        breakfast: existingDay.breakfast.copyWith(
          items: items,
          timings: timings ?? existingDay.breakfast.timings,
        ),
      );
    } else if (lower.contains('lunch')) {
      updatedDay = existingDay.copyWith(
        lunch: existingDay.lunch.copyWith(
          items: items,
          timings: timings ?? existingDay.lunch.timings,
        ),
      );
    } else if (lower.contains('snack') || lower.contains('tea')) {
      updatedDay = existingDay.copyWith(
        snacks: existingDay.snacks.copyWith(
          items: items,
          timings: timings ?? existingDay.snacks.timings,
        ),
      );
    } else {
      updatedDay = existingDay.copyWith(
        dinner: existingDay.dinner.copyWith(
          items: items,
          timings: timings ?? existingDay.dinner.timings,
        ),
      );
    }

    final newDays = Map<String, DayMenu>.from(_messMenu.days);
    newDays[existingDay.dayOfWeek] = updatedDay;
    _messMenu = MessMenuData(
      messName: _messMenu.messName,
      days: newDays,
      lastUpdated: DateTime.now(),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> resetMessMenuToDefault() async {
    _messMenu = _buildDefaultMessMenu();
    notifyListeners();
    await _persist();
  }

  // ==================== HOLIDAY OPERATIONS ====================

  CampusHoliday? getNextHoliday({DateTime? from}) {
    final upcoming = getUpcomingHolidays(from: from);
    return upcoming.isNotEmpty ? upcoming.first : null;
  }

  List<CampusHoliday> getUpcomingHolidays({DateTime? from}) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = _holidays.where((h) {
      final hDate = DateTime(h.date.year, h.date.month, h.date.day);
      return !hDate.isBefore(today);
    }).toList();
    upcoming.sort((a, b) => a.date.compareTo(b.date));
    return upcoming;
  }

  Future<void> addHoliday(CampusHoliday holiday) async {
    _holidays.removeWhere((h) => h.id == holiday.id);
    _holidays.add(holiday);
    _holidays.sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
    await _persist();
  }

  Future<void> removeHoliday(String id) async {
    _holidays.removeWhere((h) => h.id == id);
    notifyListeners();
    await _persist();
  }

  // ==================== CALENDAR OPERATIONS ====================

  AcademicCalendarItem? getNextMilestone({DateTime? from}) {
    final upcoming = getUpcomingCalendarItems(from: from);
    return upcoming.isNotEmpty ? upcoming.first : null;
  }

  List<AcademicCalendarItem> getUpcomingCalendarItems({DateTime? from}) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = _calendarItems.where((c) {
      final effectiveEnd = c.endDate ?? c.startDate;
      final end =
          DateTime(effectiveEnd.year, effectiveEnd.month, effectiveEnd.day);
      return !end.isBefore(today);
    }).toList();
    upcoming.sort((a, b) => a.startDate.compareTo(b.startDate));
    return upcoming;
  }

  Future<void> addCalendarItem(AcademicCalendarItem item) async {
    _calendarItems.removeWhere((c) => c.id == item.id);
    _calendarItems.add(item);
    _calendarItems.sort((a, b) => a.startDate.compareTo(b.startDate));
    notifyListeners();
    await _persist();
  }

  Future<void> removeCalendarItem(String id) async {
    _calendarItems.removeWhere((c) => c.id == id);
    notifyListeners();
    await _persist();
  }

  // ==================== NOTICE OPERATIONS ====================

  Future<void> addNotice(CampusNotice notice) async {
    _notices.removeWhere((n) => n.id == notice.id);
    _notices.insert(0, notice); // latest first
    notifyListeners();
    await _persist();
  }

  Future<void> markNoticeAsRead(String id) async {
    final idx = _notices.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _notices[idx] = _notices[idx].copyWith(isRead: true);
      notifyListeners();
      await _persist();
    }
  }

  Future<void> removeNotice(String id) async {
    _notices.removeWhere((n) => n.id == id);
    notifyListeners();
    await _persist();
  }

  // ==================== CAMPUS SEARCH ====================

  List<Map<String, dynamic>> searchCampus(String query) {
    final clean = query.toLowerCase().trim();
    if (clean.isEmpty) return [];

    final results = <Map<String, dynamic>>[];

    // 1. Search ID Card
    if (_idCard.studentName.toLowerCase().contains(clean) ||
        _idCard.studentId.toLowerCase().contains(clean) ||
        (_idCard.rollNumber?.toLowerCase().contains(clean) ?? false) ||
        _idCard.department.toLowerCase().contains(clean)) {
      results.add({
        'section': 'Campus',
        'category': 'ID Card',
        'title': 'Student ID Card: ${_idCard.studentName}',
        'snippet':
            'ID: ${_idCard.studentId} · Dept: ${_idCard.department} · Roll: ${_idCard.rollNumber ?? "N/A"}',
        'type': 'id_card',
      });
    }

    // 2. Search Mess Menu
    for (final entry in _messMenu.days.entries) {
      final day = entry.value;
      for (final meal in [day.breakfast, day.lunch, day.snacks, day.dinner]) {
        for (final item in meal.items) {
          if (item.toLowerCase().contains(clean)) {
            results.add({
              'section': 'Campus',
              'category': 'Mess Menu',
              'title': '${day.dayOfWeek} · ${meal.mealName}',
              'snippet':
                  '${meal.mealName} (${meal.timings}): ${day.dayOfWeek} features "$item". Full menu: ${meal.items.join(", ")}',
              'type': 'mess_menu',
            });
            break;
          }
        }
      }
    }

    // 3. Search Holidays
    for (final h in _holidays) {
      if (h.name.toLowerCase().contains(clean) ||
          (h.description?.toLowerCase().contains(clean) ?? false)) {
        results.add({
          'section': 'Campus',
          'category': 'Holidays',
          'title': h.name,
          'snippet':
              '${h.type.displayName} on ${h.date.year}-${h.date.month.toString().padLeft(2, "0")}-${h.date.day.toString().padLeft(2, "0")}. ${h.description ?? ""}',
          'type': 'holiday',
        });
      }
    }

    // 4. Search Calendar Milestones
    for (final c in _calendarItems) {
      if (c.title.toLowerCase().contains(clean) ||
          (c.description?.toLowerCase().contains(clean) ?? false)) {
        results.add({
          'section': 'Campus',
          'category': 'Academic Calendar',
          'title': c.title,
          'snippet':
              '${c.eventType.displayName} starting ${c.startDate.year}-${c.startDate.month.toString().padLeft(2, "0")}-${c.startDate.day.toString().padLeft(2, "0")}. ${c.description ?? ""}',
          'type': 'calendar',
        });
      }
    }

    // 5. Search Notices
    for (final n in _notices) {
      if (n.title.toLowerCase().contains(clean) ||
          n.extractedText.toLowerCase().contains(clean) ||
          (n.issuingAuthority?.toLowerCase().contains(clean) ?? false)) {
        results.add({
          'section': 'Campus',
          'category': 'Notices',
          'title': n.title,
          'snippet':
              '${n.category.displayName} (${n.date.year}-${n.date.month.toString().padLeft(2, "0")}-${n.date.day.toString().padLeft(2, "0")}): ${n.extractedText.length > 120 ? "${n.extractedText.substring(0, 120)}..." : n.extractedText}',
          'type': 'notice',
          'notice': n,
        });
      }
    }

    return results;
  }

  // ==================== DEFAULT SEED DATA ====================

  void _loadDefaults() {
    _idCard = IdCardData(
      studentName: 'Alex Prinse',
      studentId: 'STU-2024-8842',
      rollNumber: 'CS22B1045',
      department: 'Computer Science & Engineering',
      institution: 'National Institute of Technology',
      validUntil: 'Jun 2026',
      isExtracted: true,
      updatedAt: DateTime.now(),
    );

    _messMenu = _buildDefaultMessMenu();

    _holidays.clear();
    _holidays.addAll([
      CampusHoliday(
        id: 'hol-1',
        name: 'Gandhi Jayanti',
        date: DateTime(2026, 10, 2),
        type: CampusHolidayType.national,
        description:
            'National holiday commemorating Mahatma Gandhi\'s birthday.',
      ),
      CampusHoliday(
        id: 'hol-2',
        name: 'Dussehra (Vijayadashami)',
        date: DateTime(2026, 10, 20),
        type: CampusHolidayType.gazetted,
        description: 'Festival holiday celebrating triumph of good over evil.',
      ),
      CampusHoliday(
        id: 'hol-3',
        name: 'Diwali (Deepavali)',
        date: DateTime(2026, 11, 8),
        type: CampusHolidayType.gazetted,
        description:
            'Festival of lights holiday and mid-semester campus break.',
      ),
      CampusHoliday(
        id: 'hol-4',
        name: 'Guru Nanak Jayanti',
        date: DateTime(2026, 11, 24),
        type: CampusHolidayType.gazetted,
        description: 'Birth anniversary of Guru Nanak Dev Ji.',
      ),
      CampusHoliday(
        id: 'hol-5',
        name: 'Winter Vacation Break',
        date: DateTime(2026, 12, 21),
        type: CampusHolidayType.institutional,
        description: 'End-of-semester winter vacation begins.',
      ),
    ]);

    _calendarItems.clear();
    _calendarItems.addAll([
      AcademicCalendarItem(
        id: 'cal-1',
        title: 'Mid-Term Examinations',
        startDate: DateTime(2026, 10, 14),
        endDate: DateTime(2026, 10, 21),
        eventType: CalendarEventType.exam,
        description:
            'Odd Semester Mid-Term exam session across all departments.',
      ),
      AcademicCalendarItem(
        id: 'cal-2',
        title: 'Course Registration & Fee Deadline',
        startDate: DateTime(2026, 10, 31),
        eventType: CalendarEventType.registration,
        description:
            'Final date to submit elective course choices and examination fees.',
      ),
      AcademicCalendarItem(
        id: 'cal-3',
        title: 'End-Semester Practical Lab Exams',
        startDate: DateTime(2026, 11, 25),
        endDate: DateTime(2026, 11, 30),
        eventType: CalendarEventType.exam,
        description: 'Laboratory vivas and programming project demonstrations.',
      ),
      AcademicCalendarItem(
        id: 'cal-4',
        title: 'End-Term Theory Examinations',
        startDate: DateTime(2026, 12, 4),
        endDate: DateTime(2026, 12, 18),
        eventType: CalendarEventType.exam,
        description:
            'Major end-semester theoretical written examination window.',
      ),
      AcademicCalendarItem(
        id: 'cal-5',
        title: 'Winter Break & Semester Concludes',
        startDate: DateTime(2026, 12, 21),
        endDate: DateTime(2027, 1, 3),
        eventType: CalendarEventType.holidayBreak,
        description: 'Inter-semester recess before Spring term commencement.',
      ),
    ]);

    _notices.clear();
    _notices.addAll([
      CampusNotice(
        id: 'not-1',
        title: 'Odd Semester Mid-Term Exam Schedule & Seating Guidelines',
        date: DateTime(2026, 9, 10),
        category: NoticeCategory.exams,
        issuingAuthority: 'Office of Controller of Examinations',
        extractedText:
            'The Mid-Term examinations for all B.Tech / M.Tech departments will commence on October 14, 2026. Hall tickets and slot details will be issued via the student portal on October 5. Bring valid Student ID Card to the exam hall.',
        summary:
            'Mid-term exams commence Oct 14. Hall tickets released Oct 5. Student ID required.',
        deadline: DateTime(2026, 10, 14),
        isRead: false,
      ),
      CampusNotice(
        id: 'not-2',
        title: 'Campus Placement Registration for Final Year Students',
        date: DateTime(2026, 9, 5),
        category: NoticeCategory.placement,
        issuingAuthority: 'Career Development Centre (CDC)',
        extractedText:
            'Registration is mandatory for all students seeking campus placements for AY 2026-27. Submit verified resumes and academic transcripts before September 25, 2026 05:00 PM.',
        summary:
            'Mandatory placement registration and resume submission due September 25.',
        deadline: DateTime(2026, 9, 25, 17, 0),
        isRead: false,
      ),
      CampusNotice(
        id: 'not-3',
        title: 'Hostel Mess Fee Rebate & Holiday Application Policy',
        date: DateTime(2026, 8, 28),
        category: NoticeCategory.administration,
        issuingAuthority: 'Chief Hostel Warden',
        extractedText:
            'Students leaving campus for more than 4 consecutive days during holidays or mid-term breaks may apply for mess fee rebate online at least 48 hours prior to departure.',
        summary:
            'Mess rebate eligible for leaves exceeding 4 days; apply 48h in advance.',
        isRead: true,
      ),
    ]);
  }

  static MessMenuData _buildDefaultMessMenu() {
    return MessMenuData(
      messName: 'Central Student Mess (Hostel Dining)',
      lastUpdated: DateTime.now(),
      days: {
        'Monday': const DayMenu(
          dayOfWeek: 'Monday',
          breakfast: MealMenu(
            mealName: 'Breakfast',
            timings: '07:30 AM - 09:30 AM',
            items: [
              'Poha with Sev',
              'Boiled Eggs / Sprouts',
              'Bread & Butter / Jam',
              'Tea / Coffee / Milk'
            ],
          ),
          lunch: MealMenu(
            mealName: 'Lunch',
            timings: '12:30 PM - 02:30 PM',
            items: [
              'Paneer Butter Masala',
              'Yellow Dal Tadka',
              'Jeera Rice',
              'Tandoori Roti',
              'Boondi Raita',
              'Salad'
            ],
          ),
          snacks: MealMenu(
            mealName: 'Snacks',
            timings: '05:00 PM - 06:00 PM',
            items: ['Veg Samosa with Mint Chutney', 'Masala Chai', 'Biscuits'],
          ),
          dinner: MealMenu(
            mealName: 'Dinner',
            timings: '07:30 PM - 09:30 PM',
            items: [
              'Aloo Gobi Matar',
              'Dal Makhani',
              'Steamed Rice',
              'Chapati',
              'Gulab Jamun'
            ],
          ),
        ),
        'Tuesday': const DayMenu(
          dayOfWeek: 'Tuesday',
          breakfast: MealMenu(
            mealName: 'Breakfast',
            timings: '07:30 AM - 09:30 AM',
            items: [
              'Idli Sambar with Coconut Chutney',
              'Medu Vada',
              'Fresh Fruit',
              'Filter Coffee / Tea'
            ],
          ),
          lunch: MealMenu(
            mealName: 'Lunch',
            timings: '12:30 PM - 02:30 PM',
            items: [
              'Rajma Masala',
              'Aloo Jeera',
              'Basmati Rice',
              'Phulka',
              'Curd',
              'Kachumber Salad'
            ],
          ),
          snacks: MealMenu(
            mealName: 'Snacks',
            timings: '05:00 PM - 06:00 PM',
            items: ['Aloo Tikki Chaat', 'Ginger Tea'],
          ),
          dinner: MealMenu(
            mealName: 'Dinner',
            timings: '07:30 PM - 09:30 PM',
            items: [
              'Palak Paneer',
              'Chana Dal',
              'Veg Pulao',
              'Roti',
              'Fruit Custard'
            ],
          ),
        ),
        'Wednesday': const DayMenu(
          dayOfWeek: 'Wednesday',
          breakfast: MealMenu(
            mealName: 'Breakfast',
            timings: '07:30 AM - 09:30 AM',
            items: [
              'Masala Dosa with Chutney & Sambar',
              'Banana',
              'Tea / Milk'
            ],
          ),
          lunch: MealMenu(
            mealName: 'Lunch',
            timings: '12:30 PM - 02:30 PM',
            items: [
              'Kadai Chicken / Shahi Paneer (Veg)',
              'Dal Fry',
              'Steamed Rice',
              'Butter Naan',
              'Cucumber Raita'
            ],
          ),
          snacks: MealMenu(
            mealName: 'Snacks',
            timings: '05:00 PM - 06:00 PM',
            items: ['Veg Cutlet with Ketchup', 'Coffee / Tea'],
          ),
          dinner: MealMenu(
            mealName: 'Dinner',
            timings: '07:30 PM - 09:30 PM',
            items: [
              'Mix Vegetable Curry',
              'Moong Dal',
              'Peas Pulao',
              'Roti',
              'Ice Cream'
            ],
          ),
        ),
        'Thursday': const DayMenu(
          dayOfWeek: 'Thursday',
          breakfast: MealMenu(
            mealName: 'Breakfast',
            timings: '07:30 AM - 09:30 AM',
            items: ['Aloo Paratha with Curd & Pickle', 'Boiled Eggs', 'Chai'],
          ),
          lunch: MealMenu(
            mealName: 'Lunch',
            timings: '12:30 PM - 02:30 PM',
            items: [
              'Chole Bhature',
              'Jeera Rice',
              'Yellow Dal',
              'Onion Salad',
              'Sweet Lassi'
            ],
          ),
          snacks: MealMenu(
            mealName: 'Snacks',
            timings: '05:00 PM - 06:00 PM',
            items: ['Dhokla with Green Chutney', 'Cardamom Tea'],
          ),
          dinner: MealMenu(
            mealName: 'Dinner',
            timings: '07:30 PM - 09:30 PM',
            items: [
              'Bhindi Do Pyaza',
              'Dal Tadka',
              'Steamed Rice',
              'Tawa Roti',
              'Moong Dal Halwa'
            ],
          ),
        ),
        'Friday': const DayMenu(
          dayOfWeek: 'Friday',
          breakfast: MealMenu(
            mealName: 'Breakfast',
            timings: '07:30 AM - 09:30 AM',
            items: [
              'Upma with Peanut Podi',
              'Boiled Eggs',
              'Bread & Jam',
              'Tea / Coffee'
            ],
          ),
          lunch: MealMenu(
            mealName: 'Lunch',
            timings: '12:30 PM - 02:30 PM',
            items: [
              'Egg Curry / Matar Paneer (Veg)',
              'Kadhi Pakora',
              'Khichdi / Steamed Rice',
              'Roti',
              'Papad'
            ],
          ),
          snacks: MealMenu(
            mealName: 'Snacks',
            timings: '05:00 PM - 06:00 PM',
            items: ['Pani Puri / Bhel Puri', 'Cold Lemonade / Tea'],
          ),
          dinner: MealMenu(
            mealName: 'Dinner',
            timings: '07:30 PM - 09:30 PM',
            items: [
              'Dum Aloo Kashmiri',
              'Dal Kolhapuri',
              'Veg Fried Rice',
              'Roti',
              'Rasgulla'
            ],
          ),
        ),
        'Saturday': const DayMenu(
          dayOfWeek: 'Saturday',
          breakfast: MealMenu(
            mealName: 'Breakfast',
            timings: '07:30 AM - 09:30 AM',
            items: ['Puri Bhaji with Pickle', 'Sprouts Salad', 'Chai / Coffee'],
          ),
          lunch: MealMenu(
            mealName: 'Lunch',
            timings: '12:30 PM - 02:30 PM',
            items: [
              'Hyderabadi Veg Dum Biryani',
              'Mirchi Ka Salan',
              'Onion Raita',
              'Dal Makhani',
              'Papad'
            ],
          ),
          snacks: MealMenu(
            mealName: 'Snacks',
            timings: '05:00 PM - 06:00 PM',
            items: ['Bread Pakora', 'Masala Tea'],
          ),
          dinner: MealMenu(
            mealName: 'Dinner',
            timings: '07:30 PM - 09:30 PM',
            items: [
              'Malai Kofta',
              'Dal Tadka',
              'Jeera Rice',
              'Butter Roti',
              'Kheer'
            ],
          ),
        ),
        'Sunday': const DayMenu(
          dayOfWeek: 'Sunday',
          breakfast: MealMenu(
            mealName: 'Breakfast',
            timings: '08:00 AM - 10:00 AM',
            items: [
              'Chole Kulche',
              'Omelette / Veg Sandwich',
              'Fresh Juice',
              'Tea / Coffee'
            ],
          ),
          lunch: MealMenu(
            mealName: 'Lunch',
            timings: '12:30 PM - 02:30 PM',
            items: [
              'Special Chicken Biryani / Paneer Biryani',
              'Burani Raita',
              'Salan',
              'Gulab Jamun'
            ],
          ),
          snacks: MealMenu(
            mealName: 'Snacks',
            timings: '05:00 PM - 06:00 PM',
            items: ['Pav Bhaji', 'Filter Coffee'],
          ),
          dinner: MealMenu(
            mealName: 'Dinner',
            timings: '07:30 PM - 09:30 PM',
            items: [
              'Light Khichdi with Ghee',
              'Aloo Chokha',
              'Curd',
              'Papad',
              'Fruit Salad'
            ],
          ),
        ),
      },
    );
  }
}
