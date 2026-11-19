import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/expense_status.dart';
import '../../core/theme/role_visuals.dart';
import '../../data/models/expense.dart';
import '../../data/models/user_role.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/banners.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/expense_card.dart';
import '../expenses/receipt_inspector_screen.dart';

enum _FeedFilter { myQueue, inReview, flagged }

/// Reviewer inbox scoped to the signed-in officer's tier.
class ApprovalFeedScreen extends StatefulWidget {
  const ApprovalFeedScreen({super.key});

  @override
  State<ApprovalFeedScreen> createState() => _ApprovalFeedScreenState();
}

class _ApprovalFeedScreenState extends State<ApprovalFeedScreen> {
  _FeedFilter _filter = _FeedFilter.myQueue;

  List<Expense> _apply(LedgerProvider ledger) {
    switch (_filter) {
      case _FeedFilter.myQueue:
        final UserRoleProvider session = context.read<UserRoleProvider>();
        final role = session.role;
        return role == null ? const <Expense>[] : ledger.expensesForRole(role);
      case _FeedFilter.inReview:
        return ledger.expenses
            .where((Expense expense) => expense.isInFlight)
            .toList(growable: false);
      case _FeedFilter.flagged:
        return ledger.expenses
            .where((Expense expense) => expense.isFlagged)
            .toList(growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LedgerProvider ledger = context.watch<LedgerProvider>();
    final UserRoleProvider session = context.watch<UserRoleProvider>();
    final role = session.role;
    final List<Expense> items = _apply(ledger);
    final int myQueue = role == null ? 0 : ledger.awaitingMyReviewCount(role);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Approvals'),
            Text(
              role == null
                  ? 'No reviewer role'
                  : '${role.label} · ${RoleVisuals.tier(role)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          Badge(
            isLabelVisible: myQueue > 0,
            label: Text('$myQueue'),
            child: IconButton(
              tooltip: 'Refresh approval feed',
              onPressed: ledger.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
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
            _QueueHeader(
              role: role,
              myQueue: myQueue,
              canReview: session.canReviewExpenses,
            ),
            const SizedBox(height: 12),
            if (session.canReviewExpenses)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _chip(
                      context,
                      label: 'My queue',
                      value: _FeedFilter.myQueue,
                      count: myQueue,
                    ),
                    _chip(
                      context,
                      label: 'All in review',
                      value: _FeedFilter.inReview,
                      count: ledger.pendingApprovalsCount,
                    ),
                    _chip(
                      context,
                      label: 'Flagged',
                      value: _FeedFilter.flagged,
                      count: ledger.flaggedCount,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (!session.canReviewExpenses)
              const SizedBox(
                height: 380,
                child: EmptyState(
                  icon: Icons.verified_user_outlined,
                  title: 'Reviewer access only',
                  message:
                      'Approval queues are bound to Treasurer, Auditor, President and Adviser accounts.',
                ),
              )
            else if (ledger.isLoading && ledger.expenses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              SizedBox(
                height: 360,
                child: EmptyState(
                  icon: _filter == _FeedFilter.flagged
                      ? Icons.flag_outlined
                      : Icons.task_alt_rounded,
                  title: _filter == _FeedFilter.myQueue
                      ? 'Your queue is clear'
                      : _filter == _FeedFilter.flagged
                          ? 'No flagged expenses'
                          : 'Nothing in review',
                  message: _filter == _FeedFilter.myQueue
                      ? 'New items will appear here when the previous reviewer forwards them to your tier.'
                      : 'Try another filter or pull down to refresh the ledger.',
                  actionLabel: 'Refresh',
                  onAction: ledger.refresh,
                ),
              )
            else ...<Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '${items.length} ${items.length == 1 ? 'record' : 'records'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _filter == _FeedFilter.myQueue
                          ? 'Tap to inspect and act'
                          : 'Read-only until it reaches your tier',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...items.map(
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
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required _FeedFilter value,
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

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({
    required this.role,
    required this.myQueue,
    required this.canReview,
  });

  final UserRole? role;
  final int myQueue;
  final bool canReview;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final UserRole? reviewer = role;
    final bool isReviewer = canReview && reviewer != null;
    final Color accent = reviewer == null
        ? theme.colorScheme.onSurfaceVariant
        : RoleVisuals.color(reviewer);
    final String title;
    final String detail;
    if (!isReviewer) {
      title = 'Approval feed';
      detail = 'Sign in with a reviewer account to act on expenses.';
    } else if (myQueue == 0) {
      title = 'All caught up';
      detail = reviewer.responsibility;
    } else {
      title = '$myQueue ${myQueue == 1 ? 'item needs' : 'items need'} your action';
      detail = reviewer.responsibility;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            accent.withValues(alpha: 0.12),
            theme.colorScheme.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              reviewer == null
                  ? Icons.verified_user_outlined
                  : RoleVisuals.icon(reviewer),
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isReviewer) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'Your tier acts on: ${ExpenseStatus.label(reviewer.reviewableStatus)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
