import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/device_name.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../application/auth_controller.dart';
import '../application/auth_state.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const artworkAsset = 'assets/login/botanical_coffee.png';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _errorKey = GlobalKey();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final isLoading = ref.read(authControllerProvider) is AuthLoading;
    if (isLoading) return;

    if (!(_formKey.currentState?.validate() ?? false)) return;

    ref.read(authControllerProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          deviceName: currentDeviceName(),
        );
  }

  String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email';
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter your password';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is! AuthError) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final errorContext = _errorKey.currentContext;
        if (errorContext == null) return;
        Scrollable.ensureVisible(errorContext,
            alignment: .15,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 250));
      });
    });
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState is AuthLoading;
    final errorMessage = authState is AuthError ? authState.message : null;
    final base = Theme.of(context);
    final colors = _GardenColors(base.brightness == Brightness.dark);
    final theme = base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: colors.green,
        onPrimary: colors.onGreen,
        surface: colors.card,
        onSurface: colors.ink,
        onSurfaceVariant: colors.muted,
        outlineVariant: colors.border,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: colors.ink,
        displayColor: colors.ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.field,
        labelStyle: TextStyle(color: colors.muted),
        floatingLabelStyle: TextStyle(color: colors.green),
        prefixIconColor: colors.muted,
        suffixIconColor: colors.muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.green, width: 2),
        ),
      ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: colors.background,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.background, colors.wash],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth >= 1000 &&
                  box.maxHeight >= 560 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 24;
              final padding = box.maxWidth < 600 ? 20.0 : 32.0;
              final form = _signInForm(context, colors, isLoading, errorMessage);
              return SingleChildScrollView(
                key: const ValueKey('login-scroll'),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.all(padding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: box.maxHeight > padding * 2
                        ? box.maxHeight - padding * 2
                        : 0,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: wide ? 1120 : 460,
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Expanded(
                                  flex: 6,
                                  child: _GardenHero(),
                                ),
                                const SizedBox(width: 40),
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _CoffeeBrand(colors: colors),
                                      const SizedBox(height: 28),
                                      _FormSurface(colors: colors, child: form),
                                      const SizedBox(height: 20),
                                      _GardenNote(colors: colors),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _CoffeeBrand(colors: colors),
                                const SizedBox(height: 20),
                                _FormSurface(
                                  colors: colors,
                                  artwork: box.maxHeight >= 620,
                                  child: form,
                                ),
                                const SizedBox(height: 18),
                                _GardenNote(colors: colors),
                              ],
                            ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _signInForm(BuildContext context, _GardenColors colors,
      bool isLoading, String? errorMessage) {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Welcome back',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                    )),
            const SizedBox(height: 8),
            Text('Sign in and make today a little brighter.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.muted,
                      height: 1.5,
                    )),
            const SizedBox(height: 28),
            if (errorMessage != null) ...[
              KeyedSubtree(
                key: _errorKey,
                child: _ErrorBanner(message: errorMessage),
              ),
              const SizedBox(height: 20),
            ],
            TextFormField(
              controller: _emailController,
              focusNode: _emailFocus,
              enabled: !isLoading,
              autofillHints: const [AutofillHints.username, AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              style: TextStyle(color: colors.ink),
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: _validateEmail,
              onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              enabled: !isLoading,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              style: TextStyle(color: colors.ink),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: pos_ui.IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: colors.muted,
                  ),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: _validatePassword,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            pos_ui.PrimaryButton.icon(
              onPressed: isLoading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: colors.green,
                foregroundColor: colors.onGreen,
                side: BorderSide(color: colors.green),
              ),
              isLoading: isLoading,
              loadingLabel: 'Signing in',
              icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              label: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GardenColors {
  const _GardenColors(this.dark);
  final bool dark;

  Color get background => Color(dark ? 0xFF111F19 : 0xFFF6F4E9);
  Color get wash => Color(dark ? 0xFF243A2C : 0xFFE5EEDC);
  Color get card => Color(dark ? 0xFF1D2E25 : 0xFFFFFEF8);
  Color get field => Color(dark ? 0xFF17271F : 0xFFF7F8F0);
  Color get ink => Color(dark ? 0xFFF3F2E5 : 0xFF193D2E);
  Color get muted => Color(dark ? 0xFFBDCCBF : 0xFF526957);
  Color get green => Color(dark ? 0xFFB5D8AA : 0xFF285A3E);
  Color get onGreen => Color(dark ? 0xFF153222 : 0xFFFFFFFF);
  Color get border => Color(dark ? 0xFF405647 : 0xFFDCE5D4);
}

class _CoffeeBrand extends StatelessWidget {
  const _CoffeeBrand({required this.colors});
  final _GardenColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.green,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.spa_outlined, color: colors.onGreen, size: 26),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text('Top Coffee POS',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  )),
        ),
      ],
    );
  }
}

class _FormSurface extends StatelessWidget {
  const _FormSurface(
      {required this.colors, required this.child, this.artwork = false});
  final _GardenColors colors;
  final Widget child;
  final bool artwork;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF173C27).withValues(alpha: colors.dark ? .12 : .08),
            blurRadius: 36,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Material(
        color: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (artwork)
              SizedBox(
                height: 176,
                child: Image.asset(LoginScreen.artworkAsset,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0.25, 0.2),
                    excludeFromSemantics: true),
              ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _GardenHero extends StatelessWidget {
  const _GardenHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 640,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(LoginScreen.artworkAsset,
                fit: BoxFit.cover,
                alignment: const Alignment(0.4, 0),
                excludeFromSemantics: true),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.35, 1],
                  colors: [Color(0x00182F21), Color(0xF0182F21)],
                ),
              ),
            ),
            Positioned(
              left: 32,
              right: 32,
              bottom: 36,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.eco_outlined,
                      size: 30, color: Color(0xFFD7EBC6)),
                  const SizedBox(height: 14),
                  Text('Rooted in coffee.\nReady for your day.',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: const Color(0xFFFFFCEF),
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                            letterSpacing: -1.2,
                          )),
                  const SizedBox(height: 16),
                  Text('A fresh start, one cup at a time.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFFE2ECD9),
                            height: 1.5,
                          )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GardenNote extends StatelessWidget {
  const _GardenNote({required this.colors});
  final _GardenColors colors;

  @override
  Widget build(BuildContext context) {
    return Text('Good coffee. A fresh start.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.muted,
              letterSpacing: .3,
            ));
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    ));
  }
}
