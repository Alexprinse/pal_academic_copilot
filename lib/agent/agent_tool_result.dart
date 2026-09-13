import 'dart:convert';

class AgentToolResult {
  final String tool;
  final bool success;
  final String message;
  final dynamic data;
  final String? error;
  final bool requiresConfirmation;
  final DateTime timestamp;

  AgentToolResult({
    required this.tool,
    required this.success,
    required this.message,
    this.data,
    this.error,
    this.requiresConfirmation = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory AgentToolResult.success({
    required String tool,
    required String message,
    dynamic data,
  }) {
    return AgentToolResult(
      tool: tool,
      success: true,
      message: message,
      data: data,
    );
  }

  factory AgentToolResult.confirmationRequired({
    required String tool,
    required String message,
    dynamic data,
  }) {
    return AgentToolResult(
      tool: tool,
      success: true,
      requiresConfirmation: true,
      message: message,
      data: data,
    );
  }

  factory AgentToolResult.failure({
    required String tool,
    required String message,
    String? error,
    dynamic data,
  }) {
    return AgentToolResult(
      tool: tool,
      success: false,
      message: message,
      error: error,
      data: data,
    );
  }

  factory AgentToolResult.unknownTool(String toolName) {
    return AgentToolResult(
      tool: toolName,
      success: false,
      message:
          'Unknown tool: "$toolName". This tool is not registered in the system.',
      error: 'TOOL_NOT_FOUND',
    );
  }

  factory AgentToolResult.validationError({
    required String tool,
    required String error,
  }) {
    return AgentToolResult(
      tool: tool,
      success: false,
      message: 'Invalid arguments for tool "$tool": $error',
      error: 'ARGUMENT_VALIDATION_ERROR',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tool': tool,
      'success': success,
      'message': message,
      if (requiresConfirmation) 'requiresConfirmation': true,
      if (data != null) 'data': data,
      if (error != null) 'error': error,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  String toLlmContextString() {
    final buffer = StringBuffer();
    buffer.writeln('[Tool Result: $tool]');
    buffer.writeln('Status: ${success ? "Success" : "Failure"}');
    buffer.writeln('Message: $message');
    if (data != null) {
      try {
        final encoded = const JsonEncoder.withIndent('  ').convert(data);
        buffer.writeln('Data:\n$encoded');
      } catch (_) {
        buffer.writeln('Data: $data');
      }
    }
    if (error != null) {
      buffer.writeln('Error: $error');
    }
    return buffer.toString().trim();
  }
}
