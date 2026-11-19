import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/demo_accounts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/role_visuals.dart';
import '../../core/utils/validators.dart';
import '../../providers/theme_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/banners.dart';
import '../../widgets/brand_mark.dart';
import 'register_screen.dart';

/// Credential sign-in screen.
///
/// Role permissions are bound to the authenticated account only; there is no
/// role switcher anywhere in the app shell.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final UserRoleProvider session = context.read<UserRoleProvider>();
    if (session.isBusy) {
      return;
    }
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    setState(() => _error = null);
    final AuthResult result = await session.login(
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (!mounted) {
      return;
    }
    if (!result.success) {
      setState(() => _error = result.message);
    }
    // On success, AuthGate swaps this screen for the HomeShell.
  }

  void _fillDemo(DemoAccount account) {
    _formKey.currentState?.reset();
    _emailController.text = account.email;
    _passwordController.text = AppConstants.demoPassword;
    setState(() => _error = null);
  }

  Future<void> _openRegister() async {
    final String? email = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext context) => const RegisterScreen(),
      ),
    );
    if (!mounted || email == null || email.trim().isEmpty) {
      return;
    }
    setState(() {
      _emailController.text = email.trim();
      _passwordController.clear();
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account created. Sign in with your new password.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final UserRoleProvider session = context.watch<UserRoleProvider>();
    final ThemeProvider themeProvider = context.watch<ThemeProvider>();
    final bool busy = session.isBusy || session.isRestoring;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned(
            top: -120,
            right: -100,
            child: _AuthGlow(
              color: AppColors.emerald.withValues(alpha: 0.16),
              size: 300,
            ),
          ),
          Positioned(
            bottom: -150,
            left: -120,
            child: _AuthGlow(
              color: AppColors.info.withValues(alpha: 0.09),
              size: 320,
            ),
          ),
          SafeArea(
            child: Stack(
              children: <Widget>[
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 56,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const BrandMark(
                                  size: 66,
                                  showWordmark: true,
                                  centered: true,
                                ),
                                const SizedBox(height: 28),
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(22),
                                    child: Form(
                                      key: _formKey,
                                      autovalidateMode:
                                          AutovalidateMode.onUserInteraction,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: <Widget>[
                                          Text(
                                            'Officer sign in',
                                            style: theme.textTheme.headlineSmall,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Use your organization account to continue.',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          TextFormField(
                                            controller: _emailController,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            textInputAction: TextInputAction.next,
                                            autofillHints: const <String>[
                                              AutofillHints.username,
                                              AutofillHints.email,
                                            ],
                                            autocorrect: false,
                                            validator: Validators.email,
                                            onChanged: (_) {
                                              if (_error != null) {
                                                setState(() => _error = null);
                                              }
                                            },
                                            decoration: const InputDecoration(
                                              labelText: 'Email address',
                                              hintText: 'officer@orgledger.app',
                                              prefixIcon: Icon(
                                                Icons.alternate_email_rounded,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _passwordController,
                                            focusNode: _passwordFocus,
                                            obscureText: _obscurePassword,
                                            textInputAction: TextInputAction.done,
                                            autofillHints: const <String>[
                                              AutofillHints.password,
                                            ],
                                            validator: (String? value) {
                                              if (value == null ||
                                                  value.isEmpty) {
                                                return 'Password is required';
                                              }
                                              return null;
                                            },
                                            onFieldSubmitted: (_) => _submit(),
                                            onChanged: (_) {
                                              if (_error != null) {
                                                setState(() => _error = null);
                                              }
                                            },
                                            decoration: InputDecoration(
                                              labelText: 'Password',
                                              prefixIcon: const Icon(
                                                Icons.lock_outline_rounded,
                                              ),
                                              suffixIcon: IconButton(
                                                tooltip: _obscurePassword
                                                    ? 'Show password'
                                                    : 'Hide password',
                                                onPressed: () {
                                                  setState(() {
                                                    _obscurePassword =
                                                        !_obscurePassword;
                                                  });
                                                },
                                                icon: Icon(
                                                  _obscurePassword
                                                      ? Icons
                                                          .visibility_outlined
                                                      : Icons
                                                          .visibility_off_outlined,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (_error != null) ...<Widget>[
                                            const SizedBox(height: 14),
                                            ErrorBanner(message: _error ?? ''),
                                          ],
                                          const SizedBox(height: 18),
                                          FilledButton(
                                            onPressed: busy ? null : _submit,
                                            child: busy
                                                ? const SizedBox(
                                                    width: 21,
                                                    height: 21,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2.3,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : const Text('Sign in securely'),
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            alignment: WrapAlignment.center,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: <Widget>[
                                              Text(
                                                'New officer?',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                              TextButton(
                                                onPressed:
                                                    busy ? null : _openRegister,
                                                child: const Text(
                                                  'Create an account',
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Divider(height: 24),
                                          Row(
                                            children: <Widget>[
                                              Icon(
                                                Icons.bolt_rounded,
                                                size: 16,
                                                color: AppColors.emerald,
                                              ),
                                              const SizedBox(width: 5),
                                              Expanded(
                                                child: Text(
                                                  'Quick-fill demo accounts '
                                                  '(password123)',
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: demoAccounts
                                                .map(
                                                  (DemoAccount account) =>
                                                      ActionChip(
                                                    avatar: Icon(
                                                      RoleVisuals.icon(
                                                        account.role,
                                                      ),
                                                      size: 15,
                                                      color: RoleVisuals.color(
                                                        account.role,
                                                      ),
                                                    ),
                                                    label: Text(
                                                      account.role.label,
                                                      style: theme
                                                          .textTheme.labelSmall,
                                                    ),
                                                    tooltip:
                                                        '${account.name} · ${account.email}',
                                                    onPressed: busy
                                                        ? null
                                                        : () =>
                                                            _fillDemo(account),
                                                  ),
                                                )
                                                .toList(growable: false),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    Icon(
                                      Icons.offline_bolt_outlined,
                                      size: 14,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        'Works offline · Receipts stay on this device',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  top: 4,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Theme: ${themeProvider.mode.name}',
                    onPressed: () => themeProvider.cycle(),
                    icon: Icon(_themeIcon(themeProvider.mode)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _themeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }
}

class _AuthGlow extends StatelessWidget {
  const _AuthGlow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
