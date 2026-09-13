import 'package:flutter/material.dart';
import '../../models/campus_vault.dart';
import '../../models/vault_item.dart';
import '../../services/campus_vault_service.dart';
import '../../services/rag_service.dart';
import '../../theme/app_theme.dart';

class OrganizeSourceDialog extends StatefulWidget {
  final VaultDocument source;
  final VoidCallback? onOrganized;

  const OrganizeSourceDialog({
    super.key,
    required this.source,
    this.onOrganized,
  });

  @override
  State<OrganizeSourceDialog> createState() => _OrganizeSourceDialogState();
}

class _OrganizeSourceDialogState extends State<OrganizeSourceDialog> {
  final RagService _ragService = RagService.instance;
  final CampusVaultService _campusService = CampusVaultService.instance;

  int _selectedTab = 0; // 0 = Academic, 1 = Campus
  VaultSubject? _selectedSubject;
  VaultUnit? _selectedUnit;

  // Campus assignment
  String _campusDestination = 'notices'; // 'id_card', 'calendar', 'notices'

  @override
  void initState() {
    super.initState();
    if (_ragService.subjects.isNotEmpty) {
      _selectedSubject = _ragService.subjects.firstWhere(
        (s) => s.id == widget.source.subjectId,
        orElse: () => _ragService.subjects.first,
      );
      if (_selectedSubject!.units.isNotEmpty) {
        _selectedUnit = _selectedSubject!.units.firstWhere(
          (u) => u.id == widget.source.unitId,
          orElse: () => _selectedSubject!.units.first,
        );
      }
    }
  }

  void _onSubjectChanged(VaultSubject? subject) {
    if (subject == null) return;
    setState(() {
      _selectedSubject = subject;
      if (subject.units.isNotEmpty) {
        _selectedUnit = subject.units.first;
      } else {
        _selectedUnit = null;
      }
    });
  }

  void _promptAddSubject() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text('Add Subject',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Database Management',
            filled: true,
            fillColor: AppTheme.neutralPillFill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                _ragService.addSubject(name);
                Navigator.pop(ctx);
                setState(() {
                  _selectedSubject = _ragService.subjects.firstWhere(
                    (s) => s.name.toLowerCase() == name.toLowerCase(),
                    orElse: () => _ragService.subjects.last,
                  );
                  _selectedUnit = _selectedSubject?.units.firstOrNull;
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _promptAddUnit() {
    if (_selectedSubject == null) return;
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: Text('Add Unit to ${_selectedSubject!.name}',
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Unit 3: Transactions',
            filled: true,
            fillColor: AppTheme.neutralPillFill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                _ragService.addUnit(_selectedSubject!.name, name);
                Navigator.pop(ctx);
                setState(() {
                  _selectedUnit = _selectedSubject?.units.firstWhere(
                    (u) => u.name.toLowerCase() == name.toLowerCase(),
                    orElse: () => _selectedSubject!.units.last,
                  );
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _saveAcademicOrganization() {
    if (_selectedSubject == null || _selectedUnit == null) return;

    _ragService.organizeSource(
      sourceId: widget.source.id,
      targetSubjectId: _selectedSubject!.id,
      targetUnitId: _selectedUnit!.id,
    );

    widget.onOrganized?.call();
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        content: Row(
          children: [
            const Icon(Icons.check_circle,
                color: AppTheme.trustPillText, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Organized "${widget.source.name}" into ${_selectedSubject!.name} · ${_selectedUnit!.name}',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveCampusOrganization() async {
    if (_campusDestination == 'id_card') {
      final current = _campusService.idCard;
      final updated = current.copyWith(
        frontImagePath: widget.source.path,
        updatedAt: DateTime.now(),
      );
      await _campusService.saveIdCard(updated);
    } else if (_campusDestination == 'calendar') {
      final item = AcademicCalendarItem(
        id: 'cal-${DateTime.now().millisecondsSinceEpoch}',
        title: widget.source.name,
        startDate: DateTime.now(),
        eventType: CalendarEventType.semester,
        description: 'Organized from vault document',
        originalDocPath: widget.source.path,
      );
      await _campusService.addCalendarItem(item);
    } else {
      // Notices
      final notice = CampusNotice(
        id: 'not-${DateTime.now().millisecondsSinceEpoch}',
        title: widget.source.name,
        date: DateTime.now(),
        category: NoticeCategory.general,
        filePath: widget.source.path,
        extractedText: 'Document attached: ${widget.source.name}',
        summary: 'Imported from unorganized study vault document.',
      );
      await _campusService.addNotice(notice);
    }

    _ragService.deleteSource(sourceId: widget.source.id);
    widget.onOrganized?.call();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.darkSurface,
          content: Text(
              'Organized "${widget.source.name}" into Campus (${_campusDestination.replaceAll("_", " ").toUpperCase()})'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Organize Material',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.source.name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryAccent,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),

          // Destination Selector Tabs: Academic vs Campus
          Container(
            decoration: BoxDecoration(
              color: AppTheme.neutralPillFill,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedTab = 0),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedTab == 0
                            ? AppTheme.cardSurface
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _selectedTab == 0
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                )
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '📚 Move to Academic',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _selectedTab == 0
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedTab = 1),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedTab == 1
                            ? AppTheme.cardSurface
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _selectedTab == 1
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                )
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '🏛️ Assign to Campus',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _selectedTab == 1
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          if (_selectedTab == 0) ...[
            // Subject Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Subject',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
                TextButton(
                  onPressed: _promptAddSubject,
                  child: const Text('+ Add Subject',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.primaryAccent)),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.neutralPillFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<VaultSubject>(
                  value: _selectedSubject,
                  isExpanded: true,
                  dropdownColor: AppTheme.cardSurface,
                  hint: const Text('Select Subject',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  items: _ragService.subjects.map((s) {
                    return DropdownMenuItem<VaultSubject>(
                      value: s,
                      child: Text(s.name,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: _onSubjectChanged,
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Unit Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Unit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (_selectedSubject != null)
                  TextButton(
                    onPressed: _promptAddUnit,
                    child: const Text('+ Add Unit',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.primaryAccent)),
                  ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.neutralPillFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<VaultUnit>(
                  value: _selectedUnit,
                  isExpanded: true,
                  dropdownColor: AppTheme.cardSurface,
                  hint: const Text('Select Unit',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  items: (_selectedSubject?.units ?? []).map((u) {
                    return DropdownMenuItem<VaultUnit>(
                      value: u,
                      child: Text(u.name,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (unit) => setState(() => _selectedUnit = unit),
                ),
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: (_selectedSubject != null && _selectedUnit != null)
                    ? _saveAcademicOrganization
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.darkSurface,
                  foregroundColor: AppTheme.canvasBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Organize into Academic Unit',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ] else ...[
            // Campus Destination Selector
            const Text(
              'Select Campus Hub',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),

            _buildCampusDestinationTile(
              destKey: 'notices',
              title: 'Campus Notice / Circular',
              subtitle: 'Attach as official campus announcement',
              icon: Icons.campaign_outlined,
            ),
            const SizedBox(height: 8),
            _buildCampusDestinationTile(
              destKey: 'calendar',
              title: 'Academic Calendar Milestone',
              subtitle: 'Attach as official semester schedule document',
              icon: Icons.calendar_month_outlined,
            ),
            const SizedBox(height: 8),
            _buildCampusDestinationTile(
              destKey: 'id_card',
              title: 'Student ID Card Image',
              subtitle: 'Set as physical student card photo',
              icon: Icons.badge_outlined,
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saveCampusOrganization,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.darkSurface,
                  foregroundColor: AppTheme.canvasBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Assign to Campus Vault',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCampusDestinationTile({
    required String destKey,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _campusDestination == destKey;

    return InkWell(
      onTap: () => setState(() => _campusDestination = destKey),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:
              isSelected ? AppTheme.detectedPillFill : AppTheme.neutralPillFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.detectedPillText.withValues(alpha: 0.4)
                : AppTheme.cardBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected
                    ? AppTheme.detectedPillText
                    : AppTheme.textSecondary,
                size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? AppTheme.detectedPillText
                          : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: AppTheme.detectedPillText, size: 18),
          ],
        ),
      ),
    );
  }
}
