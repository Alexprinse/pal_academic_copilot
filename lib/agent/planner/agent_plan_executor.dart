import '../agent_context.dart';
import '../agent_tool_call.dart';
import '../agent_tool_registry.dart';
import '../agent_tool_result.dart';
import 'agent_plan.dart';
import 'agent_plan_step.dart';

class AgentPlanExecutor {
  final AgentToolRegistry registry;

  AgentPlanExecutor({required this.registry});

  Future<AgentPlan> execute(
    AgentPlan plan, {
    AgentContext? context,
  }) async {
    if (plan.isBlockedOnMissingInfo) {
      plan.status = AgentPlanStatus.failed;
      return plan;
    }

    // Enforce max step bound
    if (plan.steps.length > 6) {
      plan.steps.removeRange(6, plan.steps.length);
    }

    plan.status = AgentPlanStatus.running;

    for (var i = 0; i < plan.steps.length; i++) {
      plan.currentStepIndex = i;
      final step = plan.steps[i];
      step.status = AgentPlanStepStatus.running;

      // 1. Resolve step dependencies from previous step outputs
      if (step.dependsOnPrevious && i > 0) {
        final previousStep = plan.steps[i - 1];
        final dependencyError = _resolveDependencies(step, previousStep);
        if (dependencyError != null) {
          step.status = AgentPlanStepStatus.failed;
          step.result = AgentToolResult.failure(
            tool: step.tool,
            message: dependencyError,
            error: 'DEPENDENCY_RESOLUTION_FAILED',
          );
          _cancelRemainingSteps(plan, i + 1);
          plan.status = plan.completedSteps.isNotEmpty
              ? AgentPlanStatus.partialSuccess
              : AgentPlanStatus.failed;
          return plan;
        }
      }

      // 2. Execute tool through registry
      final toolCall = AgentToolCall(
        tool: step.tool,
        arguments: step.arguments,
      );

      final result = await registry.executeTool(toolCall, context: context);
      step.result = result;

      if (result.success && !result.requiresConfirmation) {
        step.status = AgentPlanStepStatus.success;
      } else {
        step.status = AgentPlanStepStatus.failed;
        _cancelRemainingSteps(plan, i + 1);
        plan.status = plan.completedSteps.isNotEmpty
            ? AgentPlanStatus.partialSuccess
            : AgentPlanStatus.failed;
        return plan;
      }
    }

    plan.status = AgentPlanStatus.success;
    return plan;
  }

  String? _resolveDependencies(
      AgentPlanStep currentStep, AgentPlanStep previousStep) {
    final prevResult = previousStep.result;
    if (prevResult == null || !prevResult.success) {
      return 'Previous step (${previousStep.tool}) failed.';
    }

    final prevData = prevResult.data;
    if (prevData is! Map<String, dynamic>) {
      return null;
    }

    // Dependency Case 1: Read next class -> Update timetable event
    if (currentStep.dependencyKey == 'next_class_target') {
      final classes = (prevData['classes'] as List?) ?? [];
      if (classes.isEmpty) {
        return 'No upcoming classes found in your timetable to reschedule.';
      }
      final target = classes.first as Map<String, dynamic>;
      if (target['id'] != null) {
        currentStep.arguments['id'] = target['id'];
      }
      currentStep.arguments['subject'] = target['subject'];
      currentStep.arguments['currentDay'] = target['day'];

      if (currentStep.arguments['newStartTime'] == 'OFFSET_+1H') {
        currentStep.arguments['newStartTime'] =
            _calculateOneHourLater(target['start'] as String? ?? '10:00 AM');
      }
    }

    // Dependency Case 2: Search knowledge -> Create task
    if (currentStep.dependencyKey == 'extracted_assignment') {
      final matches = (prevData['matches'] as List?) ?? [];
      if (matches.isEmpty) {
        return 'I searched your lecture notes, but couldn\'t find any assignment mentioned to add.';
      }
      final match = matches.first as Map<String, dynamic>;
      final text = match['text'] as String? ?? '';
      final docName = match['documentName'] as String? ?? 'Lecture';

      // Parse assignment title from excerpt
      String taskTitle = 'Assignment from $docName';
      final assignMatch = RegExp(
              r'(?:assignment|homework|project|problem set|lab \d+)[^.\n]*',
              caseSensitive: false)
          .firstMatch(text);
      if (assignMatch != null) {
        taskTitle = assignMatch.group(0)!.trim();
      }
      taskTitle = taskTitle.replaceAll(RegExp(r'[,;:]$'), '').trim();

      currentStep.arguments['title'] = taskTitle;
      currentStep.arguments['course'] =
          match['subject'] ?? _inferCourseFromDoc(docName);

      final dateMatch = RegExp(r'due\s+(?:on\s+)?([A-Za-z0-9\s]+?)(?:\.|\n|$)',
              caseSensitive: false)
          .firstMatch(text);
      if (dateMatch != null) {
        currentStep.arguments['dueDate'] = dateMatch.group(1)!.trim();
      } else {
        currentStep.arguments['dueDate'] = 'in 3 days';
      }
    }

    return null;
  }

  void _cancelRemainingSteps(AgentPlan plan, int startIndex) {
    for (var i = startIndex; i < plan.steps.length; i++) {
      plan.steps[i].status = AgentPlanStepStatus.cancelled;
    }
  }

  String _calculateOneHourLater(String startTimeStr) {
    final match =
        RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?$', caseSensitive: false)
            .firstMatch(startTimeStr.trim());
    if (match != null) {
      var hour = int.parse(match.group(1)!);
      final min = match.group(2) ?? '00';
      var period = match.group(3)?.toUpperCase();

      if (period != null) {
        if (hour == 12) {
          hour = 1;
        } else if (hour == 11) {
          hour = 12;
          period = (period == 'AM') ? 'PM' : 'AM';
        } else {
          hour += 1;
        }
        return '${hour.toString().padLeft(2, '0')}:$min $period';
      } else {
        hour = (hour + 1) % 24;
        return '${hour.toString().padLeft(2, '0')}:$min';
      }
    }
    return '11:00 AM';
  }

  String _inferCourseFromDoc(String doc) {
    final lower = doc.toLowerCase();
    if (lower.contains('os') || lower.contains('operating')) {
      return 'Operating Systems';
    }
    if (lower.contains('ai') || lower.contains('intelligence')) {
      return 'Artificial Intelligence';
    }
    return 'General';
  }
}
