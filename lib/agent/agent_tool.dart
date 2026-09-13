import 'agent_context.dart';
import 'agent_parameter.dart';
import 'agent_tool_result.dart';

abstract class AgentTool {
  final String name;
  final String description;
  final List<AgentParameter> parameters;
  final bool isReadOnly;

  const AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
    this.isReadOnly = true,
  });

  /// Generates a standardized schema map for LLM system prompt / tool calling format
  Map<String, dynamic> toSchema() {
    final properties = <String, dynamic>{};
    final requiredParams = <String>[];

    for (final param in parameters) {
      properties[param.name] = param.toSchema();
      if (param.required) {
        requiredParams.add(param.name);
      }
    }

    return {
      'name': name,
      'description': description,
      'readOnly': isReadOnly,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': requiredParams,
      },
    };
  }

  /// Validates all parameters against the tool schema before execution
  AgentValidationResult validateArguments(Map<String, dynamic> arguments) {
    // 1. Check all required parameters are present
    for (final param in parameters) {
      if (param.required &&
          (!arguments.containsKey(param.name) ||
              arguments[param.name] == null)) {
        return AgentValidationResult.invalid(
            'Missing required parameter: "${param.name}"');
      }
    }

    // 2. Validate types for each provided argument
    for (final entry in arguments.entries) {
      final param = parameters.cast<AgentParameter?>().firstWhere(
            (p) => p?.name == entry.key,
            orElse: () => null,
          );

      if (param != null) {
        final result = param.validate(entry.value);
        if (!result.isValid) {
          return result;
        }
      }
    }

    return const AgentValidationResult.valid();
  }

  /// Executes the tool safely with validated arguments
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  });
}
