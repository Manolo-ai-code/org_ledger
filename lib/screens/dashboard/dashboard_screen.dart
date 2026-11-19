import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../data/models/app_user.dart';
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

  Future<void> _openCreateBudgetEvent(BuildContext context) async {
    final UserRoleProvider session = context.read<UserRoleProvider>();
    final LedgerProvider ledger = context.read<LedgerProvider>();
    final AppUser? actor = session.currentUser;
    if (actor == null || !session.canManageMembers) {
      return;
    }
    final _BudgetEventFormValue? value =
        await showDialog<_BudgetEventFormValue>(
      context: context,
      builder: (BuildContext dialogContext) => const _BudgetEventFormDialog(),
    );
    if (value == null || !context.mounted) {
      return;
    }
    final LedgerActionResult result = await ledger.createBudgetEvent(
      actor: actor,
      title: value.title,
      startingBudget: value.startingBudget,
      eventType: value.eventType,
      schoolYear: value.schoolYear,
    );
    if (!context.mounted) {
      return;
    }
    _showResult(context, result);
  }

  Future<void> _openEditBudgetEvent(
    BuildContext context,
    OrgEvent event,
  ) async {
    final UserRoleProvider session = context.read<UserRoleProvider>();
    final LedgerProvider ledger = context.read<LedgerProvider>();
    final AppUser? actor = session.currentUser;
    if (actor == null || !session.canManageMembers) {
      return;
    }
    final _BudgetEventFormValue? value =
        await showDialog<_BudgetEventFormValue>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _BudgetEventFormDialog(existing: event),
    );
    if (value == null || !context.mounted) {
      return;
    }
    final LedgerActionResult result = await ledger.updateBudgetEvent(
      actor: actor,
      event: event,
      title: value.title,
      startingBudget: value.startingBudget,
      eventType: value.eventType,
      schoolYear: value.schoolYear,
    );
    if (!context.mounted) {
      return;
    }
    _showResult(context, result);
  }

  Future<void> _openManageBudgetEvents(BuildContext context) async {
    final UserRoleProvider session = context.read<UserRoleProvider>();
    if (!session.canManageMembers) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _ManageBudgetEventsSheet(
        onCreate: () async {
          Navigator.of(sheetContext).pop();
          await _openCreateBudgetEvent(context);
        },
        onEdit: (OrgEvent event) async {
          Navigator.of(sheetContext).pop();
          await _openEditBudgetEvent(context, event);
        },
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
    final bool canManageEvents = session.canManageMembers;

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
          if (canManageEvents)
            PopupMenuButton<String>(
              tooltip: 'Manage budget events',
              icon: const Icon(Icons.more_vert),
              onSelected: (String value) {
                switch (value) {
                  case 'create':
                    _openCreateBudgetEvent(context);
                    break;
                  case 'edit':
                    if (event != null) {
                      _openEditBudgetEvent(context, event);
                    }
                    break;
                  case 'manage':
                    _openManageBudgetEvents(context);
                    break;
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'create',
                  child: ListTile(
                    leading: Icon(Icons.add_circle_outline),
                    title: Text('New budget event'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'edit',
                  enabled: event != null,
                  child: const ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit selected budget'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'manage',
                  child: ListTile(
                    leading: Icon(Icons.event_note_outlined),
                    title: Text('Manage events'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
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
                  title: 'No budget event found',
                  message:
                      'Create a budget event for the semester, school year, or project to start tracking expenses.',
                  actionLabel:
                      canManageEvents ? 'Create budget event' : 'Reload ledger',
                  onAction: canManageEvents
                      ? () => _openCreateBudgetEvent(context)
                      : ledger.refresh,
                ),
              )
            else ...<Widget>[
              _EventSelector(
                events: ledger.events,
                selected: event,
                isLoading: ledger.isLoading,
                canManage: canManageEvents,
                onSelected: (OrgEvent selected) => ledger.selectEvent(selected),
                onEditSelected: () => _openEditBudgetEvent(context, event),
                onCreate: () => _openCreateBudgetEvent(context),
              ),
              const SizedBox(height: 12),
              _BudgetStatusBanner(ledger: ledger),
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
              _BurnDownCard(
                ledger: ledger,
                canManage: canManageEvents,
                onSetBudget: () => _openEditBudgetEvent(context, event),
              ),
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
    required this.canManage,
    required this.onSelected,
    required this.onEditSelected,
    required this.onCreate,
  });

  final List<OrgEvent> events;
  final OrgEvent selected;
  final bool isLoading;
  final bool canManage;
  final ValueChanged<OrgEvent> onSelected;
  final VoidCallback onEditSelected;
  final VoidCallback onCreate;

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
                  'BUDGET EVENT',
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
                if (selected.schoolYear.trim().isNotEmpty ||
                    selected.eventType.trim().isNotEmpty)
                  Text(
                    <String>[
                      if (selected.eventType.trim().isNotEmpty)
                        selected.eventType.trim(),
                      if (selected.schoolYear.trim().isNotEmpty)
                        selected.schoolYear.trim(),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
            )
          else if (canManage) ...<Widget>[
            IconButton(
              tooltip: 'Edit selected budget',
              onPressed: onEditSelected,
              icon: const Icon(Icons.edit_outlined, size: 20),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: 'New budget event',
              onPressed: onCreate,
              icon: const Icon(Icons.add_circle_outline, size: 22),
              visualDensity: VisualDensity.compact,
            ),
          ],
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
  const _BurnDownCard({
    required this.ledger,
    required this.canManage,
    required this.onSetBudget,
  });

  final LedgerProvider ledger;
  final bool canManage;
  final VoidCallback onSetBudget;

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MetricHint(
                    text:
                        'This budget event has no starting budget yet. Set or edit a starting budget to track utilization.',
                    color: theme.colorScheme.onSurfaceVariant,
                    icon: Icons.info_outline_rounded,
                  ),
                  if (canManage) ...<Widget>[
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: onSetBudget,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Set starting budget'),
                    ),
                  ],
                ],
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
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
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
                        ? 'Overspent by ${AppFormat.currency(ledger.overspentAmount)}'
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
                        ? Icons.warning_rounded
                        : Icons.warning_amber_rounded,
                    color: burnColor,
                    text: ledger.isOverBudget
                        ? 'Budget exceeded by ${AppFormat.currency(ledger.overspentAmount)} '
                            '(approved spend ${AppFormat.currency(ledger.totalSpent)} of '
                            '${AppFormat.currency(ledger.totalBudget)}). Review upcoming '
                            'submissions and approvals carefully.'
                        : '${AppFormat.percent(rawUsage)} of the budget is used. '
                            'Only ${AppFormat.currency(ledger.remainingBudget)} remains for approved spending.',
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

/// Prominent budget status/overspend banner for Stage 3 reporting.
class _BudgetStatusBanner extends StatelessWidget {
  const _BudgetStatusBanner({required this.ledger});

  final LedgerProvider ledger;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (ledger.totalBudget <= 0) {
      return const SizedBox.shrink();
    }

    final bool over = ledger.isOverBudget;
    final bool near = ledger.isNearBudgetLimit;
    if (!over && !near) {
      return const SizedBox.shrink();
    }

    final Color color = AppColors.budget(ledger.budgetUsageRaw);
    final String title = over ? 'Budget exceeded' : 'Approaching budget limit';
    final String message = over
        ? 'Approved spending is ${AppFormat.currency(ledger.overspentAmount)} over the '
            '${AppFormat.currency(ledger.totalBudget)} budget '
            '(${AppFormat.percent(ledger.budgetUsageRaw)} used). '
            'New submissions may still be recorded, but approvals should account for the overage.'
        : '${AppFormat.percent(ledger.budgetUsageRaw)} of the budget is used. '
            '${AppFormat.currency(ledger.remainingBudget)} remains based on approved expenses only.';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.18 : 0.1,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              over ? Icons.warning_rounded : Icons.warning_amber_rounded,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Official budget impact counts Adviser-approved expenses only; pending/in-review items are not deducted.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetEventFormValue {
  const _BudgetEventFormValue({
    required this.title,
    required this.startingBudget,
    required this.eventType,
    required this.schoolYear,
  });

  final String title;
  final double startingBudget;
  final String eventType;
  final String schoolYear;
}

class _BudgetEventFormDialog extends StatefulWidget {
  const _BudgetEventFormDialog({this.existing});

  final OrgEvent? existing;

  @override
  State<_BudgetEventFormDialog> createState() => _BudgetEventFormDialogState();
}

class _BudgetEventFormDialogState extends State<_BudgetEventFormDialog> {
  static const List<String> _types = <String>[
    'General',
    'School Year',
    'Semester',
    'Project',
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _budgetController;
  late final TextEditingController _schoolYearController;
  late String _type;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final OrgEvent? e = widget.existing;
    _titleController = TextEditingController(text: e?.title ?? '');
    _budgetController = TextEditingController(
      text: e == null ? '' : e.startingBudget.toStringAsFixed(2),
    );
    _schoolYearController = TextEditingController(text: e?.schoolYear ?? '');
    _type = (e?.eventType.trim().isNotEmpty ?? false)
        ? e!.eventType.trim()
        : 'General';
    if (!_types.contains(_type)) {
      _type = 'General';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _budgetController.dispose();
    _schoolYearController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final String rawBudget = _budgetController.text.trim().replaceAll(',', '');
    final double? budget = double.tryParse(rawBudget);
    if (budget == null || !budget.isFinite || budget < 0) {
      return;
    }
    Navigator.of(context).pop(
      _BudgetEventFormValue(
        title: _titleController.text.trim(),
        startingBudget: budget,
        eventType: _type,
        schoolYear: _schoolYearController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isEdit ? 'Edit budget event' : 'New budget event'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _isEdit
                    ? 'Update the allocation or details for this event. Official spend remains based on Adviser-approved expenses only.'
                    : 'Create a separate budget for a semester, school year, or project.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Event name',
                  hintText: 'e.g. SY 2026-2027 · 1st Semester',
                  prefixIcon: Icon(Icons.event_outlined),
                ),
                validator: (String? value) {
                  final String text = value?.trim() ?? '';
                  if (text.length < 3) {
                    return 'Enter a name with at least 3 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _budgetController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Starting budget (₱)',
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                validator: (String? value) {
                  final String raw = (value ?? '').trim().replaceAll(',', '');
                  if (raw.isEmpty) {
                    return 'Enter a starting budget (0 or more).';
                  }
                  final double? amount = double.tryParse(raw);
                  if (amount == null || !amount.isFinite) {
                    return 'Enter a valid amount.';
                  }
                  if (amount < 0) {
                    return 'Budget cannot be negative.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Event type',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _types
                    .map(
                      (String t) => DropdownMenuItem<String>(
                        value: t,
                        child: Text(t),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _type = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _schoolYearController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'School year / term (optional)',
                  hintText: 'e.g. SY 2026-2027 · 1st Sem',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEdit ? 'Save changes' : 'Create event'),
        ),
      ],
    );
  }
}

class _ManageBudgetEventsSheet extends StatefulWidget {
  const _ManageBudgetEventsSheet({
    required this.onCreate,
    required this.onEdit,
  });

  final Future<void> Function() onCreate;
  final Future<void> Function(OrgEvent event) onEdit;

  @override
  State<_ManageBudgetEventsSheet> createState() =>
      _ManageBudgetEventsSheetState();
}

class _ManageBudgetEventsSheetState extends State<_ManageBudgetEventsSheet> {
  late Future<List<OrgEvent>> _future;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<LedgerProvider>().fetchAllEventsForManagement();
  }

  void _reload() {
    setState(() {
      _future = context.read<LedgerProvider>().fetchAllEventsForManagement();
    });
  }

  Future<void> _toggleArchive(OrgEvent event) async {
    final UserRoleProvider session = context.read<UserRoleProvider>();
    final LedgerProvider ledger = context.read<LedgerProvider>();
    final AppUser? actor = session.currentUser;
    if (actor == null) {
      return;
    }
    final bool archive = !event.isArchived;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:
            Text(archive ? 'Archive budget event?' : 'Restore budget event?'),
        content: Text(
          archive
              ? '"${event.title}" will be hidden from the active event picker, but its expenses and records will be kept for history.'
              : '"${event.title}" will be available again in the active event picker.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(archive ? 'Archive' : 'Restore'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }
    final LedgerActionResult result = await ledger.setBudgetEventArchived(
      actor: actor,
      event: event,
      archived: archive,
    );
    if (!mounted) {
      return;
    }
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
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Budget events',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: widget.onCreate,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Create a new event for each semester, school year, or project. Archive completed periods to keep history.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show archived events'),
                value: _showArchived,
                onChanged: (bool value) =>
                    setState(() => _showArchived = value),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<OrgEvent>>(
                  future: _future,
                  builder: (
                    BuildContext context,
                    AsyncSnapshot<List<OrgEvent>> snap,
                  ) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final List<OrgEvent> all =
                        snap.data ?? const <OrgEvent>[];
                    final List<OrgEvent> visible = all
                        .where((OrgEvent e) => _showArchived || !e.isArchived)
                        .toList(growable: false);
                    if (visible.isEmpty) {
                      return Center(
                        child: Text(
                          _showArchived
                              ? 'No budget events found.'
                              : 'No active budget events. Show archived or create a new one.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: visible.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final OrgEvent e = visible[index];
                        final String meta = <String>[
                          if (e.eventType.trim().isNotEmpty)
                            e.eventType.trim(),
                          if (e.schoolYear.trim().isNotEmpty)
                            e.schoolYear.trim(),
                          if (e.isArchived) 'Archived',
                        ].join(' · ');
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            title: Text(
                              e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${AppFormat.currency(e.startingBudget)}'
                              '${meta.isEmpty ? '' : ' · $meta'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Wrap(
                              spacing: 0,
                              children: <Widget>[
                                IconButton(
                                  tooltip:
                                      e.isArchived ? 'Restore' : 'Archive',
                                  icon: Icon(
                                    e.isArchived
                                        ? Icons.unarchive_outlined
                                        : Icons.archive_outlined,
                                  ),
                                  onPressed: () => _toggleArchive(e),
                                ),
                                IconButton(
                                  tooltip: 'Edit',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => widget.onEdit(e),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
