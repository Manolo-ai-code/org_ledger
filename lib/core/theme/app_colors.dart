import 'package:material_ui/material_ui.dart';

import '../../core/constants/expense_status.dart';

/// Shared color tokens for the emerald financial theme.
abstract final class AppColors {
  static const Color seed = Color(0xFF0B6E5B);
  static const Color emerald = Color(0xFF0E7C66);
  static const Color mint = Color(0xFFD7F5EC);
  static const Color warning = Color(0xFFE0901A);
  static const Color danger = Color(0xFFD64545);
  static const Color info = Color(0xFF2F6FED);

  /// A balanced palette for category charts. Works in light and dark mode.
  static const List<Color> chartPalette = <Color>[
    Color(0xFF0E7C66),
    Color(0xFF3AA6A0),
    Color(0xFF2F6FED),
    Color(0xFF8A6BD1),
    Color(0xFFE0901A),
    Color(0xFFD64545),
    Color(0xFF4E8F3B),
    Color(0xFFB25C8A),
  ];

  static Color status(String status) {
    switch (ExpenseStatus.normalise(status)) {
      case ExpenseStatus.treasurerVerified:
        return const Color(0xFF2F6FED);
      case ExpenseStatus.auditorChecked:
        return const Color(0xFF6553C9);
      case ExpenseStatus.presidentEndorsed:
        return const Color(0xFF8A5A2B);
      case ExpenseStatus.adviserApproved:
        return const Color(0xFF0E7C66);
      case ExpenseStatus.rejected:
        return const Color(0xFFD64545);
      case ExpenseStatus.flagged:
        return const Color(0xFFE0701A);
      case ExpenseStatus.pending:
      default:
        return const Color(0xFFB27B12);
    }
  }

  static IconData statusIcon(String status) {
    switch (ExpenseStatus.normalise(status)) {
      case ExpenseStatus.treasurerVerified:
        return Icons.verified_outlined;
      case ExpenseStatus.auditorChecked:
        return Icons.fact_check_outlined;
      case ExpenseStatus.presidentEndorsed:
        return Icons.how_to_reg_outlined;
      case ExpenseStatus.adviserApproved:
        return Icons.task_alt_rounded;
      case ExpenseStatus.rejected:
        return Icons.cancel_outlined;
      case ExpenseStatus.flagged:
        return Icons.flag_outlined;
      case ExpenseStatus.pending:
      default:
        return Icons.hourglass_top_rounded;
    }
  }

  /// Color for a budget usage ratio. Transitions from emerald to amber at 80%
  /// and then smoothly toward red as the budget is exhausted.
  static Color budget(double ratio) {
    if (!ratio.isFinite || ratio <= 0.8) {
      return emerald;
    }
    if (ratio >= 1.0) {
      return danger;
    }
    final double progress = ((ratio - 0.8) / 0.2).clamp(0.0, 1.0);
    return Color.lerp(warning, danger, progress) ?? warning;
  }

  static Color category(int index) =>
      chartPalette[index.abs() % chartPalette.length];
}
