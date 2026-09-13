import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../models/rag_scope.dart';
import '../../services/rag_service.dart';

class SearchKnowledgeTool extends AgentTool {
  final RagService _ragService;

  SearchKnowledgeTool({RagService? ragService})
      : _ragService = ragService ?? RagService.instance,
        super(
          name: 'search_knowledge',
          description:
              'Search course materials across digital PDFs, handwritten notes, OCR documents, and lecture transcripts.',
          isReadOnly: true,
          parameters: const [
            AgentParameter(
              name: 'query',
              type: AgentParameterType.string,
              description:
                  'The academic query, concept, question, or keyword to look up.',
              required: true,
            ),
            AgentParameter(
              name: 'subject',
              type: AgentParameterType.string,
              description:
                  'Optional subject filter, e.g. "Operating Systems", "Computer Networks", or "Machine Learning".',
              required: false,
            ),
            AgentParameter(
              name: 'unit',
              type: AgentParameterType.string,
              description:
                  'Optional unit filter within the subject (e.g. "Unit 2"). Must be accompanied by subject.',
              required: false,
            ),
            AgentParameter(
              name: 'limit',
              type: AgentParameterType.integer,
              description:
                  'Maximum number of relevant chunks to retrieve (default 3).',
              required: false,
              defaultValue: 3,
            ),
          ],
        );

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  }) async {
    final query = arguments['query'] as String;
    final subject = arguments['subject'] as String?;
    final unit = arguments['unit'] as String?;
    final limit = (arguments['limit'] as num? ?? 3).toInt();

    RagScope? scope;
    if (subject != null && subject.trim().isNotEmpty) {
      if (unit != null && unit.trim().isNotEmpty) {
        scope = RagScope.subjectUnit(
          subjectName: subject.trim(),
          unitName: unit.trim(),
        );
      } else {
        scope = RagScope.subject(subjectName: subject.trim());
      }
    } else if (unit != null && unit.trim().isNotEmpty) {
      // HARD RULE: Unit is never global. Require subject disambiguation!
      final errMsg =
          'Unit "${unit.trim()}" requires a subject to prevent ambiguity. Which subject do you mean (e.g., Operating Systems, Computer Networks, Machine Learning)?';
      return AgentToolResult.failure(
        tool: name,
        message: errMsg,
        error: errMsg,
        data: {
          'query': query,
          'unit': unit,
          'needsSubjectDisambiguation': true,
        },
      );
    }

    final matches = _ragService.search(
      query: query,
      scope: scope,
      topK: limit,
    );

    final chunkData = matches.map((m) {
      final chunk = m.chunk;
      return {
        'id': chunk.id,
        'documentName': chunk.documentName,
        'pageNumber': chunk.pageNumber,
        'timestamp': chunk.timestamp,
        'subjectId': chunk.subjectId,
        'subject': chunk.subjectName,
        'unitId': chunk.unitId,
        'unit': chunk.unitName,
        'extractionType': chunk.extractionType.label,
        'isOcr': chunk.isOcr,
        'isAudio': chunk.isAudio,
        'score': double.parse(m.score.toStringAsFixed(3)),
        'text': chunk.text,
      };
    }).toList();

    if (chunkData.isEmpty) {
      return AgentToolResult.success(
        tool: name,
        message: 'No relevant study materials found for "$query".',
        data: {
          'query': query,
          'matchCount': 0,
          'matches': [],
        },
      );
    }

    return AgentToolResult.success(
      tool: name,
      message:
          'Found ${chunkData.length} relevant context ${chunkData.length == 1 ? "source" : "sources"} for "$query".',
      data: {
        'query': query,
        'matchCount': chunkData.length,
        'matches': chunkData,
      },
    );
  }
}
