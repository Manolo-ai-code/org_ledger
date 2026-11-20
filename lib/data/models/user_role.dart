import '../../core/constants/expense_status.dart';

/// Organization roles supported by OrgLedger.
///
/// The [storageValue] is exactly what is stored in the `users.role` column.
/// [member] is a non-officer role: members may sign in, manage their profile,
/// and view allowed records, but they never create/submit expenses or review
/// approvals. All expense creation and workflow actions are role-bound to the
/// authenticated account.
enum UserRole {
  member('Member', 'Member'),
  businessManager('BusinessManager', 'Business Manager'),
  secretary('Secretary', 'Secretary'),
  treasurer('Treasurer', 'Treasurer'),
  auditor('Auditor', 'Auditor'),
  president('President', 'President'),
  adviser('Adviser', 'Adviser');

  const UserRole(this.storageValue, this.label);

  final String storageValue;
  final String label;

  /// Safe parser for values coming from SQLite or user input.
  static UserRole fromStorage(String? value) {
    final String candidate = value?.trim().toLowerCase() ?? '';
    for (final UserRole role in UserRole.values) {
      if (role.storageValue.toLowerCase() == candidate ||
          role.label.toLowerCase() == candidate ||
          role.name.toLowerCase() == candidate) {
        return role;
      }
    }
    return UserRole.member;
  }

  /// Officer roles that participate in expense submission and/or review.
  bool get isOfficer => this != UserRole.member;

  /// Roles allowed to create/submit expenses.
  ///
  /// Members are strictly read-only for expense creation. Authenticated officer
  /// roles may add/create expenses and still participate in their designated
  /// workflow steps per existing rules.
  bool get canSubmitExpenses => isOfficer;

  bool get isReviewer =>
      this == UserRole.treasurer ||
      this == UserRole.auditor ||
      this == UserRole.president ||
      this == UserRole.adviser;

  /// The Adviser is the continuity/account-management role.
  bool get canManageMembers => this == UserRole.adviser;

  /// The status this officer is expected to act on, or `null` for
  /// non-reviewers.
  String? get reviewableStatus {
    switch (this) {
      case UserRole.treasurer:
        return ExpenseStatus.pending;
      case UserRole.auditor:
        return ExpenseStatus.treasurerVerified;
      case UserRole.president:
        return ExpenseStatus.auditorChecked;
      case UserRole.adviser:
        return ExpenseStatus.presidentEndorsed;
      case UserRole.member:
      case UserRole.businessManager:
      case UserRole.secretary:
        return null;
    }
  }

  /// One-line description shown on the profile screen.
  String get responsibility {
    switch (this) {
      case UserRole.member:
        return 'Read-only access: may view allowed expenses, budgets, burn-down, reports, and logs.';
      case UserRole.businessManager:
        return 'Prepares and submits event expenses with receipts.';
      case UserRole.secretary:
        return 'Encodes purchases and keeps documentation complete.';
      case UserRole.treasurer:
        return 'Verifies receipts and confirms funds were disbursed; may also submit expenses.';
      case UserRole.auditor:
        return 'Checks arithmetic, receipts and policy compliance; may also submit expenses.';
      case UserRole.president:
        return 'Endorses vetted expenses for final approval; may also submit expenses.';
      case UserRole.adviser:
        return 'Grants final approval, locks the liquidation, manages turnover, and may submit expenses.';
    }
  }
}
