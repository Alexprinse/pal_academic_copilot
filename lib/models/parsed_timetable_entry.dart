import 'package:flutter/material.dart';
import 'timetable_entry.dart';

/// Represents a candidate class extracted from a timetable image before user confirmation.
class ParsedTimetableEntry {
  final String id;
  String subject;
  String dayOfWeek; // 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  String startTime; // e.g. '09:00 AM'
  String endTime; // e.g. '10:00 AM'
  String? room;
  String? professor;
  String? notes;
  String type; // 'Lecture', 'Lab', 'Tutorial', 'Seminar'
  final double confidence; // 0.0 to 1.0
  bool requiresReview;
  String? reviewReason;
  bool hasExplicitEndTime;
  final Rect? sourceBoundingBox;

  ParsedTimetableEntry({
    required this.id,
    required this.subject,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.room,
    this.professor,
    this.notes,
    this.type = 'Lecture',
    this.confidence = 0.9,
    this.requiresReview = false,
    this.reviewReason,
    this.hasExplicitEndTime = false,
    this.sourceBoundingBox,
  });

  /// Convert into standard persistent [TimetableEntry].
  TimetableEntry toTimetableEntry() {
    return TimetableEntry(
      id: id,
      subject: subject.trim(),
      dayOfWeek: dayOfWeek.trim(),
      startTime: startTime.trim(),
      endTime: endTime.trim(),
      room: room?.trim().isNotEmpty == true ? room!.trim() : null,
      professor:
          professor?.trim().isNotEmpty == true ? professor!.trim() : null,
      notes: notes?.trim().isNotEmpty == true ? notes!.trim() : null,
      type: type,
      repeatWeekly: true,
    );
  }

  ParsedTimetableEntry copyWith({
    String? id,
    String? subject,
    String? dayOfWeek,
    String? startTime,
    String? endTime,
    String? room,
    String? professor,
    String? notes,
    String? type,
    double? confidence,
    bool? requiresReview,
    String? reviewReason,
    bool? hasExplicitEndTime,
    Rect? sourceBoundingBox,
  }) {
    return ParsedTimetableEntry(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      room: room ?? this.room,
      professor: professor ?? this.professor,
      notes: notes ?? this.notes,
      type: type ?? this.type,
      confidence: confidence ?? this.confidence,
      requiresReview: requiresReview ?? this.requiresReview,
      reviewReason: reviewReason ?? this.reviewReason,
      hasExplicitEndTime: hasExplicitEndTime ?? this.hasExplicitEndTime,
      sourceBoundingBox: sourceBoundingBox ?? this.sourceBoundingBox,
    );
  }
}
