import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:org_ledger/core/constants/app_categories.dart';
import 'package:org_ledger/core/constants/expense_status.dart';
import 'package:org_ledger/core/theme/app_theme.dart';
import 'package:org_ledger/data/database/database_helper.dart';
import 'package:org_ledger/data/models/app_user.dart';
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
import 'package:org_ledger/screens/dashboard/dashboard_screen.dart';
import 'package:provider/provider.dart';

DateTime _daysAgo(int days) =>
    DateTime.now().subtract(Duration(days: days));

Expense _approved(
  int id,
  String title,
  double amount,
  String category,
  int days,
) {
  return Expense(
    id: id,
    eventId: 1,
    title: title,
    amount: amount,
    category: category,
    customCategory: '',
    receiptImagePath: '',
    status: ExpenseStatus.adviserApproved,
    submittedBy: 1,
    remarks: '',
    isSynced: true,
    createdAt: _daysAgo(days),
    updatedAt: _daysAgo(days),
    submittedByName: 'Bea Manalo',
    eventTitle: 'Intramurals 2026',
  );
}

class _TestLedger extends LedgerProvider {
  _TestLedger({
    required this.event,
    required this.items,
  }) : super(
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

  final OrgEvent event;
  final List<Expense> items;

  @override
  List<OrgEvent> get events => <OrgEvent>[event];

  @override
  OrgEvent? get selectedEvent => event;

  @override
  List<Expense> get expenses => List<Expense>.unmodifiable(items);

  @override
  List<Expense> get latestExpenses => items.take(5).toList(growable: false);

  @override
  bool get isLoading => false;

  @override
  bool get isOnline => true;

  @override
  bool get isSyncing => false;

  @override
  int get pendingSyncCount => 2;

  @override
  String? get error => null;

  @override
  List<Expense> get approvedExpenses => items
      .where((Expense expense) => expense.isApproved)
      .toList(growable: false);

  @override
  double get totalBudget => event.startingBudget;

  @override
  double get totalSpent => approvedExpenses.fold<double>(
        0,
        (double sum, Expense expense) => sum + expense.amount,
      );

  @override
  double get remainingBudget => totalBudget - totalSpent;

  @override
  double get budgetUsage =>
      totalBudget <= 0 ? 0 : (totalSpent / totalBudget).clamp(0.0, 1.0);

  @override
  double get budgetUsageRaw =>
      totalBudget <= 0 ? 0 : totalSpent / totalBudget;

  @override
  bool get isOverBudget => totalSpent > totalBudget;

  @override
  bool get isNearBudgetLimit => budgetUsageRaw >= 0.8;

  @override
  int get pendingApprovalsCount =>
      items.where((Expense expense) => expense.isInFlight).length;

  @override
  int get pendingOnlyCount =>
      items.where((Expense expense) => expense.isPending).length;

  @override
  int get flaggedCount =>
      items.where((Expense expense) => expense.isFlagged).length;

  @override
  int get rejectedCount =>
      items.where((Expense expense) => expense.isRejected).length;

  @override
  Map<String, double> get categoryTotals => <String, double>{
        AppCategories.food: 12500,
        AppCategories.venues: 18000,
        AppCategories.supplies: 9800,
        AppCategories.transport: 7200,
        AppCategories.printing: 4500,
      };

  @override
  List<BurnDownPoint> get burnDownPoints => <BurnDownPoint>[
        BurnDownPoint(
          index: 0,
          date: _daysAgo(20),
          remaining: 60000,
          label: 'Start',
        ),
        BurnDownPoint(
          index: 1,
          date: _daysAgo(18),
          remaining: 47500,
          label: 'Jan 2',
        ),
        BurnDownPoint(
          index: 2,
          date: _daysAgo(15),
          remaining: 29500,
          label: 'Jan 5',
        ),
        BurnDownPoint(
          index: 3,
          date: _daysAgo(11),
          remaining: 19700,
          label: 'Jan 9',
        ),
        BurnDownPoint(
          index: 4,
          date: _daysAgo(7),
          remaining: 12500,
          label: 'Jan 13',
        ),
        BurnDownPoint(
          index: 5,
          date: _daysAgo(3),
          remaining: 8000,
          label: 'Jan 17',
        ),
      ];
}

class _TestSession extends UserRoleProvider {
  _TestSession({required this.user, required DatabaseHelper db})
      : super(
          authRepository: AuthRepository(db),
          auditRepository: AuditRepository(db),
          databaseHelper: db,
        );

  final AppUser user;

  @override
  AppUser? get currentUser => user;

  @override
  UserRole? get role => user.role;

  @override
  bool get isAuthenticated => true;

  @override
  bool get isRestoring => false;

  @override
  bool get canSubmitExpenses => true;

  @override
  bool get canReviewExpenses => false;

  @override
  String get actorLabel => '${user.name} · ${user.role.label}';
}

void main() {
  testWidgets('Dashboard renders metrics and charts on a narrow phone', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final DatabaseHelper db = DatabaseHelper();
    const OrgEvent event = OrgEvent(
      id: 1,
      title: 'Intramurals 2026',
      startingBudget: 60000,
    );
    final List<Expense> items = <Expense>[
      _approved(1, 'Catering balance', 12500, AppCategories.food, 18),
      _approved(2, 'Function hall', 18000, AppCategories.venues, 15),
      _approved(3, 'Sports supplies', 9800, AppCategories.supplies, 11),
      _approved(4, 'Shuttle service', 7200, AppCategories.transport, 7),
      _approved(5, 'Tarpaulin printing', 4500, AppCategories.printing, 3),
      Expense(
        id: 6,
        eventId: 1,
        title: 'Flagged entry',
        amount: 500,
        category: AppCategories.others,
        customCategory: 'ID Printing',
        receiptImagePath: '',
        status: ExpenseStatus.flagged,
        submittedBy: 1,
        remarks: 'Receipt mismatch',
        isSynced: false,
        createdAt: _daysAgo(1),
        updatedAt: _daysAgo(1),
        submittedByName: 'Bea Manalo',
        eventTitle: 'Intramurals 2026',
      ),
    ];
    final _TestLedger ledger = _TestLedger(event: event, items: items);
    final _TestSession session = _TestSession(
      user: const AppUser(
        id: 1,
        name: 'Bea Manalo',
        email: 'bm@orgledger.app',
        password: 'hash',
        role: UserRole.businessManager,
      ),
      db: db,
    );
    addTearDown(ledger.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LedgerProvider>.value(value: ledger),
          ChangeNotifierProvider<UserRoleProvider>.value(value: session),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Total budget'), findsOneWidget);
    expect(find.text('Budget burn-down'), findsOneWidget);
    expect(find.text('86.7%'), findsWidgets);

    // The dashboard is scrollable on a narrow phone; bring the donut chart
    // into view before asserting on it.
    await tester.dragUntilVisible(
      find.text('Spending by category'),
      find.byType(ListView),
      const Offset(0, -260),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Spending by category'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
