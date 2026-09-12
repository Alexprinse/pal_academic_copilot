import 'dart:convert';

enum TaskPriority { high, medium, low }

class Deadline {
  final String id;
  final String title;
  final String course;
  final DateTime dueDate;
  final TaskPriority priority;
  bool isCompleted;
  final bool isSpokenDetected;
  final String? audioTimestamp;
  final String? sourceLocation;

  Deadline({
    required this.id,
    required this.title,
    required this.course,
    required this.dueDate,
    this.priority = TaskPriority.medium,
    this.isCompleted = false,
    this.isSpokenDetected = false,
    this.audioTimestamp,
    this.sourceLocation,
  });

  Duration get timeLeft => dueDate.difference(DateTime.now());

  String get countdownString {
    final diff = timeLeft;
    if (diff.isNegative) return 'Overdue';
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h left';
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes % 60}m left';
    }
    return '${diff.inMinutes}m left';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'course': course,
      'dueDate': dueDate.toIso8601String(),
      'priority': priority.name,
      'isCompleted': isCompleted,
      'isSpokenDetected': isSpokenDetected,
      'audioTimestamp': audioTimestamp,
      'sourceLocation': sourceLocation,
    };
  }

  factory Deadline.fromMap(Map<String, dynamic> map) {
    return Deadline(
      id: map['id'] as String,
      title: map['title'] as String,
      course: map['course'] as String? ?? 'General',
      dueDate: DateTime.parse(map['dueDate'] as String),
      priority: TaskPriority.values.firstWhere(
        (e) => e.name == map['priority'],
        orElse: () => TaskPriority.medium,
      ),
      isCompleted: map['isCompleted'] as bool? ?? false,
      isSpokenDetected: map['isSpokenDetected'] as bool? ?? false,
      audioTimestamp: map['audioTimestamp'] as String?,
      sourceLocation: map['sourceLocation'] as String?,
    );
  }

  String toJson() => json.encode(toMap());
  factory Deadline.fromJson(String source) =>
      Deadline.fromMap(json.decode(source) as Map<String, dynamic>);
}
