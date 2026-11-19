import 'app_format.dart';

/// Reusable form validators shared by login, registration and expense forms.
abstract final class Validators {
  static String? requiredText(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required';
    }
    return null;
  }

  static String? name(String? value) {
    final String candidate = value?.trim() ?? '';
    if (candidate.isEmpty) {
      return 'Full name is required';
    }
    if (candidate.length < 2) {
      return 'Name is too short';
    }
    return null;
  }

  static String? email(String? value) {
    final String candidate = value?.trim() ?? '';
    if (candidate.isEmpty) {
      return 'Email is required';
    }
    final RegExp pattern = RegExp(
      r'^[A-Za-z0-9.!#$%&’*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$',
    );
    if (!pattern.hasMatch(candidate)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? password(String? value) {
    final String candidate = value ?? '';
    if (candidate.isEmpty) {
      return 'Password is required';
    }
    if (candidate.length < 8) {
      return 'Use at least 8 characters';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != original) {
      return 'Passwords do not match';
    }
    return null;
  }

  static String? expenseTitle(String? value) {
    final String candidate = value?.trim() ?? '';
    if (candidate.isEmpty) {
      return 'Describe what was purchased';
    }
    if (candidate.length < 3) {
      return 'Add a little more detail';
    }
    if (candidate.length > 120) {
      return 'Keep the title under 120 characters';
    }
    return null;
  }

  static String? amount(String? value) {
    final String candidate = value?.trim() ?? '';
    if (candidate.isEmpty) {
      return 'Amount is required';
    }
    final double? parsed = double.tryParse(candidate.replaceAll(',', ''));
    if (parsed == null || !parsed.isFinite) {
      return 'Enter a valid amount';
    }
    if (parsed <= 0) {
      return 'Amount must be greater than zero';
    }
    if (parsed > 1000000000) {
      return 'Amount is unrealistically large';
    }
    return null;
  }

  static String? customCategory(String? value, {required bool required}) {
    if (!required) {
      return null;
    }
    final String candidate = value?.trim() ?? '';
    if (candidate.isEmpty) {
      return 'Name the custom category';
    }
    if (candidate.length > 40) {
      return 'Keep it under 40 characters';
    }
    return null;
  }

  static String? remarks(String? value) {
    final String candidate = value?.trim() ?? '';
    if (candidate.isEmpty) {
      return 'A remark is required so the submitter understands why';
    }
    if (candidate.length < 5) {
      return 'Please give a more specific reason';
    }
    return null;
  }

  /// Parses a currency-formatted input into a safe non-negative double.
  static double parseAmount(String? value) {
    final double parsed =
        double.tryParse((value ?? '').trim().replaceAll(',', '')) ?? 0;
    return parsed.isFinite && parsed > 0 ? parsed : 0;
  }

  /// Convenience display of the remaining budget; never negative by default.
  static String remainingLabel(double budget, double spent) {
    final double remaining = budget - spent;
    return AppFormat.currency(remaining);
  }
}
