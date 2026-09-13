import 'package:flutter/material.dart';
import '../../models/vault_item.dart';
import '../../services/rag_service.dart';
import '../../theme/app_theme.dart';
import 'organize_source_dialog.dart';
import 'vault_breadcrumbs.dart';

class VaultUnorganizedScreen extends StatefulWidget {
  final Function(int,
      {String? initialQuery,
      String? filterSubject,
      String? filterUnit}) onNavigateToBrain;

  const VaultUnorganizedScreen({super.key, required this.onNavigateToBrain});

  @override
  State<VaultUnorganizedScreen> createState() => _VaultUnorganizedScreenState();
}

class _VaultUnorganizedScreenState extends State<VaultUnorganizedScreen> {
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

  void _showOrganizeDialog(VaultDocument source) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrganizeSourceDialog(
        source: source,
        onOrganized: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _confirmDelete(VaultDocument source) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text('Delete Source?',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${source.name}"?',
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _ragService.deleteSource(sourceId: source.id);
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

  @override
  Widget build(BuildContext context) {
    final unorganized = _ragService.unorganizedSources;
    final breadcrumbs = [
      BreadcrumbItem(
        label: 'Study Vault',
        onTap: () => Navigator.pop(context),
      ),
      const BreadcrumbItem(label: 'Unorganized'),
    ];

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
        title: const Text(
          'Unorganized Sources',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: ListView(
        children: [
          VaultBreadcrumbs(items: breadcrumbs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Informative header
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.neutralPillFill,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.inbox_outlined,
                            size: 22, color: AppTheme.primaryAccent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Unorganized Staging Area',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Pal never guesses metadata. Organize sources into subjects & units so they are accurately scoped for study.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                Text(
                  'SOURCES (${unorganized.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.textSecondary,
                  ),
                ),

                const SizedBox(height: 10),

                if (unorganized.isEmpty)
                  _buildEmptyState()
                else
                  ...unorganized.map((source) => _buildUnorganizedItem(source)),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnorganizedItem(VaultDocument source) {
    IconData icon = Icons.picture_as_pdf;
    Color iconColor = AppTheme.detectedPillText;
    if (source.isAudio) {
      icon = Icons.mic;
      iconColor = AppTheme.trustPillText;
    } else if (source.isHandwritten) {
      icon = Icons.draw_outlined;
      iconColor = AppTheme.primaryAccent;
    }

    final metaText = source.isAudio
        ? (source.formattedDuration.isNotEmpty
            ? source.formattedDuration
            : 'Audio')
        : '${source.pageCount} pages';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '$metaText · ${source.typeLabel}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _showOrganizeDialog(source),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.darkSurface,
              foregroundColor: AppTheme.canvasBg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Organize',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppTheme.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => _confirmDelete(source),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: const Column(
        children: [
          Icon(Icons.check_circle_outline,
              size: 44, color: AppTheme.trustPillText),
          SizedBox(height: 12),
          Text(
            'All Materials Organized!',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'All study documents and recordings are assigned to subjects and units.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
