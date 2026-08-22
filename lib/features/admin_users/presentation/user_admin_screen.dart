import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_secrets.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/widgets/user_role_label.dart';
import '../../../core/error/failure_ui.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/fund.dart';
import '../../companies/presentation/admin_providers.dart';
import 'submit_user_form.dart';
import 'user_admin_providers.dart';
import 'user_form_dialog.dart';

/// Admin-only user maintenance: lists every user with role + company, supports
/// add (the app creates the sign-in account) and tap-to-edit. Three-state aware
/// (loading/empty/error).
///
/// Route: `/admin/users` (add to app_router.dart — see notes). Role-gating is
/// also enforced at the router level via the admin home subtree, but the screen
/// fails safe if reached by a non-admin.
class UserAdminScreen extends ConsumerWidget {
  const UserAdminScreen({super.key});

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    AppUser? existing,
  }) async {
    final companies = ref.read(companiesProvider).valueOrNull ?? const [];
    if (companies.isEmpty && existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a company first.')),
      );
      return;
    }

    final isCreate = existing == null;
    final result = await showUserFormDialog(
      context,
      companies: companies,
      existing: existing,
      // EDIT-only reset pair appears only when the admin relay is configured.
      showPasswordReset: AppSecrets.hasAdminRelay,
      // The dialog watches [allFundsProvider] itself, so the fund picker
      // populates when the stream resolves even if the dialog opened mid-load.
      // Orchestration (create/edit + the profile-first, password-second
      // partial-failure contract) lives in the provider-injected
      // [submitUserForm] so it is unit-testable without pumping the dialog.
      onSubmit: (s) => submitUserForm(
        submission: s,
        existing: existing,
        companies: companies,
        // Read funds fresh at submit time (not a snapshot frozen at open) so
        // validation runs against the resolved set, not a stale empty list.
        funds: ref.read(allFundsProvider).valueOrNull ?? const <Fund>[],
        userAdminRepository: ref.read(userAdminRepositoryProvider),
        adminPasswordRepository: ref.read(adminPasswordRepositoryProvider),
      ),
    );

    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCreate ? 'User added' : 'User updated')),
      );
    }
  }

  /// Triggers Firebase Auth's built-in password-reset email for [user]: the
  /// user receives a secure link to set a new password (no admin-typed password,
  /// no relay). Confirms first, then sends. The email address is PII and is
  /// never logged.
  Future<void> _sendResetEmail(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send password reset email'),
        content: Text(
          'Send a password reset email to ${user.displayName} (${user.email})? '
          "They'll get a secure link to set a new password.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send email'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result =
        await ref.read(authRepositoryProvider).sendPasswordResetEmail(
              email: user.email,
            );
    if (!context.mounted) return;

    final failure = result.failureOrNull;
    if (failure != null) {
      context.showFailure(failure);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to ${user.email}')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    if (me != null && !me.role.isAdmin) {
      return const Scaffold(
        body: EmptyState(
          title: 'Admins only',
          message: 'You do not have access to user maintenance.',
          showMascot: false,
        ),
      );
    }

    final users = ref.watch(allUsersProvider);
    // Company id -> name lookup for the per-user company chip.
    final companyNames = <String, String>{
      for (final c in ref.watch(companiesProvider).valueOrNull ?? const <Company>[])
        c.id: c.name,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        label: const Text('Add user'),
        icon: const Icon(Icons.person_add_alt_1_rounded),
      ),
      body: users.when(
        loading: () => const _UsersSkeleton(),
        error: (e, _) => _UsersError(
          onRetry: () => ref.invalidate(allUsersProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return _UsersEmpty(onAdd: () => _openForm(context, ref));
          }
          return ListView(
            padding: const EdgeInsets.all(AppTokens.lg),
            children: [
              SectionHeader(
                title: 'All users',
                trailing: _CountBadge(list.length),
              ),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.sm,
                  vertical: AppTokens.xs,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: AppTokens.md,
                          endIndent: AppTokens.md,
                        ),
                      _UserTile(
                        user: list[i],
                        companyNames: companyNames,
                        onTap: () =>
                            _openForm(context, ref, existing: list[i]),
                        // Always available to admins now: Firebase Auth's
                        // built-in reset-email flow needs no relay.
                        onResetPassword: () =>
                            _sendResetEmail(context, ref, list[i]),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 80), // FAB breathing room
            ],
          ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0);
        },
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.companyNames,
    required this.onTap,
    this.onResetPassword,
  });
  final AppUser user;

  /// Company id -> display name, shared across the list.
  final Map<String, String> companyNames;
  final VoidCallback onTap;

  /// "Send password reset email" action. Always wired for admins (the built-in
  /// Firebase Auth reset-email flow needs no relay); null would hide the menu.
  final VoidCallback? onResetPassword;

  /// Full membership in primary-first order. Built from the real
  /// [AppUser.companyMemberships] (which already resolves legacy `companyId`-only
  /// docs to a single-company membership), with the primary `companyId` forced
  /// first so the star lands on the right company. Returns ids (not names) so
  /// the caller can resolve + label "Unknown company" consistently.
  List<String> get _membershipIds {
    final ordered = <String>[];
    final primary = user.companyId.trim();
    if (primary.isNotEmpty) ordered.add(primary);
    for (final raw in user.companyMemberships) {
      final id = raw.trim();
      if (id.isNotEmpty && !ordered.contains(id)) ordered.add(id);
    }
    return ordered;
  }

  String _nameFor(String id) => companyNames[id] ?? 'Unknown company';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final initial =
        (user.displayName.isNotEmpty ? user.displayName[0] : '?').toUpperCase();

    final ids = _membershipIds;
    final primaryName = ids.isEmpty ? null : _nameFor(ids.first);
    final extra = ids.length - 1; // companies beyond the primary

    return AppListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Text(
          initial,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
      title: user.displayName.isEmpty ? '(no name)' : user.displayName,
      subtitle: user.email,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 124),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(
                  label: userRoleLabel(user.role),
                  tone:
                      user.role.isAdmin ? StatusTone.info : StatusTone.neutral,
                ),
                if (primaryName != null) ...[
                  const SizedBox(height: AppTokens.xs),
                  _CompanyMembershipLabel(
                    primaryName: primaryName,
                    extraCount: extra,
                    // The full list powers the tooltip/semantics so an admin can
                    // read every company without opening the editor.
                    allNames: [for (final id in ids) _nameFor(id)],
                  ),
                ],
              ],
            ),
          ),
          if (onResetPassword != null)
            _UserRowMenu(
              userName:
                  user.displayName.isEmpty ? user.email : user.displayName,
              onResetPassword: onResetPassword!,
            ),
        ],
      ),
    );
  }
}

/// Per-row overflow menu. Today it offers a single "Send password reset email"
/// action (Firebase Auth's built-in flow); kept as a menu so future per-user
/// actions slot in without re-touching the tile layout. The >=48dp tap target
/// and a [Semantics]-friendly tooltip come from [PopupMenuButton] for free.
class _UserRowMenu extends StatelessWidget {
  const _UserRowMenu({
    required this.userName,
    required this.onResetPassword,
  });

  final String userName;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: 'More actions for $userName',
      shape: const RoundedRectangleBorder(borderRadius: AppTokens.brField),
      onSelected: (value) {
        if (value == 'reset') onResetPassword();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'reset',
          child: Row(
            children: [
              Icon(Icons.lock_reset_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: AppTokens.md),
              const Text('Send password reset email'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Trailing membership summary for a user row: the primary company name with a
/// leading star, plus a compact "+N" pill when the user belongs to more
/// companies. Stays scannable in a dense list — one line, primary first — while
/// exposing the full set via tooltip + semantics for discoverability/a11y.
class _CompanyMembershipLabel extends StatelessWidget {
  const _CompanyMembershipLabel({
    required this.primaryName,
    required this.extraCount,
    required this.allNames,
  });

  final String primaryName;
  final int extraCount;
  final List<String> allNames;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasExtra = extraCount > 0;

    final semanticLabel = hasExtra
        ? 'Companies: ${allNames.join(', ')}. Primary: $primaryName.'
        : 'Company: $primaryName';

    return Tooltip(
      message: allNames.join('\n'),
      child: Semantics(
        label: semanticLabel,
        container: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(
              Icons.star_rounded,
              size: 14,
              color: scheme.primary,
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                primaryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (hasExtra) ...[
              const SizedBox(width: AppTokens.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.sm,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppTokens.rPill),
                ),
                child: Text(
                  '+$extraCount',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);
  final int count;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: AppTokens.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppTokens.rPill),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _UsersSkeleton extends StatelessWidget {
  const _UsersSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.lg),
      children: [
        Skeleton.line(width: 120),
        const SizedBox(height: AppTokens.lg),
        const SurfaceCard(child: SkeletonList(count: 6)),
      ],
    );
  }
}

class _UsersEmpty extends StatelessWidget {
  const _UsersEmpty({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: 'No users yet',
      message: 'Add a user — the app creates their sign-in account, then you '
          'assign a role and company.',
      showMascot: false,
      action: FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add user'),
      ),
    );
  }
}

class _UsersError extends StatelessWidget {
  const _UsersError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: 'Couldn’t load users',
      message: 'Something went wrong while loading the user list.',
      showMascot: false,
      action: FilledButton.tonalIcon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry'),
      ),
    );
  }
}
