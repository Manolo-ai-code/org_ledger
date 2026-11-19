import 'package:sqflite/sqflite.dart';

import '../../core/utils/password_hasher.dart';
import '../database/database_helper.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';

/// Thrown for expected authentication/registration/profile failures.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Handles credential checks, registration and profile updates against the
/// local `users` table.
class AuthRepository {
  AuthRepository(this._db);

  final DatabaseHelper _db;

  Future<List<AppUser>> getUsers() async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      _db.usersTable,
      orderBy: 'is_active DESC, role ASC, name COLLATE NOCASE ASC',
    );
    return rows
        .map((Map<String, Object?> row) => AppUser.fromMap(row))
        .toList(growable: false);
  }

  Future<AppUser?> findById(int id) async {
    if (id <= 0) {
      return null;
    }
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      _db.usersTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return AppUser.fromMap(rows.first);
  }

  /// Looks up an active user by username (case-insensitive). Falls back to
  /// email match for backward compatibility when the identifier contains '@'.
  Future<AppUser?> findByIdentifier(String identifier) async {
    final String raw = identifier.trim();
    if (raw.isEmpty) {
      return null;
    }
    final Database db = await _db.database;

    // Username-first (normalized/lowercased).
    final String username = raw.toLowerCase();
    List<Map<String, Object?>> rows = await db.query(
      _db.usersTable,
      where: 'LOWER(username) = ?',
      whereArgs: <Object?>[username],
      limit: 1,
    );
    if (rows.isEmpty && raw.contains('@')) {
      rows = await db.query(
        _db.usersTable,
        where: 'LOWER(email) = ?',
        whereArgs: <Object?>[raw.toLowerCase()],
        limit: 1,
      );
    }
    if (rows.isEmpty) {
      return null;
    }
    return AppUser.fromMap(rows.first);
  }

  /// Legacy helper kept for compatibility with existing call sites/tests.
  Future<AppUser?> findByEmail(String email) async {
    final String candidate = email.trim().toLowerCase();
    if (candidate.isEmpty) {
      return null;
    }
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      _db.usersTable,
      where: 'LOWER(email) = ?',
      whereArgs: <Object?>[candidate],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return AppUser.fromMap(rows.first);
  }

  /// Authenticates by username (or email for backward compatibility).
  ///
  /// Throws [AuthException] with a user-facing message on failure.
  Future<AppUser> authenticate({
    String? identifier,
    String? username,
    String? email,
    required String password,
  }) async {
    final String raw =
        (identifier ?? username ?? email ?? '').trim();
    if (raw.isEmpty || password.isEmpty) {
      throw const AuthException('Enter your username and password.');
    }

    final AppUser? user = await findByIdentifier(raw);
    if (user == null) {
      throw const AuthException('No account found for that username.');
    }
    if (!user.isActive) {
      throw const AuthException(
        'This account is deactivated. Contact your organization adviser for help.',
      );
    }
    if (!PasswordHasher.verify(
      password: password,
      storedDigest: user.password,
    )) {
      throw const AuthException('Incorrect password. Please try again.');
    }

    // Transparently upgrade a legacy plain-text row to a digest.
    if (PasswordHasher.isLegacyPlainText(
      password: password,
      storedDigest: user.password,
    )) {
      final Database db = await _db.database;
      final String digest = PasswordHasher.hash(password);
      await db.update(
        _db.usersTable,
        <String, Object?>{'password': digest},
        where: 'id = ?',
        whereArgs: <Object?>[user.id],
      );
      return user.copyWith(password: digest);
    }

    return user;
  }

  /// Creates a new account.
  ///
  /// Public registration always creates an active [UserRole.member]. Adviser
  /// provisioning (Stage 2) may specify a different [role]. Returns the
  /// persisted user without starting a session.
  Future<AppUser> register({
    required String name,
    required String username,
    String email = '',
    required String password,
    UserRole role = UserRole.member,
    bool isActive = true,
    String term = '',
    bool mustChangePassword = false,
  }) async {
    final String cleanName = name.trim();
    final String cleanUsername = _normalizeUsername(username);
    final String cleanEmail = email.trim().toLowerCase();

    if (cleanName.length < 2) {
      throw const AuthException('Please enter your full name.');
    }
    _validateUsername(cleanUsername);
    if (cleanEmail.isNotEmpty && !cleanEmail.contains('@')) {
      throw const AuthException('Please enter a valid contact email, or leave it blank.');
    }
    if (password.length < 8) {
      throw const AuthException('Password must be at least 8 characters.');
    }

    final Database db = await _db.database;
    await _ensureUniqueUsername(db, cleanUsername);
    if (cleanEmail.isNotEmpty) {
      await _ensureUniqueEmail(db, cleanEmail);
    }

    final AppUser user = AppUser(
      id: 0,
      username: cleanUsername,
      name: cleanName,
      email: cleanEmail,
      password: PasswordHasher.hash(password),
      role: role,
      isActive: isActive,
      term: term.trim(),
      mustChangePassword: mustChangePassword,
    );

    try {
      final int id = await db.insert(
        _db.usersTable,
        user.toMap(includeId: false),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return user.copyWith(id: id);
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        if (cleanEmail.isNotEmpty) {
          // Could be username or email; check both for a specific message.
          final AppUser? byName = await findByIdentifier(cleanUsername);
          if (byName != null) {
            throw const AuthException(
              'That username is already taken. Choose another one.',
            );
          }
        }
        throw const AuthException(
          'That username or email is already in use. Try a different one.',
        );
      }
      throw const AuthException(
        'We could not create the account right now. Please try again.',
      );
    }
  }

  /// Updates profile fields the user may edit themselves.
  Future<AppUser> updateProfile({
    required int userId,
    required String name,
    String? email,
  }) async {
    final Database db = await _db.database;
    final AppUser? existing = await findById(userId);
    if (existing == null) {
      throw const AuthException('Your account could not be found. Please sign in again.');
    }

    final String cleanName = name.trim();
    if (cleanName.length < 2) {
      throw const AuthException('Please enter your full name.');
    }
    final String cleanEmail = (email ?? existing.email).trim().toLowerCase();
    if (cleanEmail.isNotEmpty && !cleanEmail.contains('@')) {
      throw const AuthException('Please enter a valid contact email, or leave it blank.');
    }
    if (cleanEmail.isNotEmpty && cleanEmail != existing.email) {
      await _ensureUniqueEmail(db, cleanEmail, exceptUserId: userId);
    }

    await db.update(
      _db.usersTable,
      <String, Object?>{
        'name': cleanName,
        'email': cleanEmail.isEmpty ? null : cleanEmail,
      },
      where: 'id = ?',
      whereArgs: <Object?>[userId],
    );
    return existing.copyWith(name: cleanName, email: cleanEmail);
  }

  /// Changes the signed-in user's password after verifying the current one.
  Future<AppUser> changePassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final Database db = await _db.database;
    final AppUser? existing = await findById(userId);
    if (existing == null) {
      throw const AuthException('Your account could not be found. Please sign in again.');
    }
    if (!PasswordHasher.verify(
      password: currentPassword,
      storedDigest: existing.password,
    )) {
      throw const AuthException('Your current password is incorrect.');
    }
    if (newPassword.length < 8) {
      throw const AuthException('New password must be at least 8 characters.');
    }
    if (PasswordHasher.verify(
      password: newPassword,
      storedDigest: existing.password,
    )) {
      throw const AuthException('Choose a password different from your current one.');
    }

    final String digest = PasswordHasher.hash(newPassword);
    await db.update(
      _db.usersTable,
      <String, Object?>{
        'password': digest,
        'must_change_password': 0,
      },
      where: 'id = ?',
      whereArgs: <Object?>[userId],
    );
    return existing.copyWith(password: digest, mustChangePassword: false);
  }

  /// Administrative password reset (no secrets logged; exposed to UI in Stage 2).
  Future<void> resetPassword({
    required int userId,
    required String newPassword,
    bool requireChange = true,
  }) async {
    if (newPassword.length < 8) {
      throw const AuthException('New password must be at least 8 characters.');
    }
    final Database db = await _db.database;
    final String digest = PasswordHasher.hash(newPassword);
    final int updated = await db.update(
      _db.usersTable,
      <String, Object?>{
        'password': digest,
        'must_change_password': requireChange ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: <Object?>[userId],
    );
    if (updated == 0) {
      throw const AuthException('The selected account could not be found.');
    }
  }

  Future<int> _countActiveManagers(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ${_db.usersTable} '
      'WHERE is_active = 1 AND role = ?',
      <Object?>[UserRole.adviser.storageValue],
    );
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  /// Deactivates an account. Never allowed for the last active Adviser/manager.
  Future<AppUser> deactivateUser(int userId) async {
    final Database db = await _db.database;
    return db.transaction<AppUser>((Transaction txn) async {
      final AppUser user = await _requireUser(txn, userId);
      if (!user.isActive) {
        return user;
      }
      if (user.role.canManageMembers) {
        final int managers = await _countActiveManagers(txn);
        if (managers <= 1) {
          throw const AuthException(
            'Cannot deactivate the last active Adviser account.',
          );
        }
      }
      final String now = DateTime.now().toIso8601String();
      await txn.update(
        _db.usersTable,
        <String, Object?>{
          'is_active': 0,
          'deactivated_at': now,
        },
        where: 'id = ?',
        whereArgs: <Object?>[userId],
      );
      return user.copyWith(isActive: false, deactivatedAt: DateTime.parse(now));
    });
  }

  /// Reactivates a previously deactivated account.
  Future<AppUser> reactivateUser(int userId) async {
    final Database db = await _db.database;
    final AppUser user = await _requireUser(db, userId);
    if (user.isActive) {
      return user;
    }
    await db.update(
      _db.usersTable,
      <String, Object?>{
        'is_active': 1,
        'deactivated_at': null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[userId],
    );
    return user.copyWith(isActive: true, deactivatedAt: null);
  }

  /// Appoints [userId] to [role].
  ///
  /// Officer seats are single-holder by default: any other active holder of the
  /// same officer role is auto-demoted to active Member. The target user is
  /// activated if needed. Never allows locking out the last active Adviser.
  Future<AppUser> appointUserToRole({
    required int userId,
    required UserRole role,
    String? term,
  }) async {
    final Database db = await _db.database;
    return db.transaction<AppUser>((Transaction txn) async {
      final AppUser target = await _requireUser(txn, userId);

      // If moving the last active adviser away from a manager role, block.
      if (target.role.canManageMembers &&
          !role.canManageMembers &&
          target.isActive) {
        final int managers = await _countActiveManagers(txn);
        if (managers <= 1) {
          throw const AuthException(
            'Cannot remove Adviser access from the last active Adviser account.',
          );
        }
      }

      if (role.isOfficer) {
        // Demote other active holders of this single-holder seat to Member.
        final List<Map<String, Object?>> holders = await txn.query(
          _db.usersTable,
          columns: <String>['id', 'role', 'is_active'],
          where: 'role = ? AND is_active = 1 AND id != ?',
          whereArgs: <Object?>[role.storageValue, userId],
        );
        for (final Map<String, Object?> row in holders) {
          final int holderId = (row['id'] as num?)?.toInt() ?? 0;
          final UserRole holderRole =
              UserRole.fromStorage(row['role']?.toString());
          if (holderRole.canManageMembers) {
            final int managers = await _countActiveManagers(txn);
            // The target will become the (or an) adviser after this appoint,
            // so demoting this adviser is safe as long as target ends as adviser
            // or another manager exists. Count includes this holder.
            final bool targetBecomesManager = role.canManageMembers;
            if (!targetBecomesManager && managers <= 1) {
              throw const AuthException(
                'Cannot remove the last active Adviser without assigning another.',
              );
            }
          }
          if (holderId > 0) {
            await txn.update(
              _db.usersTable,
              <String, Object?>{'role': UserRole.member.storageValue},
              where: 'id = ?',
              whereArgs: <Object?>[holderId],
            );
          }
        }
      }

      final Map<String, Object?> values = <String, Object?>{
        'role': role.storageValue,
        'is_active': 1,
        'deactivated_at': null,
      };
      if (term != null) {
        values['term'] = term.trim();
      }
      await txn.update(
        _db.usersTable,
        values,
        where: 'id = ?',
        whereArgs: <Object?>[userId],
      );

      final AppUser updated = await _requireUser(txn, userId);
      return updated;
    });
  }

  /// Applies election/turnover results for a term.
  ///
  /// [assignments] maps each officer seat role to the selected user id.
  /// Previous holders of assigned seats are auto-demoted to Member when
  /// replaced. Ensures at least one active Adviser remains.
  Future<void> applyElectionResults({
    required String term,
    required Map<UserRole, int> assignments,
  }) async {
    final String cleanTerm = term.trim();
    if (cleanTerm.isEmpty) {
      throw const AuthException('Please enter the school year/term.');
    }

    const List<UserRole> seats = <UserRole>[
      UserRole.businessManager,
      UserRole.secretary,
      UserRole.treasurer,
      UserRole.auditor,
      UserRole.president,
      UserRole.adviser,
    ];

    for (final UserRole seat in seats) {
      if (!assignments.containsKey(seat) || (assignments[seat] ?? 0) <= 0) {
        throw AuthException('Select a user for the ${seat.label} seat.');
      }
    }

    final List<int> ids = seats.map((UserRole s) => assignments[s] ?? 0).toList();
    if (ids.toSet().length != ids.length) {
      throw const AuthException(
        'Each officer seat must be assigned to a different person.',
      );
    }

    final Database db = await _db.database;
    await db.transaction<void>((Transaction txn) async {
      // Validate all targets exist.
      final Map<int, AppUser> targets = <int, AppUser>{};
      for (final int id in ids) {
        targets[id] = await _requireUser(txn, id);
      }

      // Apply per seat. appoint logic inlined for transaction control.
      // 1) Demote current active holders of these seats who are not selected for the same seat.
      for (final UserRole seat in seats) {
        final int selectedId = assignments[seat] ?? 0;
        final List<Map<String, Object?>> holders = await txn.query(
          _db.usersTable,
          columns: <String>['id'],
          where: 'role = ? AND is_active = 1 AND id != ?',
          whereArgs: <Object?>[seat.storageValue, selectedId],
        );
        for (final Map<String, Object?> row in holders) {
          final int holderId = (row['id'] as num?)?.toInt() ?? 0;
          if (holderId > 0) {
            // If this holder is selected for a different seat in this batch,
            // they will be promoted below; skip demoting to Member now only if selected elsewhere.
            final bool selectedElsewhere =
                ids.contains(holderId) && holderId != selectedId;
            if (!selectedElsewhere) {
              await txn.update(
                _db.usersTable,
                <String, Object?>{'role': UserRole.member.storageValue},
                where: 'id = ?',
                whereArgs: <Object?>[holderId],
              );
            }
          }
        }
      }

      // 2) Assign selected users to their seats, activate, and set term.
      for (final UserRole seat in seats) {
        final int selectedId = assignments[seat] ?? 0;
        await txn.update(
          _db.usersTable,
          <String, Object?>{
            'role': seat.storageValue,
            'is_active': 1,
            'deactivated_at': null,
            'term': cleanTerm,
          },
          where: 'id = ?',
          whereArgs: <Object?>[selectedId],
        );
      }

      // 3) Ensure at least one active adviser exists.
      final int managers = await _countActiveManagers(txn);
      if (managers < 1) {
        throw const AuthException(
          'Election results must leave at least one active Adviser.',
        );
      }
    });
  }

  Future<AppUser> _requireUser(DatabaseExecutor db, int userId) async {
    final List<Map<String, Object?>> rows = await db.query(
      _db.usersTable,
      where: 'id = ?',
      whereArgs: <Object?>[userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const AuthException('The selected account could not be found.');
    }
    return AppUser.fromMap(rows.first);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _validateUsername(String username) {
    if (username.isEmpty) {
      throw const AuthException('Username is required.');
    }
    if (username.length < 3 || username.length > 30) {
      throw const AuthException('Username must be 3 to 30 characters.');
    }
    final RegExp pattern = RegExp(r'^[a-z0-9._-]+$');
    if (!pattern.hasMatch(username)) {
      throw const AuthException(
        'Use only letters, numbers, dot, underscore, or hyphen in your username.',
      );
    }
  }

  String _normalizeUsername(String value) => value.trim().toLowerCase();

  Future<void> _ensureUniqueUsername(
    Database db,
    String username, {
    int? exceptUserId,
  }) async {
    final List<Object?> args = <Object?>[username];
    String where = 'LOWER(username) = ?';
    if (exceptUserId != null) {
      where += ' AND id != ?';
      args.add(exceptUserId);
    }
    final List<Map<String, Object?>> rows = await db.query(
      _db.usersTable,
      columns: <String>['id'],
      where: where,
      whereArgs: args,
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw const AuthException(
        'That username is already taken. Choose another one.',
      );
    }
  }

  Future<void> _ensureUniqueEmail(
    Database db,
    String email, {
    int? exceptUserId,
  }) async {
    final List<Object?> args = <Object?>[email];
    String where = 'LOWER(email) = ?';
    if (exceptUserId != null) {
      where += ' AND id != ?';
      args.add(exceptUserId);
    }
    final List<Map<String, Object?>> rows = await db.query(
      _db.usersTable,
      columns: <String>['id'],
      where: where,
      whereArgs: args,
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw const AuthException(
        'An account with that email already exists.',
      );
    }
  }
}
