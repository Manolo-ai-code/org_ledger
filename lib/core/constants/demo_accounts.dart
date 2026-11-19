import '../../data/models/user_role.dart';

/// Convenience demo credentials shown on the login screen.
class DemoAccount {
  const DemoAccount({
    required this.role,
    required this.name,
    required this.email,
  });

  final UserRole role;
  final String name;
  final String email;
}

const List<DemoAccount> demoAccounts = <DemoAccount>[
  DemoAccount(
    role: UserRole.businessManager,
    name: 'Bea Manalo',
    email: 'bm@orgledger.app',
  ),
  DemoAccount(
    role: UserRole.secretary,
    name: 'Sam Rivera',
    email: 'secretary@orgledger.app',
  ),
  DemoAccount(
    role: UserRole.treasurer,
    name: 'Tessa Cruz',
    email: 'treasurer@orgledger.app',
  ),
  DemoAccount(
    role: UserRole.auditor,
    name: 'Audie Reyes',
    email: 'auditor@orgledger.app',
  ),
  DemoAccount(
    role: UserRole.president,
    name: 'Perry Santos',
    email: 'president@orgledger.app',
  ),
  DemoAccount(
    role: UserRole.adviser,
    name: 'Ada Villanueva',
    email: 'adviser@orgledger.app',
  ),
];
