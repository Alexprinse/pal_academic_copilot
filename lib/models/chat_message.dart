import 'vault_item.dart';

class AcademicChatMessage {
  final String id;
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
}
