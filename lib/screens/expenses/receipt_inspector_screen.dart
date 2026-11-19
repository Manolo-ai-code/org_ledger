import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/expense_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/utils/app_format.dart';
import '../../data/models/expense.dart';
import '../../data/models/user_role.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/status_chip.dart';

/// Detail page for a single expense.
///
/// Shows the full approval chain, the receipt (zoomable) and, when the signed-in
/// officer's tier matches the expense's current status, the approve / reject /
/// flag actions.
class ExpenseInspectorScreen extends StatelessWidget {
  const ExpenseInspectorScreen({super.key, required this.expense});

  final Expense expense;

  /// Always reads the freshest copy from the provider so actions taken here are
  /// reflected immediately without popping the page.
  Expense _resolve(LedgerProvider ledger) {
    for (final Expense candidate in ledger.expenses) {
      if (candidate.id == expense.id) {
        return candidate;
      }
    }
    return expense;
  }

  Future<void> _review(
    BuildContext context, {
    required ReviewAction action,
  }) async {
    final UserRoleProvider session = context.read<UserRoleProvider>();
    final LedgerProvider ledger = context.read<LedgerProvider>();
    final UserRole? role = session.role;
    if (role == null) {
      return;
    }

    String remarks = '';
    if (action != ReviewAction.approve) {
      final bool reject = action == ReviewAction.reject;
      final String? entered = await showRemarkDialog(
        context: context,
        title: reject ? 'Reject this expense?' : 'Flag this expense?',
        description: reject
            ? 'Rejection is final for this record. The submitter will see your remark and must submit a corrected expense.'
            : 'Flagging pauses this record and notifies the submitter. Your remark is required.',
        confirmLabel: reject ? 'Reject expense' : 'Flag expense',
        confirmColor: reject
            ? Theme.of(context).colorScheme.error
            : AppColors.warning,
        suggestions: reject
            ? const <String>[
                'Receipt is unreadable',
                'Amount does not match receipt',
                'Purchase is outside the approved budget',
                'Duplicate entry',
              ]
            : const <String>[
                'Receipt photo is blurry',
                'Needs a clearer breakdown',
                'Please confirm the supplier',
              ],
      );
      if (!context.mounted || entered == null) {
        return;
      }
      remarks = entered;
    } else {
      final String? next = ExpenseStatus.next(_resolve(ledger).status);
      final bool confirmed = await showConfirmDialog(
        context: context,
        title: 'Approve and forward?',
        message: next == null
            ? 'This expense will be locked as the final approved record.'
            : 'This expense will move to ${ExpenseStatus.label(next)}.',
        confirmLabel: role == UserRole.adviser ? 'Grant final approval' : 'Approve',
      );
      if (!context.mounted || !confirmed) {
        return;
      }
    }

    final LedgerActionResult result = await ledger.reviewExpense(
      expense: _resolve(ledger),
      role: role,
      actorName: session.actorLabel,
      action: action,
      remarks: remarks,
    );
    if (!context.mounted) {
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
  }

  void _openReceipt(BuildContext context, String path) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ReceiptViewerScreen(path: path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LedgerProvider ledger = context.watch<LedgerProvider>();
    final Expense current = _resolve(ledger);
    final UserRoleProvider session = context.watch<UserRoleProvider>();
    final Color accent = CategoryVisuals.color(current.category);
    final bool canAct = session.canActOn(current);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Expense details'),
            Text(
              current.reference,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: canAct
          ? _ReviewBar(
              expense: current,
              role: session.role,
              onApprove: () => _review(context, action: ReviewAction.approve),
              onReject: () => _review(context, action: ReviewAction.reject),
              onFlag: () => _review(context, action: ReviewAction.flag),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: <Widget>[
          _HeaderCard(expense: current, accent: accent),
          const SizedBox(height: 12),
          _DetailsCard(expense: current, accent: accent),
          const SizedBox(height: 12),
          _WorkflowCard(expense: current),
          const SizedBox(height: 12),
          _ReceiptCard(
            expense: current,
            onOpen: (String path) => _openReceipt(context, path),
          ),
          if (current.remarks.trim().isNotEmpty && current.needsAttention) ...<Widget>[
            const SizedBox(height: 12),
            _RemarkCard(expense: current),
          ],
          if (canAct) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 18,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'You are acting as ${session.actorLabel}. Approving forwards this '
                      'expense to the next tier; only final Adviser approval affects the budget.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.expense, required this.accent});

  final Expense expense;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    CategoryVisuals.icon(expense.category),
                    color: accent,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        expense.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        expense.displayCategory,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Text(
                    AppFormat.currency(expense.amount),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                StatusChip(status: expense.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.expense, required this.accent});

  final Expense expense;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Record information', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _row(theme, 'Reference', expense.reference),
            _row(
              theme,
              'Submitted by',
              expense.submittedByName.trim().isEmpty
                  ? 'Officer #${expense.submittedBy}'
                  : expense.submittedByName,
            ),
            _row(
              theme,
              'Event',
              expense.eventTitle.trim().isEmpty
                  ? 'Current event'
                  : expense.eventTitle,
            ),
            _row(theme, 'Submitted', AppFormat.dateTime(expense.createdAt)),
            _row(theme, 'Last update', AppFormat.dateTime(expense.updatedAt)),
            _row(
              theme,
              'Sync state',
              expense.isSynced
                  ? 'Synced with server'
                  : 'Stored offline · pending sync',
              valueColor:
                  expense.isSynced ? AppColors.emerald : AppColors.warning,
            ),
            _row(
              theme,
              'Receipt',
              expense.hasReceipt ? 'Attached' : 'Missing',
              valueColor: expense.hasReceipt ? null : theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool stopped = expense.needsAttention;
    final int activeStep = ExpenseStatus.step(expense.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  stopped ? Icons.pause_circle_outline : Icons.route_outlined,
                  size: 18,
                  color: stopped
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 7),
                Text('Approval chain', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              stopped
                  ? 'This record left the normal chain with a mandatory remark.'
                  : 'Each tier must approve before the next can act.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            ...List<Widget>.generate(_WorkflowStep.values.length, (int index) {
              final _WorkflowStep step = _WorkflowStep.values[index];
              final int stepNumber = index + 1;
              final bool done = !stopped && activeStep > stepNumber;
              final bool current = !stopped && activeStep == stepNumber;
              final bool isLast = index == _WorkflowStep.values.length - 1;
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done
                                ? AppColors.emerald
                                : current
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.surfaceContainerHighest,
                            border: current
                                ? Border.all(
                                    color: theme.colorScheme.primary,
                                    width: 1.6,
                                  )
                                : null,
                          ),
                          child: Center(
                            child: done
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  )
                                : Text(
                                    '$stepNumber',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: current
                                          ? theme.colorScheme.onPrimaryContainer
                                          : theme
                                              .colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin:
                                  const EdgeInsets.symmetric(vertical: 2),
                              color: done
                                  ? AppColors.emerald.withValues(alpha: 0.5)
                                  : theme.colorScheme.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              step.label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight:
                                    current ? FontWeight.w700 : FontWeight.w600,
                                color: done || current
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              step.description,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (current)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          'Current',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

enum _WorkflowStep {
  pending('Submitted', 'Business Manager / Secretary'),
  treasurer('Treasurer verified', 'Receipt and disbursement check'),
  auditor('Auditor checked', 'Arithmetic and policy check'),
  president('President endorsed', 'Endorsement for final approval'),
  adviser('Adviser approved', 'Locks the expense for liquidation');

  const _WorkflowStep(this.label, this.description);

  final String label;
  final String description;
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.expense, required this.onOpen});

  final Expense expense;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String path = expense.receiptImagePath.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('Official receipt', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (path.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      'Tap to zoom',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.emerald,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (path.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 30),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 32,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No receipt attached',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => onOpen(path),
                  child: Stack(
                    children: <Widget>[
                      Container(
                        height: 220,
                        width: double.infinity,
                        color: theme.colorScheme.surfaceContainerHigh,
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                          ) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.broken_image_outlined,
                                    size: 34,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Receipt file is unavailable on this device',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.zoom_in_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RemarkCard extends StatelessWidget {
  const _RemarkCard({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool rejected = expense.isRejected;
    final Color accent =
        rejected ? theme.colorScheme.error : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            rejected ? Icons.cancel_outlined : Icons.flag_outlined,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  rejected ? 'Rejected by a reviewer' : 'Flagged by a reviewer',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  expense.remarks,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Remark required by the workflow policy.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewBar extends StatelessWidget {
  const _ReviewBar({
    required this.expense,
    required this.role,
    required this.onApprove,
    required this.onReject,
    required this.onFlag,
  });

  final Expense expense;
  final UserRole? role;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onFlag;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                role == UserRole.adviser
                    ? 'Final approval is irreversible and counts toward the official budget.'
                    : 'Approving forwards this record to the next approval tier.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(
                          color: theme.colorScheme.error.withValues(alpha: 0.5),
                        ),
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        role == UserRole.adviser ? 'Approve final' : 'Approve',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              TextButton.icon(
                onPressed: onFlag,
                icon: const Icon(Icons.flag_outlined, size: 17),
                label: const Text('Flag for correction instead'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.warning,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen pinch-to-zoom receipt viewer.
class ReceiptViewerScreen extends StatefulWidget {
  const ReceiptViewerScreen({super.key, required this.path});

  final String path;

  @override
  State<ReceiptViewerScreen> createState() => _ReceiptViewerScreenState();
}

class _ReceiptViewerScreenState extends State<ReceiptViewerScreen> {
  final TransformationController _controller = TransformationController();
  bool _darkBackground = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBackground ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.85),
        foregroundColor: Colors.white,
        title: const Text('Receipt'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Reset zoom',
            onPressed: () => _controller.value = Matrix4.identity(),
            icon: const Icon(Icons.fit_screen_outlined),
          ),
          IconButton(
            tooltip: _darkBackground ? 'Light background' : 'Dark background',
            onPressed: () {
              setState(() => _darkBackground = !_darkBackground);
            },
            icon: Icon(
              _darkBackground
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 0.8,
                maxScale: 6,
                boundaryMargin: const EdgeInsets.all(60),
                child: Center(
                  child: Image.file(
                    File(widget.path),
                    fit: BoxFit.contain,
                    errorBuilder: (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.broken_image_outlined,
                              size: 44,
                              color: Colors.white70,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'This receipt file is no longer available on the device.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              color: Colors.black.withValues(alpha: 0.85),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(
                    Icons.pinch_outlined,
                    size: 15,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Pinch to zoom · drag to pan · use Reset zoom above',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white70,
                          ),
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
