/// Global, compile-time constants for OrgLedger.
///
/// Keeping these values in one place avoids magic strings drifting between the
/// database layer, providers and the UI.
abstract final class AppConstants {
  static const String appName = 'OrgLedger';
  static const String organizationName = 'Student Organization';
  static const String tagline = 'Transparent finances. Faster liquidations.';
  static const String databaseName = 'org_ledger.db';
  static const int databaseVersion = 1;

  /// Demo password shared by every seeded officer account.
  ///
  /// The seeded accounts are intentionally easy to log into for evaluation.
  /// Passwords are still stored as salted SHA-256 digests, never as plain text.
  static const String demoPassword = 'password123';

  /// Static application salt. A production deployment should use a per-user
  /// salt and a memory-hard algorithm (e.g. Argon2/bcrypt) on a server.
  static const String passwordSalt = 'orgledger::v1';

  static const String receiptsDirectory = 'receipts';

  // Settings keys persisted in SQLite so the app needs no extra dependency.
  static const String settingSessionUserId = 'session_user_id';
  static const String settingThemeMode = 'theme_mode';
}
