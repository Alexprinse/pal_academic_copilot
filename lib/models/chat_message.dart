import 'vault_item.dart';

class AcademicChatMessage {
  final String id;
  final String? conversationId;
  final String role; // 'user', 'assistant', 'system'
  String text;
  final DateTime timestamp;
  double? tokensPerSecond;
  final List<ChunkMatch> citations;
  final String? audioCitation;
  final String? evidenceSnippet;
  bool isGenerating;

  AcademicChatMessage({
    required this.id,
    this.conversationId,
    required this.role,
    required this.text,
    required this.timestamp,
    this.tokensPerSecond,
    this.citations = const [],
    this.audioCitation,
    this.evidenceSnippet,
    this.isGenerating = false,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isSystem => role == 'system';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversationId': conversationId,
      'role': role,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'tokensPerSecond': tokensPerSecond,
      'citations': citations.map((c) => c.toMap()).toList(),
      'audioCitation': audioCitation,
      'evidenceSnippet': evidenceSnippet,
    };
  }

  factory AcademicChatMessage.fromMap(Map<String, dynamic> map) {
    final rawCitations = map['citations'] as List<dynamic>? ?? [];
    return AcademicChatMessage(
      id: map['id'] as String,
      conversationId: map['conversationId'] as String?,
      role: map['role'] as String? ?? 'user',
      text: map['text'] as String? ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'] as String)
          : DateTime.now(),
      tokensPerSecond: (map['tokensPerSecond'] as num?)?.toDouble(),
      citations: rawCitations
          .map((c) => ChunkMatch.fromMap(c as Map<String, dynamic>))
          .toList(),
      audioCitation: map['audioCitation'] as String?,
      evidenceSnippet: map['evidenceSnippet'] as String?,
      isGenerating: false,
    );
  }

  AcademicChatMessage copyWith({
    String? id,
    String? conversationId,
    String? role,
    String? text,
    DateTime? timestamp,
    double? tokensPerSecond,
    List<ChunkMatch>? citations,
    String? audioCitation,
    String? evidenceSnippet,
    bool? isGenerating,
  }) {
    return AcademicChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      citations: citations ?? this.citations,
      audioCitation: audioCitation ?? this.audioCitation,
      evidenceSnippet: evidenceSnippet ?? this.evidenceSnippet,
      isGenerating: isGenerating ?? this.isGenerating,
    );
  }
}
