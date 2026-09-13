import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../services/campus_vault_service.dart';

class GetIdCardTool extends AgentTool {
  final CampusVaultService _campusService;

  GetIdCardTool({CampusVaultService? campusService})
      : _campusService = campusService ?? CampusVaultService.instance,
        super(
          name: 'get_id_card',
          description:
              "Retrieve the student's on-device identity information (Student ID, Roll Number, Name, Department, Institution, Validity). Kept strictly private on device.",
          isReadOnly: true,
          parameters: const [
            AgentParameter(
              name: 'field',
              type: AgentParameterType.string,
              description:
                  'Specific field: "id", "roll_number", "name", "department", "institution", or "all". Defaults to "all".',
              required: false,
              allowedValues: [
                'id',
                'roll_number',
                'name',
                'department',
                'institution',
                'all'
              ],
              defaultValue: 'all',
            ),
          ],
        );

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  }) async {
    final idCard = _campusService.idCard;
    final field = (arguments['field'] as String? ?? 'all').toLowerCase();

    if (idCard.studentName.isEmpty && idCard.studentId.isEmpty) {
      return AgentToolResult.failure(
        tool: name,
        message:
            'No Student ID Card has been saved yet in your Personal Student Vault.',
      );
    }

    if (field == 'id' || field == 'student_id') {
      return AgentToolResult.success(
        tool: name,
        message: 'Your Student ID is ${idCard.studentId}.',
        data: {'studentId': idCard.studentId},
      );
    }

    if (field == 'roll_number' || field == 'roll') {
      final roll = idCard.rollNumber ?? idCard.studentId;
      return AgentToolResult.success(
        tool: name,
        message: 'Your Roll Number is $roll.',
        data: {'rollNumber': roll},
      );
    }

    if (field == 'department') {
      return AgentToolResult.success(
        tool: name,
        message: 'Your department is ${idCard.department}.',
        data: {'department': idCard.department},
      );
    }

    if (field == 'institution') {
      return AgentToolResult.success(
        tool: name,
        message: 'Your institution is ${idCard.institution}.',
        data: {'institution': idCard.institution},
      );
    }

    final summary = 'Student ID Card:\n'
        '• Name: ${idCard.studentName}\n'
        '• Student ID: ${idCard.studentId}\n'
        '• Roll Number: ${idCard.rollNumber ?? "N/A"}\n'
        '• Department: ${idCard.department}\n'
        '• Institution: ${idCard.institution}\n'
        '• Valid Until: ${idCard.validUntil ?? "Full Degree Period"}';

    return AgentToolResult.success(
      tool: name,
      message: summary,
      data: idCard.toMap(),
    );
  }
}
