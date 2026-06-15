import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/error/result.dart';
import '../../../core/theme/app_tokens.dart';
import '../../messaging/presentation/messaging_providers.dart';
import '../domain/bootstrap_rules.dart';
import '../domain/password_change_rules.dart';
import 'auth_providers.dart';

/// Forced, full-screen password gate.
///
/// Shown (via the router) whenever the signed-in profile carries
/// `mustChangePassword == true` — i.e. on first login after an admin creates the
/// account, or after an admin reset. It is a **gate**: there is no back
/// navigation and no app chrome behind it. The only ways out are (a) setting a
/// valid new password, or (b) signing out (an escape hatch so a user who never
/// learned their temporary password isn't trapped).
///
/// Presentation-only. Two clearly-marked TODO hooks are owned by the coder:
///   1. `authRepositoryProvider.changeOwnPassword(currentPassword:, newPassword:)`
///      returning `Result<void>`. On `Ok` we do nothing navigational — a live
///      profile listener flips `mustChangePassword` and the router redirects
///      automatically. On `Err` we surface the failure via the shared
///      `failure_ui` SnackBar.
///   2. The router redirect that lands the user here (added in app_router.dart).
///
/// Business rules (min length, must-differ, must-match) live as a pure
/// `validatePasswordChange` seam in domain; the checks here are UI affordances
/// that mirror it so the button can disable and inline hints can render without
/// a round-trip. Passwords are transient: never logged, never persisted here.
///
/// Style intentionally echoes [BootstrapScreen]: the same gradient mascot halo,
/// 52dp primary button with inline spinner, and SnackBar error contract, so the
/// three auth surfaces (login / setup / this gate) read as one app.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  // Transient credential controllers — their text is never logged or persisted.
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNext = true;
  bool _obscureConfirm = true;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Re-run the form validators (and refresh the submit-enabled gate) on every
    // keystroke so inline hints and the disabled state track the live input.
    for (final c in [_current, _next, _confirm]) {
      c.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [_current, _next, _confirm]) {
      c
        ..removeListener(_onChanged)
        ..dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {}); // cheap: only this gate's small form subtree rebuilds.
  }

  /// Local mirror of the domain rules, used ONLY to gate the submit button.
  /// The authoritative checks are the field [validator]s + the domain
  /// `validatePasswordChange` seam the coder calls before the repository.
  bool get _canSubmit {
    final current = _current.text;
    final next = _next.text;
    final confirm = _confirm.text;
    return !_submitting &&
        current.isNotEmpty &&
        next.length >= kBootstrapMinPasswordLength &&
        next != current &&
        confirm == next;
  }

  Future<void> _onUpdatePressed() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final confirmed = await _confirmChangeDialog();
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);

    // Run the pure domain seam first so rule violations (min length, reuse,
    // mismatch) land in the same SnackBar channel as re-auth errors. Passwords
    // are transient — never logged.
    final invalid = validatePasswordChange(
      currentPassword: _current.text,
      newPassword: _next.text,
      confirmPassword: _confirm.text,
    );
    final Result<void> result = invalid != null
        ? Err(invalid)
        : await ref.read(authRepositoryProvider).changeOwnPassword(
              currentPassword: _current.text,
              newPassword: _next.text,
            );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.isOk) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Password updated.')),
        );
      // Router redirect handles navigation once the profile flag clears.
    } else {
      context.showFailure(result.failureOrNull!);
    }
  }

  Future<bool?> _confirmChangeDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
          icon: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: AppTokens.brField,
            ),
            child: Icon(
              Icons.lock_reset_rounded,
              color: scheme.onPrimaryContainer,
              semanticLabel: 'Change password',
            ),
          ),
          title: const Text('Change your password?'),
          content: const Text(
            "You'll use this new password the next time you sign in. "
            'Make sure you can remember it.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
              AppTokens.lg, 0, AppTokens.lg, AppTokens.lg),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Update password'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
        title: const Text('Sign out?'),
        content: const Text(
          "You'll need your temporary password (or a new one from an "
          'administrator) to sign back in.',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
            AppTokens.lg, 0, AppTokens.lg, AppTokens.lg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // signOutProvider also de-registers push before clearing the session, so we
    // reuse it rather than calling the repository directly. The router redirects
    // to /login on the resulting null user.
    await ref.read(signOutProvider)();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return PopScope(
      // This is a gate: swallow the system back gesture so the user cannot
      // dodge the forced change. Sign-out is the sanctioned exit.
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Set a new password'),
          actions: [
            TextButton.icon(
              onPressed: _submitting ? null : _onSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
            const SizedBox(width: AppTokens.sm),
          ],
        ),
        body: Center(
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
                    _GateHeader(colorScheme: scheme, textTheme: textTheme),
                    const SizedBox(height: AppTokens.xl),
                    _ReassuranceNote(scheme: scheme, textTheme: textTheme),
                    const SizedBox(height: AppTokens.xl),
                    _PasswordField(
                      controller: _current,
                      label: 'Current (temporary) password',
                      icon: Icons.lock_clock_outlined,
                      obscured: _obscureCurrent,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.next,
                      autofillHint: AutofillHints.password,
                      onToggle: () => setState(
                          () => _obscureCurrent = !_obscureCurrent),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your current password'
                          : null,
                    ),
                    const SizedBox(height: AppTokens.lg),
                    _PasswordField(
                      controller: _next,
                      label: 'New password',
                      icon: Icons.lock_outline_rounded,
                      helperText:
                          'At least $kBootstrapMinPasswordLength characters, '
                          'different from your current one.',
                      obscured: _obscureNext,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.next,
                      autofillHint: AutofillHints.newPassword,
                      onToggle: () =>
                          setState(() => _obscureNext = !_obscureNext),
                      validator: (v) {
                        final s = v ?? '';
                        if (s.length < kBootstrapMinPasswordLength) {
                          return 'Use at least $kBootstrapMinPasswordLength '
                              'characters';
                        }
                        if (s == _current.text) {
                          return 'Choose a password different from the current '
                              'one';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTokens.lg),
                    _PasswordField(
                      controller: _confirm,
                      label: 'Confirm new password',
                      icon: Icons.lock_outline_rounded,
                      obscured: _obscureConfirm,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.done,
                      autofillHint: AutofillHints.newPassword,
                      onToggle: () => setState(
                          () => _obscureConfirm = !_obscureConfirm),
                      onFieldSubmitted: (_) =>
                          _canSubmit ? _onUpdatePressed() : null,
                      validator: (v) {
                        final s = v ?? '';
                        if (s.isEmpty) return 'Re-enter your new password';
                        if (s != _next.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTokens.xl),
                    FilledButton(
                      onPressed: _canSubmit ? _onUpdatePressed : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Update password'),
                    ),
                    const SizedBox(height: AppTokens.sm),
                    Text(
                      "You won't be able to use the app until your password is "
                      'changed.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
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

/// Branded header: the gradient mascot halo (matching login/bootstrap) with a
/// security-shield fallback, a title, and the reassuring subtitle. Const-private
/// so form keystrokes never rebuild it.
class _GateHeader extends StatelessWidget {
  const _GateHeader({required this.colorScheme, required this.textTheme});

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
                errorBuilder: (context, error, stack) => const Icon(
                  Icons.shield_outlined,
                  size: 44,
                  color: Colors.white,
                  semanticLabel: 'Security',
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTokens.xl),
        Text(
          'Set a new password',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AppTokens.sm),
        Text(
          'For your security, please set a new password before continuing.',
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

/// Soft info banner explaining the first-login / after-reset context, so the
/// forced gate reads as reassuring rather than alarming.
class _ReassuranceNote extends StatelessWidget {
  const _ReassuranceNote({required this.scheme, required this.textTheme});

  final ColorScheme scheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: AppTokens.brField,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: scheme.onSecondaryContainer,
            semanticLabel: 'Note',
          ),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Text(
              'Your account is using a temporary password set during sign-up or '
              'an administrator reset. Choose a private password only you know.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Obscured field with a show/hide eye toggle, matching the login/bootstrap and
/// user-form password fields exactly (same icons, tooltips, helper styling).
class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.obscured,
    required this.enabled,
    required this.onToggle,
    required this.validator,
    required this.textInputAction,
    required this.autofillHint,
    this.helperText,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? helperText;
  final bool obscured;
  final bool enabled;
  final VoidCallback onToggle;
  final FormFieldValidator<String> validator;
  final TextInputAction textInputAction;
  final String autofillHint;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscured,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: textInputAction,
      autofillHints: [autofillHint],
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 2,
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          onPressed: enabled ? onToggle : null,
          icon: Icon(obscured
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined),
          tooltip: obscured ? 'Show password' : 'Hide password',
        ),
      ),
      validator: validator,
    );
  }
}
