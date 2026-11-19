import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:org_ledger/core/constants/app_categories.dart';
import 'package:org_ledger/core/constants/expense_status.dart';
import 'package:org_ledger/core/theme/app_theme.dart';
import 'package:org_ledger/data/models/expense.dart';
import 'package:org_ledger/widgets/charts.dart';
import 'package:org_ledger/widgets/expense_card.dart';
import 'package:org_ledger/widgets/metric_card.dart';
import 'package:org_ledger/widgets/status_chip.dart';

void main() {
  testWidgets('StatusChip renders the friendly status label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: StatusChip(status: ExpenseStatus.treasurerVerified),
          ),
        ),
      ),
    );

    expect(find.text('Treasurer verified'), findsOneWidget);
    expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
  });

  testWidgets('StatusChip tolerates unknown database values', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Center(child: StatusChip(status: 'nonsense-status')),
        ),
      ),
    );

    // Unknown statuses normalise to Pending rather than throwing.
    expect(find.text('Pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ExpenseCard and MetricCard fit a narrow phone', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final Expense expense = Expense(
      id: 42,
      eventId: 1,
      title: 'Tarpaulin printing for the opening ceremony',
      amount: 3250.75,
      category: AppCategories.printing,
      customCategory: '',
      receiptImagePath: '/receipts/demo.jpg',
      status: ExpenseStatus.treasurerVerified,
      submittedBy: 1,
      remarks: '',
      isSynced: false,
      createdAt: DateTime(2026, 2, 1),
      updatedAt: DateTime(2026, 2, 2),
      submittedByName: 'Bea Manalo',
      eventTitle: 'Intramurals 2026',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                const MetricCard(
                  label: 'Total budget',
                  value: '₱60,000',
                  icon: Icons.account_balance_wallet_outlined,
                  accent: Color(0xFF2F6FED),
                  subtitle: 'Starting allocation',
                ),
                const SizedBox(height: 8),
                ExpenseCard(expense: expense),
                const SizedBox(height: 8),
                CategoryBreakdownCard(
                  totals: const <String, double>{
                    AppCategories.printing: 3250.75,
                  },
                  total: 3250.75,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Treasurer verified'), findsOneWidget);
    expect(find.text('Printing & Publications'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

