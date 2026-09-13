import 'chat_message.dart';
import 'conversation_state.dart';
import 'rag_scope.dart';

class ConversationSession {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  String selectedRagScope;
  final List<AcademicChatMessage> messages;
  bool isPinned;

  final String? lectureId;
  final String? lectureTitle;
  final String? documentId;
  final String? documentTitle;
  final String? sourceType;
  final String? backgroundContext;

  // Discrete Subject-Aware RAG scope metadata
  String? ragScopeType;
  String? subjectId;
  String? subjectName;
  String? unitId;
  String? unitName;

  // Active conversational state & mode
  ActiveMode activeMode;
  ActiveQuizState? activeQuiz;

  ConversationSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.selectedRagScope = 'Operating Systems · Unit 1',
    List<AcademicChatMessage>? messages,
    this.isPinned = false,
    this.lectureId,
    this.lectureTitle,
    this.documentId,
    this.documentTitle,
    this.sourceType,
    this.backgroundContext,
    this.ragScopeType,
    this.subjectId,
    this.subjectName,
    this.unitId,
    this.unitName,
    this.activeMode = ActiveMode.chat,
    this.activeQuiz,
    RagScope? ragScope,
  }) : messages = messages ?? [] {
    if (ragScope != null) {
      this.ragScope = ragScope;
    }
  }

  /// Strongly-typed subject-aware RAG scope
  RagScope get ragScope {
    if (ragScopeType != null) {
      final type = RagScopeType.values.firstWhere(
        (t) => t.name == ragScopeType,
        orElse: () => RagScopeType.allNotes,
      );
      switch (type) {
        case RagScopeType.off:
          return const RagScope.off();
        case RagScopeType.allNotes:
          return const RagScope.allNotes();
        case RagScopeType.subject:
          if (subjectName != null && subjectName!.isNotEmpty) {
            return RagScope.subject(
              subjectName: subjectName!,
              subjectId: subjectId,
            );
          }
          return const RagScope.allNotes();
        case RagScopeType.subjectUnit:
          if (subjectName != null && unitName != null) {
            return RagScope.subjectUnit(
              subjectName: subjectName!,
              unitName: unitName!,
              subjectId: subjectId,
              unitId: unitId,
            );
          }
          return const RagScope.allNotes();
        case RagScopeType.document:
          if (documentId != null) {
            return RagScope.document(
              documentId: documentId!,
              documentName: documentTitle ?? documentId!,
              subjectId: subjectId,
              subjectName: subjectName,
              unitId: unitId,
              unitName: unitName,
            );
          }
          return const RagScope.allNotes();
        case RagScopeType.lecture:
          if (lectureId != null) {
            return RagScope.lecture(
              lectureId: lectureId!,
              lectureTitle: lectureTitle ?? lectureId!,
              subjectId: subjectId,
              subjectName: subjectName,
              unitId: unitId,
              unitName: unitName,
            );
          }
          return const RagScope.allNotes();
      }
    }

    // Fallback parsing from legacy selectedRagScope string
    if (selectedRagScope == 'Off') return const RagScope.off();
    if (selectedRagScope == 'All Notes') return const RagScope.allNotes();
    if (selectedRagScope == 'This Lecture' && lectureId != null) {
      return RagScope.lecture(
        lectureId: lectureId!,
        lectureTitle: lectureTitle ?? 'This Lecture',
        subjectId: subjectId,
        subjectName: subjectName,
      );
    }
    if (selectedRagScope == 'This Document' && documentId != null) {
      return RagScope.document(
        documentId: documentId!,
        documentName: documentTitle ?? 'This Document',
        subjectId: subjectId,
        subjectName: subjectName,
      );
    }

    // Format "Operating Systems · Unit 2" or "Unit 1 (OS)"
    if (selectedRagScope.contains('·')) {
      final parts = selectedRagScope.split('·').map((p) => p.trim()).toList();
      if (parts.length >= 2) {
        return RagScope.subjectUnit(
          subjectName: parts[0],
          unitName: parts[1],
        );
      }
    } else if (selectedRagScope.contains('OS')) {
      return RagScope.subjectUnit(
        subjectName: 'Operating Systems',
        unitName: 'Unit 1',
      );
    }

    return const RagScope.allNotes();
  }

  set ragScope(RagScope scope) {
    selectedRagScope = scope.displayLabel;
    ragScopeType = scope.type.name;
    subjectId = scope.subjectId;
    subjectName = scope.subjectName;
    unitId = scope.unitId;
    unitName = scope.unitName;
  }

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

  Map<String, dynamic> toJson() => toMap();
  factory ConversationSession.fromJson(Map<String, dynamic> json) =>
      ConversationSession.fromMap(json);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'selectedRagScope': selectedRagScope,
      'messages': messages.map((m) => m.toMap()).toList(),
      'isPinned': isPinned,
      'lectureId': lectureId,
      'lectureTitle': lectureTitle,
      'documentId': documentId,
      'documentTitle': documentTitle,
      'sourceType': sourceType,
      'backgroundContext': backgroundContext,
      'ragScopeType': ragScopeType,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'unitId': unitId,
      'unitName': unitName,
      'activeMode': activeMode.name,
      'activeQuiz': activeQuiz?.toMap(),
    };
  }

  factory ConversationSession.fromMap(Map<String, dynamic> map) {
    final rawMessages = map['messages'] as List<dynamic>? ?? [];
    final activeModeStr = map['activeMode'] as String?;
    final activeMode = ActiveMode.values.firstWhere(
      (m) => m.name == activeModeStr,
      orElse: () => ActiveMode.chat,
    );
    final rawActiveQuiz = map['activeQuiz'] as Map<String, dynamic>?;

    return ConversationSession(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'New Chat',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
      selectedRagScope:
          map['selectedRagScope'] as String? ?? 'Operating Systems · Unit 1',
      messages: rawMessages
          .map((m) => AcademicChatMessage.fromMap(m as Map<String, dynamic>))
          .toList(),
      isPinned: map['isPinned'] as bool? ?? false,
      lectureId: map['lectureId'] as String?,
      lectureTitle: map['lectureTitle'] as String?,
      documentId: map['documentId'] as String?,
      documentTitle: map['documentTitle'] as String?,
      sourceType: map['sourceType'] as String?,
      backgroundContext: map['backgroundContext'] as String?,
      ragScopeType: map['ragScopeType'] as String?,
      subjectId: map['subjectId'] as String?,
      subjectName: map['subjectName'] as String?,
      unitId: map['unitId'] as String?,
      unitName: map['unitName'] as String?,
      activeMode: activeMode,
      activeQuiz:
          rawActiveQuiz != null ? ActiveQuizState.fromMap(rawActiveQuiz) : null,
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
    String? lectureId,
    String? lectureTitle,
    String? documentId,
    String? documentTitle,
    String? sourceType,
    String? backgroundContext,
    String? ragScopeType,
    String? subjectId,
    String? subjectName,
    String? unitId,
    String? unitName,
    ActiveMode? activeMode,
    ActiveQuizState? activeQuiz,
  }) {
    return ConversationSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      selectedRagScope: selectedRagScope ?? this.selectedRagScope,
      messages: messages ?? List.from(this.messages),
      isPinned: isPinned ?? this.isPinned,
      lectureId: lectureId ?? this.lectureId,
      lectureTitle: lectureTitle ?? this.lectureTitle,
      documentId: documentId ?? this.documentId,
      documentTitle: documentTitle ?? this.documentTitle,
      sourceType: sourceType ?? this.sourceType,
      backgroundContext: backgroundContext ?? this.backgroundContext,
      ragScopeType: ragScopeType ?? this.ragScopeType,
      subjectId: subjectId ?? this.subjectId,
      subjectName: subjectName ?? this.subjectName,
      unitId: unitId ?? this.unitId,
      unitName: unitName ?? this.unitName,
      activeMode: activeMode ?? this.activeMode,
      activeQuiz: activeQuiz ?? this.activeQuiz,
    );
  }
}
