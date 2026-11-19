import 'package:sqflite/sqflite.dart';

import '../../core/utils/password_hasher.dart';
import '../database/database_helper.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';

/// Thrown for expected authentication/registration failures.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Handles credential checks and registration against the local `users` table.
class AuthRepository {
  AuthRepository(this._db);

  final DatabaseHelper _db;

  Future<List<AppUser>> getUsers() async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      _db.usersTable,
      orderBy: 'name COLLATE NOCASE ASC',
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

  Future<AppUser?> findByEmail(String email) async {
    final String candidate = email.trim();
    if (candidate.isEmpty) {
      return null;
    }
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      _db.usersTable,
      where: 'email = ?',
      whereArgs: <Object?>[candidate],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return AppUser.fromMap(rows.first);
  }

  /// Authenticates an officer.
  ///
  /// Throws [AuthException] with a user-facing message on failure.
  Future<AppUser> authenticate({
    required String email,
    required String password,
  }) async {
    final String normalisedEmail = email.trim();
    if (normalisedEmail.isEmpty || password.isEmpty) {
      throw const AuthException('Enter your email and password.');
    }

    final AppUser? user = await findByEmail(normalisedEmail);
    if (user == null) {
      throw const AuthException('No account found for that email address.');
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

  /// Creates a new officer account.
  ///
  /// Returns the persisted user. Does not log the user in; the caller decides
  /// whether to return to the login screen.
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final String cleanName = name.trim();
    final String cleanEmail = email.trim().toLowerCase();

    if (cleanName.length < 2) {
      throw const AuthException('Please enter your full name.');
    }
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw const AuthException('Please enter a valid email address.');
    }
    if (password.length < 8) {
      throw const AuthException('Password must be at least 8 characters.');
    }

    final Database db = await _db.database;
    final List<Map<String, Object?>> existing = await db.query(
      _db.usersTable,
      columns: <String>['id'],
      where: 'email = ?',
      whereArgs: <Object?>[cleanEmail],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw const AuthException(
        'An account with that email already exists. Try signing in.',
      );
    }

    final AppUser user = AppUser(
      id: 0,
      name: cleanName,
      email: cleanEmail,
      password: PasswordHasher.hash(password),
      role: role,
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
        throw const AuthException(
          'An account with that email already exists. Try signing in.',
        );
      }
      throw const AuthException(
        'We could not create your account right now. Please try again.',
      );
    }
  }
}
