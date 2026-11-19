import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/expense_status.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/expense.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/banners.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/expense_card.dart';
import 'add_expense_screen.dart';
import 'receipt_inspector_screen.dart';

enum _ExpenseFilter { all, inReview, approved, attention }

/// Searchable ledger of every expense for the selected event.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final TextEditingController _searchController = TextEditingController();
  _ExpenseFilter _filter = _ExpenseFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Expense> _apply(List<Expense> source) {
    final String query = _searchController.text.trim().toLowerCase();
    return source.where((Expense expense) {
      final bool matchesFilter;
      switch (_filter) {
        case _ExpenseFilter.all:
          matchesFilter = true;
        case _ExpenseFilter.inReview:
          matchesFilter = expense.isInFlight;
        case _ExpenseFilter.approved:
          matchesFilter = expense.isApproved;
        case _ExpenseFilter.attention:
          matchesFilter = expense.needsAttention;
      }
      if (!matchesFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return expense.title.toLowerCase().contains(query) ||
          expense.displayCategory.toLowerCase().contains(query) ||
          expense.submittedByName.toLowerCase().contains(query) ||
          expense.status.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LedgerProvider ledger = context.watch<LedgerProvider>();
    final UserRoleProvider session = context.watch<UserRoleProvider>();
    final List<Expense> filtered = _apply(ledger.expenses);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Expenses'),
            Text(
              ledger.selectedEvent?.title ?? 'No event selected',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          if (session.canSubmitExpenses)
            IconButton(
              tooltip: 'Add expense',
              onPressed: () => openAddExpenseScreen(context),
              icon: const Icon(Icons.add_rounded),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: ledger.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          children: <Widget>[
            SyncBanner(
              isOnline: ledger.isOnline,
              pendingCount: ledger.pendingSyncCount,
              isSyncing: ledger.isSyncing,
              onSync: () async {
                final LedgerActionResult result = await ledger.syncPending(
                  performedBy: session.actorLabel,
                );
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result.message)),
                );
              },
            ),
            if (!ledger.isOnline || ledger.pendingSyncCount > 0)
              const SizedBox(height: 10),
            if (ledger.error != null) ...<Widget>[
              ErrorBanner(
                message: ledger.error ?? '',
                onRetry: ledger.refresh,
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search title, category or submitter',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _filterChip(
                    context,
                    label: 'All',
                    value: _ExpenseFilter.all,
                    count: ledger.expenses.length,
                  ),
                  _filterChip(
                    context,
                    label: 'In review',
                    value: _ExpenseFilter.inReview,
                    count: ledger.pendingApprovalsCount,
                  ),
                  _filterChip(
                    context,
                    label: 'Approved',
                    value: _ExpenseFilter.approved,
                    count: ledger.approvedExpenses.length,
                  ),
                  _filterChip(
                    context,
                    label: 'Needs attention',
                    value: _ExpenseFilter.attention,
                    count: ledger.flaggedCount + ledger.rejectedCount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Text(
                  '${filtered.length} of ${ledger.expenses.length} records',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                if (_filter == _ExpenseFilter.inReview)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.warning,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Moving through approvals',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            if (ledger.isLoading && ledger.expenses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              SizedBox(
                height: 360,
                child: EmptyState(
                  icon: _filter == _ExpenseFilter.all
                      ? Icons.receipt_long_outlined
                      : Icons.filter_alt_off_outlined,
                  title: _filter == _ExpenseFilter.all
                      ? 'No expenses yet'
                      : 'Nothing matches this view',
                  message: _filter == _ExpenseFilter.all
                      ? 'Submit an expense with a receipt to begin the approval chain.'
                      : 'Try another filter or clear your search.',
                  actionLabel: _filter == _ExpenseFilter.all &&
                          session.canSubmitExpenses
                      ? 'Add first expense'
                      : 'Clear filters',
                  onAction: () {
                    if (_filter == _ExpenseFilter.all &&
                        session.canSubmitExpenses) {
                      openAddExpenseScreen(context);
                    } else {
                      _searchController.clear();
                      setState(() => _filter = _ExpenseFilter.all);
                    }
                  },
                ),
              )
            else
              ...filtered.map(
                (Expense expense) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ExpenseCard(
                    expense: expense,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) =>
                              ExpenseInspectorScreen(expense: expense),
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (ledger.expenses.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Statuses refresh automatically as officers act on each record.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required _ExpenseFilter value,
    required int count,
  }) {
    final ThemeData theme = Theme.of(context);
    final bool selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        label: Text(
          '$label${count > 0 ? ' · $count' : ''}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        selectedColor: theme.colorScheme.primaryContainer,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }
}

/// Convenience used by dashboard/empty states.
String expenseStageDescription(Expense expense) {
  if (expense.isRejected) {
    return 'Rejected';
  }
  if (expense.isFlagged) {
    return 'Flagged';
  }
  return ExpenseStatus.label(expense.status);
}
