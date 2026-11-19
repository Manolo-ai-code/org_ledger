/// An immutable audit-trail entry.
///
/// [performedBy] stores a human-readable actor label (for example
/// `Tessa Cruz · Treasurer`). This keeps the audit trail readable even if the
/// originating user account is later renamed.
class AuditLog {
  const AuditLog({
    required this.id,
    required this.action,
    required this.performedBy,
    required this.timestamp,
  });

  final int id;
  final String action;
  final String performedBy;
  final DateTime timestamp;

  /// Null-safe parsing. Never throws on a malformed row.
  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: _parseInt(map['id']),
      action: map['action']?.toString() ?? '',
      performedBy: map['performed_by']?.toString() ?? 'System',
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
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
      'action': action,
      'performed_by': performedBy,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() => 'AuditLog($timestamp, $performedBy: $action)';
}
