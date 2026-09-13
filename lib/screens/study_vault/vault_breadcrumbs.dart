import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class BreadcrumbItem {
  final String label;
  final VoidCallback? onTap;

  const BreadcrumbItem({
    required this.label,
    this.onTap,
  });
}

class VaultBreadcrumbs extends StatelessWidget {
  final List<BreadcrumbItem> items;

  const VaultBreadcrumbs({
    super.key,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.canvasBg,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: AppTheme.textSecondary.withValues(alpha: 0.6),
                  ),
                ),
              _buildCrumb(items[i], isLast: i == items.length - 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCrumb(BreadcrumbItem item, {required bool isLast}) {
    final isClickable = item.onTap != null && !isLast;

    return InkWell(
      onTap: isClickable ? item.onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          item.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
            color: isLast
                ? AppTheme.textPrimary
                : (isClickable
                    ? AppTheme.primaryAccent
                    : AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}
