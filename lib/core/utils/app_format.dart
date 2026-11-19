import 'dart:math' as math;

import 'package:intl/intl.dart';

/// Centralised, locale-safe formatting helpers.
///
/// Every method tolerates null, NaN and infinite values so a bad database row
/// can never crash a dashboard tile.
abstract final class AppFormat {
  static final NumberFormat _money = NumberFormat('#,##0.00');
  static final NumberFormat _whole = NumberFormat('#,##0');
  static final DateFormat _date = DateFormat('MMM d, yyyy');
  static final DateFormat _shortDate = DateFormat('MMM d');
  static final DateFormat _dateTime = DateFormat('MMM d, yyyy · h:mm a');
  static final DateFormat _time = DateFormat('h:mm a');
  static final DateFormat _fileStamp = DateFormat('yyyyMMdd_HHmm');

  static double safeNumber(num? value) {
    if (value == null) {
      return 0;
    }
    final double result = value.toDouble();
    return result.isFinite ? result : 0;
  }

  /// `₱12,345.67`
  static String currency(num? value, {bool decimals = true}) {
    final double amount = safeNumber(value);
    final String formatted =
        decimals ? _money.format(amount) : _whole.format(amount.round());
    return '₱$formatted';
  }

  /// `₱1.2M`, `₱52.0K` — useful for chart labels and tight cards.
  static String compactCurrency(num? value) {
    final double amount = safeNumber(value);
    final double magnitude = amount.abs();
    if (magnitude >= 1000000) {
      return '₱${(amount / 1000000).toStringAsFixed(magnitude >= 10000000 ? 0 : 1)}M';
    }
    if (magnitude >= 1000) {
      return '₱${(amount / 1000).toStringAsFixed(magnitude >= 10000 ? 0 : 1)}K';
    }
    return '₱${amount.toStringAsFixed(0)}';
  }

  /// `86.7%` — pass a ratio (e.g. 0.867), not a percentage.
  static String percent(num? ratio, {int decimals = 1}) {
    final double value = safeNumber(ratio) * 100;
    return '${value.toStringAsFixed(decimals)}%';
  }

  static String date(DateTime? value) {
    if (value == null || value.millisecondsSinceEpoch <= 0) {
      return '—';
    }
    return _date.format(value.toLocal());
  }

  static String shortDate(DateTime? value) {
    if (value == null || value.millisecondsSinceEpoch <= 0) {
      return '—';
    }
    return _shortDate.format(value.toLocal());
  }

  static String dateTime(DateTime? value) {
    if (value == null || value.millisecondsSinceEpoch <= 0) {
      return '—';
    }
    return _dateTime.format(value.toLocal());
  }

  static String time(DateTime? value) {
    if (value == null || value.millisecondsSinceEpoch <= 0) {
      return '—';
    }
    return _time.format(value.toLocal());
  }

  static String fileStamp(DateTime value) => _fileStamp.format(value);

  /// Friendly relative timestamp such as `Just now`, `3h ago`, `2d ago`.
  static String relative(DateTime? value) {
    if (value == null || value.millisecondsSinceEpoch <= 0) {
      return '—';
    }
    final Duration difference = DateTime.now().difference(value.toLocal());
    if (difference.isNegative) {
      return 'Just now';
    }
    if (difference.inSeconds < 45) {
      return 'Just now';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    }
    return date(value);
  }

  /// Ratio clamped to `[0, 1]`. Protects against division by zero, NaN and
  /// negative denominators.
  static double clampRatio(num? numerator, num? denominator) {
    final double top = safeNumber(numerator);
    final double bottom = safeNumber(denominator);
    if (bottom <= 0) {
      return 0;
    }
    final double raw = top / bottom;
    if (!raw.isFinite) {
      return 0;
    }
    return raw.clamp(0.0, 1.0).toDouble();
  }

  /// Unclamped ratio for percentage labels. Returns 0 for an invalid budget.
  static double ratio(num? numerator, num? denominator) {
    final double top = safeNumber(numerator);
    final double bottom = safeNumber(denominator);
    if (bottom <= 0) {
      return 0;
    }
    final double raw = top / bottom;
    return raw.isFinite ? raw : 0;
  }

  /// The highest value in [values], or [fallback] when empty/invalid.
  static double maxValue(Iterable<num> values, {double fallback = 1}) {
    double result = fallback;
    for (final num value in values) {
      final double candidate = safeNumber(value);
      if (candidate > result) {
        result = candidate;
      }
    }
    return result.isFinite && result > 0 ? result : 1;
  }

  /// `1` → `1st`, `2` → `2nd` (used by the approval stepper).
  static String ordinal(int value) {
    final int mod100 = value.abs() % 100;
    if (mod100 >= 11 && mod100 <= 13) {
      return '${value}th';
    }
    switch (value.abs() % 10) {
      case 1:
        return '${value}st';
      case 2:
        return '${value}nd';
      case 3:
        return '${value}rd';
      default:
        return '${value}th';
    }
  }

  /// Safe divide used by charts.
  static double divide(num? numerator, num? denominator) {
    final double bottom = safeNumber(denominator);
    if (bottom == 0) {
      return 0;
    }
    final double result = safeNumber(numerator) / bottom;
    return result.isFinite ? result : 0;
  }

  /// Clamps a double into a safe range without relying on `num.clamp` return
  /// typing.
  static double clampDouble(double value, double min, double max) {
    if (!value.isFinite) {
      return min;
    }
    return math.min(math.max(value, min), max);
  }
}
