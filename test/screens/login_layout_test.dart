import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:org_ledger/core/theme/app_theme.dart';
import 'package:org_ledger/data/database/database_helper.dart';
import 'package:org_ledger/data/repositories/auth_repository.dart';
import 'package:org_ledger/providers/theme_provider.dart';
import 'package:org_ledger/providers/user_role_provider.dart';
import 'package:org_ledger/screens/auth/login_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Login screen fits a narrow phone without overflow', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final DatabaseHelper db = DatabaseHelper(seedDemoData: false);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(db),
          ),
          ChangeNotifierProvider<UserRoleProvider>(
            create: (_) => _IdleSession(
              authRepository: AuthRepository(db),
              databaseHelper: db,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LoginScreen(),
        ),
      ),
    );

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign in securely'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// The real provider starts in a restoring state; this double skips the splash
/// gate so the login form renders immediately.
class _IdleSession extends UserRoleProvider {
  _IdleSession({
    required super.authRepository,
    required super.databaseHelper,
  });

  @override
  bool get isRestoring => false;
}
