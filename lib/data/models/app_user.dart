import 'user_role.dart';

/// A registered organization account (member or officer).
///
/// [password] holds a salted digest at rest. It is kept on the model so the
/// authentication repository can verify credentials without a second query.
/// [email] is optional contact information and may be empty; [username] is the
/// primary, normalized sign-in identifier.
class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    this.isActive = true,
    this.deactivatedAt,
    this.term = '',
    this.mustChangePassword = false,
  });

  final int id;
  final String username;
  final String name;

  /// Optional contact email. Empty means not provided.
  final String email;
  final String password;
  final UserRole role;
  final bool isActive;
  final DateTime? deactivatedAt;

  /// School year / term label (e.g. "2026-2027"), if assigned.
  final String term;

  /// Set when an administrator resets the password; the user should change it.
  final bool mustChangePassword;

  /// Null-safe map parsing. No `!` operators are used anywhere in this file.
  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: _parseInt(map['id']),
      username: _normalizeUsername(map['username']?.toString()),
      name: map['name']?.toString() ?? '',
      email: _normalizeEmail(map['email']?.toString()),
      password: map['password']?.toString() ?? '',
      role: UserRole.fromStorage(map['role']?.toString()),
      isActive: _parseBool(map['is_active'], defaultValue: true),
      deactivatedAt: _parseDate(map['deactivated_at']),
      term: map['term']?.toString() ?? '',
      mustChangePassword: _parseBool(map['must_change_password']),
    );
  }

  static int _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      final double parsed = value.toDouble();
      return parsed.isFinite ? parsed.toInt() : 0;
    }
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  static bool _parseBool(Object? value, {bool defaultValue = false}) {
    if (value == null) {
      return defaultValue;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value.toInt() != 0;
    }
    final String raw = value.toString().trim().toLowerCase();
    if (raw == '1' || raw == 'true') {
      return true;
    }
    if (raw == '0' || raw == 'false') {
      return false;
    }
    return defaultValue;
  }

  static DateTime? _parseDate(Object? value) {
    final String raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  /// Normalizes a username for storage/comparison (lowercased, trimmed).
  static String _normalizeUsername(String? value) {
    final String trimmed = value?.trim().toLowerCase() ?? '';
    return trimmed;
  }

  /// Normalizes optional contact email; empty/whitespace becomes empty string.
  static String _normalizeEmail(String? value) {
    final String trimmed = value?.trim().toLowerCase() ?? '';
    return trimmed;
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return <String, Object?>{
      if (includeId && id > 0) 'id': id,
      'username': username,
      'name': name,
      'email': email.isEmpty ? null : email,
      'password': password,
      'role': role.storageValue,
      'is_active': isActive ? 1 : 0,
      'deactivated_at': deactivatedAt?.toIso8601String(),
      'term': term,
      'must_change_password': mustChangePassword ? 1 : 0,
    };
  }

  AppUser copyWith({
    int? id,
    String? username,
    String? name,
    String? email,
    String? password,
    UserRole? role,
    bool? isActive,
    Object? deactivatedAt = _sentinel,
    String? term,
    bool? mustChangePassword,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      email: email ?? this.email,
      password: password ?? this.password,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      deactivatedAt: identical(deactivatedAt, _sentinel)
          ? this.deactivatedAt
          : deactivatedAt as DateTime?,
      term: term ?? this.term,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    );
  }

  static const Object _sentinel = Object();

  /// Preferred sign-in handle shown to the user.
  String get displayHandle => username.isNotEmpty ? '@$username' : email;

  /// Initials used by the profile and reviewer avatars.
  String get initials {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'OL';
    }
    if (parts.length == 1) {
      final String word = parts.first;
      return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  @override
  String toString() =>
      'AppUser(id: $id, username: $username, role: ${role.label}, active: $isActive)';
}
