import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/widgets/user_role_label.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/company.dart';
import '../../companies/presentation/admin_providers.dart';
import '../domain/user_assignment.dart';
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
      onSubmit: (s) async {
        // Pure validation first; surface its message inline (dialog stays open).
        // Email is immutable on edit, so only validate it on the create path.
        // Passwords are CREATE-only (null on edit, which skips that branch).
        final invalid = validateUserAssignment(
          displayName: s.displayName,
          email: s.email,
          role: s.role,
          companyId: s.companyId,
          companyIds: s.companyIds,
          existingCompanyIds: {for (final c in companies) c.id},
          password: isCreate ? s.password : null,
          confirmPassword: isCreate ? s.confirmPassword : null,
          validateEmail: isCreate,
        );
        if (invalid != null) return invalid.message;

        final repo = ref.read(userAdminRepositoryProvider);
        if (isCreate) {
          // The app provisions the real Firebase Auth sign-in (on a secondary
          // app, so this admin's session is untouched) then writes the profile.
          // The password is handed to the repo and never persisted/logged here.
          final res = await repo.createUserWithAccount(
            email: s.email,
            password: s.password,
            displayName: s.displayName,
            role: s.role,
            companyId: s.companyId,
            companyIds: s.companyIds,
          );
          return res.failureOrNull?.message; // null == success
        }
        final res = await repo.updateAssignment(
          uid: existing.uid,
          role: s.role,
          companyId: s.companyId,
          companyIds: s.companyIds,
          displayName: s.displayName,
        );
        return res.failureOrNull?.message; // null == success
      },
    );

    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCreate ? 'User added' : 'User updated')),
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
  });
  final AppUser user;

  /// Company id -> display name, shared across the list.
  final Map<String, String> companyNames;
  final VoidCallback onTap;

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
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusPill(
              label: userRoleLabel(user.role),
              tone: user.role.isAdmin ? StatusTone.info : StatusTone.neutral,
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
