class TimetableEntry {
  final String id;
  final String subject;
  final String dayOfWeek; // 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  final String startTime; // e.g. '09:00 AM'
  final String endTime; // e.g. '10:00 AM'
  final String? room;
  final String? professor;
  final String? notes;
  final bool repeatWeekly;
  final String type; // 'Lecture', 'Lab', 'Tutorial', 'Seminar'

  const TimetableEntry({
    required this.id,
    required this.subject,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.room,
    this.professor,
    this.notes,
    this.repeatWeekly = true,
    this.type = 'Lecture',
  });

  /// Formatted duration string e.g. "1 hour", "1 hr 30 min"
  String get durationString {
    final startMinutes = _timeStringToMinutes(startTime);
    final endMinutes = _timeStringToMinutes(endTime);
    int diff = endMinutes - startMinutes;
    if (diff <= 0) diff += 24 * 60;

    final hours = diff ~/ 60;
    final minutes = diff % 60;

    if (hours > 0 && minutes > 0) {
      return '$hours hr $minutes min';
    } else if (hours > 0) {
      return hours == 1 ? '1 hour' : '$hours hours';
    } else {
      return '$minutes min';
    }
  }

  /// Start hour as a double for timeline positioning (e.g. 9.5 for 9:30 AM)
  double get startHourDouble {
    final totalMins = _timeStringToMinutes(startTime);
    return totalMins / 60.0;
  }

  /// End hour as a double
  double get endHourDouble {
    final totalMins = _timeStringToMinutes(endTime);
    return totalMins / 60.0;
  }

  static int _timeStringToMinutes(String timeStr) {
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPm = clean.contains('PM');
      final isAm = clean.contains('AM');

      final parts = clean.replaceAll(RegExp(r'[^\d:]'), '').split(':');
      int hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? int.parse(parts[1]) : 0;

      if (isPm && hour < 12) hour += 12;
      if (isAm && hour == 12) hour = 0;

      return hour * 60 + minute;
    } catch (_) {
      return 9 * 60; // fallback 9:00 AM
    }
  }

  TimetableEntry copyWith({
    String? id,
    String? subject,
    String? dayOfWeek,
    String? startTime,
    String? endTime,
    String? room,
    String? professor,
    String? notes,
    bool? repeatWeekly,
    String? type,
  }) {
    return TimetableEntry(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      room: room ?? this.room,
      professor: professor ?? this.professor,
      notes: notes ?? this.notes,
      repeatWeekly: repeatWeekly ?? this.repeatWeekly,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subject': subject,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'room': room,
      'professor': professor,
      'notes': notes,
      'repeatWeekly': repeatWeekly,
      'type': type,
    };
  }

  factory TimetableEntry.fromJson(Map<String, dynamic> json) {
    return TimetableEntry(
      id: json['id'] as String,
      subject: json['subject'] as String,
      dayOfWeek: json['dayOfWeek'] as String,
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      room: json['room'] as String?,
      professor: json['professor'] as String?,
      notes: json['notes'] as String?,
      repeatWeekly: (json['repeatWeekly'] as bool?) ?? true,
      type: (json['type'] as String?) ?? 'Lecture',
    );
  }
}
