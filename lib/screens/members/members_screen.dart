import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/role_visuals.dart';
import '../../core/utils/validators.dart';
import '../../data/models/app_user.dart';
import '../../data/models/user_role.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/banners.dart';
import '../../widgets/empty_state.dart';

/// Adviser/manager view for member accounts and turnover (Stage 2).
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

enum _MemberFilter { all, active, inactive }

class _MembersScreenState extends State<MembersScreen> {
  _MemberFilter _filter = _MemberFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<UserRoleProvider>().loadManagedUsers();
    });
  }

  List<AppUser> _apply(List<AppUser> users) {
    final q = _query.trim().toLowerCase();
    return users.where((u) {
      final matchesFilter = switch (_filter) {
        _MemberFilter.all => true,
        _MemberFilter.active => u.isActive,
        _MemberFilter.inactive => !u.isActive,
      };
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      return u.name.toLowerCase().contains(q) ||
          u.username.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          u.role.label.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  Future<void> _showAppointDialog(AppUser target) async {
    final session = context.read<UserRoleProvider>();
    final users = session.managedUsers;
    UserRole selectedRole = target.role;
    final termController = TextEditingController(text: target.term);
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final busy = session.isBusy;
            final AppUser? currentHolder = users.cast<AppUser?>().firstWhere(
                  (u) =>
                      u != null &&
                      u.id != target.id &&
                      u.isActive &&
                      selectedRole.isOfficer &&
                      u.role == selectedRole,
                  orElse: () => null,
                );
            return AlertDialog(
              title: const Text('Appoint / change role'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${target.name} (@${target.username})',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<UserRole>(
                      initialValue: selectedRole,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Role / seat',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      items: UserRole.values
                          .map(
                            (role) => DropdownMenuItem<UserRole>(
                              value: role,
                              child: Text(role.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: busy
                          ? null
                          : (v) {
                              if (v != null) setState(() => selectedRole = v);
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: termController,
                      decoration: const InputDecoration(
                        labelText: 'Term / school year (optional)',
                        hintText: 'e.g. 2026-2027',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                    if (currentHolder != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Seat is single-holder: ${currentHolder.name} (@${currentHolder.username}) '
                          'currently holds ${selectedRole.label} and will be demoted to active Member if you continue.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                    if (error != null) ...<Widget>[
                      const SizedBox(height: 10),
                      ErrorBanner(message: error ?? ''),
                    ],
                  ],
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
                          if (currentHolder != null) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Confirm seat change'),
                                content: Text(
                                  'Demote ${currentHolder.name} to active Member and appoint ${target.name} as ${selectedRole.label}?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    child: const Text('Confirm'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true || !context.mounted) return;
                          }
                          final result = await session.appointRole(
                            target: target,
                            role: selectedRole,
                            term: termController.text,
                          );
                          if (!context.mounted) return;
                          if (result.success) {
                            Navigator.of(context).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
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

  Future<void> _showResetPasswordDialog(AppUser target) async {
    final session = context.read<UserRoleProvider>();
    final formKey = GlobalKey<FormState>();
    final passController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscure1 = true;
    bool obscure2 = true;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final busy = session.isBusy;
            return AlertDialog(
              title: const Text('Reset password'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'Set a new password for ${target.name} (@${target.username}). '
                        'They will be required to change it on next sign-in.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passController,
                        obscureText: obscure1,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          helperText: 'At least 8 characters',
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure1 = !obscure1),
                            icon: Icon(obscure1
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: Validators.password,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmController,
                        obscureText: obscure2,
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure2 = !obscure2),
                            icon: Icon(obscure2
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: (v) => Validators.confirmPassword(v, passController.text),
                      ),
                      if (error != null) ...<Widget>[
                        const SizedBox(height: 10),
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
                          if (formKey.currentState?.validate() != true) return;
                          final result = await session.resetUserPassword(
                            target: target,
                            newPassword: passController.text,
                          );
                          if (!context.mounted) return;
                          if (result.success) {
                            Navigator.of(context).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
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
                      : const Text('Reset'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleActive(AppUser target) async {
    final session = context.read<UserRoleProvider>();
    final me = session.currentUser;
    if (target.isActive) {
      if (me != null && me.id == target.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot deactivate your own account while signed in.')),
        );
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Deactivate account'),
          content: Text(
            'Deactivate ${target.name}? They will not be able to sign in until reactivated. '
            'History is preserved.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Deactivate')),
          ],
        ),
      );
      if (ok != true) return;
      final result = await session.deactivateAccount(target);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    } else {
      final result = await session.reactivateAccount(target);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _showElectionDialog() async {
    final session = context.read<UserRoleProvider>();
    final users = session.managedUsers;
    if (users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No accounts available.')),
      );
      return;
    }

    final now = DateTime.now();
    final defaultTerm = '${now.year}-${now.year + 1}';
    final termController = TextEditingController(text: defaultTerm);
    final seats = <UserRole>[
      UserRole.businessManager,
      UserRole.secretary,
      UserRole.treasurer,
      UserRole.auditor,
      UserRole.president,
      UserRole.adviser,
    ];
    final Map<UserRole, int> selections = <UserRole, int>{};
    for (final seat in seats) {
      final current = users.cast<AppUser?>().firstWhere(
            (u) => u != null && u.isActive && u.role == seat,
            orElse: () => null,
          );
      selections[seat] = current?.id ?? (users.first.id);
    }
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final busy = session.isBusy;
            return AlertDialog(
              title: const Text('New school year / Apply election results'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Assign each officer seat for the term. Previous holders of assigned seats will be '
                        'demoted to active Member when replaced. At least one active Adviser is required.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: termController,
                        decoration: const InputDecoration(
                          labelText: 'School year / term',
                          hintText: 'e.g. 2026-2027',
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...seats.map((seat) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DropdownButtonFormField<int>(
                            initialValue: selections[seat],
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: seat.label,
                              prefixIcon: Icon(RoleVisuals.icon(seat), size: 20),
                            ),
                            items: users
                                .map(
                                  (u) => DropdownMenuItem<int>(
                                    value: u.id,
                                    child: Text(
                                      '${u.name} (@${u.username})${u.isActive ? '' : ' · inactive'}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: busy
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(() => selections[seat] = v);
                                    }
                                  },
                          ),
                        );
                      }),
                      if (error != null) ...<Widget>[
                        const SizedBox(height: 6),
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
                          final term = termController.text.trim();
                          if (term.isEmpty) {
                            setState(() => error = 'Please enter the term/school year.');
                            return;
                          }
                          final ids = selections.values.toList();
                          if (ids.toSet().length != ids.length) {
                            setState(() => error = 'Each officer seat must be assigned to a different person.');
                            return;
                          }
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Apply election results'),
                              content: Text(
                                'Apply assignments for "$term"? Replaced seat holders will be demoted to active Members.',
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Apply')),
                              ],
                            ),
                          );
                          if (ok != true || !context.mounted) return;
                          final result = await session.applyElectionResults(
                            term: term,
                            assignments: Map<UserRole, int>.from(selections),
                          );
                          if (!context.mounted) return;
                          if (result.success) {
                            Navigator.of(context).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(content: Text(result.message)),
                              );
                            }
                          } else {
                            setState(() => error = result.message);
                          }
                        },
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<UserRoleProvider>();
    if (!session.canManageMembers) {
      return const Scaffold(
        body: Center(child: Text('Only the Adviser can manage members.')),
      );
    }

    final theme = Theme.of(context);
    final users = _apply(session.managedUsers);
    final me = session.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members & turnover'),
        actions: <Widget>[
          IconButton(
            tooltip: 'New school year / Apply election results',
            onPressed: session.isBusy ? null : _showElectionDialog,
            icon: const Icon(Icons.event_repeat_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: session.isBusy ? null : () => session.loadManagedUsers(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: <Widget>[
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search name, username, role...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _filter == _MemberFilter.all,
                      onSelected: (_) => setState(() => _filter = _MemberFilter.all),
                    ),
                    ChoiceChip(
                      label: const Text('Active'),
                      selected: _filter == _MemberFilter.active,
                      onSelected: (_) => setState(() => _filter = _MemberFilter.active),
                    ),
                    ChoiceChip(
                      label: const Text('Inactive'),
                      selected: _filter == _MemberFilter.inactive,
                      onSelected: (_) => setState(() => _filter = _MemberFilter.inactive),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (session.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ErrorBanner(message: session.error ?? ''),
            ),
          Expanded(
            child: session.isBusy && session.managedUsers.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : users.isEmpty
                    ? EmptyState(
                        icon: Icons.groups_outlined,
                        title: 'No members found',
                        message: _query.isEmpty
                            ? 'Registered accounts will appear here.'
                            : 'Try a different search or filter.',
                      )
                    : RefreshIndicator(
                        onRefresh: () => session.loadManagedUsers(),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: users.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final u = users[index];
                            final isSelf = me != null && me.id == u.id;
                            final roleColor = RoleVisuals.color(u.role);
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: roleColor.withValues(alpha: 0.15),
                                  foregroundColor: roleColor,
                                  child: Text(u.initials),
                                ),
                                title: Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        u.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSelf)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Text(
                                          'You',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text('@${u.username}${u.email.isNotEmpty ? ' · ${u.email}' : ''}'),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: <Widget>[
                                        _chip(context, u.role.label, roleColor),
                                        _chip(
                                          context,
                                          u.isActive ? 'Active' : 'Inactive',
                                          u.isActive
                                              ? const Color(0xFF0E7C66)
                                              : theme.colorScheme.outline,
                                        ),
                                        if (u.term.isNotEmpty) _chip(context, u.term, theme.colorScheme.secondary),
                                      ],
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'appoint':
                                        _showAppointDialog(u);
                                        break;
                                      case 'reset':
                                        _showResetPasswordDialog(u);
                                        break;
                                      case 'toggle':
                                        _toggleActive(u);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                                    const PopupMenuItem<String>(
                                      value: 'appoint',
                                      child: Text('Appoint / change role'),
                                    ),
                                    const PopupMenuItem<String>(
                                      value: 'reset',
                                      child: Text('Reset password'),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'toggle',
                                      child: Text(u.isActive ? 'Deactivate' : 'Reactivate'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
