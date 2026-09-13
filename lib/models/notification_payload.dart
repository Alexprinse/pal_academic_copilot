import 'dart:convert';

/// Notification entity types supported across Pal
enum NotificationType {
  classReminder,
  recording,
  lecture,
  task,
  holiday,
  agent;

  String get value {
    switch (this) {
      case NotificationType.classReminder:
        return 'class';
      case NotificationType.recording:
        return 'recording';
      case NotificationType.lecture:
        return 'lecture';
      case NotificationType.task:
        return 'task';
      case NotificationType.holiday:
        return 'holiday';
      case NotificationType.agent:
        return 'agent';
    }
  }

  static NotificationType fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'class':
      case 'classreminder':
      case 'preclass':
        return NotificationType.classReminder;
      case 'recording':
        return NotificationType.recording;
      case 'lecture':
      case 'lecture_saved':
        return NotificationType.lecture;
      case 'task':
      case 'deadline':
        return NotificationType.task;
      case 'holiday':
      case 'academic':
        return NotificationType.holiday;
      case 'agent':
        return NotificationType.agent;
      default:
        return NotificationType.agent;
    }
  }
}

/// Notification action verbs triggered by tapping notification actions or bodies
enum NotificationAction {
  view,
  record,
  listen,
  transcribe,
  askPal,
  stop;

  String get value {
    switch (this) {
      case NotificationAction.view:
        return 'view';
      case NotificationAction.record:
        return 'record';
      case NotificationAction.listen:
        return 'listen';
      case NotificationAction.transcribe:
        return 'transcribe';
      case NotificationAction.askPal:
        return 'askPal';
      case NotificationAction.stop:
        return 'stop';
    }
  }

  static NotificationAction fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'view':
      case 'open':
        return NotificationAction.view;
      case 'record':
      case 'start_record':
        return NotificationAction.record;
      case 'listen':
      case 'play':
        return NotificationAction.listen;
      case 'transcribe':
        return NotificationAction.transcribe;
      case 'askpal':
      case 'ask_pal':
        return NotificationAction.askPal;
      case 'stop':
      case 'stop_record':
        return NotificationAction.stop;
      default:
        return NotificationAction.view;
    }
  }
}

/// Structured, type-safe payload embedded in every Pal notification.
class NotificationPayload {
  final NotificationType type;
  final String entityId;
  final NotificationAction action;
  final Map<String, dynamic> extra;

  const NotificationPayload({
    required this.type,
    required this.entityId,
    this.action = NotificationAction.view,
    this.extra = const {},
  });

  /// Serializes payload to JSON string for Android Notification Intent payload
  String toJsonString() {
    return jsonEncode({
      'type': type.value,
      'entityId': entityId,
      'action': action.value,
      'extra': extra,
    });
  }

  /// Parses payload safely from JSON string or legacy delimited string format
  static NotificationPayload? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final trimmed = raw.trim();

    // 1. Try JSON decoding
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final Map<String, dynamic> map = jsonDecode(trimmed);
        return NotificationPayload(
          type: NotificationType.fromString(map['type'] as String? ?? 'agent'),
          entityId: map['entityId'] as String? ?? '',
          action:
              NotificationAction.fromString(map['action'] as String? ?? 'view'),
          extra: map['extra'] is Map
              ? Map<String, dynamic>.from(map['extra'] as Map)
              : const {},
        );
      } catch (_) {}
    }

    // 2. Try colon-separated format (e.g. "class:tt-1:view" or "lecture:rec-2:listen")
    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      if (parts.length >= 2) {
        return NotificationPayload(
          type: NotificationType.fromString(parts[0]),
          entityId: parts[1],
          action: parts.length >= 3
              ? NotificationAction.fromString(parts[2])
              : NotificationAction.view,
        );
      }
    }

    // 3. Try legacy prefix format (e.g. "preclass_Data Structures", "recording_OS")
    if (trimmed.startsWith('preclass_')) {
      return NotificationPayload(
        type: NotificationType.classReminder,
        entityId: trimmed.replaceFirst('preclass_', ''),
        action: NotificationAction.view,
      );
    }
    if (trimmed.startsWith('recording_')) {
      return NotificationPayload(
        type: NotificationType.recording,
        entityId: trimmed.replaceFirst('recording_', ''),
        action: NotificationAction.view,
      );
    }
    if (trimmed.startsWith('lecture_saved_')) {
      return NotificationPayload(
        type: NotificationType.lecture,
        entityId: trimmed.replaceFirst('lecture_saved_', ''),
        action: NotificationAction.view,
      );
    }

    return NotificationPayload(
      type: NotificationType.agent,
      entityId: trimmed,
      action: NotificationAction.view,
    );
  }

  @override
  String toString() =>
      'NotificationPayload(${type.value}, entityId: $entityId, action: ${action.value})';
}
