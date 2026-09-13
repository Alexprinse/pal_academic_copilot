import 'package:flutter/material.dart';
import '../../../models/campus_vault.dart';
import '../../../services/campus_vault_service.dart';
import '../../../theme/app_theme.dart';
import '../vault_breadcrumbs.dart';

class HolidaysScreen extends StatefulWidget {
  const HolidaysScreen({super.key});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  final CampusVaultService _campusService = CampusVaultService.instance;
  String _selectedFilter =
      'all'; // 'all', 'national', 'gazetted', 'institutional'

  @override
  void initState() {
    super.initState();
    _campusService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _campusService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _showAddHolidayDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime pickedDate = DateTime.now().add(const Duration(days: 7));
    CampusHolidayType pickedType = CampusHolidayType.gazetted;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add Campus Holiday',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Holiday Name',
                  hintText: 'e.g. Republic Day, Sports Day',
                  filled: true,
                  fillColor: AppTheme.neutralPillFill,
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
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'e.g. Campus closed, library open',
                  filled: true,
                  fillColor: AppTheme.neutralPillFill,
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
              const SizedBox(height: 10),
              // Date picker tile
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.cardBorder),
                ),
                leading: const Icon(Icons.calendar_today,
                    color: AppTheme.primaryAccent, size: 20),
                title: const Text('Holiday Date',
                    style: TextStyle(
                        fontSize: 12.5, color: AppTheme.textSecondary)),
                subtitle: Text(
                  '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, "0")}-${pickedDate.day.toString().padLeft(2, "0")}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: pickedDate,
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) {
                    setDialogState(() => pickedDate = date);
                  }
                },
              ),
              const SizedBox(height: 12),
              // Category selector
              DropdownButtonFormField<CampusHolidayType>(
                initialValue: pickedType,
                decoration: InputDecoration(
                  labelText: 'Category',
                  filled: true,
                  fillColor: AppTheme.neutralPillFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.cardBorder),
                  ),
                ),
                items: CampusHolidayType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.displayName,
                        style: const TextStyle(fontSize: 13.5)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => pickedType = val);
                },
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isNotEmpty) {
                      final hol = CampusHoliday(
                        id: 'hol-${DateTime.now().millisecondsSinceEpoch}',
                        name: name,
                        date: pickedDate,
                        type: pickedType,
                        description: descCtrl.text.trim().isNotEmpty
                            ? descCtrl.text.trim()
                            : null,
                      );
                      await _campusService.addHoliday(hol);
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.darkSurface,
                    foregroundColor: AppTheme.canvasBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Add Holiday',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allHolidays = _campusService.holidays;
    final nextHoliday = _campusService.getNextHoliday();

    final filteredHolidays = allHolidays.where((h) {
      if (_selectedFilter == 'all') return true;
      return h.type.name.toLowerCase() == _selectedFilter;
    }).toList();

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
          'Campus Holidays',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.add, color: AppTheme.primaryAccent, size: 23),
            tooltip: 'Add holiday',
            onPressed: _showAddHolidayDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          VaultBreadcrumbs(
            items: [
              BreadcrumbItem(
                label: 'Vault',
                onTap: () => Navigator.pop(context),
              ),
              BreadcrumbItem(
                label: 'Campus',
                onTap: () => Navigator.pop(context),
              ),
              const BreadcrumbItem(label: 'Holidays'),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Next Holiday Highlight Card
                if (nextHoliday != null) ...[
                  _buildNextHolidayHero(nextHoliday),
                  const SizedBox(height: 20),
                ],

                // Filter tabs
                Row(
                  children: [
                    _buildFilterPill('all', 'All (${allHolidays.length})'),
                    const SizedBox(width: 8),
                    _buildFilterPill('national', 'National'),
                    const SizedBox(width: 8),
                    _buildFilterPill('gazetted', 'Gazetted'),
                    const SizedBox(width: 8),
                    _buildFilterPill('institutional', 'Institute'),
                  ],
                ),

                const SizedBox(height: 16),

                // Holiday List
                if (filteredHolidays.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'No holidays found under this filter.',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                  )
                else
                  ...filteredHolidays.map((h) => _buildHolidayCard(h)),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextHolidayHero(CampusHoliday holiday) {
    final days = holiday.daysUntil();
    String countdown;
    if (days == 0) {
      countdown = 'Today!';
    } else if (days == 1) {
      countdown = 'Tomorrow';
    } else {
      countdown = 'In $days days';
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryAccent.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryAccent.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'NEXT UPCOMING HOLIDAY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.detectedPillFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.detectedPillText.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  countdown,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.detectedPillText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            holiday.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.event, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                '${_formatMonth(holiday.date.month)} ${holiday.date.day}, ${holiday.date.year}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '•  ${holiday.type.displayName}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          if (holiday.description != null &&
              holiday.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              holiday.description!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterPill(String key, String label) {
    final isSelected = _selectedFilter == key;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = key),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.darkSurface : AppTheme.neutralPillFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.darkSurface : AppTheme.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppTheme.canvasBg : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildHolidayCard(CampusHoliday holiday) {
    final isUpcoming = holiday.isUpcoming();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isUpcoming
                ? AppTheme.detectedPillFill
                : AppTheme.neutralPillFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _formatMonth(holiday.date.month).substring(0, 3).toUpperCase(),
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: isUpcoming
                      ? AppTheme.detectedPillText
                      : AppTheme.textSecondary,
                ),
              ),
              Text(
                '${holiday.date.day}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isUpcoming
                      ? AppTheme.detectedPillText
                      : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
        title: Text(
          holiday.name,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            holiday.type.displayName +
                (holiday.description != null
                    ? ' · ${holiday.description}'
                    : ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline,
              size: 18, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
          onPressed: () => _campusService.removeHoliday(holiday.id),
        ),
      ),
    );
  }

  String _formatMonth(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
  }
}
