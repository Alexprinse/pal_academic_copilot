import 'package:flutter/material.dart';
import '../../models/vault_item.dart';
import '../../services/rag_service.dart';
import '../../theme/app_theme.dart';

class SaveToVaultDialog extends StatefulWidget {
  final String text;
  final String? initialTitle;
  final int pageCount;
  final VoidCallback? onSaved;

  const SaveToVaultDialog({
    super.key,
    required this.text,
    this.initialTitle,
    this.pageCount = 1,
    this.onSaved,
  });

  @override
  State<SaveToVaultDialog> createState() => _SaveToVaultDialogState();
}

class _SaveToVaultDialogState extends State<SaveToVaultDialog> {
  final RagService _ragService = RagService.instance;
  late final TextEditingController _titleController;
  VaultSubject? _selectedSubject;
  VaultUnit? _selectedUnit;
  bool _saveAsUnorganized = false;

  static String _formatShortDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final defaultTitle =
        (widget.initialTitle != null && widget.initialTitle!.trim().isNotEmpty)
            ? widget.initialTitle!.trim()
            : 'Handwritten Notes · ${_formatShortDate(now)}';
    _titleController = TextEditingController(text: defaultTitle);

    if (_ragService.subjects.isNotEmpty) {
      _selectedSubject = _ragService.subjects.first;
      if (_selectedSubject!.units.isNotEmpty) {
        _selectedUnit = _selectedSubject!.units.first;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
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
        title: const Text(
          'Add Subject',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Compiler Design',
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
        title: Text(
          'Add Unit to ${_selectedSubject!.name}',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Unit 4: Code Generation',
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

  void _handleSave() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final docId = 'ocr_${DateTime.now().millisecondsSinceEpoch}';

    if (_saveAsUnorganized) {
      _ragService.indexOcrDocument(
        documentId: docId,
        title: title,
        text: widget.text,
        isUnorganized: true,
        pageCount: widget.pageCount,
      );
    } else {
      if (_selectedSubject == null || _selectedUnit == null) return;
      _ragService.indexOcrDocument(
        documentId: docId,
        title: title,
        text: widget.text,
        subject: _selectedSubject!.name,
        subjectId: _selectedSubject!.id,
        unit: _selectedUnit!.name,
        unitId: _selectedUnit!.id,
        pageCount: widget.pageCount,
      );
    }

    widget.onSaved?.call();
    Navigator.pop(context, true);

    final destText = _saveAsUnorganized
        ? 'Unorganized Sources'
        : '${_selectedSubject!.name} · ${_selectedUnit!.name}';

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
                'Saved "$title" to $destText',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _titleController.text.trim().isNotEmpty &&
        (_saveAsUnorganized ||
            (_selectedSubject != null && _selectedUnit != null));

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
              const Row(
                children: [
                  Icon(Icons.folder_special_outlined,
                      color: AppTheme.primaryAccent, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Save to Study Vault',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Document Title input
          const Text(
            'Document Title',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'e.g. Handwritten Notes · Sep 12',
              filled: true,
              fillColor: AppTheme.neutralPillFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.cardBorder),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Location Mode: Organize vs Unorganized
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _saveAsUnorganized = false),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: !_saveAsUnorganized
                          ? AppTheme.primaryAccent.withValues(alpha: 0.15)
                          : AppTheme.neutralPillFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: !_saveAsUnorganized
                            ? AppTheme.primaryAccent
                            : AppTheme.cardBorder,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Assign to Unit',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: !_saveAsUnorganized
                            ? AppTheme.primaryAccent
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _saveAsUnorganized = true),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _saveAsUnorganized
                          ? AppTheme.primaryAccent.withValues(alpha: 0.15)
                          : AppTheme.neutralPillFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _saveAsUnorganized
                            ? AppTheme.primaryAccent
                            : AppTheme.cardBorder,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Unorganized Staging',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _saveAsUnorganized
                            ? AppTheme.primaryAccent
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (!_saveAsUnorganized) ...[
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
            const SizedBox(height: 12),

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
            const SizedBox(height: 16),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.neutralPillFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      color: AppTheme.textSecondary, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Material will be placed in the Unorganized staging area so you can review and organize it later.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: canSave ? _handleSave : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Save to Study Vault',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
