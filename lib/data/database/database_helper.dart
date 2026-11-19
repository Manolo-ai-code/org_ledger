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
    bool? seedDemoData,
  })  : _db = database,
        _directoryProvider = databaseDirectoryProvider,
        _seedDemoDataOverride = seedDemoData;

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

  /// Required columns in `users` (v2 schema). Used to detect stale v1 files.
  static const List<String> _requiredUserColumns = <String>[
    'id',
    'username',
    'name',
    'email',
    'password',
    'role',
    'is_active',
    'deactivated_at',
    'term',
    'must_change_password',
  ];

  /// Required columns in `events` (v3 schema). Older DBs are migrated additively.
  static const List<String> _requiredEventColumns = <String>[
    'id',
    'title',
    'starting_budget',
    'event_type',
    'school_year',
    'is_archived',
    'created_at',
    'updated_at',
  ];

  /// Optional directory override used by tests and previews.
  final Future<Directory> Function()? _directoryProvider;

  /// When non-null, overrides [AppConstants.demoSeed] (useful for tests).
  final bool? _seedDemoDataOverride;

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
        await _ensureBootstrapData(db);
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        // Migrations must be additive so offline devices keep their data.
        if (oldVersion < 1) {
          await _createSchema(db);
          await _ensureBootstrapData(db);
          return;
        }
        if (oldVersion < 2) {
          await _migrateV1ToV2(db);
        }
        if (oldVersion < 3) {
          await _migrateV2ToV3(db);
        }
      },
      onOpen: (Database db) async {
        // Ensure a usable state even after a partial/legacy open.
        await _ensureBootstrapData(db);
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

  /// Detects incomplete or unusable schemas. Throwing here makes the open
  /// routine delete and recreate the file.
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

    final Set<String> userColumns = await _columnNames(db, _usersTable);
    final List<String> missingColumns = _requiredUserColumns
        .where((String column) => !userColumns.contains(column))
        .toList(growable: false);
    if (missingColumns.isNotEmpty) {
      throw DatabaseStartupException(
        'The users table is missing columns (${missingColumns.join(', ')}).',
      );
    }

    final Set<String> eventColumns = await _columnNames(db, _eventsTable);
    final List<String> missingEventColumns = _requiredEventColumns
        .where((String column) => !eventColumns.contains(column))
        .toList(growable: false);
    if (missingEventColumns.isNotEmpty) {
      throw DatabaseStartupException(
        'The events table is missing columns (${missingEventColumns.join(', ')}).',
      );
    }

    // A ledger with no accounts cannot be used. When demo seeding is enabled
    // this is treated as corrupt and rebuilt; when disabled it means the
    // first-run bootstrap path must run.
    final int userCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_usersTable'),
        ) ??
        0;
    final bool demo = _seedDemoDataOverride ?? AppConstants.demoSeed;
    if (userCount == 0 && !demo) {
      // No seeded data expected; first-run bootstrap is allowed.
      return;
    }
    if (userCount == 0) {
      throw const DatabaseStartupException(
        'The local ledger contains no accounts.',
      );
    }
  }

  Future<Set<String>> _columnNames(Database db, String table) async {
    final List<Map<String, Object?>> rows =
        await db.rawQuery('PRAGMA table_info($table)');
    return rows
        .map((Map<String, Object?> row) => row['name']?.toString() ?? '')
        .where((String name) => name.isNotEmpty)
        .toSet();
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

  // ---------------------------------------------------------------------------
  // Schema
  // ---------------------------------------------------------------------------

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_usersTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL COLLATE NOCASE UNIQUE,
        name TEXT NOT NULL,
        email TEXT COLLATE NOCASE UNIQUE,
        password TEXT NOT NULL,
        role TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        deactivated_at TEXT,
        term TEXT NOT NULL DEFAULT '',
        must_change_password INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_eventsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        starting_budget REAL NOT NULL DEFAULT 0,
        event_type TEXT NOT NULL DEFAULT 'General',
        school_year TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_users_username '
      'ON $_usersTable(username COLLATE NOCASE)',
    );
  }

  /// Additive v1 -> v2 migration: username, optional email, active/term flags.
  /// Existing rows, relations and passwords are preserved.
  Future<void> _migrateV1ToV2(Database db) async {
    final Set<String> columns = await _columnNames(db, _usersTable);

    Future<void> addColumn(String column, String definition) async {
      if (!columns.contains(column)) {
        await db.execute(
          'ALTER TABLE $_usersTable ADD COLUMN $column $definition',
        );
        columns.add(column);
      }
    }

    await addColumn('username', 'TEXT');
    // email was NOT NULL in v1; SQLite cannot drop NOT NULL in-place, but
    // existing non-null values remain valid and new inserts may be null.
    // We allow nulls at the application level; the column definition stays as-is
    // for existing databases but we no longer require a value.
    await addColumn('is_active', 'INTEGER NOT NULL DEFAULT 1');
    await addColumn('deactivated_at', 'TEXT');
    await addColumn('term', "TEXT NOT NULL DEFAULT ''");
    await addColumn('must_change_password', 'INTEGER NOT NULL DEFAULT 0');

    await _backfillUsernames(db);

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_unique '
      'ON $_usersTable(username COLLATE NOCASE) '
      "WHERE username IS NOT NULL AND TRIM(username) <> ''",
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_users_username '
      'ON $_usersTable(username COLLATE NOCASE)',
    );
  }

  /// Additive v2 -> v3 migration: budget event metadata and archiving.
  Future<void> _migrateV2ToV3(Database db) async {
    final Set<String> columns = await _columnNames(db, _eventsTable);

    Future<void> addColumn(String column, String definition) async {
      if (!columns.contains(column)) {
        await db.execute(
          'ALTER TABLE $_eventsTable ADD COLUMN $column $definition',
        );
        columns.add(column);
      }
    }

    await addColumn('event_type', "TEXT NOT NULL DEFAULT 'General'");
    await addColumn('school_year', "TEXT NOT NULL DEFAULT ''");
    await addColumn('is_archived', 'INTEGER NOT NULL DEFAULT 0');
    await addColumn('created_at', 'TEXT');
    await addColumn('updated_at', 'TEXT');

    final String now = DateTime.now().toIso8601String();
    await db.rawUpdate(
      'UPDATE $_eventsTable '
      "SET event_type = CASE WHEN event_type IS NULL OR TRIM(event_type) = '' "
      "THEN 'General' ELSE event_type END, "
      "school_year = COALESCE(school_year, ''), "
      'is_archived = COALESCE(is_archived, 0), '
      'created_at = COALESCE(created_at, ?), '
      'updated_at = COALESCE(updated_at, COALESCE(created_at, ?))',
      <Object?>[now, now],
    );
  }

  Future<void> _backfillUsernames(Database db) async {
    final List<Map<String, Object?>> rows = await db.query(
      _usersTable,
      columns: <String>['id', 'username', 'email', 'name'],
      orderBy: 'id ASC',
    );
    final Set<String> used = <String>{};

    for (final Map<String, Object?> row in rows) {
      final int id = (row['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) {
        continue;
      }
      final String existing = row['username']?.toString().trim() ?? '';
      if (existing.isNotEmpty) {
        final String normalized = _normalizeUsername(existing);
        final String uniqueExisting = _dedupeUsername(normalized, used, id);
        if (uniqueExisting != normalized ||
            uniqueExisting != existing ||
            !used.contains(uniqueExisting)) {
          await db.update(
            _usersTable,
            <String, Object?>{'username': uniqueExisting},
            where: 'id = ?',
            whereArgs: <Object?>[id],
          );
        }
        used.add(uniqueExisting);
        continue;
      }

      String base = _usernameBase(
        email: row['email']?.toString(),
        name: row['name']?.toString(),
        id: id,
      );
      base = _normalizeUsername(base);
      if (base.isEmpty) {
        base = 'user$id';
      }
      final String username = _dedupeUsername(base, used, id);
      used.add(username);
      await db.update(
        _usersTable,
        <String, Object?>{'username': username},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    }
  }

  String _usernameBase({String? email, String? name, required int id}) {
    final String emailRaw = (email ?? '').trim();
    if (emailRaw.contains('@')) {
      final String local = emailRaw.split('@').first;
      final String cleaned = local.toLowerCase().replaceAll(
            RegExp(r'[^a-z0-9._-]'),
            '',
          );
      if (cleaned.isNotEmpty) {
        return cleaned;
      }
    }
    final String nameClean = (name ?? '').trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '',
        );
    if (nameClean.length >= 3) {
      return nameClean.length > 20 ? nameClean.substring(0, 20) : nameClean;
    }
    return 'user$id';
  }

  String _normalizeUsername(String value) {
    String normalized = value.trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9._-]'),
          '',
        );
    normalized = normalized.replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
    if (normalized.length < 3) {
      normalized = normalized.padRight(3, '0');
    }
    if (normalized.length > 30) {
      normalized = normalized.substring(0, 30);
    }
    return normalized;
  }

  String _dedupeUsername(String base, Set<String> used, int id) {
    String candidate = base;
    if (!used.contains(candidate)) {
      return candidate;
    }
    candidate = _trimToLength('$base$id', 30);
    if (!used.contains(candidate)) {
      return candidate;
    }
    int suffix = 2;
    while (true) {
      final String withSuffix = _trimToLength('$base$suffix', 30);
      if (!used.contains(withSuffix)) {
        return withSuffix;
      }
      suffix++;
    }
  }

  String _trimToLength(String value, int max) {
    if (value.length <= max) {
      return value;
    }
    return value.substring(0, max);
  }

  // ---------------------------------------------------------------------------
  // Bootstrap data (demo-only) / first-run readiness
  // ---------------------------------------------------------------------------

  Future<void> _ensureBootstrapData(Database db) async {
    final int userCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_usersTable'),
        ) ??
        0;
    final bool demo = _seedDemoDataOverride ?? AppConstants.demoSeed;

    if (demo) {
      if (userCount == 0) {
        await _seedDemoData(db);
      }
      return;
    }

    // Production/default mode: start clean. A safe first-run bootstrap
    // (creating the initial Adviser/manager) is handled by the app UI when
    // no users exist. Keep the database schema ready with no accounts/events.
  }

  /// Whether the ledger has no user accounts yet (first-run state).
  Future<bool> isFirstRun() async {
    final Database db = await database;
    final int count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_usersTable'),
        ) ??
        0;
    return count == 0;
  }

  // ---------------------------------------------------------------------------
  // Demo seeding (enabled only when DEMO_SEED=true)
  // ---------------------------------------------------------------------------

  Future<void> _seedDemoData(Database db) async {
    final String passwordDigest = PasswordHasher.hash(AppConstants.demoPassword);
    final Map<String, int> userIds = <String, int>{};

    Future<void> addUser(
      String name,
      String username,
      String email,
      UserRole role,
    ) async {
      final int id = await db.insert(_usersTable, <String, Object?>{
        'username': username,
        'name': name,
        'email': email,
        'password': passwordDigest,
        'role': role.storageValue,
        'is_active': 1,
        'term': '',
        'must_change_password': 0,
      });
      userIds[role.storageValue] = id;
    }

    await addUser('Bea Manalo', 'bm', 'bm@orgledger.app', UserRole.businessManager);
    await addUser('Sam Rivera', 'secretary', 'secretary@orgledger.app', UserRole.secretary);
    await addUser('Tessa Cruz', 'treasurer', 'treasurer@orgledger.app', UserRole.treasurer);
    await addUser('Audie Reyes', 'auditor', 'auditor@orgledger.app', UserRole.auditor);
    await addUser('Perry Santos', 'president', 'president@orgledger.app', UserRole.president);
    await addUser('Ada Villanueva', 'adviser', 'adviser@orgledger.app', UserRole.adviser);

    final int bmId = userIds[UserRole.businessManager.storageValue] ?? 0;
    final int secretaryId = userIds[UserRole.secretary.storageValue] ?? 0;

    final String seedNow = DateTime.now().toIso8601String();
    final int intramuralsId = await db.insert(_eventsTable, <String, Object?>{
      'title': 'Intramurals 2026',
      'starting_budget': 60000.0,
      'event_type': 'School Year',
      'school_year': 'SY 2025-2026',
      'is_archived': 0,
      'created_at': seedNow,
      'updated_at': seedNow,
    });
    final int summitId = await db.insert(_eventsTable, <String, Object?>{
      'title': 'Leadership Summit 2026',
      'starting_budget': 25000.0,
      'event_type': 'Project',
      'school_year': 'SY 2025-2026',
      'is_archived': 0,
      'created_at': seedNow,
      'updated_at': seedNow,
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
    await addExpense(eventId: intramuralsId, title: 'Catering balance for opening day', amount: 12500, category: AppCategories.food, status: ExpenseStatus.adviserApproved, submittedBy: bmId, daysAgo: 18);
    await addExpense(eventId: intramuralsId, title: 'Function hall reservation', amount: 18000, category: AppCategories.venues, status: ExpenseStatus.adviserApproved, submittedBy: secretaryId, daysAgo: 15);
    await addExpense(eventId: intramuralsId, title: 'Sports supplies and materials', amount: 9800, category: AppCategories.supplies, status: ExpenseStatus.adviserApproved, submittedBy: bmId, daysAgo: 11);
    await addExpense(eventId: intramuralsId, title: 'Shuttle service for participants', amount: 7200, category: AppCategories.transport, status: ExpenseStatus.adviserApproved, submittedBy: secretaryId, daysAgo: 7);
    await addExpense(eventId: intramuralsId, title: 'Tarpaulin and poster printing', amount: 4500, category: AppCategories.printing, status: ExpenseStatus.adviserApproved, submittedBy: bmId, daysAgo: 3);

    // Live pipeline entries.
    await addExpense(eventId: intramuralsId, title: 'Snacks for student volunteers', amount: 2800, category: AppCategories.food, status: ExpenseStatus.pending, submittedBy: bmId, synced: 0, daysAgo: 1);
    await addExpense(eventId: intramuralsId, title: 'Printing of participant ID laces', amount: 950, category: AppCategories.others, customCategory: 'ID Printing', status: ExpenseStatus.pending, submittedBy: secretaryId, daysAgo: 0);
    await addExpense(eventId: intramuralsId, title: 'Sound system rental', amount: 6000, category: AppCategories.venues, status: ExpenseStatus.treasurerVerified, submittedBy: bmId, synced: 0, daysAgo: 2);
    await addExpense(eventId: intramuralsId, title: 'Medals and trophies', amount: 7500, category: AppCategories.prizes, status: ExpenseStatus.auditorChecked, submittedBy: secretaryId, daysAgo: 4);
    await addExpense(eventId: intramuralsId, title: 'Emergency medical kits', amount: 3200, category: AppCategories.supplies, status: ExpenseStatus.presidentEndorsed, submittedBy: bmId, daysAgo: 5);
    await addExpense(eventId: intramuralsId, title: 'Personal cloud storage renewal', amount: 1200, category: AppCategories.miscellaneous, status: ExpenseStatus.rejected, submittedBy: secretaryId, remarks: 'Receipt is a personal subscription and not an organization expense.', daysAgo: 6);
    await addExpense(eventId: intramuralsId, title: 'Emergency extension cords', amount: 2400, category: AppCategories.supplies, status: ExpenseStatus.flagged, submittedBy: bmId, remarks: 'Amount on the receipt does not match the encoded amount. Please re-upload a clear official receipt.', synced: 0, daysAgo: 2);

    // A second event proves the dashboard is scoped per event.
    await addExpense(eventId: summitId, title: 'Speaker honorarium', amount: 4000, category: AppCategories.miscellaneous, status: ExpenseStatus.adviserApproved, submittedBy: bmId, daysAgo: 9);
    await addExpense(eventId: summitId, title: 'Workshop materials', amount: 2500, category: AppCategories.supplies, status: ExpenseStatus.pending, submittedBy: secretaryId, daysAgo: 1);

    const String bmLabel = 'Bea Manalo · Business Manager';
    const String secretaryLabel = 'Sam Rivera · Secretary';
    const String treasurerLabel = 'Tessa Cruz · Treasurer';
    const String auditorLabel = 'Audie Reyes · Auditor';
    const String presidentLabel = 'Perry Santos · President';
    const String adviserLabel = 'Ada Villanueva · Adviser';

    Future<void> audit(String action, String actor, DateTime timestamp) async {
      await db.insert(_auditLogsTable, <String, Object?>{
        'action': action,
        'performed_by': actor,
        'timestamp': timestamp.toIso8601String(),
      });
    }

    Future<void> pipelineHistory({
      required String title,
      required int submittedBy,
      required String status,
      required DateTime submittedAt,
    }) async {
      final String submitter = submittedBy == bmId ? bmLabel : secretaryLabel;
      await audit('Submitted "$title" for review', submitter, submittedAt);
      if (status == ExpenseStatus.rejected) {
        await audit('Rejected "$title": receipt is not an organization expense', treasurerLabel, submittedAt.add(const Duration(hours: 4)));
        return;
      }
      if (status == ExpenseStatus.flagged) {
        await audit('Flagged "$title" for receipt mismatch', auditorLabel, submittedAt.add(const Duration(hours: 5)));
        return;
      }
      final int step = ExpenseStatus.step(status);
      if (step >= 2) {
        await audit('Verified receipt and disbursement for "$title"', treasurerLabel, submittedAt.add(const Duration(hours: 6)));
      }
      if (step >= 3) {
        await audit('Checked arithmetic for "$title"', auditorLabel, submittedAt.add(const Duration(hours: 12)));
      }
      if (step >= 4) {
        await audit('Endorsed "$title" for final approval', presidentLabel, submittedAt.add(const Duration(hours: 18)));
      }
      if (step >= 5) {
        await audit('Approved and locked "$title"', adviserLabel, submittedAt.add(const Duration(days: 1)));
      }
    }

    final List<({String title, int submittedBy, String status, int daysAgo})> pipeline =
        <({String title, int submittedBy, String status, int daysAgo})>[
      (title: 'Snacks for student volunteers', submittedBy: bmId, status: ExpenseStatus.pending, daysAgo: 1),
      (title: 'Printing of participant ID laces', submittedBy: secretaryId, status: ExpenseStatus.pending, daysAgo: 0),
      (title: 'Sound system rental', submittedBy: bmId, status: ExpenseStatus.treasurerVerified, daysAgo: 2),
      (title: 'Medals and trophies', submittedBy: secretaryId, status: ExpenseStatus.auditorChecked, daysAgo: 4),
      (title: 'Emergency medical kits', submittedBy: bmId, status: ExpenseStatus.presidentEndorsed, daysAgo: 5),
      (title: 'Personal cloud storage renewal', submittedBy: secretaryId, status: ExpenseStatus.rejected, daysAgo: 6),
      (title: 'Emergency extension cords', submittedBy: bmId, status: ExpenseStatus.flagged, daysAgo: 2),
    ];
    for (final ({String title, int submittedBy, String status, int daysAgo}) data in pipeline) {
      await pipelineHistory(title: data.title, submittedBy: data.submittedBy, status: data.status, submittedAt: now.subtract(Duration(days: data.daysAgo)));
    }

    for (final ({String title, int submittedBy, int daysAgo}) item in <({String title, int submittedBy, int daysAgo})>[
      (title: 'Catering balance for opening day', submittedBy: bmId, daysAgo: 18),
      (title: 'Function hall reservation', submittedBy: secretaryId, daysAgo: 15),
      (title: 'Sports supplies and materials', submittedBy: bmId, daysAgo: 11),
      (title: 'Shuttle service for participants', submittedBy: secretaryId, daysAgo: 7),
      (title: 'Tarpaulin and poster printing', submittedBy: bmId, daysAgo: 3),
    ]) {
      await pipelineHistory(title: item.title, submittedBy: item.submittedBy, status: ExpenseStatus.adviserApproved, submittedAt: now.subtract(Duration(days: item.daysAgo)));
    }

    await audit('Initialized OrgLedger with demo accounts and sample liquidation data', 'System', now.subtract(const Duration(minutes: 5)));
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
