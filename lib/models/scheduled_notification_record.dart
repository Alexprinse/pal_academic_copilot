/// Record for tracking and reconciling scheduled local notifications across app lifecycles.
class ScheduledNotificationRecord {
  final int id;
  final String type;
  final String entityId;
  final DateTime scheduledTime;
  final String title;
  final String body;
  final String payload;

  const ScheduledNotificationRecord({
    required this.id,
    required this.type,
    required this.entityId,
    required this.scheduledTime,
    required this.title,
    required this.body,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'entityId': entityId,
        'scheduledTime': scheduledTime.toIso8601String(),
        'title': title,
        'body': body,
        'payload': payload,
      };

  factory ScheduledNotificationRecord.fromJson(Map<String, dynamic> json) =>
      ScheduledNotificationRecord(
        id: json['id'] as int,
        type: json['type'] as String? ?? 'general',
        entityId: json['entityId'] as String? ?? '',
        scheduledTime:
            DateTime.tryParse(json['scheduledTime'] as String? ?? '') ??
                DateTime.now(),
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        payload: json['payload'] as String? ?? '',
      );
}
