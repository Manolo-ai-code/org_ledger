import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../constants/app_constants.dart';

/// Small password hashing helper.
///
/// The local demo database must never contain plain-text passwords, so the
/// seeder and registration flow both store a salted SHA-256 digest.
///
/// NOTE: SHA-256 is used here because this is an offline, on-device demo.
/// A production server should perform authentication with a memory-hard
/// algorithm such as Argon2id and a unique per-user salt.
abstract final class PasswordHasher {
  static String hash(String password) {
    final List<int> bytes = utf8.encode(
      '${AppConstants.passwordSalt}:$password',
    );
    return sha256.convert(bytes).toString();
  }

  /// Verifies a submitted password against a stored digest.
  ///
  /// The legacy branch allows a database created by an older prototype (which
  /// may have stored plain text) to keep working; the caller can then upgrade
  /// the record to a digest.
  static bool verify({
    required String password,
    required String storedDigest,
  }) {
    if (storedDigest.trim().isEmpty) {
      return false;
    }
    if (storedDigest == password) {
      return true;
    }
    return hash(password) == storedDigest;
  }

  static bool isLegacyPlainText({
    required String password,
    required String storedDigest,
  }) {
    return storedDigest.isNotEmpty && storedDigest == password;
  }
}
