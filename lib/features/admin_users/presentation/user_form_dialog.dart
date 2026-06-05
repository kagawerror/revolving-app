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
    required this.companyIds,
  });

  final String uid;
  final String displayName;
  final String email;
  final UserRole role;

  /// The **primary** (default) company. Empty string for admins (admins belong
  /// to no company). For a non-admin this is one of [companyIds] — by
  /// convention the first element, which the selector keeps in primary order.
  final String companyId;

  /// Full company membership. Empty for admins. For a non-admin always contains
  /// [companyId] as its first element followed by the remaining memberships, so
  /// callers can derive both the primary and the set from one ordered list.
  final List<String> companyIds;
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
///     // s.companyId is the primary; s.companyIds is the full membership
///     // (companyId first). Pass both through to validation + persistence.
///     final invalid = validateUserAssignment(
///       role: s.role, companyId: s.companyId /*, companyIds: s.companyIds */);
///     if (invalid != null) return invalid.message;
///     final repo = ref.read(userAdminRepositoryProvider);
///     final res = isCreate
///       ? await repo.createProfile(AppUser(
///           uid: s.uid, displayName: s.displayName, email: s.email,
///           role: s.role, companyId: s.companyId,
///           companyIds: s.companyIds))
///       : await repo.updateAssignment(
///           uid: s.uid, role: s.role, companyId: s.companyId,
///           companyIds: s.companyIds, displayName: s.displayName);
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

  /// Selected company ids in **primary-first** order: element 0 is the primary
  /// company, the rest are additional memberships. Empty == nothing selected.
  /// Keeping it ordered (rather than a Set + separate primary field) means the
  /// submission derivation is just `first` + the whole list, with no chance of
  /// a primary that isn't in the membership.
  final List<String> _companyIds = [];

  bool _saving = false;
  String? _serverError;

  /// Inline error scoped to the company selector (e.g. "assign at least one
  /// company"). Kept separate from [_serverError] so it can render directly
  /// under the chips like a normal field validation message.
  String? _companyError;

  bool get _isCreate => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _uid = TextEditingController(text: e?.uid ?? '');
    _displayName = TextEditingController(text: e?.displayName ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _role = e?.role ?? UserRole.incharge;
    // Seed membership from the existing user. Treat a legacy user (only
    // companyId, no companyIds) as a single-company membership, and guarantee
    // the primary companyId sits first so the star starts on the right chip.
    final primary = (e?.companyId ?? '').trim();
    final ids = _membershipOf(e);
    if (primary.isNotEmpty) _companyIds.add(primary);
    for (final id in ids) {
      if (id.isNotEmpty && !_companyIds.contains(id)) _companyIds.add(id);
    }
  }

  /// Reads the user's full membership from the real model accessor, which
  /// already resolves a legacy `companyId`-only doc to a single-company
  /// membership. Admins return `const []` (no company).
  static List<String> _membershipOf(AppUser? user) =>
      user?.companyMemberships ?? const [];

  @override
  void dispose() {
    _uid.dispose();
    _displayName.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _isAdminRole => _role == UserRole.admin;

  /// At least one company is required for every non-admin role; admins must
  /// have none. Mirrors the dialog's existing pre-flight validity gate.
  bool get _companyValid => _isAdminRole || _companyIds.isNotEmpty;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_companyValid) {
      setState(() => _companyError =
          'Assign at least one company for this role.');
      return;
    }
    setState(() {
      _saving = true;
      _serverError = null;
      _companyError = null;
    });

    // Derive the data shape: admins carry nothing; a non-admin's primary is the
    // first selected id and the membership is the whole ordered list (primary
    // first), so `companyId` is always a member of `companyIds`.
    final ids = _isAdminRole ? const <String>[] : List<String>.from(_companyIds);
    final submission = UserFormSubmission(
      uid: _uid.text.trim(),
      displayName: _displayName.text.trim(),
      email: _email.text.trim(),
      role: _role,
      companyId: ids.isEmpty ? '' : ids.first,
      companyIds: ids,
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
                          // so we never submit stale memberships for an admin.
                          if (r == UserRole.admin) _companyIds.clear();
                          _serverError = null;
                          _companyError = null;
                        });
                      },
              ),
              // Company membership. Hidden entirely for admins (they belong to
              // no company), mirroring the old behaviour where the role==admin
              // path cleared and disabled the single dropdown.
              if (!_isAdminRole) ...[
                const SizedBox(height: AppTokens.lg),
                _CompanyMultiSelect(
                  companies: widget.companies,
                  selectedIds: _companyIds,
                  enabled: !_saving,
                  errorText: _companyError,
                  onToggle: (id) => setState(() {
                    if (_companyIds.contains(id)) {
                      _companyIds.remove(id);
                    } else {
                      _companyIds.add(id);
                    }
                    _companyError = null;
                    _serverError = null;
                  }),
                  onMakePrimary: (id) => setState(() {
                    // Move the chosen id to the front; index 0 is the primary.
                    _companyIds
                      ..remove(id)
                      ..insert(0, id);
                  }),
                ),
              ] else ...[
                const SizedBox(height: AppTokens.lg),
                _ReadOnlyField(
                  label: 'Company',
                  value: 'Not tied to a company',
                  icon: Icons.business_outlined,
                ),
              ],
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

/// Multi-company picker for the user form.
///
/// PATTERN — FilterChips in a [Wrap] (recommended over a checkbox list):
///   * The dialog is narrow and the company set is small-to-medium; chips wrap
///     compactly and read as a "set of tags", which matches this form's other
///     compact controls far better than a tall vertical checklist that would
///     blow out the dialog height and force scrolling.
///   * Selection state is glanceable — selected chips carry the theme's
///     check + primaryContainer fill (chips already inherit the app StadiumBorder
///     from chipTheme), so they look native, not bolted-on.
///   * Each chip is a >=48dp tap target via [VisualDensity.standard]/padding.
///
/// PRIMARY designation: once 2+ companies are selected a compact "Primary"
/// strip appears letting the admin star exactly one of the *selected* companies
/// (single-select). With one company selected it's implicitly primary, so we
/// hide the strip and just label the lone chip. Primary is conveyed with both a
/// filled star icon AND the word "Primary" — never color alone.
class _CompanyMultiSelect extends StatelessWidget {
  const _CompanyMultiSelect({
    required this.companies,
    required this.selectedIds,
    required this.enabled,
    required this.errorText,
    required this.onToggle,
    required this.onMakePrimary,
  });

  /// All assignable companies (order as provided by the caller).
  final List<Company> companies;

  /// Selected ids in primary-first order; element 0 is the current primary.
  final List<String> selectedIds;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onMakePrimary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasError = errorText != null;
    final primaryId = selectedIds.isEmpty ? null : selectedIds.first;
    final selectedSet = selectedIds.toSet();
    final selectedCompanies =
        companies.where((c) => selectedSet.contains(c.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Field-style label so it lines up with the dropdowns above it.
        Row(
          children: [
            Icon(
              Icons.business_outlined,
              size: 20,
              color: hasError ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTokens.sm),
            Text(
              'Companies',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: hasError ? scheme.error : scheme.onSurface,
              ),
            ),
            const SizedBox(width: AppTokens.sm),
            if (selectedIds.isNotEmpty)
              Text(
                '${selectedIds.length} selected',
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppTokens.sm),
        if (companies.isEmpty)
          // Defensive: the screen blocks "Add user" with no companies, but on
          // edit the list could momentarily be empty.
          Text(
            'No companies provisioned yet.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: AppTokens.sm,
            runSpacing: AppTokens.sm,
            children: [
              for (final c in companies)
                FilterChip(
                  selected: selectedSet.contains(c.id),
                  onSelected: enabled ? (_) => onToggle(c.id) : null,
                  showCheckmark: true,
                  label: Text(c.name),
                  labelStyle: textTheme.labelLarge?.copyWith(
                    fontWeight: selectedSet.contains(c.id)
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                  selectedColor: scheme.primaryContainer,
                  checkmarkColor: scheme.onPrimaryContainer,
                  tooltip: selectedSet.contains(c.id)
                      ? 'Remove ${c.name}'
                      : 'Add ${c.name}',
                ),
            ],
          ),
        // Primary designation — only meaningful with 2+ companies.
        if (selectedCompanies.length >= 2) ...[
          const SizedBox(height: AppTokens.md),
          _PrimaryPicker(
            selected: selectedCompanies,
            primaryId: primaryId,
            enabled: enabled,
            onMakePrimary: onMakePrimary,
          ),
        ] else if (selectedCompanies.length == 1) ...[
          const SizedBox(height: AppTokens.sm),
          Row(
            children: [
              Icon(Icons.star_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: AppTokens.xs),
              Expanded(
                child: Text(
                  '${selectedCompanies.first.name} is the primary company.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (hasError) ...[
          const SizedBox(height: AppTokens.sm),
          Text(
            errorText!,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ] else if (selectedIds.isEmpty) ...[
          const SizedBox(height: AppTokens.sm),
          Text(
            'Pick one or more companies this user works in.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Single-select "which selected company is primary?" control. Renders the
/// selected companies as a tappable list with a star radio; the active one
/// shows a filled star + the "Primary" label.
class _PrimaryPicker extends StatelessWidget {
  const _PrimaryPicker({
    required this.selected,
    required this.primaryId,
    required this.enabled,
    required this.onMakePrimary,
  });

  final List<Company> selected;
  final String? primaryId;
  final bool enabled;
  final ValueChanged<String> onMakePrimary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: AppTokens.brField,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: AppTokens.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PRIMARY COMPANY',
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppTokens.xs),
          for (final c in selected)
            _PrimaryOption(
              company: c,
              isPrimary: c.id == primaryId,
              enabled: enabled,
              onTap: () => onMakePrimary(c.id),
            ),
        ],
      ),
    );
  }
}

class _PrimaryOption extends StatelessWidget {
  const _PrimaryOption({
    required this.company,
    required this.isPrimary,
    required this.enabled,
    required this.onTap,
  });

  final Company company;
  final bool isPrimary;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: isPrimary,
      label: isPrimary
          ? '${company.name}, primary company'
          : 'Make ${company.name} the primary company',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled && !isPrimary ? onTap : null,
          borderRadius: AppTokens.brField,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Icon(
                  isPrimary ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 22,
                  color: isPrimary ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTokens.sm),
                Expanded(
                  child: Text(
                    company.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isPrimary ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (isPrimary)
                  Text(
                    'Primary',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
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
