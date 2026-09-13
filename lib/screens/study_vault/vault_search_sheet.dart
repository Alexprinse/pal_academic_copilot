import 'package:flutter/material.dart';
import '../../services/campus_vault_service.dart';
import '../../services/rag_service.dart';
import '../../theme/app_theme.dart';
import 'campus/academic_calendar_screen.dart';
import 'campus/holidays_screen.dart';
import 'campus/id_card_screen.dart';
import 'campus/mess_menu_screen.dart';
import 'campus/notices_screen.dart';
import 'vault_source_detail_screen.dart';
import 'vault_subject_screen.dart';
import 'vault_unit_screen.dart';

class VaultSearchSheet extends StatefulWidget {
  final Function(int,
      {String? initialQuery,
      String? filterSubject,
      String? filterUnit}) onNavigateToBrain;

  const VaultSearchSheet({super.key, required this.onNavigateToBrain});

  @override
  State<VaultSearchSheet> createState() => _VaultSearchSheetState();
}

class _VaultSearchSheetState extends State<VaultSearchSheet> {
  final RagService _ragService = RagService.instance;
  final CampusVaultService _campusService = CampusVaultService.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  List<VaultSearchResult> _academicResults = [];
  List<Map<String, dynamic>> _campusResults = [];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    setState(() {
      _academicResults = _ragService.searchVault(q);
      _campusResults = _campusService.searchCampus(q);
    });
  }

  bool get _hasResults =>
      _academicResults.isNotEmpty || _campusResults.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppTheme.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: _onSearch,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText:
                        'Search subjects, notes, meals, holidays, notices...',
                    hintStyle: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12.5),
                    prefixIcon: const Icon(Icons.search,
                        size: 20, color: AppTheme.primaryAccent),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                size: 18, color: AppTheme.textSecondary),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearch('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppTheme.neutralPillFill,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppTheme.cardBorder),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _searchCtrl.text.trim().isEmpty
                ? _buildInitialState()
                : !_hasResults
                    ? _buildEmptyState()
                    : _buildResultsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.manage_search,
              size: 44, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          const Text(
            'Search Personal Student Vault',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Find academic subjects, notes, mess food, holidays & circulars',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off,
              size: 40, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(
            'No results for "${_searchCtrl.text.trim()}"',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    return ListView(
      children: [
        // Campus results section
        if (_campusResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Text(
                  'CAMPUS ESSENTIALS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.detectedPillFill,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_campusResults.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.detectedPillText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._campusResults.map((item) => _buildCampusResultTile(item)),
          const SizedBox(height: 14),
        ],

        // Academic results section
        if (_academicResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Text(
                  'ACADEMIC MATERIAL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.neutralPillFill,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_academicResults.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._academicResults.map((item) => _buildAcademicResultTile(item)),
        ],
      ],
    );
  }

  Widget _buildCampusResultTile(Map<String, dynamic> item) {
    final type = item['type'] as String?;
    IconData icon = Icons.info_outline;
    Color iconColor = AppTheme.primaryAccent;

    if (type == 'id_card') {
      icon = Icons.badge_outlined;
      iconColor = Colors.indigo.shade600;
    } else if (type == 'mess_menu') {
      icon = Icons.restaurant;
      iconColor = Colors.orange.shade700;
    } else if (type == 'holiday') {
      icon = Icons.celebration_outlined;
      iconColor = Colors.purple.shade600;
    } else if (type == 'calendar') {
      icon = Icons.calendar_month_outlined;
      iconColor = Colors.blue.shade700;
    } else if (type == 'notice') {
      icon = Icons.campaign_outlined;
      iconColor = Colors.teal.shade700;
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item['title'] as String? ?? 'Campus Result',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: AppTheme.neutralPillFill,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              item['category'] as String? ?? 'Campus',
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        item['snippet'] as String? ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
      ),
      trailing: const Icon(Icons.arrow_forward_ios,
          size: 13, color: AppTheme.textSecondary),
      onTap: () {
        Navigator.pop(context);
        if (type == 'id_card') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IdCardScreen()),
          );
        } else if (type == 'mess_menu') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MessMenuScreen()),
          );
        } else if (type == 'holiday') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HolidaysScreen()),
          );
        } else if (type == 'calendar') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AcademicCalendarScreen()),
          );
        } else if (type == 'notice') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NoticesScreen(
                onNavigateToBrain: widget.onNavigateToBrain,
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildAcademicResultTile(VaultSearchResult item) {
    IconData icon;
    Color iconColor;

    if (item.type == 'subject') {
      icon = Icons.school_outlined;
      iconColor = AppTheme.detectedPillText;
    } else if (item.type == 'unit') {
      icon = Icons.folder_outlined;
      iconColor = AppTheme.primaryAccent;
    } else {
      final isAudio = item.source?.isAudio ?? false;
      icon = isAudio ? Icons.mic_outlined : Icons.description_outlined;
      iconColor = isAudio ? AppTheme.trustPillText : AppTheme.detectedPillText;
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
      title: Text(
        item.title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
      subtitle: Text(
        item.subtitle,
        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
      ),
      trailing: const Icon(Icons.arrow_forward_ios,
          size: 13, color: AppTheme.textSecondary),
      onTap: () {
        Navigator.pop(context);
        if (item.type == 'subject' && item.subject != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VaultSubjectScreen(
                subject: item.subject!,
                onNavigateToBrain: widget.onNavigateToBrain,
              ),
            ),
          );
        } else if (item.type == 'unit' &&
            item.subject != null &&
            item.unit != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VaultUnitScreen(
                subject: item.subject!,
                unit: item.unit!,
                onNavigateToBrain: widget.onNavigateToBrain,
              ),
            ),
          );
        } else if (item.type == 'source' && item.source != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VaultSourceDetailScreen(
                subject: item.subject,
                unit: item.unit,
                source: item.source!,
                onNavigateToBrain: widget.onNavigateToBrain,
              ),
            ),
          );
        }
      },
    );
  }
}
