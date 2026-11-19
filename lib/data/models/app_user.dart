import 'user_role.dart';

/// A registered organization officer.
///
/// [password] holds a salted SHA-256 digest at rest. It is kept on the model so
/// the authentication repository can verify credentials without a second query.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.role,
  });

  final int id;
  final String name;
  final String email;
  final String password;
  final UserRole role;

  /// Null-safe map parsing. No `!` operators are used anywhere in this file.
  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: _parseInt(map['id']),
      name: map['name']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      password: map['password']?.toString() ?? '',
      role: UserRole.fromStorage(map['role']?.toString()),
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

  Map<String, Object?> toMap({bool includeId = true}) {
    return <String, Object?>{
      if (includeId && id > 0) 'id': id,
      'name': name,
      'email': email,
      'password': password,
      'role': role.storageValue,
    };
  }

  AppUser copyWith({
    int? id,
    String? name,
    String? email,
    String? password,
    UserRole? role,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      password: password ?? this.password,
      role: role ?? this.role,
    );
  }

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
  String toString() => 'AppUser(id: $id, email: $email, role: ${role.label})';
}
