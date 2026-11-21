import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/audit_log.dart';
import '../models/expense.dart';

/// Append-only, expense-only audit trail access.
///
/// Every entry must be tied to a specific expense record (create/submit,
/// approval/stage transitions, reject/flag with mandatory remarks, and
/// expense-related liquidation/sync actions). Sign-in/session and other
/// non-expense events are intentionally not recorded.
class AuditRepository {
  AuditRepository(this._db);

  final DatabaseHelper _db;

  /// Writes an expense-linked audit entry. Callers should treat failures as
  /// non-fatal for the main action (e.g. an approval should still succeed if
  /// logging fails).
  Future<int> logExpenseAction({
    required Expense expense,
    required String action,
    required String performedBy,
    String? status,
    String? remarks,
    DateTime? timestamp,
  }) {
    return logExpense(
      expenseId: expense.id,
      expenseTitle: expense.title,
      amount: expense.amount,
      status: status ?? expense.status,
      action: action,
      performedBy: performedBy,
      remarks: remarks ?? expense.remarks,
      timestamp: timestamp,
    );
  }

  /// Writes an expense-linked audit entry from explicit fields.
  Future<int> logExpense({
    required int expenseId,
    required String expenseTitle,
    required double amount,
    required String status,
    required String action,
    required String performedBy,
    String remarks = '',
    DateTime? timestamp,
  }) async {
    final Database db = await _db.database;
    final int id = expenseId > 0 ? expenseId : 0;
    if (id <= 0) {
      return 0;
    }
    final String actor =
        performedBy.trim().isEmpty ? 'System' : performedBy.trim();
    final Map<String, Object?> row = <String, Object?>{
      'expense_id': id,
      'expense_title': expenseTitle.trim(),
      'amount': amount.isFinite && amount >= 0 ? amount : 0.0,
      'status': status.trim(),
      'action': action.trim(),
      'performed_by': actor,
      'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
      'remarks': remarks.trim(),
    };
    if (await _hasColumn(db, 'expense_id')) {
      return db.insert(_db.auditLogsTable, row);
    }
    // Legacy schema fallback (pre-v4): store a clear, expense-linked action
    // string without recording non-expense events.
    return db.insert(_db.auditLogsTable, <String, Object?>{
      'action': _legacyAction(row),
      'performed_by': actor,
      'timestamp': row['timestamp'],
    });
  }

  Future<List<AuditLog>> getRecent({
    int limit = 150,
    bool approvedOnly = false,
  }) async {
    final Database db = await _db.database;
    final int safeLimit = limit > 0 ? limit : 150;
    final List<Map<String, Object?>> rows;
    if (approvedOnly && await _hasColumn(db, 'expense_id')) {
      rows = await db.rawQuery(
        '''
        SELECT a.*
        FROM ${_db.auditLogsTable} a
        INNER JOIN ${_db.expensesTable} e ON e.id = a.expense_id
        WHERE a.expense_id > 0 AND e.status = ?
        ORDER BY a.timestamp DESC, a.id DESC
        LIMIT ?
        ''',
        <Object?>['Adviser_Approved', safeLimit],
      );
    } else if (approvedOnly) {
      // Legacy schema fallback: without expense linkage we cannot prove an
      // expense is approved, so return no logs for approved-only viewers.
      rows = const <Map<String, Object?>>[];
    } else {
      rows = await db.query(
        _db.auditLogsTable,
        orderBy: 'timestamp DESC, id DESC',
        limit: safeLimit,
      );
    }
    final List<AuditLog> logs = rows
        .map((Map<String, Object?> row) => AuditLog.fromMap(row))
        .where((AuditLog log) => _isExpenseLog(log))
        .toList(growable: false);
    return logs;
  }

  Future<int> count() async {
    final Database db = await _db.database;
    if (await _hasColumn(db, 'expense_id')) {
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT COUNT(*) AS total FROM ${_db.auditLogsTable} '
        'WHERE expense_id IS NOT NULL AND expense_id > 0',
      );
      if (rows.isEmpty) {
        return 0;
      }
      return (rows.first['total'] as num?)?.toInt() ?? 0;
    }
    // Legacy DBs may contain non-expense rows; count only entries that look
    // expense-linked by text.
    final List<AuditLog> logs = await getRecent(limit: 10000);
    return logs.length;
  }

  bool _isExpenseLog(AuditLog log) {
    if (log.expenseId > 0) {
      return true;
    }
    final String text = log.action.toLowerCase();
    return text.contains('expense') ||
        text.contains('submitted "') ||
        text.contains('verified receipt') ||
        text.contains('checked arithmetic') ||
        text.contains('endorsed "') ||
        text.contains('approved and locked') ||
        text.contains('rejected "') ||
        text.contains('flagged "') ||
        text.contains('liquidation');
  }

  Future<bool> _hasColumn(Database db, String column) async {
    try {
      final List<Map<String, Object?>> rows =
          await db.rawQuery('PRAGMA table_info(${_db.auditLogsTable})');
      for (final Map<String, Object?> row in rows) {
        if ((row['name']?.toString() ?? '') == column) {
          return true;
        }
      }
    } catch (_) {
      // Best-effort compatibility check.
    }
    return false;
  }

  String _legacyAction(Map<String, Object?> row) {
    final String title = (row['expense_title']?.toString() ?? '').trim();
    final String action = (row['action']?.toString() ?? '').trim();
    final String status = (row['status']?.toString() ?? '').trim();
    final String amount = (row['amount'] as num?)?.toStringAsFixed(2) ?? '0.00';
    final int id = (row['expense_id'] as num?)?.toInt() ?? 0;
    final String remarks = (row['remarks']?.toString() ?? '').trim();
    final String remarkSuffix =
        remarks.isEmpty ? '' : ' (Remarks: $remarks)';
    return '$action for expense #$id "$title" (₱$amount, $status)$remarkSuffix';
  }
}
