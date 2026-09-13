import 'agent_tool_call.dart';
import 'agent_tool_result.dart';

class AgentResponse {
  final String text;
  final List<AgentToolCall> toolCalls;
  final List<AgentToolResult> toolResults;
  final String? rawLlmOutput;

  AgentResponse({
    required this.text,
    List<AgentToolCall>? toolCalls,
    List<AgentToolResult>? toolResults,
    this.rawLlmOutput,
  })  : toolCalls = toolCalls ?? [],
        toolResults = toolResults ?? [];

  bool get hasToolExecution => toolCalls.isNotEmpty;
  bool get isDirectAnswer => toolCalls.isEmpty;
  bool get requiresConfirmation =>
      toolResults.any((r) => r.requiresConfirmation);

  AgentToolResult? get firstResult =>
      toolResults.isNotEmpty ? toolResults.first : null;

  AgentToolResult? get pendingConfirmationResult {
    for (final r in toolResults) {
      if (r.requiresConfirmation) return r;
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'hasToolExecution': hasToolExecution,
      'toolCalls': toolCalls.map((c) => c.toJson()).toList(),
      'toolResults': toolResults.map((r) => r.toJson()).toList(),
    };
  }
}
