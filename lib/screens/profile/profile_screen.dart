import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/expense_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/role_visuals.dart';
import '../../core/utils/app_format.dart';
import '../../core/utils/validators.dart';
import '../../data/models/app_user.dart';
import '../../data/models/user_role.dart';
import '../../providers/audit_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/banners.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/dialogs.dart';

/// Account, permissions, appearance and sign-out.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _editProfile(BuildContext context, AppUser user) async {
    final UserRoleProvider session = context.read<UserRoleProvider>();
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: user.name);
    final emailController = TextEditingController(text: user.email);
    String? error;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            final bool busy = session.isBusy;
            return AlertDialog(
              title: const Text('Edit profile'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: Validators.name,
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'Contact email (optional)',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: Validators.optionalEmail,
                        autocorrect: false,
                      ),
                      if (error != null) ...<Widget>[
                        const SizedBox(height: 12),
                        ErrorBanner(message: error ?? ''),
                      ],
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (formKey.currentState?.validate() != true) {
                            return;
                          }
                          final result = await session.updateProfile(
                            name: nameController.text,
                            email: emailController.text,
                          );
                          if (!context.mounted) return;
                          if (result.success) {
                            Navigator.of(context).pop();
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text(result.message)),
                              );
                            }
                          } else {
                            setState(() => error = result.message);
                          }
                        },
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final UserRoleProvider session = context.read<UserRoleProvider>();
    final formKey = GlobalKey<FormState>();
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            final bool busy = session.isBusy;
            return AlertDialog(
              title: const Text('Change password'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        controller: currentController,
                        obscureText: obscureCurrent,
                        decoration: InputDecoration(
                          labelText: 'Current password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => obscureCurrent = !obscureCurrent,
                            ),
                            icon: Icon(
                              obscureCurrent
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Enter your current password'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: newController,
                        obscureText: obscureNew,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          helperText: 'At least 8 characters',
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => obscureNew = !obscureNew),
                            icon: Icon(
                              obscureNew
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: Validators.password,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmController,
                        obscureText: obscureConfirm,
                        decoration: InputDecoration(
                          labelText: 'Confirm new password',
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => obscureConfirm = !obscureConfirm,
                            ),
                            icon: Icon(
                              obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => Validators.confirmPassword(
                          v,
                          newController.text,
                        ),
                      ),
                      if (error != null) ...<Widget>[
                        const SizedBox(height: 12),
                        ErrorBanner(message: error ?? ''),
                      ],
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (formKey.currentState?.validate() != true) {
                            return;
                          }
                          final result = await session.changePassword(
                            currentPassword: currentController.text,
                            newPassword: newController.text,
                          );
                          if (!context.mounted) return;
                          if (result.success) {
                            Navigator.of(context).pop();
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text(result.message)),
                              );
                            }
                          } else {
                            setState(() => error = result.message);
                          }
                        },
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final UserRoleProvider session = context.read<UserRoleProvider>();
    final LedgerProvider ledger = context.read<LedgerProvider>();
    final AuditProvider audit = context.read<AuditProvider>();

    final bool confirmed = await showConfirmDialog(
      context: context,
      title: 'Sign out of OrgLedger?',
      message:
          'Your local ledger stays on this device. You will need your credentials '
          'to sign back in.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }

    // Clear the session first so the auth gate swaps to login immediately,
    // then drop role-scoped ledger/audit state.
    await session.logout();
    await ledger.reset();
    audit.reset();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final UserRoleProvider session = context.watch<UserRoleProvider>();
    final LedgerProvider ledger = context.watch<LedgerProvider>();
    final ThemeProvider themes = context.watch<ThemeProvider>();
    final AppUser? user = session.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final UserRole role = user.role;
    final Color roleColor = RoleVisuals.color(role);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Profile'),
            Text(
              'Signed in as ${role.label}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              roleColor,
                              Color.lerp(roleColor, Colors.black, 0.22) ??
                                  roleColor,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            user.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.displayHandle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (user.email.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 1),
                              Text(
                                user.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: roleColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          RoleVisuals.icon(role),
                          size: 19,
                          color: roleColor,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '${role.label} · ${RoleVisuals.tier(role)}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: roleColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                role.responsibility,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (user.mustChangePassword) ...<Widget>[
                    const SizedBox(height: 10),
                    const ErrorBanner(
                      message:
                          'Your password was reset. Please change it to keep your account secure.',
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: session.isBusy
                            ? null
                            : () => _editProfile(context, user),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit profile'),
                      ),
                      OutlinedButton.icon(
                        onPressed: session.isBusy
                            ? null
                            : () => _changePassword(context),
                        icon: const Icon(Icons.lock_reset_rounded, size: 18),
                        label: const Text('Change password'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(
                    title: 'Permissions',
                    subtitle: 'Bound to this signed-in account only',
                  ),
                  const SizedBox(height: 12),
                  _PermissionRow(
                    icon: Icons.add_card_outlined,
                    label: 'Submit expenses',
                    granted: session.canSubmitExpenses,
                    detail: session.canSubmitExpenses
                        ? (role == UserRole.member
                            ? 'You can submit and view your own expense requests.'
                            : 'You can add expenses with receipts.')
                        : 'You cannot submit expenses with this account.',
                  ),
                  _PermissionRow(
                    icon: Icons.fact_check_outlined,
                    label: 'Review expenses',
                    granted: session.canReviewExpenses,
                    detail: session.canReviewExpenses
                        ? 'Your tier acts on ${ExpenseStatus.label(session.reviewableStatus)}.'
                        : (role == UserRole.member
                            ? 'Members cannot review approvals.'
                            : 'Submitters do not review approvals.'),
                  ),
                  _PermissionRow(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'Export liquidation',
                    granted: ledger.approvedExpenses.isNotEmpty,
                    detail: ledger.approvedExpenses.isNotEmpty
                        ? '${ledger.approvedExpenses.length} approved '
                            '${ledger.approvedExpenses.length == 1 ? 'expense' : 'expenses'} ready.'
                        : 'Requires at least one Adviser-approved expense.',
                  ),
                  _PermissionRow(
                    icon: Icons.cloud_sync_outlined,
                    label: 'Offline queue',
                    granted: true,
                    detail: ledger.pendingSyncCount == 0
                        ? 'All local records are synced.'
                        : '${ledger.pendingSyncCount} ${ledger.pendingSyncCount == 1 ? 'record is' : 'records are'} waiting to sync.',
                    isLast: true,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.switch_account_outlined,
                          size: 17,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your role and status are managed by the organization adviser. '
                            'There is no in-app role switcher.',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(
                    title: 'Appearance',
                    subtitle: 'The choice is remembered on this device',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const <ButtonSegment<ThemeMode>>[
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_outlined, size: 17),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_outlined, size: 17),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_outlined, size: 17),
                        ),
                      ],
                      selected: <ThemeMode>{themes.mode},
                      showSelectedIcon: false,
                      onSelectionChanged: (Set<ThemeMode> selection) {
                        if (selection.isNotEmpty) {
                          themes.setMode(selection.first);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(title: 'Ledger snapshot'),
                  const SizedBox(height: 12),
                  _statRow(
                    theme,
                    'Selected event',
                    ledger.selectedEvent?.title ?? 'None',
                  ),
                  _statRow(
                    theme,
                    'Starting budget',
                    AppFormat.currency(ledger.totalBudget),
                  ),
                  _statRow(
                    theme,
                    'Approved spend',
                    AppFormat.currency(ledger.totalSpent),
                  ),
                  _statRow(
                    theme,
                    'Records in ledger',
                    '${ledger.expenses.length}',
                  ),
                  _statRow(
                    theme,
                    'Audit entries retained',
                    '7 years (policy)',
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 7),
                      Text('Data & privacy', style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'OrgLedger is offline-first. Expenses, receipts and audit entries are '
                    'stored in a private SQLite database and an app-private receipts folder '
                    'on this device. Nothing is uploaded by this build.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      const BrandMark(size: 26),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${AppConstants.appName} · ${AppConstants.tagline}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(
                color: theme.colorScheme.error.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'OrgLedger v1.0 · ${AppConstants.organizationName}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(
    ThemeData theme,
    String label,
    String value, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.granted,
    required this.detail,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final bool granted;
  final String detail;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (granted ? AppColors.emerald : theme.colorScheme.outline)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 17,
              color: granted
                  ? AppColors.emerald
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      granted
                          ? Icons.check_circle_rounded
                          : Icons.remove_circle_outline_rounded,
                      size: 16,
                      color: granted
                          ? AppColors.emerald
                          : theme.colorScheme.outline,
                    ),
                  ],
                ),
                Text(
                  detail,
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
