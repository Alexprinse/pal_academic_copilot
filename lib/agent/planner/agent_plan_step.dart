import '../agent_tool_result.dart';

enum AgentPlanStepStatus {
  pending,
  running,
  success,
  failed,
  cancelled,
}

class AgentPlanStep {
  final String id;
  final String tool;
  Map<String, dynamic> arguments;
  AgentPlanStepStatus status;
  AgentToolResult? result;
  final String description;
  final bool dependsOnPrevious;
  final String? dependencyKey;

  AgentPlanStep({
    required this.id,
    required this.tool,
    required this.arguments,
    this.status = AgentPlanStepStatus.pending,
    this.result,
    required this.description,
    this.dependsOnPrevious = false,
    this.dependencyKey,
  });

  bool get isPending => status == AgentPlanStepStatus.pending;
  bool get isRunning => status == AgentPlanStepStatus.running;
  bool get isSuccess => status == AgentPlanStepStatus.success;
  bool get isFailed => status == AgentPlanStepStatus.failed;
  bool get isCancelled => status == AgentPlanStepStatus.cancelled;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tool': tool,
      'arguments': arguments,
      'status': status.name,
      if (result != null) 'result': result!.toJson(),
      'description': description,
      'dependsOnPrevious': dependsOnPrevious,
      if (dependencyKey != null) 'dependencyKey': dependencyKey,
    };
  }
}
