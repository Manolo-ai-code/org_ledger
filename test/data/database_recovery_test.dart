import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:org_ledger/core/constants/app_constants.dart';
import 'package:org_ledger/data/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Startup resilience tests: directory creation, corruption recovery, schema
/// mismatch repair and the asynchronous "Try again" path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory databaseDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('org_ledger_startup_');
    databaseDirectory = Directory(p.join(root.path, 'nested', 'databases'));
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {
      // Windows can keep a handle briefly after close; the temp folder is
      // cleaned up by the OS if this fails.
    }
  });

  Future<DatabaseHelper> helperFor(Directory directory) async => DatabaseHelper(
        databaseDirectoryProvider: () async => directory,
      );

  int countValue(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return 0;
    }
    final Object? value = rows.first.values.first;
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<int> userCount(DatabaseHelper helper) async {
    final Database db = await helper.database;
    return countValue(
      await db.rawQuery('SELECT COUNT(*) FROM ${helper.usersTable}'),
    );
  }

  test('creates a missing database directory and seeds it', () async {
    final DatabaseHelper helper = await helperFor(databaseDirectory);
    addTearDown(helper.close);

    expect(await databaseDirectory.exists(), isFalse);
    expect(await userCount(helper), 6);
    expect(await databaseDirectory.exists(), isTrue);
    expect(
      await File(
        p.join(databaseDirectory.path, AppConstants.databaseName),
      ).exists(),
      isTrue,
    );
  });

  test('recovers from a corrupt database file', () async {
    await databaseDirectory.create(recursive: true);
    final File file = File(
      p.join(databaseDirectory.path, AppConstants.databaseName),
    );
    await file.writeAsBytes(
      List<int>.generate(1024, (int index) => index % 251),
      flush: true,
    );

    final DatabaseHelper helper = await helperFor(databaseDirectory);
    addTearDown(helper.close);

    expect(await userCount(helper), 6);
    // The rebuilt file is a real SQLite database, not the junk we wrote.
    expect(await file.length(), greaterThan(1024));
  });

  test('rebuilds a version-1 database with an incomplete schema', () async {
    await databaseDirectory.create(recursive: true);
    final String path = p.join(
      databaseDirectory.path,
      AppConstants.databaseName,
    );

    // Simulates an interrupted first run: the user_version is current but the
    // tables were never committed, so onCreate/onUpgrade do not run.
    final Database broken = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppConstants.databaseVersion,
        onCreate: (Database db, int version) async {},
      ),
    );
    await broken.close();

    final DatabaseHelper helper = await helperFor(databaseDirectory);
    addTearDown(helper.close);

    final Database db = await helper.database;
    final List<Map<String, Object?>> events = await db.query(
      helper.eventsTable,
    );
    expect(await userCount(helper), 6);
    expect(events, hasLength(2));
  });

  test('reopen retries after a transient directory resolution failure', () async {
    int attempts = 0;
    final DatabaseHelper helper = DatabaseHelper(
      databaseDirectoryProvider: () async {
        attempts++;
        if (attempts == 1) {
          throw const FileSystemException('Directory temporarily unavailable');
        }
        return databaseDirectory;
      },
    );
    addTearDown(helper.close);

    await expectLater(
      helper.database,
      throwsA(isA<DatabaseStartupException>()),
    );
    expect(attempts, 1);

    // The "Try again" action calls reopen(); the second resolution succeeds.
    final Database db = await helper.reopen();
    expect(attempts, 2);
    expect(
      countValue(
        await db.rawQuery('SELECT COUNT(*) FROM ${helper.usersTable}'),
      ),
      6,
    );
  });

  test('reopen rebuilds a database corrupted after a successful open', () async {
    final DatabaseHelper helper = await helperFor(databaseDirectory);
    addTearDown(helper.close);

    expect(await userCount(helper), 6);
    await helper.close();

    final File file = File(
      p.join(databaseDirectory.path, AppConstants.databaseName),
    );
    await file.writeAsBytes(
      List<int>.filled(512, 7),
      flush: true,
    );

    final Database db = await helper.reopen();
    expect(
      countValue(
        await db.rawQuery('SELECT COUNT(*) FROM ${helper.usersTable}'),
      ),
      6,
    );
    expect(await userCount(helper), 6);
  });
}
