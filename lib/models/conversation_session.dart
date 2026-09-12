import 'chat_message.dart';

class ConversationSession {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  String selectedRagScope;
  final List<AcademicChatMessage> messages;
  bool isPinned;

  ConversationSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.selectedRagScope = 'Unit 1 (OS)',
    List<AcademicChatMessage>? messages,
    this.isPinned = false,
  }) : messages = messages ?? [];

  int get userMessagesCount => messages.where((m) => m.role == 'user').length;

  AcademicChatMessage? get firstUserMessage {
    try {
      return messages.firstWhere((m) => m.role == 'user');
    } catch (_) {
      return null;
    }
  }

  AcademicChatMessage? get lastMessage {
    return messages.isNotEmpty ? messages.last : null;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'selectedRagScope': selectedRagScope,
      'messages': messages.map((m) => m.toMap()).toList(),
      'isPinned': isPinned,
    };
  }

  factory ConversationSession.fromMap(Map<String, dynamic> map) {
    final rawMessages = map['messages'] as List<dynamic>? ?? [];
    return ConversationSession(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'New Chat',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
      selectedRagScope: map['selectedRagScope'] as String? ?? 'Unit 1 (OS)',
      messages: rawMessages
          .map((m) => AcademicChatMessage.fromMap(m as Map<String, dynamic>))
          .toList(),
      isPinned: map['isPinned'] as bool? ?? false,
    );
  }

  ConversationSession copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? selectedRagScope,
    List<AcademicChatMessage>? messages,
    bool? isPinned,
  }) {
    return ConversationSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      selectedRagScope: selectedRagScope ?? this.selectedRagScope,
      messages: messages ?? List.from(this.messages),
      isPinned: isPinned ?? this.isPinned,
    );
  }
}
