import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../data/models/org_event.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/banners.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/charts.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/expense_card.dart';
import '../../widgets/metric_card.dart';
import '../expenses/receipt_inspector_screen.dart';

/// Financial overview for the selected event.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Future<void> _sync(BuildContext context) async {
    final LedgerProvider ledger = context.read<LedgerProvider>();
    final UserRoleProvider session = context.read<UserRoleProvider>();
    final LedgerActionResult result = await ledger.syncPending(
      performedBy: session.actorLabel,
    );
    if (!context.mounted) {
      return;
    }
    _showResult(context, result);
  }

  Future<void> _export(BuildContext context) async {
    final LedgerProvider ledger = context.read<LedgerProvider>();
    final UserRoleProvider session = context.read<UserRoleProvider>();
    final LedgerActionResult result = await ledger.exportLiquidation(
      preparedBy: session.actorLabel,
    );
    if (!context.mounted) {
      return;
    }
    _showResult(context, result);
  }

  void _showResult(BuildContext context, LedgerActionResult result) {
    final ThemeData theme = Theme.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.message,
          style: result.success
              ? null
              : TextStyle(color: theme.colorScheme.onError),
        ),
        backgroundColor: result.success ? null : theme.colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LedgerProvider ledger = context.watch<LedgerProvider>();
    final UserRoleProvider session = context.watch<UserRoleProvider>();
    final OrgEvent? event = ledger.selectedEvent;
    final bool hasApproved = ledger.approvedExpenses.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Dashboard'),
            Text(
              '${session.role?.label ?? 'Officer'} · ${event?.title ?? 'No event'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          Badge(
            isLabelVisible: ledger.pendingSyncCount > 0,
            label: Text('${ledger.pendingSyncCount}'),
            child: IconButton(
              tooltip: ledger.isOnline
                  ? 'Sync offline records'
                  : 'Offline — records are saved locally',
              onPressed: ledger.isSyncing ? null : () => _sync(context),
              icon: ledger.isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      ledger.isOnline
                          ? Icons.cloud_sync_outlined
                          : Icons.cloud_off_rounded,
                    ),
            ),
          ),
          IconButton(
            tooltip: 'Export liquidation PDF',
            onPressed: hasApproved && event != null
                ? () => _export(context)
                : null,
            icon: const Icon(Icons.picture_as_pdf_outlined),
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
              onSync: () => _sync(context),
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
            if (ledger.isLoading && ledger.events.isEmpty)
              const SizedBox(
                height: 300,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (event == null)
              SizedBox(
                height: 420,
                child: EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'No event found',
                  message:
                      'Create or restore an event in the local ledger to start tracking expenses.',
                  actionLabel: 'Reload ledger',
                  onAction: ledger.refresh,
                ),
              )
            else ...<Widget>[
              _EventSelector(
                events: ledger.events,
                selected: event,
                isLoading: ledger.isLoading,
                onSelected: (OrgEvent selected) => ledger.selectEvent(selected),
              ),
              const SizedBox(height: 12),
              _MetricsGrid(ledger: ledger),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.verified_outlined,
                    size: 14,
                    color: AppColors.emerald,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Budget metrics count Adviser-approved expenses only.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _BurnDownCard(ledger: ledger),
              const SizedBox(height: 14),
              _ChartsSection(ledger: ledger),
              const SizedBox(height: 18),
              SectionHeader(
                title: 'Recent activity',
                subtitle: 'Latest records for ${event.title}',
              ),
              const SizedBox(height: 10),
              if (ledger.expenses.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No expenses yet',
                      message:
                          'Add the first expense and its receipt to start the approval pipeline.',
                    ),
                  ),
                )
              else
                ...ledger.latestExpenses.map(
                  (expense) => Padding(
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
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '${ledger.expenses.length} records · updated ${AppFormat.time(DateTime.now())}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EventSelector extends StatelessWidget {
  const _EventSelector({
    required this.events,
    required this.selected,
    required this.isLoading,
    required this.onSelected,
  });

  final List<OrgEvent> events;
  final OrgEvent selected;
  final bool isLoading;
  final ValueChanged<OrgEvent> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.event_available_outlined,
              color: AppColors.emerald,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'VIEWING EVENT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<OrgEvent>(
                    value: selected,
                    isDense: true,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(12),
                    items: events
                        .map(
                          (OrgEvent event) => DropdownMenuItem<OrgEvent>(
                            value: event,
                            child: Text(
                              event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (OrgEvent? value) {
                      if (value != null) {
                        onSelected(value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.ledger});

  final LedgerProvider ledger;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 760 ? 4 : 2;
        final int inReview =
            (ledger.pendingApprovalsCount - ledger.pendingOnlyCount)
                .clamp(0, 9999);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: 168,
          children: <Widget>[
            MetricCard(
              label: 'Total budget',
              value: AppFormat.currency(ledger.totalBudget, decimals: false),
              icon: Icons.account_balance_wallet_outlined,
              accent: AppColors.info,
              subtitle: 'Starting allocation',
            ),
            MetricCard(
              label: 'Total spent',
              value: AppFormat.currency(ledger.totalSpent, decimals: false),
              icon: Icons.receipt_long_outlined,
              accent: AppColors.emerald,
              subtitle: '${ledger.approvedExpenses.length} approved',
            ),
            MetricCard(
              label: 'Pending approvals',
              value: '${ledger.pendingApprovalsCount}',
              icon: Icons.hourglass_top_rounded,
              accent: AppColors.warning,
              subtitle:
                  '${ledger.pendingOnlyCount} new · $inReview in review',
            ),
            MetricCard(
              label: 'Flagged items',
              value: '${ledger.flaggedCount}',
              icon: Icons.flag_outlined,
              accent: AppColors.danger,
              subtitle: '${ledger.rejectedCount} rejected',
            ),
          ],
        );
      },
    );
  }
}

class _BurnDownCard extends StatelessWidget {
  const _BurnDownCard({required this.ledger});

  final LedgerProvider ledger;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double usage = ledger.budgetUsage;
    final double rawUsage = ledger.budgetUsageRaw;
    final bool hasBudget = ledger.totalBudget > 0;
    final Color burnColor = AppColors.budget(rawUsage);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Expanded(
                  child: SectionHeader(
                    title: 'Budget burn-down',
                    subtitle: 'Only fully approved spending is deducted',
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: burnColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasBudget ? AppFormat.percent(rawUsage) : 'No budget',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: burnColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!hasBudget)
              MetricHint(
                text:
                    'This event has no starting budget yet. Add a budget to track utilization.',
                color: theme.colorScheme.onSurfaceVariant,
                icon: Icons.info_outline_rounded,
              )
            else ...<Widget>[
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: usage),
                duration: const Duration(milliseconds: 750),
                curve: Curves.easeOutCubic,
                builder: (BuildContext context, double value, Widget? child) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 11,
                      color: AppColors.budget(rawUsage),
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  );
                },
              ),
              const SizedBox(height: 9),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Spent ${AppFormat.currency(ledger.totalSpent)} of ${AppFormat.currency(ledger.totalBudget)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ledger.isOverBudget
                        ? 'Over by ${AppFormat.currency(ledger.totalSpent - ledger.totalBudget)}'
                        : '${AppFormat.currency(ledger.remainingBudget)} left',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: burnColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (ledger.isNearBudgetLimit) ...<Widget>[
                const SizedBox(height: 11),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: burnColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: burnColor.withValues(alpha: 0.22),
                    ),
                  ),
                  child: MetricHint(
                    icon: ledger.isOverBudget
                        ? Icons.trending_up_rounded
                        : Icons.warning_amber_rounded,
                    color: burnColor,
                    text: ledger.isOverBudget
                        ? 'Budget exceeded. Review upcoming purchases before submitting more expenses.'
                        : '${AppFormat.percent(rawUsage)} of the budget is used. Remaining funds are limited.',
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Budget runway',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Remaining per approval',
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
              const SizedBox(height: 10),
              BurnDownChart(
                points: ledger.burnDownPoints,
                budget: ledger.totalBudget,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChartsSection extends StatelessWidget {
  const _ChartsSection({required this.ledger});

  final LedgerProvider ledger;

  @override
  Widget build(BuildContext context) {
    return CategoryBreakdownCard(
      totals: ledger.categoryTotals,
      total: ledger.totalSpent,
    );
  }
}
