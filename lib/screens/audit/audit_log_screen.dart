import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/expense_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../data/models/audit_log.dart';
import '../../providers/audit_provider.dart';
import '../../widgets/banners.dart';
import '../../widgets/empty_state.dart';

/// Read-only, append-only audit trail for expense records.
///
/// Tracks expense create/submit, approval and stage transitions, reject/flag
/// actions (with remarks), and expense-related liquidation/sync actions.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<AuditProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AuditLog> _filtered(List<AuditLog> logs) {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return logs;
    }
    return logs.where((AuditLog log) {
      final String statusLabel = ExpenseStatus.label(log.status).toLowerCase();
      return log.action.toLowerCase().contains(query) ||
          log.performedBy.toLowerCase().contains(query) ||
          log.expenseTitle.toLowerCase().contains(query) ||
          log.status.toLowerCase().contains(query) ||
          statusLabel.contains(query) ||
          log.remarks.toLowerCase().contains(query) ||
          log.expenseId.toString().contains(query) ||
          log.amount.toStringAsFixed(2).contains(query) ||
          AppFormat.currency(log.amount).toLowerCase().contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuditProvider audit = context.watch<AuditProvider>();
    final List<AuditLog> logs = _filtered(audit.logs);
    final Map<String, List<AuditLog>> grouped = <String, List<AuditLog>>{};
    for (final AuditLog log in logs) {
      final String key = log.timestamp.millisecondsSinceEpoch <= 0
          ? 'Earlier'
          : AppFormat.date(log.timestamp);
      grouped.putIfAbsent(key, () => <AuditLog>[]).add(log);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Audit trail'),
            Text(
              'Expense-linked activity only',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh audit trail',
            onPressed: audit.isLoading ? null : audit.refresh,
            icon: audit.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: audit.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          children: <Widget>[
            if (audit.error != null) ...<Widget>[
              ErrorBanner(
                message: audit.error ?? '',
                onRetry: audit.refresh,
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _searchController,
              onChanged: (String value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search expense, status, action, officer, amount, or ID',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.info.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 17,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Entries are read-only and limited to expense records: '
                      'submissions, workflow actions, reject/flag remarks, '
                      'and expense-related liquidation/sync activity.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (audit.isLoading && audit.logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (logs.isEmpty)
              SizedBox(
                height: 340,
                child: EmptyState(
                  icon: Icons.history_toggle_off_rounded,
                  title: _query.isEmpty
                      ? 'No expense activity recorded yet'
                      : 'No matching entries',
                  message: _query.isEmpty
                      ? 'Expense submissions, reviews, syncs, and liquidation exports will appear here.'
                      : 'Try a different expense title, ID, status, officer, or action.',
                  actionLabel: _query.isEmpty ? 'Reload' : 'Clear search',
                  onAction: () {
                    if (_query.isEmpty) {
                      audit.refresh();
                    } else {
                      _searchController.clear();
                      setState(() => _query = '');
                    }
                  },
                ),
              )
            else ...<Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '${logs.length} ${logs.length == 1 ? 'entry' : 'entries'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Newest first',
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
              ...grouped.entries.map(
                (MapEntry<String, List<AuditLog>> group) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.emerald,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            group.key,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Card(
                        child: Column(
                          children: group.value
                              .asMap()
                              .entries
                              .map(
                                (MapEntry<int, AuditLog> entry) => Column(
                                  children: <Widget>[
                                    _AuditTile(log: entry.value),
                                    if (entry.key < group.value.length - 1)
                                      const Padding(
                                        padding:
                                            EdgeInsets.symmetric(horizontal: 14),
                                        child: Divider(height: 1),
                                      ),
                                  ],
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ],
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

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.log});

  final AuditLog log;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final _AuditVisual visual = _visualFor(log);
    final String statusLabel = log.status.trim().isEmpty
        ? 'Unknown status'
        : ExpenseStatus.label(log.status);
    final String expenseTitle = log.expenseTitle.trim().isEmpty
        ? 'Expense record'
        : log.expenseTitle.trim();
    final String when = log.timestamp.millisecondsSinceEpoch <= 0
        ? 'Unknown time'
        : '${AppFormat.date(log.timestamp)} · ${AppFormat.time(log.timestamp)}';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: visual.color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(visual.icon, size: 18, color: visual.color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  log.action,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '#${log.expenseId} · $expenseTitle',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    _MetaChip(
                      label: AppFormat.currency(log.amount),
                      color: theme.colorScheme.primary,
                    ),
                    _MetaChip(
                      label: statusLabel,
                      color: visual.color,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${log.performedBy} · $when',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (log.remarks.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'Remarks: ${log.remarks.trim()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
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

  static _AuditVisual _visualFor(AuditLog log) {
    final String text =
        '${log.action} ${log.status} ${log.remarks}'.toLowerCase();
    if (text.contains('reject')) {
      return const _AuditVisual(Icons.cancel_outlined, AppColors.danger);
    }
    if (text.contains('flag')) {
      return const _AuditVisual(Icons.flag_outlined, AppColors.warning);
    }
    if (text.contains('approve') ||
        text.contains('endorse') ||
        text.contains('locked') ||
        text.contains('advance')) {
      return const _AuditVisual(Icons.task_alt_rounded, AppColors.emerald);
    }
    if (text.contains('export') || text.contains('liquidation')) {
      return const _AuditVisual(Icons.picture_as_pdf_outlined, AppColors.info);
    }
    if (text.contains('sync')) {
      return const _AuditVisual(Icons.cloud_sync_outlined, AppColors.info);
    }
    if (text.contains('submit') || text.contains('created')) {
      return const _AuditVisual(Icons.upload_file_outlined, AppColors.info);
    }
    return const _AuditVisual(Icons.receipt_long_outlined, AppColors.info);
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _AuditVisual {
  const _AuditVisual(this.icon, this.color);

  final IconData icon;
  final Color color;
}
