class EnrolledCourse {
  final String code;
  final String title;
  final String instructor;
  final int credits;
  final String schedule;
  final String room;

  const EnrolledCourse({
    required this.code,
    required this.title,
    required this.instructor,
    required this.credits,
    required this.schedule,
    required this.room,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'title': title,
        'instructor': instructor,
        'credits': credits,
        'schedule': schedule,
        'room': room,
      };

  factory EnrolledCourse.fromJson(Map<String, dynamic> json) => EnrolledCourse(
        code: json['code'] as String? ?? '',
        title: json['title'] as String? ?? '',
        instructor: json['instructor'] as String? ?? '',
        credits: json['credits'] as int? ?? 3,
        schedule: json['schedule'] as String? ?? '',
        room: json['room'] as String? ?? '',
      );
}

class UserProfile {
  final String name;
  final String studentId;
  final String email;
  final String university;
  final String degree;
  final String major;
  final String academicYear;
  final String semester;
  final double gpa;
  final int streakDays;
  final double totalStudyHours;
  final double dailyGoalHours;
  final bool offlineStrictPrivacy;
  final bool autoExtractDeadlines;
  final bool smartAudioSummaries;
  final bool examAlerts;
  final List<EnrolledCourse> courses;

  const UserProfile({
    required this.name,
    required this.studentId,
    required this.email,
    required this.university,
    required this.degree,
    required this.major,
    required this.academicYear,
    required this.semester,
    required this.gpa,
    required this.streakDays,
    required this.totalStudyHours,
    required this.dailyGoalHours,
    this.offlineStrictPrivacy = true,
    this.autoExtractDeadlines = true,
    this.smartAudioSummaries = true,
    this.examAlerts = true,
    required this.courses,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'AP';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  UserProfile copyWith({
    String? name,
    String? studentId,
    String? email,
    String? university,
    String? degree,
    String? major,
    String? academicYear,
    String? semester,
    double? gpa,
    int? streakDays,
    double? totalStudyHours,
    double? dailyGoalHours,
    bool? offlineStrictPrivacy,
    bool? autoExtractDeadlines,
    bool? smartAudioSummaries,
    bool? examAlerts,
    List<EnrolledCourse>? courses,
  }) {
    return UserProfile(
      name: name ?? this.name,
      studentId: studentId ?? this.studentId,
      email: email ?? this.email,
      university: university ?? this.university,
      degree: degree ?? this.degree,
      major: major ?? this.major,
      academicYear: academicYear ?? this.academicYear,
      semester: semester ?? this.semester,
      gpa: gpa ?? this.gpa,
      streakDays: streakDays ?? this.streakDays,
      totalStudyHours: totalStudyHours ?? this.totalStudyHours,
      dailyGoalHours: dailyGoalHours ?? this.dailyGoalHours,
      offlineStrictPrivacy: offlineStrictPrivacy ?? this.offlineStrictPrivacy,
      autoExtractDeadlines: autoExtractDeadlines ?? this.autoExtractDeadlines,
      smartAudioSummaries: smartAudioSummaries ?? this.smartAudioSummaries,
      examAlerts: examAlerts ?? this.examAlerts,
      courses: courses ?? this.courses,
    );
  }

  static UserProfile defaultProfile() => const UserProfile(
        name: 'Alex Palmer',
        studentId: 'STU-2026-8841',
        email: 'alex.palmer@university.edu',
        university: 'Institute of Science & Technology',
        degree: 'Bachelor of Science',
        major: 'Computer Science & Engineering',
        academicYear: 'Junior (Year 3)',
        semester: 'Fall 2026',
        gpa: 3.88,
        streakDays: 14,
        totalStudyHours: 148.5,
        dailyGoalHours: 4.0,
        offlineStrictPrivacy: true,
        autoExtractDeadlines: true,
        smartAudioSummaries: true,
        examAlerts: true,
        courses: [
          EnrolledCourse(
            code: 'CS 301',
            title: 'Operating Systems: Concurrency & Locks',
            instructor: 'Dr. Aris Thorne',
            credits: 4,
            schedule: 'Mon / Wed 10:00 AM',
            room: 'Lecture Hall B3',
          ),
          EnrolledCourse(
            code: 'MATH 220',
            title: 'Discrete Mathematics: Graph Theory',
            instructor: 'Prof. Elena Vance',
            credits: 3,
            schedule: 'Tue / Thu 01:30 PM',
            room: 'Room 402',
          ),
          EnrolledCourse(
            code: 'PHYS 102',
            title: 'Engineering Physics: Wave Optics',
            instructor: 'Dr. Marcus Webb',
            credits: 4,
            schedule: 'Mon / Wed 03:30 PM',
            room: 'Science Complex C1',
          ),
          EnrolledCourse(
            code: 'CS 340',
            title: 'Database Systems & Query Optimization',
            instructor: 'Prof. Sarah Lin',
            credits: 3,
            schedule: 'Friday 09:00 AM',
            room: 'Tech Lab 105',
          ),
        ],
      );
}
