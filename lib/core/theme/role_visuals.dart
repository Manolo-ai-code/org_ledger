import 'package:material_ui/material_ui.dart';

import '../../data/models/user_role.dart';

/// Per-role icon and accent color used across login, profile and admin views.
abstract final class RoleVisuals {
  static IconData icon(UserRole role) {
    switch (role) {
      case UserRole.member:
        return Icons.person_outline_rounded;
      case UserRole.businessManager:
        return Icons.business_center_outlined;
      case UserRole.secretary:
        return Icons.description_outlined;
      case UserRole.treasurer:
        return Icons.account_balance_wallet_outlined;
      case UserRole.auditor:
        return Icons.fact_check_outlined;
      case UserRole.president:
        return Icons.workspace_premium_outlined;
      case UserRole.adviser:
        return Icons.school_outlined;
    }
  }

  static Color color(UserRole role) {
    switch (role) {
      case UserRole.member:
        return const Color(0xFF4B6356);
      case UserRole.businessManager:
        return const Color(0xFF2F6FED);
      case UserRole.secretary:
        return const Color(0xFF7A5AC8);
      case UserRole.treasurer:
        return const Color(0xFF0E7C66);
      case UserRole.auditor:
        return const Color(0xFFB26A00);
      case UserRole.president:
        return const Color(0xFF8A5A2B);
      case UserRole.adviser:
        return const Color(0xFFB25068);
    }
  }

  /// Short explanation of the approval tier for badges.
  static String tier(UserRole role) {
    switch (role) {
      case UserRole.member:
        return 'Member';
      case UserRole.businessManager:
      case UserRole.secretary:
        return 'Submitter';
      case UserRole.treasurer:
        return 'Stage 1 – Verification';
      case UserRole.auditor:
        return 'Stage 2 – Audit';
      case UserRole.president:
        return 'Stage 3 – Endorsement';
      case UserRole.adviser:
        return 'Stage 4 – Final approval';
    }
  }
}
