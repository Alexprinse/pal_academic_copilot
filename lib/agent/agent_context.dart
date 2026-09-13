class AgentContext {
  final String? userId;
  final String? conversationId;
  final DateTime currentDateTime;
  final String? activeRagScope;
  final Map<String, dynamic> metadata;

  AgentContext({
    this.userId,
    this.conversationId,
    DateTime? currentDateTime,
    this.activeRagScope,
    Map<String, dynamic>? metadata,
  })  : currentDateTime = currentDateTime ?? DateTime.now(),
        metadata = metadata ?? {};

  AgentContext copyWith({
    String? userId,
    String? conversationId,
    DateTime? currentDateTime,
    String? activeRagScope,
    Map<String, dynamic>? metadata,
  }) {
    return AgentContext(
      userId: userId ?? this.userId,
      conversationId: conversationId ?? this.conversationId,
      currentDateTime: currentDateTime ?? this.currentDateTime,
      activeRagScope: activeRagScope ?? this.activeRagScope,
      metadata: metadata ?? Map.from(this.metadata),
    );
  }
}
