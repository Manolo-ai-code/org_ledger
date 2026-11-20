/// An immutable, expense-only audit-trail entry.
///
/// Each entry is tied to a specific expense record so the trail clearly shows
/// who performed what expense action, on which expense, and when.
/// [performedBy] stores a human-readable actor label (for example
/// `Tessa Cruz · Treasurer`).
class AuditLog {
  const AuditLog({
    required this.id,
    required this.expenseId,
    required this.expenseTitle,
    required this.amount,
    required this.status,
    required this.action,
    required this.performedBy,
    required this.timestamp,
    required this.remarks,
  });

  final int id;
  final int expenseId;
  final String expenseTitle;
  final double amount;

  /// Expense status/action state at the time of the logged action.
  final String status;
  final String action;
  final String performedBy;
  final DateTime timestamp;

  /// Required for reject/flag actions; may be empty for other expense actions.
  final String remarks;

  /// Null-safe parsing. Never throws on a malformed row.
  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: _parseInt(map['id']),
      expenseId: _parseInt(map['expense_id']),
      expenseTitle: (map['expense_title']?.toString() ?? '').trim(),
      amount: _parseDouble(map['amount']),
      status: (map['status']?.toString() ?? '').trim(),
      action: (map['action']?.toString() ?? '').trim(),
      performedBy: (map['performed_by']?.toString() ?? 'System').trim(),
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      remarks: (map['remarks']?.toString() ?? '').trim(),
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

  static double _parseDouble(Object? value) {
    if (value is double && value.isFinite) {
      return value;
    }
    if (value is num) {
      final double parsed = value.toDouble();
      return parsed.isFinite ? parsed : 0.0;
    }
    return double.tryParse(value?.toString().trim() ?? '') ?? 0.0;
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return <String, Object?>{
      if (includeId && id > 0) 'id': id,
      'expense_id': expenseId,
      'expense_title': expenseTitle,
      'amount': amount,
      'status': status,
      'action': action,
      'performed_by': performedBy,
      'timestamp': timestamp.toIso8601String(),
      'remarks': remarks,
    };
  }

  @override
  String toString() =>
      'AuditLog(#$expenseId $expenseTitle, $action, $performedBy, $timestamp)';
}
