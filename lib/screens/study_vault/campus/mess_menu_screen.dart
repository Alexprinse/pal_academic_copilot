import 'package:flutter/material.dart';
import '../../../models/campus_vault.dart';
import '../../../services/campus_vault_service.dart';
import '../../../theme/app_theme.dart';
import '../vault_breadcrumbs.dart';

class MessMenuScreen extends StatefulWidget {
  const MessMenuScreen({super.key});

  @override
  State<MessMenuScreen> createState() => _MessMenuScreenState();
}

class _MessMenuScreenState extends State<MessMenuScreen> {
  final CampusVaultService _campusService = CampusVaultService.instance;
  late String _selectedDay;

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _campusService.addListener(_onServiceUpdate);
    final now = DateTime.now();
    _selectedDay = _weekdays[now.weekday - 1];
  }

  @override
  void dispose() {
    _campusService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  String get _todayName {
    final now = DateTime.now();
    return _weekdays[now.weekday - 1];
  }

  String get _tomorrowName {
    final now = DateTime.now();
    final tomorrowIndex =
        (now.weekday) % 7; // 1->Tue (index 1), 7->Mon (index 0)
    return _weekdays[tomorrowIndex];
  }

  void _selectToday() {
    setState(() {
      _selectedDay = _todayName;
    });
  }

  void _selectTomorrow() {
    setState(() {
      _selectedDay = _tomorrowName;
    });
  }

  void _editMeal(MealMenu meal) {
    final itemsCtrl = TextEditingController(text: meal.items.join(', '));
    final timingCtrl = TextEditingController(text: meal.timings);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
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
                Text(
                  'Edit $_selectedDay ${meal.mealName}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: timingCtrl,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Serving Timings',
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
              controller: itemsCtrl,
              maxLines: 4,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Food Items (comma separated)',
                hintText: 'e.g. Paneer Butter Masala, Dal, Jeera Rice, Roti',
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
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  final newItems = itemsCtrl.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                  await _campusService.updateMeal(
                    dayOfWeek: _selectedDay,
                    mealName: meal.mealName,
                    items: newItems,
                    timings: timingCtrl.text.trim().isNotEmpty
                        ? timingCtrl.text.trim()
                        : null,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.darkSurface,
                  foregroundColor: AppTheme.canvasBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Update Meal',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmResetDefaults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text('Reset Mess Menu?'),
        content: const Text(
          'This will reset the entire weekly dining menu to default hostel standards.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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
              _campusService.resetMessMenuToDefault();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messMenu = _campusService.messMenu;
    final currentDayMenu = messMenu.days[_selectedDay] ??
        messMenu.days['Monday'] ??
        const DayMenu(
          dayOfWeek: 'Monday',
          breakfast: MealMenu(
              mealName: 'Breakfast',
              timings: '07:30 AM',
              items: ['Items loading']),
          lunch: MealMenu(
              mealName: 'Lunch', timings: '12:30 PM', items: ['Items loading']),
          snacks: MealMenu(
              mealName: 'Snacks',
              timings: '05:00 PM',
              items: ['Items loading']),
          dinner: MealMenu(
              mealName: 'Dinner',
              timings: '07:30 PM',
              items: ['Items loading']),
        );

    final isTodaySelected = _selectedDay == _todayName;

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mess Menu',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              messMenu.messName,
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt,
                color: AppTheme.textSecondary, size: 21),
            tooltip: 'Reset to default menu',
            onPressed: _confirmResetDefaults,
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
              const BreadcrumbItem(label: 'Mess Menu'),
            ],
          ),

          // Quick Navigation Bar: Today / Tomorrow shortcuts
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _buildQuickJumpPill(
                  label: 'Today ($_todayName)',
                  isSelected: isTodaySelected,
                  onTap: _selectToday,
                ),
                const SizedBox(width: 8),
                _buildQuickJumpPill(
                  label: 'Tomorrow ($_tomorrowName)',
                  isSelected: _selectedDay == _tomorrowName,
                  onTap: _selectTomorrow,
                ),
              ],
            ),
          ),

          // 7-day horizontal tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _weekdays.map((day) {
                final isSel = day == _selectedDay;
                final isToday = day == _todayName;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(day.substring(0, 3)),
                        if (isToday) ...[
                          const SizedBox(width: 4),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    selected: isSel,
                    selectedColor: AppTheme.darkSurface,
                    backgroundColor: AppTheme.cardSurface,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isSel ? AppTheme.canvasBg : AppTheme.textSecondary,
                    ),
                    side: BorderSide(
                      color: isSel ? AppTheme.darkSurface : AppTheme.cardBorder,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _selectedDay = day);
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1, color: AppTheme.cardBorder),

          // 4 Meals Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMealCard(
                  meal: currentDayMenu.breakfast,
                  icon: Icons.wb_sunny_outlined,
                  color: Colors.amber.shade700,
                ),
                const SizedBox(height: 12),
                _buildMealCard(
                  meal: currentDayMenu.lunch,
                  icon: Icons.restaurant,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(height: 12),
                _buildMealCard(
                  meal: currentDayMenu.snacks,
                  icon: Icons.local_cafe_outlined,
                  color: Colors.teal.shade700,
                ),
                const SizedBox(height: 12),
                _buildMealCard(
                  meal: currentDayMenu.dinner,
                  icon: Icons.nights_stay_outlined,
                  color: Colors.indigo.shade700,
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickJumpPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected ? AppTheme.detectedPillFill : AppTheme.neutralPillFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.detectedPillText.withValues(alpha: 0.3)
                : AppTheme.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color:
                isSelected ? AppTheme.detectedPillText : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMealCard({
    required MealMenu meal,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal.mealName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        meal.timings,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 18, color: AppTheme.textSecondary),
                  tooltip: 'Edit meal',
                  onPressed: () => _editMeal(meal),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.cardBorder),

          // Food items chips/bullets
          Padding(
            padding: const EdgeInsets.all(14),
            child: meal.items.isEmpty
                ? const Text(
                    'No items listed for this meal.',
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: meal.items.map((item) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.neutralPillFill,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.cardBorder.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              item,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
