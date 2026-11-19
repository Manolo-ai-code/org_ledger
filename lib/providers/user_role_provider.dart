import 'package:material_ui/material_ui.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/app_constants.dart';
import '../data/database/database_helper.dart';
import '../data/models/app_user.dart';
import '../data/models/expense.dart';
import '../data/models/user_role.dart';
import '../data/repositories/audit_repository.dart';
import '../data/repositories/auth_repository.dart';

/// Result returned by login/registration/profile actions.
class AuthResult {
  const AuthResult({
    required this.success,
    this.message = '',
    this.user,
  });

  final bool success;
  final String message;
  final AppUser? user;
}

/// Global session and permission state.
///
/// The logged-in user is the *only* source of truth for role permissions.
/// There is deliberately no in-app role switcher: an officer must sign out and
/// sign in with the correct account to change their permissions.
class UserRoleProvider extends ChangeNotifier {
  UserRoleProvider({
    required AuthRepository authRepository,
    required AuditRepository auditRepository,
    required DatabaseHelper databaseHelper,
  })  : _auth = authRepository,
        _audit = auditRepository,
        _db = databaseHelper;

  final AuthRepository _auth;
  final AuditRepository _audit;
  final DatabaseHelper _db;

  AppUser? _currentUser;
  bool _isRestoring = true;
  bool _isBusy = false;
  String? _error;
  bool _needsBootstrap = false;
  List<AppUser> _managedUsers = <AppUser>[];

  AppUser? get currentUser => _currentUser;
  UserRole? get role => _currentUser?.role;
  bool get isAuthenticated => _currentUser != null;
  bool get isRestoring => _isRestoring;
  bool get isBusy => _isBusy;
  String? get error => _error;
  List<AppUser> get managedUsers => List<AppUser>.unmodifiable(_managedUsers);

  /// True when production mode has no accounts yet and first-run setup is
  /// required before sign-in is possible.
  bool get needsBootstrap => _needsBootstrap;

  /// Name + role label used in audit logs.
  String get actorLabel {
    final AppUser? user = _currentUser;
    if (user == null) {
      return 'System';
    }
    return '${user.name} · ${user.role.label}';
  }

  bool get canSubmitExpenses =>
      (_currentUser?.isActive ?? false) &&
      (_currentUser?.role.canSubmitExpenses ?? false);

  bool get canReviewExpenses =>
      (_currentUser?.isActive ?? false) &&
      (_currentUser?.role.isReviewer ?? false);

  bool get canManageMembers =>
      (_currentUser?.isActive ?? false) &&
      (_currentUser?.role.canManageMembers ?? false);

  /// True when [expense] is waiting at this officer's exact tier.
  bool canActOn(Expense expense) {
    final String? expected = role?.reviewableStatus;
    return expected != null && expense.status == expected;
  }

  /// The status this officer may act on, if any.
  String? get reviewableStatus => role?.reviewableStatus;

  /// Restores a persisted session (if any) when the app launches.
  Future<void> restoreSession() async {
    _isRestoring = true;
    _error = null;
    notifyListeners();
    try {
      _needsBootstrap = !AppConstants.demoSeed && await _db.isFirstRun();

      final String? stored =
          await _db.getSetting(AppConstants.settingSessionUserId);
      final int userId = int.tryParse(stored?.trim() ?? '') ?? 0;
      if (userId > 0) {
        final AppUser? user = await _auth.findById(userId);
        if (user != null && user.isActive) {
          _currentUser = user;
        } else {
          _currentUser = null;
          await _db.removeSetting(AppConstants.settingSessionUserId);
          if (user != null && !user.isActive) {
            _error = 'Your account is deactivated. Contact your adviser.';
          }
        }
      }
    } on DatabaseStartupException {
      rethrow;
    } catch (_) {
      _error = 'Your saved session could not be restored. Please sign in.';
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  /// Authenticates an account by username (or email) and persists the session.
  Future<AuthResult> login({
    String? identifier,
    String? username,
    String? email,
    required String password,
  }) async {
    final String raw = (identifier ?? username ?? email ?? '').trim();
    if (_isBusy) {
      return const AuthResult(
        success: false,
        message: 'A sign-in is already in progress.',
      );
    }
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      final AppUser user = await _auth.authenticate(
        identifier: raw,
        password: password,
      );
      _currentUser = user;
      _needsBootstrap = false;
      try {
        await _db.setSetting(
          AppConstants.settingSessionUserId,
          user.id.toString(),
        );
      } catch (_) {
        // Session persistence is best effort; the in-memory sign-in remains valid.
      }
      await _tryAudit(
        'Signed in to OrgLedger',
        '${user.name} · ${user.role.label}',
      );
      final String greeting = user.name.trim().split(RegExp(r'\s+')).first;
      return AuthResult(
        success: true,
        message: user.mustChangePassword
            ? 'Welcome, $greeting. Please change your password.'
            : 'Welcome back, $greeting.',
        user: user,
      );
    } catch (error) {
      final String message =
          error is AuthException ? error.message : _friendlyAuthError(error);
      _error = message;
      await _tryAudit(
        'Failed sign-in attempt for ${raw.toLowerCase()}',
        'System',
      );
      return AuthResult(success: false, message: message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Creates an account without starting a session.
  ///
  /// Public registration always creates an active Member. The caller returns to
  /// the login screen with the new username prefilled.
  Future<AuthResult> registerAccount({
    required String name,
    required String username,
    String email = '',
    required String password,
  }) async {
    if (_isBusy) {
      return const AuthResult(
        success: false,
        message: 'A request is already in progress.',
      );
    }
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      final AppUser user = await _auth.register(
        name: name,
        username: username,
        email: email,
        password: password,
        role: UserRole.member,
      );
      await _tryAudit(
        'Registered a new ${user.role.label} account (@${user.username})',
        '${user.name} · ${user.role.label}',
      );
      return AuthResult(
        success: true,
        message: 'Account created. You can sign in now.',
        user: user,
      );
    } catch (error) {
      final String message =
          error is AuthException ? error.message : _friendlyAuthError(error);
      _error = message;
      return AuthResult(success: false, message: message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// First-run bootstrap: creates the initial Adviser/manager (production mode)
  /// and signs them in. Only allowed when there are no accounts yet.
  Future<AuthResult> bootstrapInitialAdviser({
    required String name,
    required String username,
    String email = '',
    required String password,
  }) async {
    if (_isBusy) {
      return const AuthResult(
        success: false,
        message: 'A request is already in progress.',
      );
    }
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      final bool firstRun = await _db.isFirstRun();
      if (!firstRun) {
        _needsBootstrap = false;
        return const AuthResult(
          success: false,
          message: 'Setup is already complete. Please sign in.',
        );
      }

      final AppUser user = await _auth.register(
        name: name,
        username: username,
        email: email,
        password: password,
        role: UserRole.adviser,
        isActive: true,
      );

      try {
        // Create a default event so the ledger is usable immediately.
        final db = await _db.database;
        final int existingEvents = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM ${_db.eventsTable}'),
            ) ??
            0;
        if (existingEvents == 0) {
          final String now = DateTime.now().toIso8601String();
          await db.insert(_db.eventsTable, <String, Object?>{
            'title': 'Organization Fund',
            'starting_budget': 0.0,
            'event_type': 'General',
            'school_year': '',
            'is_archived': 0,
            'created_at': now,
            'updated_at': now,
          });
        }

        _currentUser = user;
        _needsBootstrap = false;
        try {
          await _db.setSetting(
            AppConstants.settingSessionUserId,
            user.id.toString(),
          );
        } catch (_) {
          // Best effort; setup already created the account and signed in in-memory.
        }
        await _tryAudit(
          'Completed first-run setup and created initial Adviser account (@${user.username})',
          '${user.name} · ${user.role.label}',
        );
        return AuthResult(
          success: true,
          message: 'Setup complete. Welcome, ${user.name.split(' ').first}.',
          user: user,
        );
      } catch (error) {
        // The adviser account was created but post-setup steps failed. Recompute
        // bootstrap state so the user can sign in instead of being trapped.
        try {
          _needsBootstrap =
              !AppConstants.demoSeed && await _db.isFirstRun();
        } catch (_) {
          _needsBootstrap = false;
        }
        final String message =
            'Your adviser account was created, but setup could not be completed. '
            'Please sign in to continue.';
        _error = message;
        return AuthResult(success: false, message: message);
      }
    } catch (error) {
      try {
        _needsBootstrap = !AppConstants.demoSeed && await _db.isFirstRun();
      } catch (_) {
        // Keep the previous bootstrap state if it cannot be determined.
      }
      final String message =
          error is AuthException ? error.message : _friendlyAuthError(error);
      _error = message;
      return AuthResult(success: false, message: message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Self-service profile update (name and optional contact email).
  Future<AuthResult> updateProfile({
    required String name,
    String? email,
  }) async {
    final AppUser? user = _currentUser;
    if (user == null) {
      return const AuthResult(
        success: false,
        message: 'You must be signed in to update your profile.',
      );
    }
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      final AppUser updated = await _auth.updateProfile(
        userId: user.id,
        name: name,
        email: email,
      );
      _currentUser = updated;
      await _tryAudit(
        'Updated profile information',
        '${updated.name} · ${updated.role.label}',
      );
      return AuthResult(
        success: true,
        message: 'Profile updated.',
        user: updated,
      );
    } catch (error) {
      final String message =
          error is AuthException ? error.message : _friendlyAuthError(error);
      _error = message;
      return AuthResult(success: false, message: message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Self-service password change (requires current password).
  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final AppUser? user = _currentUser;
    if (user == null) {
      return const AuthResult(
        success: false,
        message: 'You must be signed in to change your password.',
      );
    }
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      final AppUser updated = await _auth.changePassword(
        userId: user.id,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      _currentUser = updated;
      await _tryAudit(
        'Changed account password',
        '${updated.name} · ${updated.role.label}',
      );
      return AuthResult(
        success: true,
        message: 'Password changed successfully.',
        user: updated,
      );
    } catch (error) {
      final String message =
          error is AuthException ? error.message : _friendlyAuthError(error);
      _error = message;
      return AuthResult(success: false, message: message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Member / turnover management (Adviser/manager only)
  // ---------------------------------------------------------------------------

  bool _ensureManager() {
    final AppUser? user = _currentUser;
    return user != null && user.isActive && user.role.canManageMembers;
  }

  Future<void> loadManagedUsers({bool silent = false}) async {
    if (!_ensureManager()) {
      return;
    }
    if (!silent) {
      _isBusy = true;
      notifyListeners();
    }
    try {
      _managedUsers = await _auth.getUsers();
      _error = null;
    } catch (_) {
      _error = 'Could not load member accounts. Please try again.';
    } finally {
      if (!silent) {
        _isBusy = false;
      }
      notifyListeners();
    }
  }

  Future<AuthResult> deactivateAccount(AppUser target) async {
    if (!_ensureManager()) {
      return const AuthResult(
        success: false,
        message: 'Only the Adviser can manage accounts.',
      );
    }
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      final AppUser updated = await _auth.deactivateUser(target.id);
      await _tryAudit(
        'Deactivated account @${target.username} (${target.name})',
        actorLabel,
      );
      _refreshManagedUser(updated);
      return AuthResult(
        success: true,
        message: '${target.name} has been deactivated.',
        user: updated,
      );
    } catch (error) {
      final String message =
          error is AuthException ? error.message : _friendlyAuthError(error);
      _error = message;
      return AuthResult(success: false, message: message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<AuthResult> reactivateAccount(AppUser target) async {
    if (!_ensureManager()) {
      return const AuthResult(
        success: false,
        message: 'Only the Adviser can manage accounts.',
      );
    }
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      final AppUser updated = await _auth.reactivateUser(target.id);
      await _tryAudit(
        'Reactivated account @${target.username} (${target.name})',
        actorLabel,
      );
      _refreshManagedUser(updated);
      return AuthResult(
        success: true,
        message: '${target.name} is active again.',
        user: updated,
      );
    } catch (error) {
      final String message =
          error is AuthException ? error.message : _friendlyAuthError(error);
      _error = message;
      return AuthResult(success: false, message: message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<AuthResult> appointRole({
    required AppUser target,
    required UserRole role,
    String? term,
  }) async {
    if (!_ensureManager()) {
      return const AuthResult(
        success: false,
        message: 'Only the Adviser can manage accounts.',
      );
    }
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      final AppUser updated = await _auth.appointUserToRole(
        userId: target.id,
        role: role,
        term: term,
      );
      await _tryAudit(
        'Appointed @${target.username} (${target.name}) as ${role.label}'
        '${term != null && term.trim().isNotEmpty ? ' for ${term.trim()}' : ''}',
        actorLabel,
      );
      await loadManagedUsers(silent: true);
      if (_currentUser?.id == updated.id) {
        _currentUser = updated;
      }
      return AuthResult(
        success: true,
        message: '${target.name} is now ${role.label}.',
        user: updated,
      );
    } catch (error) {
      final String message =
          error is AuthException ? error.message : _friendlyAuthError(error);
      _error = message;
      return AuthResult(success: false, message: message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<AuthResult> resetUserPassword({
    required AppUser target,
    required String newPassword,
  }) async {
    if (!_ensureManager()) {
      return const AuthResult(
        success: false,
        message: 'Only the Adviser can manage accounts.',
      );
    }
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      await _auth.resetPassword(
        userId: target.id,
        newPassword: newPassword,
        requireChange: true,
      );
      await _tryAudit(
        'Reset password for @${target.username} (${target.name})',
        actorLabel,
      );
      await loadManagedUsers(silent: true);
      return AuthResult(
        success: true,
        message: 'Password reset for ${target.name}. They must change it on sign-in.',
      );
    } catch (error) {
      final String message =
          error is AuthException ? error.message : _friendlyAuthError(error);
      _error = message;
      return AuthResult(success: false, message: message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<AuthResult> applyElectionResults({
    required String term,
    required Map<UserRole, int> assignments,
  }) async {
    if (!_ensureManager()) {
      return const AuthResult(
        success: false,
        message: 'Only the Adviser can manage turnover.',
      );
    }
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      await _auth.applyElectionResults(term: term, assignments: assignments);
      await _tryAudit(
        'Applied election results for ${term.trim()}',
        actorLabel,
      );
      await loadManagedUsers(silent: true);
      final AppUser? self = _currentUser;
      if (self != null) {
        final AppUser? refreshed = await _auth.findById(self.id);
        if (refreshed != null && refreshed.isActive) {
          _currentUser = refreshed;
        }
      }
      return AuthResult(
        success: true,
        message: 'Election results applied for ${term.trim()}.',
      );
    } catch (error) {
      final String message =
          error is AuthException ? error.message : _friendlyAuthError(error);
      _error = message;
      return AuthResult(success: false, message: message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void _refreshManagedUser(AppUser updated) {
    _managedUsers = _managedUsers
        .map((AppUser user) => user.id == updated.id ? updated : user)
        .toList(growable: false);
  }

  Future<void> logout() async {
    final AppUser? user = _currentUser;
    _currentUser = null;
    _managedUsers = <AppUser>[];
    _error = null;
    notifyListeners();
    try {
      await _db.removeSetting(AppConstants.settingSessionUserId);
      if (user != null) {
        await _tryAudit(
          'Signed out of OrgLedger',
          '${user.name} · ${user.role.label}',
        );
      }
    } catch (_) {
      // The in-memory session is already cleared; persistence is best effort.
    }
  }

  void clearError() {
    if (_error == null) {
      return;
    }
    _error = null;
    notifyListeners();
  }

  Future<void> _tryAudit(String action, String actor) async {
    try {
      await _audit.log(action: action, performedBy: actor);
    } catch (_) {
      // Authentication/profile actions must not fail because an audit row could
      // not be written.
    }
  }

  String _friendlyAuthError(Object error) {
    if (error is DatabaseStartupException) {
      return '${error.message} Please restart the app and try again.';
    }
    final String raw = error.toString().toLowerCase();
    if (raw.contains('database') || raw.contains('sqlite')) {
      return 'The local ledger could not be opened. Please restart the app.';
    }
    return 'Something went wrong. Please try again.';
  }
}