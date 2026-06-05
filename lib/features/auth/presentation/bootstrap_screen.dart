import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../domain/bootstrap_rules.dart';
import 'bootstrap_controller.dart';

/// First-time setup screen.
///
/// Shown when the app's `users` collection is empty: it lets the very first
/// person create the founding administrator account. Pure presentation — it
/// reads/writes only through [bootstrapControllerProvider] and never touches
/// Firebase or repositories directly.
///
/// Mirrors the [LoginScreen] state contract (`loading` / `error` /
/// `succeeded`) and its loading-button + SnackBar error patterns so the two
/// auth surfaces feel like one app. A little extra warmth (a shield mark and a
/// short explanatory subtitle) marks this as the special, one-time founding
/// step without inventing a parallel design language.
class BootstrapScreen extends ConsumerStatefulWidget {
  const BootstrapScreen({super.key});

  @override
  ConsumerState<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends ConsumerState<BootstrapScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    // Dismiss the keyboard so the result (SnackBar / navigation) is visible.
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(bootstrapControllerProvider.notifier).submit(
            _email.text.trim(),
            _password.text,
            _displayName.text.trim(),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final state = ref.watch(bootstrapControllerProvider);

    ref.listen(bootstrapControllerProvider, (_, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('First-time setup')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.xl),
          child: ConstrainedBox(
            // Keep the form readable on tablets / wide windows.
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SetupHeader(
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: AppTokens.xxl),
                  TextFormField(
                    controller: _displayName,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    keyboardType: TextInputType.name,
                    autofillHints: const [AutofillHints.name],
                    enabled: !state.loading,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a display name'
                        : null,
                  ),
                  const SizedBox(height: 16),
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
                    enabled: !state.loading,
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Enter a valid email'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText:
                          'At least $kBootstrapMinPasswordLength characters',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: state.loading
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword),
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        tooltip:
                            _obscurePassword ? 'Show password' : 'Hide password',
                      ),
                    ),
                    obscureText: _obscurePassword,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    enabled: !state.loading,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) =>
                        (v == null || v.length < kBootstrapMinPasswordLength)
                            ? 'Use at least $kBootstrapMinPasswordLength characters'
                            : null,
                  ),
                  const SizedBox(height: 28),
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
                        : const Text('Create admin account'),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.06, end: 0),
          ),
        ),
      ),
    );
  }
}

/// Founding-admin header: a bold gradient halo over the Revvy mascot, a title,
/// and a short subtitle explaining why this screen exists. Kept as a private
/// const widget so it never rebuilds with the form's keystrokes.
class _SetupHeader extends StatelessWidget {
  const _SetupHeader({required this.colorScheme, required this.textTheme});

  static const String _mascotAsset = 'assets/images/revvy.gif';

  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 104,
            height: 104,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: AppTokens.heroGradient(colorScheme.primary),
              shape: BoxShape.circle,
              boxShadow: AppTokens.softShadow(colorScheme.primary),
            ),
            child: ClipOval(
              child: Image.asset(
                _mascotAsset,
                fit: BoxFit.cover,
                semanticLabel: 'Revvy, the rev_app mascot',
                errorBuilder: (context, error, stack) => Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 44,
                  color: Colors.white,
                  semanticLabel: 'Administrator setup',
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTokens.xl),
        Text(
          'Create the first administrator',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AppTokens.sm),
        Text(
          'No accounts exist yet. Create the first administrator '
          'to get started.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
