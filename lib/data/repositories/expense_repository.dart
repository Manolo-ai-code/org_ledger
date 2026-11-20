import 'package:sqflite/sqflite.dart';

import '../../core/constants/expense_status.dart';
import '../database/database_helper.dart';
import '../models/expense.dart';
import '../models/org_event.dart';

/// All event and expense SQL lives here so providers and UI stay storage-agnostic.
class ExpenseRepository {
  ExpenseRepository(this._db);

  final DatabaseHelper _db;

  static const String _expenseSelect = '''
    SELECT
      e.*,
      u.name AS submitted_by_name,
      ev.title AS event_title
    FROM expenses e
    LEFT JOIN users u ON u.id = e.submitted_by
    LEFT JOIN events ev ON ev.id = e.event_id
  ''';

  Future<List<OrgEvent>> getEvents({bool includeArchived = false}) async {
    final Database db = await _db.database;
    final bool hasArchiveColumn = await _hasColumn(db, _db.eventsTable, 'is_archived');
    final List<Map<String, Object?>> rows = await db.query(
      _db.eventsTable,
      where: (!includeArchived && hasArchiveColumn) ? 'is_archived = 0' : null,
      orderBy: hasArchiveColumn ? 'is_archived ASC, id ASC' : 'id ASC',
    );
    return rows
        .map((Map<String, Object?> row) => OrgEvent.fromMap(row))
        .toList(growable: false);
  }

  Future<int> createEvent({
    required String title,
    required double startingBudget,
    String eventType = 'General',
    String schoolYear = '',
  }) async {
    final Database db = await _db.database;
    final DateTime now = DateTime.now();
    final Map<String, Object?> values = <String, Object?>{
      'title': title.trim(),
      'starting_budget': _safeBudget(startingBudget),
    };
    if (await _hasColumn(db, _db.eventsTable, 'event_type')) {
      values['event_type'] =
          eventType.trim().isEmpty ? 'General' : eventType.trim();
    }
    if (await _hasColumn(db, _db.eventsTable, 'school_year')) {
      values['school_year'] = schoolYear.trim();
    }
    if (await _hasColumn(db, _db.eventsTable, 'is_archived')) {
      values['is_archived'] = 0;
    }
    if (await _hasColumn(db, _db.eventsTable, 'created_at')) {
      values['created_at'] = now.toIso8601String();
    }
    if (await _hasColumn(db, _db.eventsTable, 'updated_at')) {
      values['updated_at'] = now.toIso8601String();
    }
    return db.insert(_db.eventsTable, values);
  }

  Future<int> updateEvent({
    required int eventId,
    required String title,
    required double startingBudget,
    String? eventType,
    String? schoolYear,
  }) async {
    final Database db = await _db.database;
    final DateTime now = DateTime.now();
    final Map<String, Object?> values = <String, Object?>{
      'title': title.trim(),
      'starting_budget': _safeBudget(startingBudget),
    };
    if (eventType != null && await _hasColumn(db, _db.eventsTable, 'event_type')) {
      values['event_type'] =
          eventType.trim().isEmpty ? 'General' : eventType.trim();
    }
    if (schoolYear != null &&
        await _hasColumn(db, _db.eventsTable, 'school_year')) {
      values['school_year'] = schoolYear.trim();
    }
    if (await _hasColumn(db, _db.eventsTable, 'updated_at')) {
      values['updated_at'] = now.toIso8601String();
    }
    return db.update(
      _db.eventsTable,
      values,
      where: 'id = ?',
      whereArgs: <Object?>[eventId],
    );
  }

  /// Archives or restores an event. Archived events remain in the ledger (and
  /// keep their expenses/history) but are hidden from the default active view.
  Future<int> setEventArchived({
    required int eventId,
    required bool archived,
  }) async {
    final Database db = await _db.database;
    if (!await _hasColumn(db, _db.eventsTable, 'is_archived')) {
      return 0;
    }
    final Map<String, Object?> values = <String, Object?>{
      'is_archived': archived ? 1 : 0,
    };
    if (await _hasColumn(db, _db.eventsTable, 'updated_at')) {
      values['updated_at'] = DateTime.now().toIso8601String();
    }
    return db.update(
      _db.eventsTable,
      values,
      where: 'id = ?',
      whereArgs: <Object?>[eventId],
    );
  }

  double _safeBudget(double value) {
    if (!value.isFinite || value < 0) {
      return 0;
    }
    return value;
  }

  Future<bool> _hasColumn(Database db, String table, String column) async {
    final List<Map<String, Object?>> rows =
        await db.rawQuery('PRAGMA table_info($table)');
    for (final Map<String, Object?> row in rows) {
      if ((row['name']?.toString() ?? '') == column) {
        return true;
      }
    }
    return false;
  }

  Future<OrgEvent?> getEvent(int id) async {
    if (id <= 0) {
      return null;
    }
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      _db.eventsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return OrgEvent.fromMap(rows.first);
  }

  /// Loads expenses, optionally scoped to an event and/or status.
  Future<List<Expense>> getExpenses({
    int? eventId,
    String? status,
    int? limit,
  }) async {
    final Database db = await _db.database;
    final List<String> clauses = <String>[];
    final List<Object?> args = <Object?>[];

    if (eventId != null && eventId > 0) {
      clauses.add('e.event_id = ?');
      args.add(eventId);
    }
    if (status != null && status.trim().isNotEmpty) {
      clauses.add('e.status = ?');
      args.add(ExpenseStatus.normalise(status));
    }

    final String where =
        clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final String limitSql = limit != null && limit > 0 ? 'LIMIT $limit' : '';

    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_expenseSelect $where '
      'ORDER BY e.created_at DESC, e.id DESC $limitSql',
      args,
    );
    return rows
        .map((Map<String, Object?> row) => Expense.fromMap(row))
        .toList(growable: false);
  }

  Future<Expense?> getExpense(int id) async {
    if (id <= 0) {
      return null;
    }
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_expenseSelect WHERE e.id = ? LIMIT 1',
      <Object?>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return Expense.fromMap(rows.first);
  }

  Future<List<Expense>> getApprovedExpenses(int eventId) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_expenseSelect WHERE e.event_id = ? AND e.status = ? '
      'ORDER BY e.created_at ASC, e.id ASC',
      <Object?>[eventId, ExpenseStatus.adviserApproved],
    );
    return rows
        .map((Map<String, Object?> row) => Expense.fromMap(row))
        .toList(growable: false);
  }

  Future<int> insertExpense(Expense expense) async {
    final Database db = await _db.database;
    return db.insert(
      _db.expensesTable,
      expense.toMap(includeId: false),
    );
  }

  Future<int> updateStatus({
    required int expenseId,
    required String status,
    required String remarks,
    bool isSynced = false,
    String? expectedStatus,
  }) async {
    final Database db = await _db.database;
    // When [expectedStatus] is supplied the update is conditional, so a stale
    // screen cannot overwrite a record that another officer already moved.
    final bool guarded = expectedStatus != null;
    return db.update(
      _db.expensesTable,
      <String, Object?>{
        'status': ExpenseStatus.normalise(status),
        'remarks': remarks,
        'is_synced': isSynced ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: guarded ? 'id = ? AND status = ?' : 'id = ?',
      whereArgs: guarded
          ? <Object?>[expenseId, ExpenseStatus.normalise(expectedStatus)]
          : <Object?>[expenseId],
    );
  }

  Future<int> updateReceiptPath({
    required int expenseId,
    required String path,
  }) async {
    final Database db = await _db.database;
    return db.update(
      _db.expensesTable,
      <String, Object?>{
        'receipt_image_path': path,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[expenseId],
    );
  }

  /// Returns expenses currently queued for sync (`is_synced = 0`).
  Future<List<Expense>> getUnsyncedExpenses({int? eventId}) async {
    final Database db = await _db.database;
    final List<String> clauses = <String>['e.is_synced = 0'];
    final List<Object?> args = <Object?>[];
    if (eventId != null && eventId > 0) {
      clauses.add('e.event_id = ?');
      args.add(eventId);
    }
    final String where = 'WHERE ${clauses.join(' AND ')}';
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_expenseSelect $where ORDER BY e.created_at ASC, e.id ASC',
      args,
    );
    return rows
        .map((Map<String, Object?> row) => Expense.fromMap(row))
        .toList(growable: false);
  }

  /// Marks every locally-queued record as synced.
  ///
  /// This is the single write point used by [SyncService]; when a real backend
  /// is connected, replace this with a per-record upload loop.
  Future<int> markAllSynced() async {
    final Database db = await _db.database;
    return db.update(
      _db.expensesTable,
      <String, Object?>{'is_synced': 1},
      where: 'is_synced = 0',
    );
  }

  Future<int> pendingSyncCount() async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ${_db.expensesTable} WHERE is_synced = 0',
    );
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<int> countForEvent(int eventId) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ${_db.expensesTable} WHERE event_id = ?',
      <Object?>[eventId],
    );
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }
}
