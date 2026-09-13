import 'dart:convert';

class AgentToolCall {
  final String tool;
  final Map<String, dynamic> arguments;
  final String? id;
  final String? rawInput;

  const AgentToolCall({
    required this.tool,
    required this.arguments,
    this.id,
    this.rawInput,
  });

  factory AgentToolCall.fromJson(Map<String, dynamic> json) {
    final toolName = json['tool'] ?? json['name'] ?? json['function'] ?? '';
    final rawArgs =
        json['arguments'] ?? json['parameters'] ?? <String, dynamic>{};
    final Map<String, dynamic> parsedArgs = rawArgs is Map<String, dynamic>
        ? rawArgs
        : (rawArgs is Map
            ? Map<String, dynamic>.from(rawArgs)
            : <String, dynamic>{});

    return AgentToolCall(
      tool: toolName.toString().trim(),
      arguments: parsedArgs,
      id: json['id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': tool,
      'arguments': arguments,
      if (id != null) 'id': id,
    };
  }

  /// Formats the tool call using the standard XML-tag protocol for on-device LLMs.
  String toXmlProtocolString() {
    final prettyJson = const JsonEncoder.withIndent('  ').convert({
      'name': tool,
      'arguments': arguments,
    });
    return '<tool_call>\n$prettyJson\n</tool_call>';
  }

  /// Extracts all tool calls from text (supporting `<tool_call>` tags, markdown code blocks, or embedded JSON).
  static List<AgentToolCall> extractCalls(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return [];

    final List<AgentToolCall> found = [];

    // 1. Check for <tool_call> ... </tool_call> blocks
    final tagRegex = RegExp(r'<tool_call>\s*([\s\S]*?)\s*<\/tool_call>',
        caseSensitive: false);
    for (final match in tagRegex.allMatches(clean)) {
      final inner = match.group(1)?.trim();
      if (inner != null && inner.isNotEmpty) {
        final parsed = _tryDecodeJson(inner);
        if (parsed != null) {
          found.add(parsed);
        }
      }
    }
    if (found.isNotEmpty) return found;

    // 2. Check for markdown code blocks ```tool_call ... ``` or ```json ... ```
    final mdRegex = RegExp(r'```(?:json|tool_call)?\s*([\s\S]*?)\s*```',
        caseSensitive: false);
    for (final match in mdRegex.allMatches(clean)) {
      final inner = match.group(1)?.trim();
      if (inner != null && inner.isNotEmpty) {
        final parsed = _tryDecodeJson(inner);
        if (parsed != null) {
          found.add(parsed);
        }
      }
    }
    if (found.isNotEmpty) return found;

    // 3. Fallback: single call check
    final single = tryParse(clean);
    if (single != null) {
      return [single];
    }

    return [];
  }

  /// Attempts to parse a single structured tool call from LLM output.
  static AgentToolCall? tryParse(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return null;

    // 1. Check <tool_call> tag
    final tagMatch = RegExp(r'<tool_call>\s*([\s\S]*?)\s*<\/tool_call>',
            caseSensitive: false)
        .firstMatch(clean);
    if (tagMatch != null) {
      final inner = tagMatch.group(1)?.trim();
      if (inner != null && inner.isNotEmpty) {
        final parsed = _tryDecodeJson(inner);
        if (parsed != null) return parsed;
      }
    }

    // 2. Check markdown code block ```json ... ```
    final mdMatch = RegExp(r'```(?:json|tool_call)?\s*([\s\S]*?)\s*```',
            caseSensitive: false)
        .firstMatch(clean);
    if (mdMatch != null) {
      final jsonBlock = mdMatch.group(1)?.trim();
      if (jsonBlock != null && jsonBlock.isNotEmpty) {
        final parsed = _tryDecodeJson(jsonBlock);
        if (parsed != null) return parsed;
      }
    }

    // 3. Try parsing raw string as JSON
    final directParsed = _tryDecodeJson(clean);
    if (directParsed != null) return directParsed;

    // 4. Search for embedded JSON object containing "tool" or "name"
    final braceStart = clean.indexOf('{');
    final braceEnd = clean.lastIndexOf('}');
    if (braceStart != -1 && braceEnd != -1 && braceEnd > braceStart) {
      final candidate = clean.substring(braceStart, braceEnd + 1);
      final candidateParsed = _tryDecodeJson(candidate);
      if (candidateParsed != null) return candidateParsed;
    }

    return null;
  }

  static AgentToolCall? _tryDecodeJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        if (map.containsKey('tool') ||
            map.containsKey('function') ||
            map.containsKey('name')) {
          return AgentToolCall.fromJson(map);
        }
      }
    } catch (_) {
      // Ignore parse failure
    }
    return null;
  }
}
