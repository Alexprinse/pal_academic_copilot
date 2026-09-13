import 'dart:convert';

/// Category for Campus Notices
enum NoticeCategory {
  exams,
  placement,
  events,
  administration,
  general;

  String get displayName {
    switch (this) {
      case NoticeCategory.exams:
        return 'Examinations';
      case NoticeCategory.placement:
        return 'Placements & Internships';
      case NoticeCategory.events:
        return 'Campus Events';
      case NoticeCategory.administration:
        return 'Administration';
      case NoticeCategory.general:
        return 'General Notice';
    }
  }

  static NoticeCategory fromString(String? val) {
    if (val == null) return NoticeCategory.general;
    final clean = val.toLowerCase().trim();
    if (clean.contains('exam')) return NoticeCategory.exams;
    if (clean.contains('place') || clean.contains('intern')) {
      return NoticeCategory.placement;
    }
    if (clean.contains('event') || clean.contains('fest')) {
      return NoticeCategory.events;
    }
    if (clean.contains('admin')) return NoticeCategory.administration;
    return NoticeCategory.general;
  }
}

/// Type for Academic Calendar Events
enum CalendarEventType {
  semester,
  exam,
  registration,
  holidayBreak,
  event;

  String get displayName {
    switch (this) {
      case CalendarEventType.semester:
        return 'Semester Timeline';
      case CalendarEventType.exam:
        return 'Examination';
      case CalendarEventType.registration:
        return 'Registration & Fees';
      case CalendarEventType.holidayBreak:
        return 'Vacation & Break';
      case CalendarEventType.event:
        return 'Academic Event';
    }
  }

  static CalendarEventType fromString(String? val) {
    if (val == null) return CalendarEventType.event;
    final clean = val.toLowerCase().trim();
    if (clean.contains('exam')) return CalendarEventType.exam;
    if (clean.contains('sem')) return CalendarEventType.semester;
    if (clean.contains('reg') || clean.contains('fee')) {
      return CalendarEventType.registration;
    }
    if (clean.contains('break') ||
        clean.contains('vacation') ||
        clean.contains('holiday')) {
      return CalendarEventType.holidayBreak;
    }
    return CalendarEventType.event;
  }
}

/// Type for Campus Holidays
enum CampusHolidayType {
  national,
  gazetted,
  restricted,
  institutional;

  String get displayName {
    switch (this) {
      case CampusHolidayType.national:
        return 'National Holiday';
      case CampusHolidayType.gazetted:
        return 'Gazetted Holiday';
      case CampusHolidayType.restricted:
        return 'Restricted Holiday';
      case CampusHolidayType.institutional:
        return 'Institute Holiday';
    }
  }

  static CampusHolidayType fromString(String? val) {
    if (val == null) return CampusHolidayType.gazetted;
    final clean = val.toLowerCase().trim();
    if (clean.contains('national')) return CampusHolidayType.national;
    if (clean.contains('restrict')) return CampusHolidayType.restricted;
    if (clean.contains('inst') || clean.contains('college')) {
      return CampusHolidayType.institutional;
    }
    return CampusHolidayType.gazetted;
  }
}

/// Student ID Card Data Model (Guarded On-Device)
class IdCardData {
  final String? frontImagePath;
  final String? backImagePath;
  final String studentName;
  final String studentId;
  final String? rollNumber;
  final String department;
  final String institution;
  final String? validUntil;
  final bool isExtracted;
  final DateTime updatedAt;

  const IdCardData({
    this.frontImagePath,
    this.backImagePath,
    required this.studentName,
    required this.studentId,
    this.rollNumber,
    required this.department,
    required this.institution,
    this.validUntil,
    this.isExtracted = false,
    required this.updatedAt,
  });

  bool get hasImages => frontImagePath != null || backImagePath != null;

  IdCardData copyWith({
    String? frontImagePath,
    String? backImagePath,
    String? studentName,
    String? studentId,
    String? rollNumber,
    String? department,
    String? institution,
    String? validUntil,
    bool? isExtracted,
    DateTime? updatedAt,
  }) {
    return IdCardData(
      frontImagePath: frontImagePath ?? this.frontImagePath,
      backImagePath: backImagePath ?? this.backImagePath,
      studentName: studentName ?? this.studentName,
      studentId: studentId ?? this.studentId,
      rollNumber: rollNumber ?? this.rollNumber,
      department: department ?? this.department,
      institution: institution ?? this.institution,
      validUntil: validUntil ?? this.validUntil,
      isExtracted: isExtracted ?? this.isExtracted,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'frontImagePath': frontImagePath,
      'backImagePath': backImagePath,
      'studentName': studentName,
      'studentId': studentId,
      'rollNumber': rollNumber,
      'department': department,
      'institution': institution,
      'validUntil': validUntil,
      'isExtracted': isExtracted,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory IdCardData.fromMap(Map<String, dynamic> map) {
    return IdCardData(
      frontImagePath: map['frontImagePath'] as String?,
      backImagePath: map['backImagePath'] as String?,
      studentName: (map['studentName'] as String?) ?? 'Student',
      studentId: (map['studentId'] as String?) ?? '',
      rollNumber: map['rollNumber'] as String?,
      department: (map['department'] as String?) ?? '',
      institution: (map['institution'] as String?) ?? '',
      validUntil: map['validUntil'] as String?,
      isExtracted: (map['isExtracted'] as bool?) ?? false,
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory IdCardData.fromJson(String source) =>
      IdCardData.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

/// Single meal menu entry (e.g. Breakfast on Monday)
class MealMenu {
  final String mealName; // 'Breakfast', 'Lunch', 'Snacks', 'Dinner'
  final String timings;
  final List<String> items;
  final String? specialNote;

  const MealMenu({
    required this.mealName,
    required this.timings,
    required this.items,
    this.specialNote,
  });

  MealMenu copyWith({
    String? mealName,
    String? timings,
    List<String>? items,
    String? specialNote,
  }) {
    return MealMenu(
      mealName: mealName ?? this.mealName,
      timings: timings ?? this.timings,
      items: items ?? this.items,
      specialNote: specialNote ?? this.specialNote,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mealName': mealName,
      'timings': timings,
      'items': items,
      if (specialNote != null) 'specialNote': specialNote,
    };
  }

  factory MealMenu.fromMap(Map<String, dynamic> map) {
    return MealMenu(
      mealName: (map['mealName'] as String?) ?? 'Meal',
      timings: (map['timings'] as String?) ?? '',
      items:
          (map['items'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              [],
      specialNote: map['specialNote'] as String?,
    );
  }
}

/// Daily menu containing all 4 meals
class DayMenu {
  final String dayOfWeek; // 'Monday', 'Tuesday', ..., 'Sunday'
  final MealMenu breakfast;
  final MealMenu lunch;
  final MealMenu snacks;
  final MealMenu dinner;

  const DayMenu({
    required this.dayOfWeek,
    required this.breakfast,
    required this.lunch,
    required this.snacks,
    required this.dinner,
  });

  MealMenu getMeal(String name) {
    final lower = name.toLowerCase().trim();
    if (lower.contains('break')) return breakfast;
    if (lower.contains('lunch')) return lunch;
    if (lower.contains('snack') || lower.contains('tea')) return snacks;
    if (lower.contains('din')) return dinner;
    return lunch;
  }

  DayMenu copyWith({
    String? dayOfWeek,
    MealMenu? breakfast,
    MealMenu? lunch,
    MealMenu? snacks,
    MealMenu? dinner,
  }) {
    return DayMenu(
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      breakfast: breakfast ?? this.breakfast,
      lunch: lunch ?? this.lunch,
      snacks: snacks ?? this.snacks,
      dinner: dinner ?? this.dinner,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dayOfWeek': dayOfWeek,
      'breakfast': breakfast.toMap(),
      'lunch': lunch.toMap(),
      'snacks': snacks.toMap(),
      'dinner': dinner.toMap(),
    };
  }

  factory DayMenu.fromMap(Map<String, dynamic> map) {
    return DayMenu(
      dayOfWeek: (map['dayOfWeek'] as String?) ?? 'Monday',
      breakfast: MealMenu.fromMap((map['breakfast'] as Map<String, dynamic>?) ??
          {
            'mealName': 'Breakfast',
            'timings': '07:30 AM - 09:30 AM',
            'items': []
          }),
      lunch: MealMenu.fromMap((map['lunch'] as Map<String, dynamic>?) ??
          {'mealName': 'Lunch', 'timings': '12:30 PM - 02:30 PM', 'items': []}),
      snacks: MealMenu.fromMap((map['snacks'] as Map<String, dynamic>?) ??
          {
            'mealName': 'Snacks',
            'timings': '05:00 PM - 06:00 PM',
            'items': []
          }),
      dinner: MealMenu.fromMap((map['dinner'] as Map<String, dynamic>?) ??
          {
            'mealName': 'Dinner',
            'timings': '07:30 PM - 09:30 PM',
            'items': []
          }),
    );
  }
}

/// Full weekly mess schedule
class MessMenuData {
  final String messName;
  final Map<String, DayMenu> days; // keyed by 'Monday', 'Tuesday', etc.
  final DateTime lastUpdated;

  const MessMenuData({
    this.messName = 'Central Student Mess',
    required this.days,
    required this.lastUpdated,
  });

  DayMenu? getMenuForDayName(String day) {
    final clean = day.trim().toLowerCase();
    for (final entry in days.entries) {
      if (entry.key.toLowerCase().startsWith(clean.substring(0, 3))) {
        return entry.value;
      }
    }
    return days['Monday'];
  }

  DayMenu getMenuForDate(DateTime date) {
    const weekdayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final dayName = weekdayNames[date.weekday - 1];
    return days[dayName] ?? days['Monday']!;
  }

  Map<String, dynamic> toMap() {
    return {
      'messName': messName,
      'days': days.map((k, v) => MapEntry(k, v.toMap())),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory MessMenuData.fromMap(Map<String, dynamic> map) {
    final daysMap = <String, DayMenu>{};
    if (map['days'] != null) {
      final rawDays = map['days'] as Map<String, dynamic>;
      rawDays.forEach((k, v) {
        daysMap[k] = DayMenu.fromMap(v as Map<String, dynamic>);
      });
    }
    return MessMenuData(
      messName: (map['messName'] as String?) ?? 'Central Student Mess',
      days: daysMap,
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.parse(map['lastUpdated'] as String)
          : DateTime.now(),
    );
  }
}

/// Campus Holiday Model
class CampusHoliday {
  final String id;
  final String name;
  final DateTime date;
  final CampusHolidayType type;
  final String? description;

  const CampusHoliday({
    required this.id,
    required this.name,
    required this.date,
    this.type = CampusHolidayType.gazetted,
    this.description,
  });

  bool isUpcoming({DateTime? from}) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hDate = DateTime(date.year, date.month, date.day);
    return !hDate.isBefore(today);
  }

  int daysUntil({DateTime? from}) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hDate = DateTime(date.year, date.month, date.day);
    return hDate.difference(today).inDays;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'date': date.toIso8601String(),
      'type': type.name,
      if (description != null) 'description': description,
    };
  }

  factory CampusHoliday.fromMap(Map<String, dynamic> map) {
    return CampusHoliday(
      id: map['id'] as String,
      name: (map['name'] as String?) ?? 'Holiday',
      date: map['date'] != null
          ? DateTime.parse(map['date'] as String)
          : DateTime.now(),
      type: CampusHolidayType.fromString(map['type'] as String?),
      description: map['description'] as String?,
    );
  }
}

/// Academic Calendar Milestone
class AcademicCalendarItem {
  final String id;
  final String title;
  final DateTime startDate;
  final DateTime? endDate;
  final CalendarEventType eventType;
  final String? description;
  final String? originalDocPath;

  const AcademicCalendarItem({
    required this.id,
    required this.title,
    required this.startDate,
    this.endDate,
    this.eventType = CalendarEventType.event,
    this.description,
    this.originalDocPath,
  });

  bool isUpcoming({DateTime? from}) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final effectiveEnd = endDate ?? startDate;
    final end =
        DateTime(effectiveEnd.year, effectiveEnd.month, effectiveEnd.day);
    return !end.isBefore(today);
  }

  int daysUntil({DateTime? from}) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    return start.difference(today).inDays;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'startDate': startDate.toIso8601String(),
      if (endDate != null) 'endDate': endDate!.toIso8601String(),
      'eventType': eventType.name,
      if (description != null) 'description': description,
      if (originalDocPath != null) 'originalDocPath': originalDocPath,
    };
  }

  factory AcademicCalendarItem.fromMap(Map<String, dynamic> map) {
    return AcademicCalendarItem(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? 'Academic Event',
      startDate: map['startDate'] != null
          ? DateTime.parse(map['startDate'] as String)
          : DateTime.now(),
      endDate: map['endDate'] != null
          ? DateTime.parse(map['endDate'] as String)
          : null,
      eventType: CalendarEventType.fromString(map['eventType'] as String?),
      description: map['description'] as String?,
      originalDocPath: map['originalDocPath'] as String?,
    );
  }
}

/// Campus Notice / Circular
class CampusNotice {
  final String id;
  final String title;
  final DateTime date;
  final NoticeCategory category;
  final String? issuingAuthority;
  final String? filePath;
  final String extractedText;
  final String? summary;
  final DateTime? deadline;
  final bool isRead;

  const CampusNotice({
    required this.id,
    required this.title,
    required this.date,
    this.category = NoticeCategory.general,
    this.issuingAuthority,
    this.filePath,
    required this.extractedText,
    this.summary,
    this.deadline,
    this.isRead = false,
  });

  CampusNotice copyWith({
    String? id,
    String? title,
    DateTime? date,
    NoticeCategory? category,
    String? issuingAuthority,
    String? filePath,
    String? extractedText,
    String? summary,
    DateTime? deadline,
    bool? isRead,
  }) {
    return CampusNotice(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      category: category ?? this.category,
      issuingAuthority: issuingAuthority ?? this.issuingAuthority,
      filePath: filePath ?? this.filePath,
      extractedText: extractedText ?? this.extractedText,
      summary: summary ?? this.summary,
      deadline: deadline ?? this.deadline,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'date': date.toIso8601String(),
      'category': category.name,
      if (issuingAuthority != null) 'issuingAuthority': issuingAuthority,
      if (filePath != null) 'filePath': filePath,
      'extractedText': extractedText,
      if (summary != null) 'summary': summary,
      if (deadline != null) 'deadline': deadline!.toIso8601String(),
      'isRead': isRead,
    };
  }

  factory CampusNotice.fromMap(Map<String, dynamic> map) {
    return CampusNotice(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? 'Circular Notice',
      date: map['date'] != null
          ? DateTime.parse(map['date'] as String)
          : DateTime.now(),
      category: NoticeCategory.fromString(map['category'] as String?),
      issuingAuthority: map['issuingAuthority'] as String?,
      filePath: map['filePath'] as String?,
      extractedText: (map['extractedText'] as String?) ?? '',
      summary: map['summary'] as String?,
      deadline: map['deadline'] != null
          ? DateTime.parse(map['deadline'] as String)
          : null,
      isRead: (map['isRead'] as bool?) ?? false,
    );
  }
}
