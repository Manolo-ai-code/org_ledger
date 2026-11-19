import '../../core/constants/expense_status.dart';

/// Officer roles supported by OrgLedger.
///
/// The `storageValue` is exactly what is stored in the `users.role` column.
enum UserRole {
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
    return UserRole.secretary;
  }

  /// Submitters create expenses; reviewers move them along the chain.
  bool get canSubmitExpenses =>
      this == UserRole.businessManager || this == UserRole.secretary;

  bool get isReviewer =>
      this == UserRole.treasurer ||
      this == UserRole.auditor ||
      this == UserRole.president ||
      this == UserRole.adviser;

  /// The status this officer is expected to act on, or `null` for submitters.
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
      case UserRole.businessManager:
      case UserRole.secretary:
        return null;
    }
  }

  /// One-line description shown on the profile screen.
  String get responsibility {
    switch (this) {
      case UserRole.businessManager:
        return 'Prepares and submits event expenses with receipts.';
      case UserRole.secretary:
        return 'Encodes purchases and keeps documentation complete.';
      case UserRole.treasurer:
        return 'Verifies receipts and confirms funds were disbursed.';
      case UserRole.auditor:
        return 'Checks arithmetic, receipts and policy compliance.';
      case UserRole.president:
        return 'Endorses vetted expenses for final approval.';
      case UserRole.adviser:
        return 'Grants final approval and locks the liquidation.';
    }
  }
}
