import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:org_ledger/core/constants/app_categories.dart';
import 'package:org_ledger/core/constants/expense_status.dart';
import 'package:org_ledger/core/theme/app_theme.dart';
import 'package:org_ledger/data/database/database_helper.dart';
import 'package:org_ledger/data/models/app_user.dart';
import 'package:org_ledger/data/models/expense.dart';
import 'package:org_ledger/data/models/user_role.dart';
import 'package:org_ledger/data/repositories/audit_repository.dart';
import 'package:org_ledger/data/repositories/auth_repository.dart';
import 'package:org_ledger/data/repositories/expense_repository.dart';
import 'package:org_ledger/data/services/connectivity_service.dart';
import 'package:org_ledger/data/services/liquidation_pdf_service.dart';
import 'package:org_ledger/data/services/sync_service.dart';
import 'package:org_ledger/providers/ledger_provider.dart';
import 'package:org_ledger/providers/user_role_provider.dart';
import 'package:org_ledger/screens/expenses/receipt_inspector_screen.dart';
import 'package:provider/provider.dart';

/// Session double that bypasses SQLite; no database call is made in these tests.
class _TestSession extends UserRoleProvider {
  _TestSession(this._user, {required DatabaseHelper db})
      : super(
          authRepository: AuthRepository(db),
          auditRepository: AuditRepository(db),
          databaseHelper: db,
        );

  final AppUser? _user;

  @override
  AppUser? get currentUser => _user;

  @override
  UserRole? get role => _user?.role;

  @override
  bool get isAuthenticated => _user != null;

  @override
  bool get canSubmitExpenses => _user?.role.canSubmitExpenses ?? false;

  @override
  bool get canReviewExpenses => _user?.role.isReviewer ?? false;

  @override
  String get actorLabel =>
      _user == null ? 'System' : '${_user.name} · ${_user.role.label}';

  @override
  String? get reviewableStatus => _user?.role.reviewableStatus;

  @override
  bool canActOn(Expense expense) {
    final String? expected = _user?.role.reviewableStatus;
    return expected != null && expense.status == expected;
  }
}

void main() {
  final DatabaseHelper db = DatabaseHelper();
  final AuditRepository audit = AuditRepository(db);
  final ConnectivityService connectivity = ConnectivityService();
  final ExpenseRepository expenses = ExpenseRepository(db);
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

  final Expense pendingExpense = Expense(
    id: 11,
    eventId: 1,
    title: 'Sound system rental for the program',
    amount: 4500,
    category: AppCategories.venues,
    customCategory: '',
    receiptImagePath: '',
    status: ExpenseStatus.pending,
    submittedBy: 1,
    remarks: '',
    isSynced: false,
    createdAt: DateTime(2026, 2, 4, 9, 30),
    updatedAt: DateTime(2026, 2, 4, 10),
    submittedByName: 'Bea Manalo',
    eventTitle: 'Intramurals 2026',
  );

  tearDownAll(ledger.dispose);

  Future<void> pumpInspector(
    WidgetTester tester,
    UserRole? role, {
    Size size = const Size(360, 780),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppUser? user = role == null
        ? null
        : AppUser(
            id: 9,
            name: 'Tessa Cruz',
            email: 'treasurer@orgledger.app',
            password: 'hash',
            role: role,
          );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LedgerProvider>.value(value: ledger),
          ChangeNotifierProvider<UserRoleProvider>.value(
            value: _TestSession(user, db: db),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ExpenseInspectorScreen(expense: pendingExpense),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Expense details render for a non-reviewer', (
    WidgetTester tester,
  ) async {
    await pumpInspector(tester, null, size: const Size(320, 760));

    expect(find.text('Sound system rental for the program'), findsOneWidget);
    expect(find.text('Approval chain'), findsOneWidget);
    // No review actions are exposed without a reviewer session.
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reviewer sees approve/reject/flag actions', (
    WidgetTester tester,
  ) async {
    await pumpInspector(tester, UserRole.treasurer, size: const Size(320, 780));

    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Flag for correction instead'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
