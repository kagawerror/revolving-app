import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/bootstrap_rules.dart';

/// Admin "Reset password" dialog — a DEDICATED action, distinct from the
/// optional reset pair inside the create/edit user form. Use it from a user row
/// (popup-menu item / trailing icon) and only when `AppSecrets.hasAdminRelay`
/// is true (the caller gates visibility; this widget assumes the relay exists).
///
/// Visual style mirrors `user_form_dialog.dart` exactly: rounded
/// [AppTokens.brCard] chrome, a primaryContainer icon chip, read-only identity
/// fields for the target, obscured fields with eye toggles, and a
/// `Cancel` / `FilledButton.icon` action row.
///
/// Contract — mirrors `submitUserForm`'s `Future<String?>` channel:
///   [onSubmit] performs the async reset and returns either
///     - `null` on success  → dialog closes (caller shows a SnackBar), or
///     - a message `String`  → shown inline under the form; dialog stays open.
///
/// The architect's orchestrator (TODO hook, owned by the coder) is expected to
/// look like:
///
///   `Future<String?>` resetUserPassword({
///     required AppUser target,
///     required String newPassword,
///     required AdminPasswordRepository adminPasswordRepository,
///   }) async {
///     final invalid = validateNewPassword(newPassword, newPassword);
///     if (invalid != null) return invalid.message;
///     final res = await adminPasswordRepository
///         .setUserPassword(uid: target.uid, newPassword: newPassword);
///     return res.failureOrNull?.message; // null == success
///     // The reset also stamps `mustChangePassword = true` so the target hits
///     // the ChangePasswordScreen gate on next sign-in.
///   }
///
/// Business rules (min length, match) live in the pure `validateNewPassword`
/// seam in domain. The checks here are UI affordances that mirror it; the
/// password is transient and never logged or persisted by this widget.
Future<bool?> showResetPasswordDialog(
  BuildContext context, {
  required AppUser target,
  required Future<String?> Function(String newPassword) onSubmit,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ResetPasswordDialog(target: target, onSubmit: onSubmit),
  );
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.target, required this.onSubmit});

  final AppUser target;
  final Future<String?> Function(String newPassword) onSubmit;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  // Transient: never logged or persisted by this widget.
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  bool _saving = false;
  String? _serverError;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final confirmed = await _confirmDialog();
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _serverError = null;
    });

    // Passwords are intentionally NOT trimmed (leading/trailing spaces are legal).
    final error = await widget.onSubmit(_password.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true); // caller shows the success SnackBar.
    } else {
      setState(() {
        _saving = false;
        _serverError = error;
      });
    }
  }

  Future<bool?> _confirmDialog() {
    final name = _targetName;
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
              semanticLabel: 'Reset password',
            ),
          ),
          title: Text('Reset password for $name?'),
          content: const Text(
            'This immediately replaces their sign-in password. They will be '
            'required to set a new password the next time they sign in.',
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
              icon: const Icon(Icons.lock_reset_rounded),
              label: const Text('Reset password'),
            ),
          ],
        );
      },
    );
  }

  String get _targetName => widget.target.displayName.trim().isEmpty
      ? widget.target.email
      : widget.target.displayName.trim();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
          semanticLabel: 'Reset password',
        ),
      ),
      title: const Text('Reset password'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReadOnlyField(
                label: 'User',
                value: _targetName,
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: AppTokens.lg),
              _ReadOnlyField(
                label: 'Email',
                value: widget.target.email,
                icon: Icons.alternate_email_rounded,
              ),
              const SizedBox(height: AppTokens.lg),
              TextFormField(
                controller: _password,
                enabled: !_saving,
                autofocus: true,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least $kBootstrapMinPasswordLength characters.',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: _saving
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
                validator: (v) {
                  final s = v ?? '';
                  if (s.isEmpty) return 'Required';
                  if (s.length < kBootstrapMinPasswordLength) {
                    return 'At least $kBootstrapMinPasswordLength characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppTokens.lg),
              TextFormField(
                controller: _confirm,
                enabled: !_saving,
                obscureText: _obscureConfirm,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _saving ? null : _save(),
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _obscureConfirm = !_obscureConfirm),
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    tooltip: _obscureConfirm
                        ? 'Show confirm password'
                        : 'Hide confirm password',
                  ),
                ),
                validator: (v) {
                  final s = v ?? '';
                  if (s.isEmpty) return 'Required';
                  if (s != _password.text) return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: AppTokens.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                    semanticLabel: 'Note',
                  ),
                  const SizedBox(width: AppTokens.sm),
                  Expanded(
                    child: Text(
                      'The user will be required to set a new password the next '
                      'time they sign in.',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              if (_serverError != null) ...[
                const SizedBox(height: AppTokens.lg),
                _InlineError(message: _serverError!),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
          AppTokens.lg, 0, AppTokens.lg, AppTokens.lg),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_reset_rounded),
          label: Text(_saving ? 'Resetting…' : 'Reset password'),
        ),
      ],
    );
  }
}

/// Read-only identity field — same look as the disabled inputs in
/// user_form_dialog.dart, for visual continuity.
class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      enabled: false,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
      ),
    );
  }
}

/// Inline, persistent error surface — identical to user_form_dialog.dart's so a
/// relay failure reads the same in both flows.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: AppTokens.brField,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: scheme.onErrorContainer,
            semanticLabel: 'Error',
          ),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
