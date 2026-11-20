import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/database/database_helper.dart';
import 'data/repositories/audit_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/expense_repository.dart';
import 'data/services/connectivity_service.dart';
import 'data/services/liquidation_pdf_service.dart';
import 'data/services/receipt_storage_service.dart';
import 'data/services/sync_service.dart';
import 'providers/audit_provider.dart';
import 'providers/ledger_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/user_role_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/setup_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/splash/splash_screen.dart';

/// Wires every repository and service once, so the widget tree only has to
/// construct providers.
class AppDependencies {
  AppDependencies({
    required this.databaseHelper,
    required this.authRepository,
    required this.auditRepository,
    required this.expenseRepository,
    required this.connectivityService,
    required this.syncService,
    required this.pdfService,
    required this.receiptStorageService,
  });

  /// Production wiring. All storage is local; the sync service is a documented
  /// stub ready for a future backend integration.
  factory AppDependencies.production() {
    final DatabaseHelper db = DatabaseHelper.instance;
    final AuditRepository audit = AuditRepository(db);
    final ExpenseRepository expenses = ExpenseRepository(db);
    final ConnectivityService connectivity = ConnectivityService();
    return AppDependencies(
      databaseHelper: db,
      authRepository: AuthRepository(db),
      auditRepository: audit,
      expenseRepository: expenses,
      connectivityService: connectivity,
      syncService: SyncService(
        expenseRepository: expenses,
        auditRepository: audit,
        connectivityService: connectivity,
      ),
      pdfService: const LiquidationPdfService(),
      receiptStorageService: ReceiptStorageService(),
    );
  }

  final DatabaseHelper databaseHelper;
  final AuthRepository authRepository;
  final AuditRepository auditRepository;
  final ExpenseRepository expenseRepository;
  final ConnectivityService connectivityService;
  final SyncService syncService;
  final LiquidationPdfService pdfService;
  final ReceiptStorageService receiptStorageService;
}

/// Root widget: providers, theme and the auth-aware navigation gate.
class OrgLedgerApp extends StatefulWidget {
  const OrgLedgerApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<OrgLedgerApp> createState() => _OrgLedgerAppState();
}

class _OrgLedgerAppState extends State<OrgLedgerApp> {
  late final ThemeProvider _themeProvider;
  late final UserRoleProvider _sessionProvider;
  late final LedgerProvider _ledgerProvider;
  late final AuditProvider _auditProvider;

  @override
  void initState() {
    super.initState();
    final AppDependencies deps = widget.dependencies;
    _themeProvider = ThemeProvider(deps.databaseHelper);
    _sessionProvider = UserRoleProvider(
      authRepository: deps.authRepository,
      databaseHelper: deps.databaseHelper,
    );
    _ledgerProvider = LedgerProvider(
      expenseRepository: deps.expenseRepository,
      auditRepository: deps.auditRepository,
      syncService: deps.syncService,
      connectivityService: deps.connectivityService,
      pdfService: deps.pdfService,
      databaseHelper: deps.databaseHelper,
    );
    _auditProvider = AuditProvider(deps.auditRepository);
  }

  @override
  void dispose() {
    _auditProvider.dispose();
    _ledgerProvider.dispose();
    _sessionProvider.dispose();
    _themeProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: _themeProvider),
        ChangeNotifierProvider<UserRoleProvider>.value(value: _sessionProvider),
        ChangeNotifierProvider<LedgerProvider>.value(value: _ledgerProvider),
        ChangeNotifierProvider<AuditProvider>.value(value: _auditProvider),
        Provider<DatabaseHelper>.value(
          value: widget.dependencies.databaseHelper,
        ),
        Provider<ReceiptStorageService>.value(
          value: widget.dependencies.receiptStorageService,
        ),
        Provider<LiquidationPdfService>.value(
          value: widget.dependencies.pdfService,
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (BuildContext context, ThemeProvider theme, Widget? child) {
          return MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: theme.mode,
            home: const _AppBootstrap(),
          );
        },
      ),
    );
  }
}

/// Restores the saved theme and session before showing login or home.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Loads theme and session. When [isRetry] is true the database helper is
  /// asked to discard any failed handle and run its recovery sequence again.
  Future<void> _bootstrap({bool isRetry = false}) async {
    if (!mounted) {
      return;
    }
    final ThemeProvider theme = context.read<ThemeProvider>();
    final UserRoleProvider session = context.read<UserRoleProvider>();
    final DatabaseHelper database = context.read<DatabaseHelper>();

    setState(() {
      _ready = false;
      _error = null;
    });

    try {
      if (isRetry) {
        await database.reopen();
      }
      await Future.wait<void>(<Future<void>>[
        theme.load(),
        session.restoreSession(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() => _ready = true);
    } catch (error, stackTrace) {
      // Keep the technical detail in logs; the splash screen shows a friendly
      // message and a retry button that runs this method again.
      debugPrint('OrgLedger database startup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _startupMessage(error);
      });
    }
  }

  static String _startupMessage(Object error) {
    if (error is DatabaseStartupException) {
      return '${error.message} Try again to rebuild the local ledger. If the '
          'problem persists, check available storage.';
    }
    return 'OrgLedger could not open its local database. Check available '
        'storage and try again.';
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return SplashScreen(
        error: _error,
        onRetry: _error == null ? null : () => _bootstrap(isRetry: true),
      );
    }
    return const AuthGate();
  }
}

/// Swaps between login and the authenticated shell.
///
/// The ledger itself is loaded only after authentication so role-scoped state
/// is always built against a known user.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _preparing = false;

  void _prepareLedger() {
    if (_preparing) {
      return;
    }
    final LedgerProvider ledger = context.read<LedgerProvider>();
    if (ledger.isInitialized) {
      return;
    }
    _preparing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final UserRoleProvider session = context.read<UserRoleProvider>();
      if (!session.isAuthenticated || ledger.isInitialized) {
        setState(() => _preparing = false);
        return;
      }
      try {
        await ledger.initialize(viewer: session.currentUser);
      } catch (_) {
        // The provider stores a friendly error and the dashboard exposes a
        // retry; never trap the officer on the splash screen.
      } finally {
        if (mounted) {
          setState(() => _preparing = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final UserRoleProvider session = context.watch<UserRoleProvider>();
    final LedgerProvider ledger = context.watch<LedgerProvider>();

    if (session.isRestoring) {
      return const SplashScreen();
    }
    if (session.needsBootstrap && !session.isAuthenticated) {
      return const SetupScreen();
    }
    if (!session.isAuthenticated) {
      return const LoginScreen();
    }
    if (!ledger.isInitialized || _preparing) {
      _prepareLedger();
      return const SplashScreen();
    }
    return const HomeShell();
  }
}
