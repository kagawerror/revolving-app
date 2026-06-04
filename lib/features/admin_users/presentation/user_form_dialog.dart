import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/user_role_label.dart';
import '../../auth/domain/app_user.dart';
import '../../companies/domain/company.dart';

/// What the form hands back to the caller. For CREATE, all fields are present.
/// For EDIT, [uid] and [email] are immutable (the dialog shows them read-only)
/// but are still passed through so the caller has the full identity.
class UserFormSubmission {
  const UserFormSubmission({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.companyId,
  });

  final String uid;
  final String displayName;
  final String email;
  final UserRole role;

  /// Empty string for admins (admins belong to no company), else the selected
  /// company id.
  final String companyId;
}

/// Create-or-edit user dialog. Mirrors the app's async-submit contract:
/// [onSubmit] performs the async write and returns either:
///   - `null` on success  → dialog closes, returning the submission, or
///   - a message `String`  → shown inline under the form; dialog stays open.
///
/// The caller is expected to run the architect's `validateUserAssignment(...)`
/// (which returns a `Failure` with a `.message`) plus the repository call, and
/// surface either failure's message back through this `String?` channel — so
/// validation and permission errors land inline rather than in a transient
/// snackbar.
///
/// INTEGRATION (caller):
///   onSubmit: (s) async {
///     final invalid = validateUserAssignment(
///       role: s.role, companyId: s.companyId);
///     if (invalid != null) return invalid.message;
///     final repo = ref.read(userAdminRepositoryProvider);
///     final res = isCreate
///       ? await repo.createProfile(AppUser(
///           uid: s.uid, displayName: s.displayName, email: s.email,
///           role: s.role, companyId: s.companyId))
///       : await repo.updateAssignment(
///           uid: s.uid, role: s.role, companyId: s.companyId,
///           displayName: s.displayName);
///     return res.failureOrNull?.message; // null on success
///   }
Future<UserFormSubmission?> showUserFormDialog(
  BuildContext context, {
  required List<Company> companies,
  AppUser? existing,
  required Future<String?> Function(UserFormSubmission submission) onSubmit,
}) {
  return showDialog<UserFormSubmission>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UserFormDialog(
      companies: companies,
      existing: existing,
      onSubmit: onSubmit,
    ),
  );
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({
    required this.companies,
    required this.existing,
    required this.onSubmit,
  });
  final List<Company> companies;
  final AppUser? existing;
  final Future<String?> Function(UserFormSubmission submission) onSubmit;
  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _uid;
  late final TextEditingController _displayName;
  late final TextEditingController _email;
  late UserRole _role;
  String? _companyId;

  bool _saving = false;
  String? _serverError;

  bool get _isCreate => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _uid = TextEditingController(text: e?.uid ?? '');
    _displayName = TextEditingController(text: e?.displayName ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _role = e?.role ?? UserRole.incharge;
    // Admins carry companyId '' — normalise that to "no selection".
    final cid = e?.companyId ?? '';
    _companyId = cid.isEmpty ? null : cid;
  }

  @override
  void dispose() {
    _uid.dispose();
    _displayName.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _isAdminRole => _role == UserRole.admin;

  /// Company is required for every non-admin role; admins must have none.
  bool get _companyValid => _isAdminRole || _companyId != null;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_companyValid) {
      setState(() => _serverError = 'Select a company for this role.');
      return;
    }
    setState(() {
      _saving = true;
      _serverError = null;
    });

    final submission = UserFormSubmission(
      uid: _uid.text.trim(),
      displayName: _displayName.text.trim(),
      email: _email.text.trim(),
      role: _role,
      companyId: _isAdminRole ? '' : (_companyId ?? ''),
    );

    final error = await widget.onSubmit(submission);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(submission);
    } else {
      setState(() {
        _saving = false;
        _serverError = error;
      });
    }
  }

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
          _isCreate ? Icons.person_add_alt_1_rounded : Icons.manage_accounts_rounded,
          color: scheme.onPrimaryContainer,
          semanticLabel: _isCreate ? 'Add user' : 'Edit user',
        ),
      ),
      title: Text(_isCreate ? 'Add user' : 'Edit user'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // UID — CREATE-only and editable; EDIT shows it read-only so the
              // admin can still confirm identity.
              if (_isCreate)
                TextFormField(
                  controller: _uid,
                  enabled: !_saving,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'User UID',
                    helperText: 'Paste the UID from Firebase Console.',
                    prefixIcon: Icon(Icons.fingerprint_rounded),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                )
              else
                _ReadOnlyField(
                  label: 'User UID',
                  value: widget.existing!.uid,
                  icon: Icons.fingerprint_rounded,
                ),
              const SizedBox(height: AppTokens.lg),
              TextFormField(
                controller: _displayName,
                enabled: !_saving,
                autofocus: !_isCreate,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppTokens.lg),
              // Email — CREATE-only; EDIT shows it read-only (identity field).
              if (_isCreate)
                TextFormField(
                  controller: _email,
                  enabled: !_saving,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Required';
                    if (!s.contains('@') || !s.contains('.')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                )
              else
                _ReadOnlyField(
                  label: 'Email',
                  value: widget.existing!.email,
                  icon: Icons.alternate_email_rounded,
                ),
              const SizedBox(height: AppTokens.lg),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.security_rounded),
                ),
                items: [
                  for (final r in UserRole.values)
                    DropdownMenuItem(
                      value: r,
                      child: Text(userRoleLabel(r)),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (r) {
                        if (r == null) return;
                        setState(() {
                          _role = r;
                          // Admins belong to no company — clear any selection
                          // so we never submit a stale companyId for an admin.
                          if (r == UserRole.admin) _companyId = null;
                          _serverError = null;
                        });
                      },
              ),
              const SizedBox(height: AppTokens.lg),
              DropdownButtonFormField<String>(
                initialValue: _companyId,
                isExpanded: true,
                // Disabled and cleared for admins (companyId == '').
                onChanged: (_saving || _isAdminRole)
                    ? null
                    : (v) => setState(() {
                          _companyId = v;
                          _serverError = null;
                        }),
                decoration: InputDecoration(
                  labelText: 'Company',
                  prefixIcon: const Icon(Icons.business_outlined),
                  helperText: _isAdminRole
                      ? 'Admins are not tied to a company.'
                      : null,
                ),
                items: [
                  for (final c in widget.companies)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                validator: (v) {
                  if (_isAdminRole) return null;
                  return v == null ? 'Select a company' : null;
                },
              ),
              if (_serverError != null) ...[
                const SizedBox(height: AppTokens.lg),
                _InlineError(message: _serverError!),
              ],
              if (_isCreate) ...[
                const SizedBox(height: AppTokens.md),
                Text(
                  'Creating an account here only links a profile to an existing '
                  'Firebase Auth user. Create the sign-in first in the console.',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding:
          const EdgeInsets.fromLTRB(AppTokens.lg, 0, AppTokens.lg, AppTokens.lg),
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
              : const Icon(Icons.check_rounded),
          label: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

/// Read-only, disabled-looking field used for immutable identity values (UID,
/// email) on the EDIT path. Looks like the other inputs for visual continuity.
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

/// Inline, persistent error surface for validation/permission failures returned
/// by the caller — clearer for forms than a transient snackbar.
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
