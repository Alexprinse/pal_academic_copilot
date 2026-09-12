import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';

class ProfileService extends ChangeNotifier {
  static final ProfileService instance = ProfileService._();
  ProfileService._();

  UserProfile _profile = UserProfile.defaultProfile();
  UserProfile get profile => _profile;

  Future<void> init() async {
    // Ready for persistence or default loading
    notifyListeners();
  }

  void updateProfile({
    String? name,
    String? studentId,
    String? email,
    String? university,
    String? degree,
    String? major,
    String? academicYear,
    String? semester,
    double? gpa,
    double? dailyGoalHours,
  }) {
    _profile = _profile.copyWith(
      name: name,
      studentId: studentId,
      email: email,
      university: university,
      degree: degree,
      major: major,
      academicYear: academicYear,
      semester: semester,
      gpa: gpa,
      dailyGoalHours: dailyGoalHours,
    );
    notifyListeners();
  }

  void updatePrivacyAndAiSettings({
    bool? offlineStrictPrivacy,
    bool? autoExtractDeadlines,
    bool? smartAudioSummaries,
    bool? examAlerts,
  }) {
    _profile = _profile.copyWith(
      offlineStrictPrivacy: offlineStrictPrivacy,
      autoExtractDeadlines: autoExtractDeadlines,
      smartAudioSummaries: smartAudioSummaries,
      examAlerts: examAlerts,
    );
    notifyListeners();
  }

  void addCourse(EnrolledCourse course) {
    final updatedList = List<EnrolledCourse>.from(_profile.courses)..add(course);
    _profile = _profile.copyWith(courses: updatedList);
    notifyListeners();
  }

  void removeCourse(String courseCode) {
    final updatedList = _profile.courses.where((c) => c.code != courseCode).toList();
    _profile = _profile.copyWith(courses: updatedList);
    notifyListeners();
  }

  void logStudyHours(double hours) {
    _profile = _profile.copyWith(
      totalStudyHours: _profile.totalStudyHours + hours,
    );
    notifyListeners();
  }

  String exportAcademicSummary() {
    final Map<String, dynamic> data = {
      'student': {
        'name': _profile.name,
        'studentId': _profile.studentId,
        'email': _profile.email,
        'university': _profile.university,
        'degree': _profile.degree,
        'major': _profile.major,
        'academicYear': _profile.academicYear,
        'semester': _profile.semester,
        'gpa': _profile.gpa,
      },
      'metrics': {
        'streakDays': _profile.streakDays,
        'totalStudyHours': _profile.totalStudyHours,
        'dailyGoalHours': _profile.dailyGoalHours,
      },
      'courses': _profile.courses.map((c) => c.toJson()).toList(),
      'security': {
        'onDeviceOnly': _profile.offlineStrictPrivacy,
        'exportedAt': DateTime.now().toIso8601String(),
      }
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}
