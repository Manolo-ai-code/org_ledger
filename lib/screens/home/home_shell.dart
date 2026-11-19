import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models/user_role.dart';
import '../../providers/audit_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/user_role_provider.dart';
import '../approvals/approval_feed_screen.dart';
import '../audit/audit_log_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../expenses/add_expense_screen.dart';
import '../expenses/expenses_screen.dart';
import '../members/members_screen.dart';
import '../profile/profile_screen.dart';

/// Authenticated application shell.
///
/// The bottom navigation is generated from the signed-in officer's role. There
/// is no role switcher: permissions change only by signing in with another
/// account.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  List<_ShellTab> _tabsFor(UserRole role) {
    final List<_ShellTab> tabs = <_ShellTab>[
      const _ShellTab(
        label: 'Dashboard',
        icon: Icons.space_dashboard_outlined,
        selectedIcon: Icons.space_dashboard_rounded,
        screen: DashboardScreen(),
        isAudit: false,
        showsFab: true,
      ),
    ];
    if (role.isReviewer) {
      tabs.add(
        const _ShellTab(
          label: 'Approvals',
          icon: Icons.fact_check_outlined,
          selectedIcon: Icons.fact_check_rounded,
          screen: ApprovalFeedScreen(),
          isAudit: false,
          isApprovals: true,
        ),
      );
    }
    if (role.canManageMembers) {
      tabs.add(
        const _ShellTab(
          label: 'Members',
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups_rounded,
          screen: MembersScreen(),
          isAudit: false,
        ),
      );
    }
    tabs.add(
      const _ShellTab(
        label: 'Expenses',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        screen: ExpensesScreen(),
        isAudit: false,
        showsFab: true,
      ),
    );
    if (role.isOfficer) {
      tabs.add(
        const _ShellTab(
          label: 'Audit',
          icon: Icons.history_rounded,
          selectedIcon: Icons.history_toggle_off_rounded,
          screen: AuditLogScreen(),
          isAudit: true,
        ),
      );
    }
    tabs.add(
      const _ShellTab(
        label: 'Profile',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        screen: ProfileScreen(),
        isAudit: false,
      ),
    );
    return tabs;
  }

  void _select(int index, List<_ShellTab> tabs) {
    if (index < 0 || index >= tabs.length) {
      return;
    }
    setState(() => _index = index);
    // The audit trail is cached to avoid a query on every build; refresh it
    // whenever the officer opens the tab so new actions are visible.
    if (tabs[index].isAudit) {
      context.read<AuditProvider>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final UserRoleProvider session = context.watch<UserRoleProvider>();
    final LedgerProvider ledger = context.watch<LedgerProvider>();
    final UserRole role = session.role ?? UserRole.member;
    final List<_ShellTab> tabs = _tabsFor(role);
    final int index = _index.clamp(0, tabs.length - 1).toInt();
    final bool showFab = session.canSubmitExpenses && tabs[index].showsFab;

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: tabs.map((_ShellTab tab) => tab.screen).toList(growable: false),
      ),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: () => openAddExpenseScreen(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add expense'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (int value) => _select(value, tabs),
        destinations: tabs
            .map(
              (_ShellTab tab) => NavigationDestination(
                icon: _maybeBadge(
                  tab: tab,
                  ledger: ledger,
                  role: role,
                  child: Icon(tab.icon),
                ),
                selectedIcon: _maybeBadge(
                  tab: tab,
                  ledger: ledger,
                  role: role,
                  child: Icon(tab.selectedIcon),
                ),
                label: tab.label,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _maybeBadge({
    required _ShellTab tab,
    required LedgerProvider ledger,
    required UserRole role,
    required Widget child,
  }) {
    if (!tab.isApprovals) {
      return child;
    }
    final int count = ledger.awaitingMyReviewCount(role);
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: child,
    );
  }
}

class _ShellTab {
  const _ShellTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
    required this.isAudit,
    this.isApprovals = false,
    this.showsFab = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
  final bool isAudit;
  final bool isApprovals;
  final bool showsFab;
}
