import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:org_ledger/core/constants/app_categories.dart';
import 'package:org_ledger/core/constants/app_constants.dart';
import 'package:org_ledger/core/constants/expense_status.dart';
import 'package:org_ledger/core/utils/password_hasher.dart';
import 'package:org_ledger/data/database/database_helper.dart';
import 'package:org_ledger/data/models/app_user.dart';
import 'package:org_ledger/data/models/audit_log.dart';
import 'package:org_ledger/data/models/expense.dart';
import 'package:org_ledger/data/models/org_event.dart';
import 'package:org_ledger/data/models/user_role.dart';
import 'package:org_ledger/data/repositories/audit_repository.dart';
import 'package:org_ledger/data/repositories/auth_repository.dart';
import 'package:org_ledger/data/repositories/expense_repository.dart';
import 'package:org_ledger/data/services/connectivity_service.dart';
import 'package:org_ledger/data/services/liquidation_pdf_service.dart';
import 'package:org_ledger/data/services/sync_service.dart';
import 'package:org_ledger/providers/ledger_provider.dart';
import 'package:org_ledger/providers/user_role_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Integration tests for the SQLite schema, seeder and repositories.
///
/// These run on the Dart VM using `sqflite_common_ffi`, so the real schema,
/// seed data, password hashing and joins are exercised without a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory databaseDirectory;
  late DatabaseHelper db;
  late AuthRepository auth;
  late ExpenseRepository expenses;
  late AuditRepository audit;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('org_ledger_db_test_');
    databaseDirectory = Directory(p.join(tempRoot.path, 'databases'));
    await databaseDirectory.create(recursive: true);
    db = DatabaseHelper(
      seedDemoData: true,
      databaseDirectoryProvider: () async => databaseDirectory,
    );
    auth = AuthRepository(db);
    expenses = ExpenseRepository(db);
    audit = AuditRepository(db);
  });

  tearDown(() async {
    await db.close();
    try {
      await tempRoot.delete(recursive: true);
    } catch (_) {
      // A locked file on Windows is harmless; each test uses a fresh temp dir.
    }
  });

  test('seeds six officers, two events and approved spending', () async {
    final List<AppUser> users = await auth.getUsers();
    expect(users, hasLength(6));
    expect(
      users.map((AppUser user) => user.role).toSet(),
      UserRole.values.where((UserRole r) => r.isOfficer).toSet(),
    );
    expect(
      users.every((AppUser user) => user.username.isNotEmpty && user.isActive),
      isTrue,
    );
    // Plain text is never persisted, even for seeded demo accounts.
    expect(
      users.every(
        (AppUser user) =>
            user.password ==
            PasswordHasher.hash(AppConstants.demoPassword),
      ),
      isTrue,
    );
    expect(
      users.any((AppUser user) => user.password == AppConstants.demoPassword),
      isFalse,
    );

    final List<OrgEvent> events = await expenses.getEvents();
    expect(events, hasLength(2));
    final OrgEvent intramurals = events.firstWhere(
      (OrgEvent event) => event.title == 'Intramurals 2026',
    );
    expect(intramurals.startingBudget, 60000);

    final List<Expense> approved = await expenses.getApprovedExpenses(
      intramurals.id,
    );
    expect(approved, isNotEmpty);
    final double spent = approved.fold<double>(
      0,
      (double sum, Expense expense) => sum + expense.amount,
    );
    expect(spent, 52000);
    expect(approved.every((Expense e) => e.submittedByName.isNotEmpty), isTrue);
    expect(
      approved.every((Expense e) => e.eventTitle == 'Intramurals 2026'),
      isTrue,
    );

    // Every workflow state is represented in the demo data.
    final List<Expense> all = await expenses.getExpenses();
    expect(
      all.map((Expense expense) => expense.status).toSet(),
      containsAll(<String>[
        ExpenseStatus.pending,
        ExpenseStatus.treasurerVerified,
        ExpenseStatus.auditorChecked,
        ExpenseStatus.presidentEndorsed,
        ExpenseStatus.adviserApproved,
        ExpenseStatus.rejected,
        ExpenseStatus.flagged,
      ]),
    );
    expect(
      all.where((Expense expense) => !expense.isSynced).length,
      greaterThanOrEqualTo(3),
    );
  });

  test('authenticates seeded roles and rejects bad credentials', () async {
    final AppUser adviser = await auth.authenticate(
      identifier: 'adviser',
      password: AppConstants.demoPassword,
    );
    expect(adviser.role, UserRole.adviser);
    expect(adviser.name, 'Ada Villanueva');
    expect(adviser.isActive, isTrue);

    // Email login remains supported for backward compatibility.
    final AppUser byEmail = await auth.authenticate(
      identifier: 'ADVISER@orgledger.app',
      password: AppConstants.demoPassword,
    );
    expect(byEmail.id, adviser.id);

    await expectLater(
      auth.authenticate(identifier: 'adviser', password: 'nope'),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      auth.authenticate(
        identifier: 'ghost',
        password: AppConstants.demoPassword,
      ),
      throwsA(isA<AuthException>()),
    );
  });

  test('registration hashes passwords and refuses duplicates', () async {
    final AppUser created = await auth.register(
      name: 'Nina Flores',
      username: 'nina',
      email: 'Nina@OrgLedger.app',
      password: 'supersecret1',
    );

    expect(created.id, greaterThan(0));
    expect(created.username, 'nina');
    expect(created.email, 'nina@orgledger.app');
    expect(created.role, UserRole.member);
    expect(created.isActive, isTrue);
    expect(created.password, isNot('supersecret1'));
    expect(created.password, PasswordHasher.hash('supersecret1'));

    final AppUser signedIn = await auth.authenticate(
      identifier: 'nina',
      password: 'supersecret1',
    );
    expect(signedIn.name, 'Nina Flores');
    expect(signedIn.role, UserRole.member);

    await expectLater(
      auth.register(
        name: 'Duplicate Account',
        username: 'nina',
        email: 'other@orgledger.app',
        password: 'supersecret1',
      ),
      throwsA(isA<AuthException>()),
    );
  });

  test('stores expenses and advances their workflow status', () async {
    final OrgEvent event = (await expenses.getEvents()).first;
    final AppUser submitter = await auth.authenticate(
      identifier: 'bm',
      password: AppConstants.demoPassword,
    );

    final DateTime now = DateTime.now();
    final Expense draft = Expense(
      id: 0,
      eventId: event.id,
      title: 'Test banner printing',
      amount: 750.5,
      category: AppCategories.printing,
      customCategory: '',
      receiptImagePath: '',
      status: ExpenseStatus.pending,
      submittedBy: submitter.id,
      remarks: '',
      isSynced: false,
      createdAt: now,
      updatedAt: now,
    );

    final int id = await expenses.insertExpense(draft);
    expect(id, greaterThan(0));

    final Expense? stored = await expenses.getExpense(id);
    expect(stored, isNotNull);
    expect(stored!.amount, 750.5);
    expect(stored.status, ExpenseStatus.pending);
    expect(stored.submittedByName, submitter.name);
    expect(stored.eventTitle, event.title);

    final int pendingBefore = await expenses.pendingSyncCount();
    expect(pendingBefore, greaterThanOrEqualTo(1));

    await expenses.updateStatus(
      expenseId: id,
      status: ExpenseStatus.treasurerVerified,
      remarks: 'Receipt checked',
      isSynced: true,
    );

    final Expense? updated = await expenses.getExpense(id);
    expect(updated!.status, ExpenseStatus.treasurerVerified);
    expect(updated.remarks, 'Receipt checked');
    expect(updated.isSynced, isTrue);
    expect(await expenses.pendingSyncCount(), pendingBefore - 1);

    // Invalid ids are handled without throwing.
    expect(await expenses.getExpense(0), isNull);
    expect(await expenses.getExpense(999999), isNull);
  });

  test('persists session and theme settings', () async {
    expect(await db.getSetting('session_user_id'), isNull);

    await db.setSetting('session_user_id', '3');
    await db.setSetting('theme_mode', 'dark');
    expect(await db.getSetting('session_user_id'), '3');
    expect(await db.getSetting('theme_mode'), 'dark');

    await db.removeSetting('session_user_id');
    expect(await db.getSetting('session_user_id'), isNull);
    expect(await db.getSetting('theme_mode'), 'dark');
  });

  test('writes expense-only audit entries newest first', () async {
    final OrgEvent event = (await expenses.getEvents()).first;
    final Expense expense = (await expenses.getExpenses(eventId: event.id)).first;

    await audit.logExpenseAction(
      expense: expense,
      action: 'Approved expense and advanced workflow',
      performedBy: 'Tessa Cruz · Treasurer',
      status: ExpenseStatus.treasurerVerified,
    );
    await audit.logExpenseAction(
      expense: expense,
      action: 'Flagged expense',
      performedBy: 'Audie Reyes · Auditor',
      status: ExpenseStatus.flagged,
      remarks: 'Receipt amount does not match the encoded amount.',
    );

    final List<AuditLog> logs = await audit.getRecent(limit: 2);
    expect(logs, hasLength(2));
    expect(logs.first.action, 'Flagged expense');
    expect(logs.first.expenseId, expense.id);
    expect(logs.first.expenseTitle, expense.title);
    expect(logs.first.status, ExpenseStatus.flagged);
    expect(logs.first.performedBy, 'Audie Reyes · Auditor');
    expect(
      logs.first.remarks,
      'Receipt amount does not match the encoded amount.',
    );
    expect(await audit.count(), greaterThanOrEqualTo(2));
  });

  test('production first-run bootstrap creates initial adviser and default event',
      () async {
    await db.close();
    try {
      await tempRoot.delete(recursive: true);
    } catch (_) {
      // Best effort cleanup before switching to a fresh production-mode DB.
    }
    tempRoot = await Directory.systemTemp.createTemp('org_ledger_db_test_');
    databaseDirectory = Directory(p.join(tempRoot.path, 'databases'));
    await databaseDirectory.create(recursive: true);

    final DatabaseHelper prodDb = DatabaseHelper(
      seedDemoData: false,
      databaseDirectoryProvider: () async => databaseDirectory,
    );
    addTearDown(() async {
      await prodDb.close();
    });

    expect(await prodDb.isFirstRun(), isTrue);

    final AuthRepository prodAuth = AuthRepository(prodDb);
    final UserRoleProvider session = UserRoleProvider(
      authRepository: prodAuth,
      databaseHelper: prodDb,
    );
    addTearDown(session.dispose);

    await session.restoreSession();
    expect(session.needsBootstrap, isTrue);
    expect(session.isAuthenticated, isFalse);

    final AuthResult result = await session.bootstrapInitialAdviser(
      name: 'Ada Villanueva',
      username: 'adviser',
      email: 'adviser@orgledger.app',
      password: 'supersecret1',
    );
    expect(result.success, isTrue, reason: result.message);
    expect(session.isAuthenticated, isTrue);
    expect(session.needsBootstrap, isFalse);
    expect(session.currentUser?.role, UserRole.adviser);
    expect(session.currentUser?.username, 'adviser');
    expect(session.currentUser?.isActive, isTrue);

    final List<OrgEvent> events = await ExpenseRepository(prodDb).getEvents();
    expect(events, hasLength(1));
    expect(events.single.title, 'Organization Fund');

    expect(await prodDb.isFirstRun(), isFalse);

    final AuthResult second = await session.bootstrapInitialAdviser(
      name: 'Another Adviser',
      username: 'another',
      password: 'supersecret1',
    );
    expect(second.success, isFalse);
    expect(second.message, contains('already complete'));

    final Database raw = await prodDb.database;
    final List<Map<String, Object?>> sessionRows = await raw.query(
      'app_settings',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>['session_user_id'],
      limit: 1,
    );
    final String? storedSession =
        sessionRows.isEmpty ? null : sessionRows.single['value']?.toString();
    expect(storedSession, session.currentUser?.id.toString());
  });

  test('restoreSession rethrows database startup failures for bootstrap retry',
      () async {
    final DatabaseHelper brokenDb = DatabaseHelper(
      seedDemoData: false,
      databaseDirectoryProvider: () async {
        throw const FileSystemException('No storage available');
      },
    );
    addTearDown(brokenDb.close);

    final UserRoleProvider session = UserRoleProvider(
      authRepository: AuthRepository(brokenDb),
      databaseHelper: brokenDb,
    );
    addTearDown(session.dispose);

    await expectLater(
      session.restoreSession(),
      throwsA(isA<DatabaseStartupException>()),
    );
    expect(session.isRestoring, isFalse);
  });

  test('provider scopes queues and advances the full approval chain', () async {
    final ConnectivityService connectivity = ConnectivityService();
    final LedgerProvider ledger = LedgerProvider(
      expenseRepository: expenses,
      auditRepository: audit,
      syncService: SyncService(
        expenseRepository: expenses,
        auditRepository: audit,
        connectivityService: connectivity,
      ),
      connectivityService: connectivity,
      pdfService: const LiquidationPdfService(),
    );
    addTearDown(ledger.dispose);

    await ledger.initialize();
    expect(ledger.isInitialized, isTrue);
    expect(ledger.error, isNull);
    expect(ledger.events, hasLength(2));
    expect(ledger.selectedEvent?.title, 'Intramurals 2026');
    expect(ledger.expenses, hasLength(12));
    expect(ledger.pendingOnlyCount, 2);
    expect(ledger.flaggedCount, 1);
    expect(ledger.rejectedCount, 1);
    expect(ledger.totalBudget, 60000);
    expect(ledger.totalSpent, 52000);

    // Each reviewer queue contains only its own tier.
    final List<Expense> treasurerQueue = ledger.expensesForRole(
      UserRole.treasurer,
    );
    expect(treasurerQueue, hasLength(2));
    expect(
      treasurerQueue.every(
        (Expense expense) => expense.status == ExpenseStatus.pending,
      ),
      isTrue,
    );
    expect(ledger.awaitingMyReviewCount(UserRole.treasurer), 2);
    expect(
      ledger
          .expensesForRole(UserRole.auditor)
          .every(
            (Expense expense) =>
                expense.status == ExpenseStatus.treasurerVerified,
          ),
      isTrue,
    );

    final int targetId = treasurerQueue.first.id;
    Expense current() =>
        ledger.expenses.firstWhere((Expense expense) => expense.id == targetId);

    final List<(UserRole, String)> chain = <(UserRole, String)>[
      (UserRole.treasurer, ExpenseStatus.treasurerVerified),
      (UserRole.auditor, ExpenseStatus.auditorChecked),
      (UserRole.president, ExpenseStatus.presidentEndorsed),
      (UserRole.adviser, ExpenseStatus.adviserApproved),
    ];

    final double spendBefore = ledger.totalSpent;
    for (final (UserRole role, String expected) in chain) {
      final LedgerActionResult result = await ledger.reviewExpense(
        expense: current(),
        role: role,
        actorName: 'Test Reviewer',
        action: ReviewAction.approve,
      );
      expect(result.success, isTrue, reason: result.message);
      expect(current().status, expected);
      // In-flight approvals must never affect official spend.
      if (expected != ExpenseStatus.adviserApproved) {
        expect(ledger.totalSpent, spendBefore);
      }
    }

    expect(current().status, ExpenseStatus.adviserApproved);
    expect(ledger.totalSpent, spendBefore + current().amount);
    expect(ledger.approvedExpenses.any((Expense e) => e.id == targetId), isTrue);
    expect(
      ledger.expensesForRole(UserRole.adviser).any((Expense e) => e.id == targetId),
      isFalse,
    );

    // Rejecting without a remark is refused; a real remark is persisted.
    final Expense toReject = ledger
        .expensesForRole(UserRole.treasurer)
        .first;
    final LedgerActionResult missingRemark = await ledger.reviewExpense(
      expense: toReject,
      role: UserRole.treasurer,
      actorName: 'Test Reviewer',
      action: ReviewAction.reject,
    );
    expect(missingRemark.success, isFalse);
    expect(missingRemark.message, contains('at least 5 characters'));

    final LedgerActionResult rejected = await ledger.reviewExpense(
      expense: toReject,
      role: UserRole.treasurer,
      actorName: 'Test Reviewer',
      action: ReviewAction.reject,
      remarks: 'Receipt does not match the encoded amount.',
    );
    expect(rejected.success, isTrue);
    expect(
      ledger.expenses
          .firstWhere((Expense expense) => expense.id == toReject.id)
          .status,
      ExpenseStatus.rejected,
    );

    // A stale action against an already-moved record is refused.
    final LedgerActionResult stale = await ledger.reviewExpense(
      expense: toReject,
      role: UserRole.treasurer,
      actorName: 'Test Reviewer',
      action: ReviewAction.approve,
    );
    expect(stale.success, isFalse);
    expect(stale.message, contains('no longer awaiting'));
  });
}
