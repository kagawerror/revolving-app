import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_tokens.dart';
import 'auth_providers.dart';
import 'login_controller.dart';

/// Branded sign-in. Presentation-only redesign — the email/password validators,
/// submit path into [loginControllerProvider], SnackBar error mapping, and the
/// `needsSetup` gating of the first-time-setup entry are all preserved exactly.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(loginControllerProvider.notifier).submit(_email.text, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginControllerProvider);
    // Only the very first run (no admin seeded yet) offers first-time setup.
    final needsSetup =
        ref.watch(bootstrapNeededProvider).maybeWhen(orElse: () => false, data: (v) => v);
    ref.listen(loginControllerProvider, (_, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _LoginHeader(),
                    const SizedBox(height: AppTokens.xxl),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: AppTokens.lg),
                    TextFormField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          tooltip:
                              _obscurePassword ? 'Show password' : 'Hide password',
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Enter your password' : null,
                    ),
                    const SizedBox(height: AppTokens.xl),
                    FilledButton(
                      onPressed: state.loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: state.loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                    if (needsSetup) ...[
                      const SizedBox(height: AppTokens.sm),
                      TextButton(
                        onPressed: () => context.push('/setup'),
                        child: const Text('First-time setup'),
                      ),
                    ],
                  ],
                ),
              ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.06, end: 0),
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand header: Revvy mascot on a gradient halo plus the app name. Kept private
/// and const-friendly so keystrokes in the form never rebuild it.
class _LoginHeader extends StatelessWidget {
  const _LoginHeader();

  static const String _mascotAsset = 'assets/images/revvy.gif';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 112,
          height: 112,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: AppTokens.heroGradient(scheme.primary),
            shape: BoxShape.circle,
            boxShadow: AppTokens.softShadow(scheme.primary),
          ),
          child: ClipOval(
            child: Image.asset(
              _mascotAsset,
              fit: BoxFit.cover,
              semanticLabel: 'Revvy, the rev_app mascot',
              errorBuilder: (context, error, stack) => Icon(
                Icons.account_balance_wallet_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTokens.xl),
        Text(
          'Revolving Fund',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: AppTokens.xs),
        Text(
          'Sign in to manage your funds',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
