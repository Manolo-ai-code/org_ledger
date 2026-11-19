import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_categories.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/expense_status.dart';
import '../../core/utils/password_hasher.dart';
import '../models/user_role.dart';

/// Raised when the local SQLite database cannot be opened, even after the
/// helper has tried to repair or rebuild it.
///
/// The UI should show [message] to the user and offer a retry, because the next
/// attempt performs another full recovery pass.
class DatabaseStartupException implements Exception {
  const DatabaseStartupException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'DatabaseStartupException: $message${cause == null ? '' : ' ($cause)'}';
}

/// Central SQLite access point.
///
/// The helper is a singleton in the running app but accepts an optional
/// [Database] in its constructor so tests or previews can inject an in-memory
/// database without touching platform channels.
///
/// Startup is intentionally defensive:
/// 1. The database directory is created if it does not exist.
/// 2. If the platform database path is unusable, the app-support directory is
///    tried as a fallback.
/// 3. A corrupt file, interrupted first-run creation or stale schema (version
///    matches but tables are missing) is deleted and rebuilt from scratch.
class DatabaseHelper {
  DatabaseHelper({
    Database? database,
    Future<Directory> Function()? databaseDirectoryProvider,
  })  : _db = database,
        _directoryProvider = databaseDirectoryProvider;

  static final DatabaseHelper instance = DatabaseHelper();

  static const String _usersTable = 'users';
  static const String _eventsTable = 'events';
  static const String _expensesTable = 'expenses';
  static const String _auditLogsTable = 'audit_logs';
  static const String _settingsTable = 'app_settings';

  static const List<String> _requiredTables = <String>[
    _usersTable,
    _eventsTable,
    _expensesTable,
    _auditLogsTable,
    _settingsTable,
  ];

  /// Optional directory override used by tests and previews.
  final Future<Directory> Function()? _directoryProvider;

  Database? _db;
  Future<Database>? _opening;

  String get usersTable => _usersTable;
  String get eventsTable => _eventsTable;
  String get expensesTable => _expensesTable;
  String get auditLogsTable => _auditLogsTable;
  String get settingsTable => _settingsTable;

  /// Opens (once) and returns the application database.
  Future<Database> get database {
    final Database? existing = _db;
    if (existing != null && existing.isOpen) {
      return Future<Database>.value(existing);
    }
    return _opening ??= _openWithRecovery().then((Database db) {
      _db = db;
      return db;
    }).whenComplete(() {
      _opening = null;
    });
  }

  /// Forces a fresh open, even if a previous attempt failed.
  ///
  /// The startup error screen calls this from its "Try again" action. It closes
  /// any half-open handle, cancels the cached attempt and runs the full
  /// recovery sequence again.
  Future<Database> reopen() async {
    final Future<Database>? pending = _opening;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // The previous attempt already failed; a fresh one is starting now.
      }
    }
    await _closeQuietly();
    _opening = null;
    return database;
  }

  /// Resolves the database directory and opens it with repair.
  Future<Database> _openWithRecovery() async {
    final Future<Directory> Function()? override = _directoryProvider;
    if (override != null) {
      final Directory directory;
      try {
        directory = await override();
      } catch (error) {
        throw DatabaseStartupException(
          'OrgLedger could not resolve a folder for its local database.',
          cause: error,
        );
      }
      return _openWithRepair(directory);
    }

    Object? lastError;
    Directory? primary;
    try {
      primary = Directory(await getDatabasesPath());
    } catch (error) {
      lastError = error;
    }

    if (primary != null) {
      try {
        return await _openWithRepair(primary);
      } catch (error) {
        lastError = error;
      }
    }

    // Some devices report a databases path that exists but is not writable.
    // The app-support directory is private and always writable when the app
    // itself can run, so it is the final fallback.
    try {
      final Directory support = await getApplicationSupportDirectory();
      final Directory fallback = Directory(p.join(support.path, 'databases'));
      if (primary != null && p.equals(primary.path, fallback.path)) {
        throw DatabaseStartupException(
          'OrgLedger could not rebuild its local database.',
          cause: lastError,
        );
      }
      return await _openWithRepair(fallback);
    } on DatabaseStartupException {
      rethrow;
    } catch (error) {
      lastError = error;
    }

    throw DatabaseStartupException(
      'OrgLedger could not open its local database.',
      cause: lastError,
    );
  }

  /// Ensures [directory] exists, then opens the file. A failed open is treated
  /// as corruption: the file and its sidecars are deleted and rebuilt once.
  Future<Database> _openWithRepair(Directory directory) async {
    final String path = p.join(directory.path, AppConstants.databaseName);
    try {
      await _ensureDirectory(directory);
      return await _openDatabaseAt(path);
    } catch (_) {
      try {
        await _closeQuietly();
        await _deleteDatabaseFiles(path);
        await _ensureDirectory(directory);
        return await _openDatabaseAt(path);
      } catch (retryError) {
        await _closeQuietly();
        await _deleteDatabaseFiles(path);
        throw DatabaseStartupException(
          'OrgLedger could not rebuild its local database.',
          cause: retryError,
        );
      }
    }
  }

  Future<void> _ensureDirectory(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  Future<Database> _openDatabaseAt(String path) async {
    final Database db = await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onConfigure: (Database db) async {
        // Foreign keys are disabled by default in SQLite.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database db, int version) async {
        await _createSchema(db);
        await _seedDemoData(db);
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        // Version 1 is the initial schema. Future migrations belong here and
        // must be additive so offline devices can upgrade without data loss.
        if (oldVersion < 1) {
          await _createSchema(db);
        }
      },
    );

    try {
      await _verifySchema(db);
      return db;
    } catch (_) {
      // Never leave a partially usable database open; the caller rebuilds it.
      try {
        await db.close();
      } catch (_) {
        // Ignore close failures; the file is deleted next.
      }
      rethrow;
    }
  }

  /// Detects the "version matches but schema is incomplete" failure mode left
  /// behind by an interrupted first run or an older build. Throwing here makes
  /// the open routine delete and recreate the file.
  Future<void> _verifySchema(Database db) async {
    final List<Map<String, Object?>> rows = await db.query(
      'sqlite_master',
      columns: <String>['name'],
      where: 'type = ? AND name IN (?, ?, ?, ?, ?)',
      whereArgs: <Object?>['table', ..._requiredTables],
    );
    final Set<String> found = rows
        .map((Map<String, Object?> row) => row['name']?.toString() ?? '')
        .toSet();
    final List<String> missing = _requiredTables
        .where((String table) => !found.contains(table))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw DatabaseStartupException(
        'The local ledger schema is incomplete (missing ${missing.join(', ')}).',
      );
    }

    // A valid schema with no accounts can never reach the login screen, so it
    // is treated as corrupt demo data and rebuilt.
    final int userCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_usersTable'),
        ) ??
        0;
    if (userCount == 0) {
      throw const DatabaseStartupException(
        'The local ledger contains no officer accounts.',
      );
    }
  }

  /// Removes the database and SQLite sidecar files, ignoring individual errors
  /// so the caller can still attempt a fresh open.
  Future<void> _deleteDatabaseFiles(String path) async {
    try {
      await deleteDatabase(path);
    } catch (_) {
      // Direct file removal below is the fallback.
    }
    for (final String suffix in const <String>['', '-wal', '-shm', '-journal']) {
      final File file = File('$path$suffix');
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Best effort; the next open attempt surfaces the real error.
      }
    }
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_usersTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL COLLATE NOCASE UNIQUE,
        password TEXT NOT NULL,
        role TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_eventsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        starting_budget REAL NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_expensesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        category TEXT NOT NULL,
        custom_category TEXT NOT NULL DEFAULT '',
        receipt_image_path TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'Pending',
        submitted_by INTEGER NOT NULL,
        remarks TEXT NOT NULL DEFAULT '',
        is_synced INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (event_id) REFERENCES $_eventsTable (id) ON DELETE CASCADE,
        FOREIGN KEY (submitted_by) REFERENCES $_usersTable (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_auditLogsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        performed_by TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    // Session and theme preferences are stored in SQLite so the app has no
    // additional dependency and works fully offline.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_settingsTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_event '
      'ON $_expensesTable(event_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_status '
      'ON $_expensesTable(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_submitted_by '
      'ON $_expensesTable(submitted_by)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_timestamp '
      'ON $_auditLogsTable(timestamp)',
    );
  }

  // ---------------------------------------------------------------------------
  // Demo seeding
  // ---------------------------------------------------------------------------

  Future<void> _seedDemoData(Database db) async {
    final String passwordDigest = PasswordHasher.hash(AppConstants.demoPassword);
    final Map<String, int> userIds = <String, int>{};

    Future<void> addUser(String name, String email, UserRole role) async {
      final int id = await db.insert(_usersTable, <String, Object?>{
        'name': name,
        'email': email,
        'password': passwordDigest,
        'role': role.storageValue,
      });
      userIds[role.storageValue] = id;
    }

    await addUser(
      'Bea Manalo',
      'bm@orgledger.app',
      UserRole.businessManager,
    );
    await addUser(
      'Sam Rivera',
      'secretary@orgledger.app',
      UserRole.secretary,
    );
    await addUser(
      'Tessa Cruz',
      'treasurer@orgledger.app',
      UserRole.treasurer,
    );
    await addUser(
      'Audie Reyes',
      'auditor@orgledger.app',
      UserRole.auditor,
    );
    await addUser(
      'Perry Santos',
      'president@orgledger.app',
      UserRole.president,
    );
    await addUser(
      'Ada Villanueva',
      'adviser@orgledger.app',
      UserRole.adviser,
    );

    final int bmId = userIds[UserRole.businessManager.storageValue] ?? 0;
    final int secretaryId = userIds[UserRole.secretary.storageValue] ?? 0;

    final int intramuralsId = await db.insert(_eventsTable, <String, Object?>{
      'title': 'Intramurals 2026',
      'starting_budget': 60000.0,
    });
    final int summitId = await db.insert(_eventsTable, <String, Object?>{
      'title': 'Leadership Summit 2026',
      'starting_budget': 25000.0,
    });

    final DateTime now = DateTime.now();

    Future<int> addExpense({
      required int eventId,
      required String title,
      required double amount,
      required String category,
      String customCategory = '',
      required String status,
      required int submittedBy,
      String remarks = '',
      int synced = 1,
      required int daysAgo,
      String receipt = '',
    }) async {
      final DateTime created = now.subtract(Duration(days: daysAgo));
      return db.insert(_expensesTable, <String, Object?>{
        'event_id': eventId,
        'title': title,
        'amount': amount,
        'category': category,
        'custom_category': customCategory,
        'receipt_image_path': receipt,
        'status': status,
        'submitted_by': submittedBy,
        'remarks': remarks,
        'is_synced': synced,
        'created_at': created.toIso8601String(),
        'updated_at': created.add(const Duration(hours: 6)).toIso8601String(),
      });
    }

    // Approved history: ₱52,000 of the ₱60,000 budget, i.e. ~86.7% used.
    await addExpense(
      eventId: intramuralsId,
      title: 'Catering balance for opening day',
      amount: 12500,
      category: AppCategories.food,
      status: ExpenseStatus.adviserApproved,
      submittedBy: bmId,
      daysAgo: 18,
    );
    await addExpense(
      eventId: intramuralsId,
      title: 'Function hall reservation',
      amount: 18000,
      category: AppCategories.venues,
      status: ExpenseStatus.adviserApproved,
      submittedBy: secretaryId,
      daysAgo: 15,
    );
    await addExpense(
      eventId: intramuralsId,
      title: 'Sports supplies and materials',
      amount: 9800,
      category: AppCategories.supplies,
      status: ExpenseStatus.adviserApproved,
      submittedBy: bmId,
      daysAgo: 11,
    );
    await addExpense(
      eventId: intramuralsId,
      title: 'Shuttle service for participants',
      amount: 7200,
      category: AppCategories.transport,
      status: ExpenseStatus.adviserApproved,
      submittedBy: secretaryId,
      daysAgo: 7,
    );
    await addExpense(
      eventId: intramuralsId,
      title: 'Tarpaulin and poster printing',
      amount: 4500,
      category: AppCategories.printing,
      status: ExpenseStatus.adviserApproved,
      submittedBy: bmId,
      daysAgo: 3,
    );

    // Live pipeline entries.
    final int pendingFoodId = await addExpense(
      eventId: intramuralsId,
      title: 'Snacks for student volunteers',
      amount: 2800,
      category: AppCategories.food,
      status: ExpenseStatus.pending,
      submittedBy: bmId,
      synced: 0,
      daysAgo: 1,
    );
    final int pendingOthersId = await addExpense(
      eventId: intramuralsId,
      title: 'Printing of participant ID laces',
      amount: 950,
      category: AppCategories.others,
      customCategory: 'ID Printing',
      status: ExpenseStatus.pending,
      submittedBy: secretaryId,
      daysAgo: 0,
    );
    final int verifiedId = await addExpense(
      eventId: intramuralsId,
      title: 'Sound system rental',
      amount: 6000,
      category: AppCategories.venues,
      status: ExpenseStatus.treasurerVerified,
      submittedBy: bmId,
      synced: 0,
      daysAgo: 2,
    );
    final int checkedId = await addExpense(
      eventId: intramuralsId,
      title: 'Medals and trophies',
      amount: 7500,
      category: AppCategories.prizes,
      status: ExpenseStatus.auditorChecked,
      submittedBy: secretaryId,
      daysAgo: 4,
    );
    final int endorsedId = await addExpense(
      eventId: intramuralsId,
      title: 'Emergency medical kits',
      amount: 3200,
      category: AppCategories.supplies,
      status: ExpenseStatus.presidentEndorsed,
      submittedBy: bmId,
      daysAgo: 5,
    );
    final int rejectedId = await addExpense(
      eventId: intramuralsId,
      title: 'Personal cloud storage renewal',
      amount: 1200,
      category: AppCategories.miscellaneous,
      status: ExpenseStatus.rejected,
      submittedBy: secretaryId,
      remarks:
          'Receipt is a personal subscription and not an organization expense.',
      daysAgo: 6,
    );
    final int flaggedId = await addExpense(
      eventId: intramuralsId,
      title: 'Emergency extension cords',
      amount: 2400,
      category: AppCategories.supplies,
      status: ExpenseStatus.flagged,
      submittedBy: bmId,
      remarks:
          'Amount on the receipt does not match the encoded amount. Please re-upload a clear official receipt.',
      synced: 0,
      daysAgo: 2,
    );

    // A second event proves the dashboard is scoped per event.
    await addExpense(
      eventId: summitId,
      title: 'Speaker honorarium',
      amount: 4000,
      category: AppCategories.miscellaneous,
      status: ExpenseStatus.adviserApproved,
      submittedBy: bmId,
      daysAgo: 9,
    );
    await addExpense(
      eventId: summitId,
      title: 'Workshop materials',
      amount: 2500,
      category: AppCategories.supplies,
      status: ExpenseStatus.pending,
      submittedBy: secretaryId,
      daysAgo: 1,
    );

    final String bmLabel = 'Bea Manalo · Business Manager';
    final String secretaryLabel = 'Sam Rivera · Secretary';
    final String treasurerLabel = 'Tessa Cruz · Treasurer';
    final String auditorLabel = 'Audie Reyes · Auditor';
    final String presidentLabel = 'Perry Santos · President';
    final String adviserLabel = 'Ada Villanueva · Adviser';

    Future<void> audit(
      String action,
      String actor,
      DateTime timestamp,
    ) async {
      await db.insert(_auditLogsTable, <String, Object?>{
        'action': action,
        'performed_by': actor,
        'timestamp': timestamp.toIso8601String(),
      });
    }

    // Build a realistic timeline for the seeded pipeline.
    Future<void> pipelineHistory({
      required int id,
      required String title,
      required int submittedBy,
      required String status,
      required DateTime submittedAt,
    }) async {
      final String submitter = submittedBy == bmId ? bmLabel : secretaryLabel;
      await audit(
        'Submitted "$title" for review',
        submitter,
        submittedAt,
      );
      if (status == ExpenseStatus.rejected) {
        await audit(
          'Rejected "$title": receipt is not an organization expense',
          treasurerLabel,
          submittedAt.add(const Duration(hours: 4)),
        );
        return;
      }
      if (status == ExpenseStatus.flagged) {
        await audit(
          'Flagged "$title" for receipt mismatch',
          auditorLabel,
          submittedAt.add(const Duration(hours: 5)),
        );
        return;
      }
      final int step = ExpenseStatus.step(status);
      if (step >= 2) {
        await audit(
          'Verified receipt and disbursement for "$title"',
          treasurerLabel,
          submittedAt.add(const Duration(hours: 6)),
        );
      }
      if (step >= 3) {
        await audit(
          'Checked arithmetic for "$title"',
          auditorLabel,
          submittedAt.add(const Duration(hours: 12)),
        );
      }
      if (step >= 4) {
        await audit(
          'Endorsed "$title" for final approval',
          presidentLabel,
          submittedAt.add(const Duration(hours: 18)),
        );
      }
      if (step >= 5) {
        await audit(
          'Approved and locked "$title"',
          adviserLabel,
          submittedAt.add(const Duration(days: 1)),
        );
      }
    }

    final Map<int, ({String title, int submittedBy, String status, int daysAgo})>
        pipeline = <int, ({String title, int submittedBy, String status, int daysAgo})>{
      pendingFoodId: (
        title: 'Snacks for student volunteers',
        submittedBy: bmId,
        status: ExpenseStatus.pending,
        daysAgo: 1,
      ),
      pendingOthersId: (
        title: 'Printing of participant ID laces',
        submittedBy: secretaryId,
        status: ExpenseStatus.pending,
        daysAgo: 0,
      ),
      verifiedId: (
        title: 'Sound system rental',
        submittedBy: bmId,
        status: ExpenseStatus.treasurerVerified,
        daysAgo: 2,
      ),
      checkedId: (
        title: 'Medals and trophies',
        submittedBy: secretaryId,
        status: ExpenseStatus.auditorChecked,
        daysAgo: 4,
      ),
      endorsedId: (
        title: 'Emergency medical kits',
        submittedBy: bmId,
        status: ExpenseStatus.presidentEndorsed,
        daysAgo: 5,
      ),
      rejectedId: (
        title: 'Personal cloud storage renewal',
        submittedBy: secretaryId,
        status: ExpenseStatus.rejected,
        daysAgo: 6,
      ),
      flaggedId: (
        title: 'Emergency extension cords',
        submittedBy: bmId,
        status: ExpenseStatus.flagged,
        daysAgo: 2,
      ),
    };

    for (final MapEntry<int, ({String title, int submittedBy, String status, int daysAgo})>
        entry in pipeline.entries) {
      final ({String title, int submittedBy, String status, int daysAgo}) data =
          entry.value;
      await pipelineHistory(
        id: entry.key,
        title: data.title,
        submittedBy: data.submittedBy,
        status: data.status,
        submittedAt: now.subtract(Duration(days: data.daysAgo)),
      );
    }

    // Full history for approved items so the audit screen is populated.
    for (final ({String title, int submittedBy, int daysAgo}) item
        in <({String title, int submittedBy, int daysAgo})>[
      (
        title: 'Catering balance for opening day',
        submittedBy: bmId,
        daysAgo: 18,
      ),
      (
        title: 'Function hall reservation',
        submittedBy: secretaryId,
        daysAgo: 15,
      ),
      (
        title: 'Sports supplies and materials',
        submittedBy: bmId,
        daysAgo: 11,
      ),
      (
        title: 'Shuttle service for participants',
        submittedBy: secretaryId,
        daysAgo: 7,
      ),
      (
        title: 'Tarpaulin and poster printing',
        submittedBy: bmId,
        daysAgo: 3,
      ),
    ]) {
      await pipelineHistory(
        id: 0,
        title: item.title,
        submittedBy: item.submittedBy,
        status: ExpenseStatus.adviserApproved,
        submittedAt: now.subtract(Duration(days: item.daysAgo)),
      );
    }

    await audit(
      'Initialized OrgLedger with demo accounts and sample liquidation data',
      'System',
      now.subtract(const Duration(minutes: 5)),
    );
  }

  // ---------------------------------------------------------------------------
  // Settings used for session persistence and theme preference.
  // ---------------------------------------------------------------------------

  Future<String?> getSetting(String key) async {
    try {
      final Database db = await database;
      final List<Map<String, Object?>> rows = await db.query(
        _settingsTable,
        columns: <String>['value'],
        where: 'key = ?',
        whereArgs: <Object?>[key],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return rows.first['value']?.toString();
    } on DatabaseException {
      return null;
    }
  }

  Future<void> setSetting(String key, String value) async {
    final Database db = await database;
    await db.insert(
      _settingsTable,
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeSetting(String key) async {
    final Database db = await database;
    await db.delete(_settingsTable, where: 'key = ?', whereArgs: <Object?>[key]);
  }

  /// Closes the active database. Mainly useful in tests.
  Future<void> close() async {
    _opening = null;
    await _closeQuietly();
  }

  /// Closes any open handle without throwing, so recovery can delete the file.
  Future<void> _closeQuietly() async {
    final Database? db = _db;
    _db = null;
    if (db != null && db.isOpen) {
      try {
        await db.close();
      } catch (_) {
        // A handle that cannot close cleanly is still unusable for recovery;
        // deletion below reports any remaining lock as a normal error.
      }
    }
  }
}
