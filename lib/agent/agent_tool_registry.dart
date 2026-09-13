import 'agent_context.dart';
import 'agent_tool.dart';
import 'agent_tool_call.dart';
import 'agent_tool_result.dart';

class AgentToolRegistry {
  final Map<String, AgentTool> _tools = {};

  AgentToolRegistry([Iterable<AgentTool>? initialTools]) {
    if (initialTools != null) {
      registerTools(initialTools);
    }
  }

  void registerTool(AgentTool tool) {
    _tools[tool.name] = tool;
  }

  void registerTools(Iterable<AgentTool> tools) {
    for (final tool in tools) {
      registerTool(tool);
    }
  }

  void unregisterTool(String name) {
    _tools.remove(name);
  }

  void clear() {
    _tools.clear();
  }

  AgentTool? getTool(String name) => _tools[name];

  bool hasTool(String name) => _tools.containsKey(name);

  List<AgentTool> get tools => _tools.values.toList();

  List<String> get toolNames => _tools.keys.toList();

  List<Map<String, dynamic>> get toolsSchema =>
      _tools.values.map((t) => t.toSchema()).toList();

  /// Formats all registered tools as a structured string for LLM system prompt instructions
  String formatToolsForPrompt() {
    if (_tools.isEmpty) return 'No tools available.';

    final buffer = StringBuffer();
    buffer.writeln('AVAILABLE ON-DEVICE TOOLS:');
    for (final tool in _tools.values) {
      buffer.writeln('- Tool: "${tool.name}"');
      buffer.writeln('  Description: ${tool.description}');
      buffer.writeln('  Read-Only: ${tool.isReadOnly}');
      if (tool.parameters.isEmpty) {
        buffer.writeln('  Arguments: none');
      } else {
        buffer.writeln('  Arguments:');
        for (final param in tool.parameters) {
          final req = param.required ? 'required' : 'optional';
          final defaultStr = param.defaultValue != null
              ? ', default: ${param.defaultValue}'
              : '';
          final enumStr = param.allowedValues != null
              ? ', allowed: [${param.allowedValues!.join(", ")}]'
              : '';
          buffer.writeln(
              '    • ${param.name} (${param.type.name}, $req$defaultStr$enumStr): ${param.description}');
        }
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  /// Builds a complete LLM system prompt incorporating the tools manifest
  /// and explicit `<tool_call>` protocol instructions.
  String buildSystemPrompt({String? baseInstructions}) {
    final buffer = StringBuffer();
    buffer.writeln(baseInstructions ??
        'You are Pal, the user\'s personal academic copilot running entirely on-device.\n'
            'You have direct access to on-device tools to inspect and manage the user\'s academic schedule, timetable, tasks, recordings, and knowledge vault.\n'
            'When the user asks about their schedule, classes, timetable, deadlines, tasks, or study notes, YOU MUST CALL THE APPROPRIATE TOOL.\n'
            'NEVER claim you do not know the user\'s schedule or classes without calling a tool first.\n'
            'NEVER hallucinate or invent timetable entries, tasks, or recordings.');
    buffer.writeln();
    buffer.writeln(formatToolsForPrompt());
    buffer.writeln();
    buffer.writeln('TOOL CALLING PROTOCOL:');
    buffer.writeln(
        'If an on-device tool is needed to fulfill the student\'s request, output a single tool call in the following format:');
    buffer.writeln('<tool_call>');
    buffer.writeln(
        '{\n  "name": "<tool_name>",\n  "arguments": { <arguments> }\n}');
    buffer.writeln('</tool_call>');
    buffer.writeln();
    buffer.writeln('RULES:\n'
        '1. If an available tool can answer the user\'s query, invoke it using the <tool_call> format.\n'
        '2. Output ONLY the <tool_call>...</tool_call> block without extra conversational filler when invoking a tool.\n'
        '3. If no tool is needed (e.g. general conversational greeting or conceptual academic explanation), answer directly.\n'
        '4. Never invent fake schedule or task data.');
    return buffer.toString().trim();
  }

  /// Safely executes a structured tool call.
  /// Guarantees:
  /// - Unknown tools are rejected immediately without execution.
  /// - Malformed arguments are caught before tool code runs.
  /// - Exceptions are caught and transformed into standardized failure results.
  Future<AgentToolResult> executeTool(
    AgentToolCall call, {
    AgentContext? context,
  }) async {
    final tool = _tools[call.tool];
    if (tool == null) {
      return AgentToolResult.unknownTool(call.tool);
    }

    // Apply default values for missing optional parameters
    final Map<String, dynamic> arguments = Map.from(call.arguments);
    for (final param in tool.parameters) {
      if (!arguments.containsKey(param.name) && param.defaultValue != null) {
        arguments[param.name] = param.defaultValue;
      }
    }

    // Validate arguments against schema
    final validation = tool.validateArguments(arguments);
    if (!validation.isValid) {
      return AgentToolResult.validationError(
        tool: call.tool,
        error: validation.error ?? 'Invalid arguments',
      );
    }

    // Safe execution
    try {
      return await tool.execute(arguments, context: context);
    } catch (e, stack) {
      return AgentToolResult.failure(
        tool: call.tool,
        message: 'Tool execution encountered an error: $e',
        error: '$e\n$stack',
      );
    }
  }
}
