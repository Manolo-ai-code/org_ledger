/// Global, compile-time constants for OrgLedger.
///
/// Keeping these values in one place avoids magic strings drifting between the
/// database layer, providers and the UI.
abstract final class AppConstants {
  static const String appName = 'OrgLedger';
  static const String organizationName = 'Student Organization';
  static const String tagline = 'Transparent finances. Faster liquidations.';
  static const String databaseName = 'org_ledger.db';

  /// Bumped for additive migrations (v2: username/member/active-status,
  /// v3: budget event metadata/archiving, v4: expense-only audit trail with
  /// expense linkage). Migrations must preserve local data.
  static const int databaseVersion = 4;

  /// Compile-time flag for evaluation/demo builds. When false (default) the app
  /// does not seed demo accounts/data or expose demo credentials in the UI.
  static const bool demoSeed =
      bool.fromEnvironment('DEMO_SEED', defaultValue: false);

  /// Demo password shared by every seeded officer account.
  ///
  /// Only used when [demoSeed] is enabled. Passwords are stored as salted
  /// digests, never as plain text.
  static const String demoPassword = 'password123';

  /// Static application salt. A production deployment should use a per-user
  /// salt and a memory-hard algorithm (e.g. Argon2/bcrypt) on a server.
  static const String passwordSalt = 'orgledger::v1';

  static const String receiptsDirectory = 'receipts';

  // Settings keys persisted in SQLite so the app needs no extra dependency.
  static const String settingSessionUserId = 'session_user_id';
  static const String settingThemeMode = 'theme_mode';
  static const String settingSelectedEventId = 'selected_event_id';
}
