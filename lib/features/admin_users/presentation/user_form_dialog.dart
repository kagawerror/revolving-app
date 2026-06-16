import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/user_role_label.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/bootstrap_rules.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/fund.dart';
import '../../companies/presentation/admin_providers.dart';
import 'assign_funds_confirm.dart';

/// What the form hands back to the caller. For CREATE, all fields are present
/// (including [password]/[confirmPassword], which the caller uses to provision
/// the Firebase Auth account). For EDIT, [email] is immutable (the dialog shows
/// it read-only) and the password fields are empty.
class UserFormSubmission {
  const UserFormSubmission({
    required this.displayName,
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.newPassword,
    required this.newConfirmPassword,
    required this.role,
    required this.companyId,
    required this.companyIds,
    this.fundIds = const [],
  });

  final String displayName;
  final String email;

  /// The new account's password. **CREATE-only and transient** — empty on EDIT.
  /// This value is never persisted to Firestore and must never be logged; the
  /// caller hands it straight to Firebase Auth account creation and drops it.
  final String password;

  /// Confirmation of [password] for typo-protection. Same transient, never-log,
  /// never-persist contract as [password]. Empty on EDIT.
  final String confirmPassword;

  /// EDIT-only optional password reset. **Transient** — never persisted to
  /// Firestore and never logged. Empty means "leave the current password
  /// unchanged"; a non-empty value is handed to the admin-relay Worker (after a
  /// successful profile update) to reset the target user's sign-in password.
  /// Always empty on CREATE.
  final String newPassword;

  /// Confirmation of [newPassword]. Same transient, never-log, never-persist
  /// contract. Empty on CREATE and when no reset is requested on EDIT.
  final String newConfirmPassword;

  final UserRole role;

  /// The **primary** (default) company. Empty string for admins (admins belong
  /// to no company). For a non-admin this is one of [companyIds] — by
  /// convention the first element, which the selector keeps in primary order.
  final String companyId;

  /// Full company membership. Empty for admins. For a non-admin always contains
  /// [companyId] as its first element followed by the remaining memberships, so
  /// callers can derive both the primary and the set from one ordered list.
  final List<String> companyIds;

  /// Per-incharge assigned fund document ids. Meaningful only for the incharge
  /// role; always empty for every other role (the dialog clears it on a role
  /// change). A zero-fund incharge is a valid saved state (strict empty state).
  final List<String> fundIds;
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
///     // On CREATE, s.password/s.confirmPassword carry the new account's
///     // credentials — hand them to Auth account creation, never persist/log.
///     final invalid = validateUserAssignment(
///       role: s.role, companyId: s.companyId,
///       password: s.password, confirmPassword: s.confirmPassword);
///     if (invalid != null) return invalid.message;
///     final repo = ref.read(userAdminRepositoryProvider);
///     final res = isCreate
///       ? await repo.createUserWithAccount(
///           email: s.email, password: s.password,
///           displayName: s.displayName, role: s.role,
///           companyId: s.companyId, companyIds: s.companyIds)
///       : await repo.updateAssignment(
///           uid: existing.uid, role: s.role, companyId: s.companyId,
///           companyIds: s.companyIds, displayName: s.displayName);
///     return res.failureOrNull?.message; // null on success
///   }
Future<UserFormSubmission?> showUserFormDialog(
  BuildContext context, {
  required List<Company> companies,
  AppUser? existing,
  required Future<String?> Function(UserFormSubmission submission) onSubmit,
  bool showPasswordReset = false,
}) {
  return showDialog<UserFormSubmission>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UserFormDialog(
      companies: companies,
      existing: existing,
      onSubmit: onSubmit,
      showPasswordReset: showPasswordReset,
    ),
  );
}

class _UserFormDialog extends ConsumerStatefulWidget {
  const _UserFormDialog({
    required this.companies,
    required this.existing,
    required this.onSubmit,
    required this.showPasswordReset,
  });
  final List<Company> companies;
  final AppUser? existing;
  final Future<String?> Function(UserFormSubmission submission) onSubmit;

  /// Whether to surface the EDIT-only "New password (optional)" pair. The caller
  /// passes `AppSecrets.hasAdminRelay`, so the field is hidden entirely until
  /// the admin relay is configured (graceful degradation).
  final bool showPasswordReset;
  @override
  ConsumerState<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayName;
  late final TextEditingController _email;
  // CREATE-only credential controllers. Their text is the account password and
  // must never be logged. Always disposed below.
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();
  // EDIT-only optional password-reset controllers. Their text is the new
  // account password and must never be logged. Always disposed below.
  final TextEditingController _newPassword = TextEditingController();
  final TextEditingController _newConfirmPassword = TextEditingController();
  late UserRole _role;

  /// Visibility toggles for the two CREATE-only password fields. Default to
  /// obscured; the eye icon reveals on demand.
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  /// Visibility toggles for the two EDIT-only reset fields. Same default.
  bool _obscureNewPassword = true;
  bool _obscureNewConfirm = true;

  /// Selected company ids in **primary-first** order: element 0 is the primary
  /// company, the rest are additional memberships. Empty == nothing selected.
  /// Keeping it ordered (rather than a Set + separate primary field) means the
  /// submission derivation is just `first` + the whole list, with no chance of
  /// a primary that isn't in the membership.
  final List<String> _companyIds = [];

  /// Selected fund ids for an incharge. Set semantics (order irrelevant); seeded
  /// from the existing user's assignment in [initState]. Cleared whenever the
  /// role changes away from incharge, and pruned when a backing company is
  /// dropped from [_companyIds].
  final Set<String> _fundIds = {};

  /// Latest funds snapshot resolved from [allFundsProvider] in [build]. Held in
  /// state so callbacks fired between builds (e.g. [_toggleFund],
  /// [_companyForFund]) see the same resolved set the picker rendered. Reactive:
  /// when the stream resolves the dialog rebuilds and this repopulates, so a
  /// dialog opened while funds are still loading fills in once they arrive.
  List<Fund> _funds = const [];

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
    // Seed fund assignment from the existing incharge (empty for everyone else
    // and for an unassigned/created incharge).
    _fundIds.addAll(e?.assignedFundIds ?? const []);
  }

  /// Owning companyId for a selected fund id, or null if the fund isn't in the
  /// loaded set. Used to count distinct companies for the confirm summary.
  String? _companyForFund(String fundId) {
    for (final f in _funds) {
      if (f.id == fundId) return f.companyId;
    }
    return null;
  }

  /// Toggles a fund in the assignment. Selecting a fund auto-adds its owning
  /// company to [_companyIds] (so the membership always backs the funds), which
  /// matches the validation rule "every assigned fund's company is a member".
  void _toggleFund(Fund fund) {
    setState(() {
      if (_fundIds.contains(fund.id)) {
        _fundIds.remove(fund.id);
      } else {
        _fundIds.add(fund.id);
        if (!_companyIds.contains(fund.companyId)) {
          _companyIds.add(fund.companyId);
        }
      }
      _serverError = null;
      _companyError = null;
    });
  }

  /// Reads the user's full membership from the real model accessor, which
  /// already resolves a legacy `companyId`-only doc to a single-company
  /// membership. Admins return `const []` (no company).
  static List<String> _membershipOf(AppUser? user) =>
      user?.companyMemberships ?? const [];

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _newPassword.dispose();
    _newConfirmPassword.dispose();
    super.dispose();
  }

  bool get _isAdminRole => _role == UserRole.admin;

  /// Show the EDIT-only optional reset pair only on the edit path AND when the
  /// admin relay is configured (graceful degradation when it isn't).
  bool get _showPasswordReset => !_isCreate && widget.showPasswordReset;

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

    // Derive the data shape: admins carry nothing; a non-admin's primary is the
    // first selected id and the membership is the whole ordered list (primary
    // first), so `companyId` is always a member of `companyIds`. Funds belong to
    // the incharge role only.
    final ids = _isAdminRole ? const <String>[] : List<String>.from(_companyIds);
    final fundIds =
        _role == UserRole.incharge ? _fundIds.toList() : const <String>[];

    // Business-decision confirmation on the incharge path: assigning funds (or
    // saving an EXISTING incharge with none) changes what they can release
    // against, so gate it AFTER validation, BEFORE submit. The zero-fund warning
    // only fires when editing an existing incharge (a brand-new one with no
    // funds is an ordinary, un-warned create).
    if (_role == UserRole.incharge) {
      final companyCount =
          fundIds.map((id) => _companyForFund(id)).whereType<String>().toSet().length;
      final isZeroFundWarning = !_isCreate && fundIds.isEmpty;
      final proceed = await showAssignFundsConfirm(
        context,
        name: _displayName.text.trim(),
        fundCount: fundIds.length,
        companyCount: companyCount,
        isZeroFundWarning: isZeroFundWarning,
      );
      if (!mounted || !proceed) return;
    }

    setState(() {
      _saving = true;
      _serverError = null;
      _companyError = null;
    });

    final submission = UserFormSubmission(
      displayName: _displayName.text.trim(),
      email: _email.text.trim(),
      // Passwords are CREATE-only and intentionally NOT trimmed (leading/trailing
      // spaces are legal in a password); empty on the EDIT path.
      password: _isCreate ? _password.text : '',
      confirmPassword: _isCreate ? _confirmPassword.text : '',
      // EDIT-only optional reset; empty unless the admin typed a new password.
      // Like the CREATE password, intentionally NOT trimmed. Always empty on
      // create. Empty means "leave the current password unchanged".
      newPassword: _showPasswordReset ? _newPassword.text : '',
      newConfirmPassword: _showPasswordReset ? _newConfirmPassword.text : '',
      role: _role,
      companyId: ids.isEmpty ? '' : ids.first,
      companyIds: ids,
      fundIds: fundIds,
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

    // Funds drive the per-incharge picker AND submit-time pruning. Watching the
    // provider (rather than receiving a frozen prop) means a dialog opened while
    // the stream is still loading repopulates the picker once it resolves — no
    // close/reopen needed. Cached into [_funds] so callbacks between builds see
    // the same resolved set.
    final fundsAsync = ref.watch(allFundsProvider);
    _funds = fundsAsync.valueOrNull ?? const <Fund>[];
    final fundsLoading = fundsAsync.isLoading;

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
              // UID is no longer an input — the app creates the auth account
              // itself. On EDIT we still surface the existing uid read-only so
              // the admin can confirm identity.
              if (!_isCreate) ...[
                _ReadOnlyField(
                  label: 'User UID',
                  value: widget.existing!.uid,
                  icon: Icons.fingerprint_rounded,
                ),
                const SizedBox(height: AppTokens.lg),
              ],
              TextFormField(
                controller: _displayName,
                enabled: !_saving,
                autofocus: true,
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
              // Password + confirm — CREATE-only. The app provisions the sign-in
              // account, so we collect (and confirm) the initial password here.
              if (_isCreate) ...[
                const SizedBox(height: AppTokens.lg),
                TextFormField(
                  controller: _password,
                  enabled: !_saving,
                  obscureText: _obscurePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText:
                        'At least $kBootstrapMinPasswordLength characters.',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: _saving
                          ? null
                          : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
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
                  controller: _confirmPassword,
                  enabled: !_saving,
                  obscureText: _obscureConfirm,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _saving ? null : _save(),
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: _saving
                          ? null
                          : () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
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
              ],
              // EDIT-only optional password reset. Hidden entirely unless the
              // admin relay is configured (graceful degradation). Leaving both
              // blank keeps the current password; if either is filled we enforce
              // the same min-length + match rules as the create path.
              if (_showPasswordReset) ...[
                const SizedBox(height: AppTokens.lg),
                TextFormField(
                  controller: _newPassword,
                  enabled: !_saving,
                  obscureText: _obscureNewPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'New password (optional)',
                    helperText: 'Leave blank to keep the current password.',
                    prefixIcon: const Icon(Icons.password_rounded),
                    suffixIcon: IconButton(
                      onPressed: _saving
                          ? null
                          : () => setState(
                                () => _obscureNewPassword = !_obscureNewPassword,
                              ),
                      icon: Icon(
                        _obscureNewPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      tooltip: _obscureNewPassword
                          ? 'Show new password'
                          : 'Hide new password',
                    ),
                  ),
                  validator: (v) {
                    final s = v ?? '';
                    // Both blank == no reset requested; valid (do not block save).
                    if (s.isEmpty && _newConfirmPassword.text.isEmpty) {
                      return null;
                    }
                    if (s.length < kBootstrapMinPasswordLength) {
                      return 'At least $kBootstrapMinPasswordLength characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTokens.lg),
                TextFormField(
                  controller: _newConfirmPassword,
                  enabled: !_saving,
                  obscureText: _obscureNewConfirm,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _saving ? null : _save(),
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    prefixIcon: const Icon(Icons.password_rounded),
                    suffixIcon: IconButton(
                      onPressed: _saving
                          ? null
                          : () => setState(
                                () => _obscureNewConfirm = !_obscureNewConfirm,
                              ),
                      icon: Icon(
                        _obscureNewConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      tooltip: _obscureNewConfirm
                          ? 'Show confirm new password'
                          : 'Hide confirm new password',
                    ),
                  ),
                  validator: (v) {
                    final s = v ?? '';
                    // Both blank == no reset requested; valid.
                    if (s.isEmpty && _newPassword.text.isEmpty) return null;
                    if (s != _newPassword.text) return 'Passwords do not match';
                    return null;
                  },
                ),
              ],
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
                          // Only the incharge is fund-scoped; any other role
                          // must carry no funds (mirrors validateUserAssignment).
                          if (r != UserRole.incharge) _fundIds.clear();
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
                      // Dropping a company drops any funds it backs — the
                      // assignment must never reference a non-member company.
                      _fundIds.removeWhere((fundId) => _funds.any(
                            (f) => f.id == fundId && f.companyId == id,
                          ));
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
                // Per-incharge fund assignment — only the incharge role is
                // fund-scoped, so the picker is shown for that role only.
                if (_role == UserRole.incharge) ...[
                  const SizedBox(height: AppTokens.lg),
                  _FundMultiSelect(
                    funds: _funds,
                    companyNames: {
                      for (final c in widget.companies) c.id: c.name,
                    },
                    selectedCompanyIds: _companyIds,
                    selectedFundIds: _fundIds,
                    loading: fundsLoading,
                    enabled: !_saving,
                    onToggle: _saving ? null : _toggleFund,
                  ),
                ],
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: 'Note',
                    ),
                    const SizedBox(width: AppTokens.sm),
                    Expanded(
                      child: Text(
                        "The app will create this person's sign-in account.",
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
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

/// Per-incharge fund picker. Shows the funds of the *currently selected*
/// companies, grouped by company, as toggleable chips. Selecting a fund also
/// grants its company (handled by [_UserFormDialogState._toggleFund]).
///
/// States:
///   * **loading** → a small skeleton (the fund stream hasn't resolved yet).
///   * **no company selected** → a hint to pick a company first.
///   * **company selected but no funds** → an empty hint per the company group.
///   * **funds present** → grouped [_FundChip]s.
class _FundMultiSelect extends StatelessWidget {
  const _FundMultiSelect({
    required this.funds,
    required this.companyNames,
    required this.selectedCompanyIds,
    required this.selectedFundIds,
    required this.loading,
    required this.enabled,
    required this.onToggle,
  });

  /// All loadable funds across reachable companies.
  final List<Fund> funds;

  /// companyId -> display name, for the per-company group header.
  final Map<String, String> companyNames;

  /// Currently selected company ids (the picker shows only these companies'
  /// funds).
  final List<String> selectedCompanyIds;

  /// Currently selected fund ids.
  final Set<String> selectedFundIds;
  final bool loading;
  final bool enabled;

  /// Null disables interaction (e.g. while saving).
  final ValueChanged<Fund>? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selectedCompanies = selectedCompanyIds.toSet();

    // Funds belonging to the selected companies, grouped by company.
    final byCompany = <String, List<Fund>>{};
    for (final f in funds) {
      if (selectedCompanies.contains(f.companyId)) {
        (byCompany[f.companyId] ??= []).add(f);
      }
    }
    for (final list in byCompany.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTokens.sm),
            Text(
              'Assigned funds',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: AppTokens.sm),
            if (selectedFundIds.isNotEmpty)
              Text(
                '${selectedFundIds.length} selected',
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppTokens.sm),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppTokens.sm),
            child: SkeletonList(count: 2),
          )
        else if (selectedCompanyIds.isEmpty)
          const _Hint(
            'Pick a company first, then choose which of its funds this '
            'incharge manages.',
          )
        else ...[
          for (final companyId in selectedCompanyIds)
            _FundGroup(
              companyName: companyNames[companyId] ?? companyId,
              funds: byCompany[companyId] ?? const [],
              selectedFundIds: selectedFundIds,
              enabled: enabled,
              onToggle: onToggle,
            ),
          const SizedBox(height: AppTokens.xs),
          const _Hint(
            'A zero-fund incharge sees no funds until you assign one.',
          ),
        ],
      ],
    );
  }
}

/// One company's worth of fund chips, with a small company-name header and an
/// empty hint when the company has no funds yet.
class _FundGroup extends StatelessWidget {
  const _FundGroup({
    required this.companyName,
    required this.funds,
    required this.selectedFundIds,
    required this.enabled,
    required this.onToggle,
  });

  final String companyName;
  final List<Fund> funds;
  final Set<String> selectedFundIds;
  final bool enabled;
  final ValueChanged<Fund>? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            companyName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppTokens.xs),
          if (funds.isEmpty)
            const _Hint('No funds in this company yet.')
          else
            Wrap(
              spacing: AppTokens.sm,
              runSpacing: AppTokens.sm,
              children: [
                for (final f in funds)
                  _FundChip(
                    fund: f,
                    selected: selectedFundIds.contains(f.id),
                    onToggle: enabled && onToggle != null
                        ? () => onToggle!(f)
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A single toggleable fund chip showing the fund name and its available
/// balance, using the app's tabular-figure money formatting.
class _FundChip extends StatelessWidget {
  const _FundChip({
    required this.fund,
    required this.selected,
    required this.onToggle,
  });

  final Fund fund;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FilterChip(
      selected: selected,
      onSelected: onToggle == null ? null : (_) => onToggle!(),
      showCheckmark: true,
      selectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.onPrimaryContainer,
      tooltip: selected ? 'Unassign ${fund.name}' : 'Assign ${fund.name}',
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fund.name,
            style: textTheme.labelLarge?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            fund.availableBalance.format(),
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small muted helper text used for the fund picker's hint/empty states.
class _Hint extends StatelessWidget {
  const _Hint(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      message,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: scheme.onSurfaceVariant),
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
