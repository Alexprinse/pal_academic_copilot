import 'package:flutter/material.dart';
import '../../models/rag_scope.dart';
import '../../models/vault_item.dart';
import '../../services/conversation_service.dart';
import '../../services/rag_service.dart';
import '../../theme/app_theme.dart';
import 'vault_breadcrumbs.dart';
import 'vault_source_detail_screen.dart';
import 'vault_unit_screen.dart';

class VaultSubjectScreen extends StatefulWidget {
  final VaultSubject subject;
  final Function(int,
      {String? initialQuery,
      String? filterSubject,
      String? filterUnit}) onNavigateToBrain;

  const VaultSubjectScreen({
    super.key,
    required this.subject,
    required this.onNavigateToBrain,
  });

  @override
  State<VaultSubjectScreen> createState() => _VaultSubjectScreenState();
}

class _VaultSubjectScreenState extends State<VaultSubjectScreen> {
  final RagService _ragService = RagService.instance;
  final ConversationService _conversationService = ConversationService.instance;

  late VaultSubject _subject;

  @override
  void initState() {
    super.initState();
    _subject = widget.subject;
    _ragService.addListener(_onRagUpdate);
  }

  @override
  void dispose() {
    _ragService.removeListener(_onRagUpdate);
    super.dispose();
  }

  void _onRagUpdate() {
    if (!mounted) return;
    final s = _ragService.subjects.firstWhere(
      (sub) => sub.id == _subject.id,
      orElse: () => _subject,
    );
    setState(() => _subject = s);
  }

  void _askPalAboutSubject() async {
    final scope = RagScope.subject(
      subjectName: _subject.name,
      subjectId: _subject.id,
    );

    await _conversationService.createConversation(
      initialTitle: _subject.name,
      initialRagScope: scope.displayLabel,
      subjectId: _subject.id,
      subjectName: _subject.name,
      ragScopeType: scope.type.name,
      ragScope: scope,
    );

    if (!mounted) return;
    widget.onNavigateToBrain(
      2, // Brain chat tab
      initialQuery:
          'What are the core subjects and learning objectives of ${_subject.name}?',
      filterSubject: _subject.name,
    );
  }

  void _showAddUnitDialog() {
    final unitCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add Unit to ${_subject.name}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: TextField(
          controller: unitCtrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Unit 4: Storage & File Systems',
            filled: true,
            fillColor: AppTheme.neutralPillFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.cardBorder),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              final unitName = unitCtrl.text.trim();
              if (unitName.isNotEmpty) {
                _ragService.addUnit(_subject.name, unitName);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add Unit'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSubject() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text(
          'Delete Subject?',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${_subject.name}"? This will remove all ${_subject.units.length} units and ${_subject.totalSources} sources from Pal. This action cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _ragService.deleteSubject(_subject.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.cardSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  content: Text('Deleted "${_subject.name}"',
                      style: const TextStyle(color: AppTheme.textPrimary)),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  List<VaultDocument> _getRecentDocuments() {
    final allDocs = <VaultDocument>[];
    for (final u in _subject.units) {
      allDocs.addAll(u.documents);
    }
    allDocs.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return allDocs.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final breadcrumbs = [
      BreadcrumbItem(
        label: 'Study Vault',
        onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
      ),
      BreadcrumbItem(label: _subject.name),
    ];

    final recentDocs = _getRecentDocuments();

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _subject.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 20, color: AppTheme.textSecondary),
            tooltip: 'Delete Subject',
            onPressed: _confirmDeleteSubject,
          ),
        ],
      ),
      body: ListView(
        children: [
          VaultBreadcrumbs(items: breadcrumbs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject Overview Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.detectedPillFill,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.school,
                                size: 24, color: AppTheme.detectedPillText),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _subject.name,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${_subject.totalSources} sources · ${_subject.units.length} units${_subject.code != null ? ' · ${_subject.code}' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Ask Pal subject action button
                      InkWell(
                        onTap: _askPalAboutSubject,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.neutralPillFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.cardBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome,
                                  size: 16, color: AppTheme.primaryAccent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Ask Pal about ${_subject.name}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  size: 16, color: AppTheme.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // Units Header + Add Unit
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'UNITS (${_subject.units.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    InkWell(
                      onTap: _showAddUnitDialog,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.neutralPillFill,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.cardBorder),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.add,
                                size: 14, color: AppTheme.primaryAccent),
                            SizedBox(width: 4),
                            Text(
                              'Add Unit',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                if (_subject.units.isEmpty)
                  _buildEmptyUnitsState()
                else
                  ..._subject.units.map((unit) => _buildUnitTile(unit)),

                if (recentDocs.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'RECENT ACTIVITY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...recentDocs.map((doc) => _buildRecentDocTile(doc)),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitTile(VaultUnit unit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.neutralPillFill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.folder_outlined,
              size: 20, color: AppTheme.primaryAccent),
        ),
        title: Text(
          unit.name,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${unit.totalSources} sources',
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        trailing: const Icon(Icons.arrow_forward_ios,
            size: 13, color: AppTheme.textSecondary),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VaultUnitScreen(
                subject: _subject,
                unit: unit,
                onNavigateToBrain: widget.onNavigateToBrain,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentDocTile(VaultDocument doc) {
    final unit = _subject.units.firstWhere(
      (u) => u.id == doc.unitId,
      orElse: () => _subject.units.first,
    );

    IconData icon = Icons.picture_as_pdf;
    Color iconColor = AppTheme.detectedPillText;
    if (doc.isAudio) {
      icon = Icons.mic;
      iconColor = AppTheme.trustPillText;
    } else if (doc.isHandwritten) {
      icon = Icons.draw_outlined;
      iconColor = AppTheme.primaryAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              doc.name,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            unit.name.split(':').first.trim(),
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.chevron_right,
                size: 16, color: AppTheme.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VaultSourceDetailScreen(
                    subject: _subject,
                    unit: unit,
                    source: doc,
                    onNavigateToBrain: widget.onNavigateToBrain,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyUnitsState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Icon(Icons.folder_open_outlined,
              size: 40, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          const Text(
            'No units yet.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add a unit to organize documents and notes.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _showAddUnitDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Unit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.darkSurface,
              foregroundColor: AppTheme.canvasBg,
            ),
          ),
        ],
      ),
    );
  }
}
