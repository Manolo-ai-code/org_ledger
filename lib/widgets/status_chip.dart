import 'package:material_ui/material_ui.dart';

import '../../core/constants/expense_status.dart';
import '../../core/theme/app_colors.dart';

/// Colored status pill used in lists, detail pages and the dashboard.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.compact = false,
  });

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color accent = AppColors.status(status);
    final Color foreground = isDark
        ? Color.lerp(accent, Colors.white, 0.35) ?? accent
        : accent;

    return Semantics(
      label: 'Status: ${ExpenseStatus.label(status)}',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 170 : 200),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 9,
            vertical: compact ? 3 : 5,
          ),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                AppColors.statusIcon(status),
                size: compact ? 12 : 14,
                color: foreground,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  ExpenseStatus.label(status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (compact
                          ? theme.textTheme.labelSmall
                          : theme.textTheme.labelMedium)
                      ?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
