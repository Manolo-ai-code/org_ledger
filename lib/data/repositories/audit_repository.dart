import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/audit_log.dart';

/// Append-only audit trail access.
class AuditRepository {
  AuditRepository(this._db);

  final DatabaseHelper _db;

  /// Writes an entry. Callers should treat failures as non-fatal for the main
  /// action (e.g. an expense approval should still succeed if logging fails).
  Future<int> log({
    required String action,
    required String performedBy,
    DateTime? timestamp,
  }) async {
    final Database db = await _db.database;
    return db.insert(_db.auditLogsTable, <String, Object?>{
      'action': action,
      'performed_by': performedBy.trim().isEmpty ? 'System' : performedBy.trim(),
      'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
    });
  }

  Future<List<AuditLog>> getRecent({int limit = 150}) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      _db.auditLogsTable,
      orderBy: 'timestamp DESC, id DESC',
      limit: limit > 0 ? limit : 150,
    );
    return rows
        .map((Map<String, Object?> row) => AuditLog.fromMap(row))
        .toList(growable: false);
  }

  Future<int> count() async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows =
        await db.rawQuery('SELECT COUNT(*) AS total FROM ${_db.auditLogsTable}');
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }
}
