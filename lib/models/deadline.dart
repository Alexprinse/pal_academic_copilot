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

  // Rich metadata & source linkage
  final String? description;
  final String? lectureId;
  final String? recordingId;
  final int? sourceTimestampSeconds;
  final String? evidenceText;
  final String? subjectId;
  final String? sourceType;
  final double confidence;
  final bool needsReview;
  final bool hasExplicitDueDate;
  final bool hasExplicitDueTime;

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
    this.description,
    this.lectureId,
    this.recordingId,
    this.sourceTimestampSeconds,
    this.evidenceText,
    this.subjectId,
    this.sourceType,
    this.confidence = 1.0,
    this.needsReview = false,
    this.hasExplicitDueDate = true,
    this.hasExplicitDueTime = false,
  });

  Duration get timeLeft => dueDate.difference(DateTime.now());

  String get countdownString {
    if (!hasExplicitDueDate) return 'No deadline set';
    final diff = timeLeft;
    if (diff.isNegative) return 'Overdue';
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h left';
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes % 60}m left';
    }
    return '${diff.inMinutes}m left';
  }

  Deadline copyWith({
    String? id,
    String? title,
    String? course,
    DateTime? dueDate,
    TaskPriority? priority,
    bool? isCompleted,
    bool? isSpokenDetected,
    String? audioTimestamp,
    String? sourceLocation,
    String? description,
    String? lectureId,
    String? recordingId,
    int? sourceTimestampSeconds,
    String? evidenceText,
    String? subjectId,
    String? sourceType,
    double? confidence,
    bool? needsReview,
    bool? hasExplicitDueDate,
    bool? hasExplicitDueTime,
  }) {
    return Deadline(
      id: id ?? this.id,
      title: title ?? this.title,
      course: course ?? this.course,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      isSpokenDetected: isSpokenDetected ?? this.isSpokenDetected,
      audioTimestamp: audioTimestamp ?? this.audioTimestamp,
      sourceLocation: sourceLocation ?? this.sourceLocation,
      description: description ?? this.description,
      lectureId: lectureId ?? this.lectureId,
      recordingId: recordingId ?? this.recordingId,
      sourceTimestampSeconds:
          sourceTimestampSeconds ?? this.sourceTimestampSeconds,
      evidenceText: evidenceText ?? this.evidenceText,
      subjectId: subjectId ?? this.subjectId,
      sourceType: sourceType ?? this.sourceType,
      confidence: confidence ?? this.confidence,
      needsReview: needsReview ?? this.needsReview,
      hasExplicitDueDate: hasExplicitDueDate ?? this.hasExplicitDueDate,
      hasExplicitDueTime: hasExplicitDueTime ?? this.hasExplicitDueTime,
    );
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
      'description': description,
      'lectureId': lectureId,
      'recordingId': recordingId,
      'sourceTimestampSeconds': sourceTimestampSeconds,
      'evidenceText': evidenceText,
      'subjectId': subjectId,
      'sourceType': sourceType,
      'confidence': confidence,
      'needsReview': needsReview,
      'hasExplicitDueDate': hasExplicitDueDate,
      'hasExplicitDueTime': hasExplicitDueTime,
    };
  }

  factory Deadline.fromMap(Map<String, dynamic> map) {
    return Deadline(
      id: map['id'] as String,
      title: map['title'] as String,
      course: map['course'] as String? ?? 'General',
      dueDate: DateTime.tryParse(map['dueDate'] as String? ?? '') ??
          DateTime.now().add(const Duration(days: 2)),
      priority: TaskPriority.values.firstWhere(
        (e) => e.name == map['priority'],
        orElse: () => TaskPriority.medium,
      ),
      isCompleted: map['isCompleted'] as bool? ?? false,
      isSpokenDetected: map['isSpokenDetected'] as bool? ?? false,
      audioTimestamp: map['audioTimestamp'] as String?,
      sourceLocation: map['sourceLocation'] as String?,
      description: map['description'] as String?,
      lectureId: map['lectureId'] as String?,
      recordingId: map['recordingId'] as String?,
      sourceTimestampSeconds: map['sourceTimestampSeconds'] as int?,
      evidenceText: map['evidenceText'] as String?,
      subjectId: map['subjectId'] as String?,
      sourceType: map['sourceType'] as String?,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      needsReview: map['needsReview'] as bool? ?? false,
      hasExplicitDueDate: map['hasExplicitDueDate'] as bool? ?? true,
      hasExplicitDueTime: map['hasExplicitDueTime'] as bool? ?? false,
    );
  }

  String toJson() => json.encode(toMap());
  factory Deadline.fromJson(String source) =>
      Deadline.fromMap(json.decode(source) as Map<String, dynamic>);
}
