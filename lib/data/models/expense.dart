import '../../core/constants/app_categories.dart';
import '../../core/constants/expense_status.dart';

/// A single expense entry and its position in the approval pipeline.
///
/// All database parsing uses explicit casts with safe fallbacks. There are no
/// forced null-check (`!`) operators on map values anywhere in this model.
class Expense {
  const Expense({
    required this.id,
    required this.eventId,
    required this.title,
    required this.amount,
    required this.category,
    required this.customCategory,
    required this.receiptImagePath,
    required this.status,
    required this.submittedBy,
    required this.remarks,
    required this.isSynced,
    required this.createdAt,
    required this.updatedAt,
    this.submittedByName = '',
    this.eventTitle = '',
  });

  final int id;
  final int eventId;
  final String title;
  final double amount;

  /// One of [AppCategories.all].
  final String category;

  /// Populated only when [category] is `Others`.
  final String customCategory;
  final String receiptImagePath;
  final String status;
  final int submittedBy;
  final String remarks;
  final bool isSynced;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Read-only fields joined from the users/events tables.
  final String submittedByName;
  final String eventTitle;

  /// Bulletproof map parsing.
  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: _parseInt(map['id']),
      eventId: _parseInt(map['event_id']),
      title: map['title']?.toString() ?? '',
      amount: _parseDouble(map['amount']),
      category: AppCategories.normalise(map['category']?.toString()),
      customCategory: map['custom_category']?.toString() ?? '',
      receiptImagePath: map['receipt_image_path']?.toString() ?? '',
      status: ExpenseStatus.normalise(map['status']?.toString()),
      submittedBy: _parseInt(map['submitted_by']),
      remarks: map['remarks']?.toString() ?? '',
      isSynced: _parseSynced(map['is_synced']),
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
      submittedByName: map['submitted_by_name']?.toString() ?? '',
      eventTitle: map['event_title']?.toString() ?? '',
    );
  }

  /// Accepts ints, doubles and numeric strings from SQLite or fixtures.
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

  /// Accepts ints, doubles and numeric strings, never returning NaN/Infinity.
  static double _parseDouble(Object? value) {
    if (value is num) {
      final double parsed = value.toDouble();
      return parsed.isFinite ? parsed : 0;
    }
    final double parsed = double.tryParse(value?.toString().trim() ?? '') ?? 0;
    return parsed.isFinite ? parsed : 0;
  }

  /// Tolerates integers, booleans and numeric strings.
  static bool _parseSynced(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value.toInt() == 1;
    }
    final String raw = value?.toString().trim().toLowerCase() ?? '';
    return raw == '1' || raw == 'true';
  }

  static DateTime _parseDate(Object? value) {
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return <String, Object?>{
      if (includeId && id > 0) 'id': id,
      'event_id': eventId,
      'title': title,
      'amount': amount,
      'category': category,
      'custom_category': customCategory,
      'receipt_image_path': receiptImagePath,
      'status': status,
      'submitted_by': submittedBy,
      'remarks': remarks,
      'is_synced': isSynced ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Expense copyWith({
    int? id,
    int? eventId,
    String? title,
    double? amount,
    String? category,
    String? customCategory,
    String? receiptImagePath,
    String? status,
    int? submittedBy,
    String? remarks,
    bool? isSynced,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? submittedByName,
    String? eventTitle,
  }) {
    return Expense(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      customCategory: customCategory ?? this.customCategory,
      receiptImagePath: receiptImagePath ?? this.receiptImagePath,
      status: status ?? this.status,
      submittedBy: submittedBy ?? this.submittedBy,
      remarks: remarks ?? this.remarks,
      isSynced: isSynced ?? this.isSynced,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      submittedByName: submittedByName ?? this.submittedByName,
      eventTitle: eventTitle ?? this.eventTitle,
    );
  }

  // ---------------------------------------------------------------------------
  // Derived helpers used throughout the UI.
  // ---------------------------------------------------------------------------

  /// The category shown to users: the custom name when `Others` was selected.
  String get displayCategory {
    final String custom = customCategory.trim();
    if (category == AppCategories.others && custom.isNotEmpty) {
      return custom;
    }
    return category;
  }

  /// Grouping key for charts. Custom categories are rolled into `Others`.
  String get categoryGroup => category;

  bool get isApproved => ExpenseStatus.isApproved(status);
  bool get isPending => status == ExpenseStatus.pending;
  bool get isInFlight => ExpenseStatus.isInFlight(status);
  bool get isRejected => ExpenseStatus.isRejected(status);
  bool get isFlagged => ExpenseStatus.isFlagged(status);
  bool get needsAttention => isRejected || isFlagged;

  /// True when this expense currently has a receipt on disk.
  bool get hasReceipt => receiptImagePath.trim().isNotEmpty;

  /// A short reference shown in tables, e.g. `EXP-0042`.
  String get reference =>
      'EXP-${id.toString().padLeft(4, '0')}';

  @override
  String toString() =>
      'Expense(id: $id, title: $title, amount: $amount, status: $status)';
}
