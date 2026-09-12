import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/vault_item.dart';
import '../services/rag_service.dart';
import '../theme/app_theme.dart';

class StudyVaultScreen extends StatefulWidget {
  final Function(int,
      {String? initialQuery,
      String? filterSubject,
      String? filterUnit}) onNavigateToBrain;

  const StudyVaultScreen({super.key, required this.onNavigateToBrain});

  @override
  State<StudyVaultScreen> createState() => _StudyVaultScreenState();
}

class _StudyVaultScreenState extends State<StudyVaultScreen> {
  final RagService _ragService = RagService.instance;

  @override
  void initState() {
    super.initState();
    _ragService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _ragService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _pickAndIndexPdf(String subjectName, String unitName) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.cardDark,
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.cyanAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Indexing "$name" with Pure Dart PDF Parser...'),
              ),
            ],
          ),
        ),
      );

      final doc = await _ragService.indexPdfFile(
        filePath: path,
        fileName: name,
        subjectName: subjectName,
        unitName: unitName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.cardDark,
            content: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppTheme.greenAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Indexed ${doc.chunkCount} chunks across ${doc.pageCount} pages!',
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Study Vault'),
            Text(
              'Subject & Unit RAG Knowledge Base',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.data_array,
                    size: 14, color: AppTheme.cyanAccent),
                const SizedBox(width: 6),
                Text(
                  '${_ragService.totalIndexedChunks} Chunks',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.cyanAccent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // RAG In-Memory Status Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.bolt, color: AppTheme.amberAccent, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'In-Memory BM25 Lexical Retriever',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Zero-NDK collision, <5ms retrieval latency, 100% offline.',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Enrolled Subjects',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          ..._ragService.subjects.map((subject) => _buildSubjectCard(subject)),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSubjectCard(VaultSubject subject) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.purpleAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.school,
                color: AppTheme.purpleAccent, size: 20),
          ),
          title: Text(
            subject.name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: Text(
            '${subject.units.length} Units • ${subject.totalDocuments} PDFs • ${subject.totalChunks} Chunks',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 14),
              child: Column(
                children: subject.units
                    .map((unit) => _buildUnitItem(subject, unit))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitItem(VaultSubject subject, VaultUnit unit) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  unit.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.cyanAccent,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    size: 18, color: AppTheme.cyanAccent),
                tooltip: 'Add PDF Notes',
                onPressed: () => _pickAndIndexPdf(subject.name, unit.name),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${unit.documents.length} PDF Notes uploaded (${unit.totalChunks} Chunks indexed)',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          // Quick Action Chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                avatar: const Icon(Icons.psychology,
                    size: 14, color: AppTheme.cyanAccent),
                label: const Text('Ask Pal from Unit'),
                onPressed: () {
                  widget.onNavigateToBrain(
                    4,
                    initialQuery:
                        'Summarize the core principles of ${unit.name}',
                    filterSubject: subject.name,
                    filterUnit: unit.name,
                  );
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.quiz_outlined,
                    size: 14, color: AppTheme.amberAccent),
                label: const Text('Generate 3 Quiz Qs'),
                onPressed: () {
                  widget.onNavigateToBrain(
                    4,
                    initialQuery:
                        'Generate 3 practice exam questions with detailed answers based on ${unit.name}',
                    filterSubject: subject.name,
                    filterUnit: unit.name,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
