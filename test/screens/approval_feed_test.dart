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
import 'package:org_ledger/screens/approvals/approval_feed_screen.dart';
import 'package:provider/provider.dart';

Expense _expense(int id, String title, String status) {
  return Expense(
    id: id,
    eventId: 1,
    title: title,
    amount: 1000.0 + id,
    category: AppCategories.supplies,
    customCategory: '',
    receiptImagePath: '',
    status: status,
    submittedBy: 1,
    remarks: '',
    isSynced: true,
    createdAt: DateTime(2026, 2, id),
    updatedAt: DateTime(2026, 2, id),
    submittedByName: 'Bea Manalo',
    eventTitle: 'Intramurals 2026',
  );
}

class _StubLedger extends LedgerProvider {
  _StubLedger(this._items)
      : super(
          expenseRepository: ExpenseRepository(DatabaseHelper()),
          auditRepository: AuditRepository(DatabaseHelper()),
          syncService: SyncService(
            expenseRepository: ExpenseRepository(DatabaseHelper()),
            auditRepository: AuditRepository(DatabaseHelper()),
            connectivityService: ConnectivityService(),
          ),
          connectivityService: ConnectivityService(),
          pdfService: const LiquidationPdfService(),
        );

  final List<Expense> _items;

  @override
  List<Expense> get expenses => List<Expense>.unmodifiable(_items);

  @override
  bool get isInitialized => true;

  @override
  bool get isLoading => false;

  @override
  bool get isOnline => false;

  @override
  bool get isSyncing => false;

  @override
  int get pendingSyncCount => 2;

  @override
  String? get error => null;

  @override
  int get pendingApprovalsCount =>
      _items.where((Expense expense) => expense.isInFlight).length;

  @override
  int get pendingOnlyCount =>
      _items.where((Expense expense) => expense.isPending).length;

  @override
  int get flaggedCount =>
      _items.where((Expense expense) => expense.isFlagged).length;

  @override
  int get rejectedCount =>
      _items.where((Expense expense) => expense.isRejected).length;

  @override
  Future<void> refresh() async {}

  @override
  int awaitingMyReviewCount(UserRole role) =>
      expensesForRole(role).length;

  @override
  List<Expense> expensesForRole(UserRole role) {
    final String? status = role.reviewableStatus;
    if (status == null) {
      return const <Expense>[];
    }
    return _items
        .where((Expense expense) => expense.status == status)
        .toList(growable: false);
  }
}

class _StubSession extends UserRoleProvider {
  _StubSession({required this.role})
      : super(
          authRepository: AuthRepository(DatabaseHelper()),
          auditRepository: AuditRepository(DatabaseHelper()),
          databaseHelper: DatabaseHelper(),
        );

  @override
  final UserRole? role;

  @override
  AppUser? get currentUser => role == null
      ? null
      : AppUser(
          id: 3,
          username: 'treasurer',
          name: 'Tessa Cruz',
          email: 'treasurer@orgledger.app',
          password: 'hash',
          role: role!,
          isActive: true,
        );

  @override
  bool get isAuthenticated => role != null;

  @override
  bool get isRestoring => false;

  @override
  bool get canSubmitExpenses => false;

  @override
  bool get canReviewExpenses => true;

  @override
  String get actorLabel => 'Tessa Cruz · Treasurer';
}

void main() {
  testWidgets('Approval feed shows only the signed-in tier and survives 320px', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 780);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _StubLedger ledger = _StubLedger(<Expense>[
      _expense(1, 'Snacks for volunteers', ExpenseStatus.pending),
      _expense(2, 'Sound system rental', ExpenseStatus.treasurerVerified),
      _expense(3, 'Blurry tarpaulin receipt', ExpenseStatus.flagged),
    ]);
    final _StubSession session = _StubSession(role: UserRole.treasurer);
    addTearDown(ledger.dispose);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LedgerProvider>.value(value: ledger),
          ChangeNotifierProvider<UserRoleProvider>.value(value: session),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ApprovalFeedScreen(),
        ),
      ),
    );
    await tester.pump();

    // Treasurers only act on Pending records; the verified record is not shown.
    expect(find.text('1 item needs your action'), findsOneWidget);
    expect(find.text('Snacks for volunteers'), findsOneWidget);
    expect(find.text('Sound system rental'), findsNothing);
    expect(find.text('Your tier acts on: Pending'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The chip row scrolls horizontally on a narrow phone.
    await tester.dragUntilVisible(
      find.textContaining('All in review'),
      find.byType(SingleChildScrollView),
      const Offset(-70, 0),
    );
    await tester.pump();

    // Switching to the review-wide filter reveals the forwarded record.
    await tester.tap(find.textContaining('All in review'));
    await tester.pump();
    expect(find.text('Sound system rental'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
