import '../../data/models/user_role.dart';

/// Convenience demo credentials shown on the login screen (demo builds only).
class DemoAccount {
  const DemoAccount({
    required this.role,
    required this.name,
    required this.username,
  });

  final UserRole role;
  final String name;
  final String username;
}

const List<DemoAccount> demoAccounts = <DemoAccount>[
  DemoAccount(
    role: UserRole.businessManager,
    name: 'Bea Manalo',
    username: 'bm',
  ),
  DemoAccount(
    role: UserRole.secretary,
    name: 'Sam Rivera',
    username: 'secretary',
  ),
  DemoAccount(
    role: UserRole.treasurer,
    name: 'Tessa Cruz',
    username: 'treasurer',
  ),
  DemoAccount(
    role: UserRole.auditor,
    name: 'Audie Reyes',
    username: 'auditor',
  ),
  DemoAccount(
    role: UserRole.president,
    name: 'Perry Santos',
    username: 'president',
  ),
  DemoAccount(
    role: UserRole.adviser,
    name: 'Ada Villanueva',
    username: 'adviser',
  ),
];
