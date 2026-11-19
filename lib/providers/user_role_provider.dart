import 'package:material_ui/material_ui.dart';

import '../core/constants/app_constants.dart';
import '../data/database/database_helper.dart';
import '../data/models/app_user.dart';
import '../data/models/expense.dart';
import '../data/models/user_role.dart';
import '../data/repositories/audit_repository.dart';
import '../data/repositories/auth_repository.dart';

/// Result returned by login/registration actions.
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

  AppUser? get currentUser => _currentUser;
  UserRole? get role => _currentUser?.role;
  bool get isAuthenticated => _currentUser != null;
  bool get isRestoring => _isRestoring;
  bool get isBusy => _isBusy;
  String? get error => _error;

  /// Name + role label used in audit logs.
  String get actorLabel {
    final AppUser? user = _currentUser;
    if (user == null) {
      return 'System';
    }
    return '${user.name} · ${user.role.label}';
  }

  bool get canSubmitExpenses =>
      _currentUser?.role.canSubmitExpenses ?? false;

  bool get canReviewExpenses => _currentUser?.role.isReviewer ?? false;

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
      final String? stored =
          await _db.getSetting(AppConstants.settingSessionUserId);
      final int userId = int.tryParse(stored?.trim() ?? '') ?? 0;
      if (userId > 0) {
        final AppUser? user = await _auth.findById(userId);
        if (user != null) {
          _currentUser = user;
        } else {
          await _db.removeSetting(AppConstants.settingSessionUserId);
        }
      }
    } catch (_) {
      _error = 'Your saved session could not be restored. Please sign in.';
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  /// Authenticates an officer and persists the session.
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
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
        email: email,
        password: password,
      );
      _currentUser = user;
      await _db.setSetting(
        AppConstants.settingSessionUserId,
        user.id.toString(),
      );
      await _tryAudit(
        'Signed in to OrgLedger',
        '${user.name} · ${user.role.label}',
      );
      return AuthResult(
        success: true,
        message: 'Welcome back, ${user.name.split(' ').first}.',
        user: user,
      );
    } catch (error) {
      final String message =
          error is AuthException ? error.message : _friendlyAuthError(error);
      _error = message;
      await _tryAudit(
        'Failed sign-in attempt for ${email.trim()}',
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
  /// The caller returns to the login screen with the new email prefilled.
  Future<AuthResult> registerAccount({
    required String name,
    required String email,
    required String password,
    required UserRole role,
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
        email: email,
        password: password,
        role: role,
      );
      await _tryAudit(
        'Registered a new ${role.label} account',
        '${user.name} · ${role.label}',
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

  Future<void> logout() async {
    final AppUser? user = _currentUser;
    _currentUser = null;
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
      // Authentication must not fail because an audit row could not be written.
    }
  }

  String _friendlyAuthError(Object error) {
    final String raw = error.toString().toLowerCase();
    if (raw.contains('database') || raw.contains('sqlite')) {
      return 'The local ledger could not be opened. Please restart the app.';
    }
    return 'Something went wrong. Please try again.';
  }
}
