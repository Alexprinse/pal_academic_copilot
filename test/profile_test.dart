import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/user_profile.dart';
import 'package:pal_academic_copilot/services/profile_service.dart';
import 'package:pal_academic_copilot/screens/profile_screen.dart';

void main() {
  group('Profile Service & Model Tests', () {
    test('Default profile has correct initials and details', () {
      final service = ProfileService.instance;
      expect(service.profile.name, 'Alex Palmer');
      expect(service.profile.initials, 'AP');
      expect(service.profile.courses.isNotEmpty, true);
    });

    test('Updating profile changes student name and initials', () {
      final service = ProfileService.instance;
      service.updateProfile(
        name: 'Jordan Rivera',
        studentId: 'JR-2026-9900',
        major: 'Data Science & AI',
      );

      expect(service.profile.name, 'Jordan Rivera');
      expect(service.profile.initials, 'JR');
      expect(service.profile.studentId, 'JR-2026-9900');
      expect(service.profile.major, 'Data Science & AI');

      // Reset back to Alex Palmer for consistent defaults
      service.updateProfile(
        name: 'Alex Palmer',
        studentId: 'STU-2026-8841',
        major: 'Computer Science & Engineering',
      );
    });

    test('Add and remove course works', () {
      final service = ProfileService.instance;
      const newCourse = EnrolledCourse(
        code: 'CS 590',
        title: 'Advanced Machine Learning',
        instructor: 'Dr. Turing',
        credits: 4,
        schedule: 'Wed 4 PM',
        room: 'Lab 300',
      );

      service.addCourse(newCourse);
      expect(service.profile.courses.any((c) => c.code == 'CS 590'), true);

      service.removeCourse('CS 590');
      expect(service.profile.courses.any((c) => c.code == 'CS 590'), false);
    });
  });

  group('Profile Screen Widget Tests', () {
    testWidgets('ProfileScreen renders student name and sections', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );

      // Verify Header
      expect(find.text('Student Profile'), findsOneWidget);
      expect(find.text('Alex Palmer'), findsOneWidget);
      expect(find.text('Academic Metrics'), findsOneWidget);
      expect(find.text('Enrolled Courses'), findsOneWidget);
      expect(find.text('On-Device Copilot & Privacy'), findsOneWidget);
      expect(find.text('Hardware & Local Sandbox'), findsOneWidget);
      expect(find.text('Export Academic Record & Summary'), findsOneWidget);
    });
  });
}
