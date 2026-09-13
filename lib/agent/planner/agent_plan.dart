import 'agent_plan_step.dart';

enum AgentPlanStatus {
  pending,
  running,
  success,
  partialSuccess,
  failed,
  cancelled,
}

class AgentPlan {
  final String planId;
  final String originalRequest;
  final List<AgentPlanStep> steps;
  int currentStepIndex;
  AgentPlanStatus status;
  final String? missingInformationQuestion;

  AgentPlan({
    required this.planId,
    required this.originalRequest,
    required this.steps,
    this.currentStepIndex = 0,
    this.status = AgentPlanStatus.pending,
    this.missingInformationQuestion,
  });

  bool get isBlockedOnMissingInfo =>
      missingInformationQuestion != null &&
      missingInformationQuestion!.isNotEmpty;

  bool get isCompleted =>
      status == AgentPlanStatus.success ||
      status == AgentPlanStatus.partialSuccess ||
      status == AgentPlanStatus.failed ||
      status == AgentPlanStatus.cancelled;

  bool get hasFailures => steps.any((s) => s.isFailed);

  bool get allSucceeded => steps.isNotEmpty && steps.every((s) => s.isSuccess);

  AgentPlanStep? get currentStep =>
      currentStepIndex < steps.length ? steps[currentStepIndex] : null;

  List<AgentPlanStep> get completedSteps =>
      steps.where((s) => s.isSuccess).toList();

  List<AgentPlanStep> get failedSteps =>
      steps.where((s) => s.isFailed).toList();

  String formatProgressSummary() {
    final buffer = StringBuffer();
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final icon = s.isSuccess
          ? '✓'
          : s.isFailed
              ? '✗'
              : s.isRunning
                  ? '⏳'
                  : '•';
      buffer.writeln('${i + 1}. $icon ${s.description}');
    }
    return buffer.toString().trim();
  }

  Map<String, dynamic> toJson() {
    return {
      'planId': planId,
      'originalRequest': originalRequest,
      'steps': steps.map((s) => s.toJson()).toList(),
      'currentStepIndex': currentStepIndex,
      'status': status.name,
      if (missingInformationQuestion != null)
        'missingInformationQuestion': missingInformationQuestion,
    };
  }
}
