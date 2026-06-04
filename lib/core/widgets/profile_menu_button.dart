import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/messaging/presentation/messaging_providers.dart';
import '../theme/app_tokens.dart';
import 'app_avatar.dart';

/// App-bar account control: avatar + display name + chevron that opens a menu
/// with a profile shortcut and sign out. Replaces the old unlabeled
/// avatar-only button across every role home screen, and absorbs the
/// standalone logout icon those screens used to carry.
///
/// Uses [MenuAnchor] (Material 3) rather than [PopupMenuButton]: it gives us a
/// custom, non-interactive header row (name + email + role chip) alongside
/// real `MenuItemButton`s, honours M3 surface tint/elevation, and anchors to
/// our own tappable child instead of forcing the legacy three-dot affordance.
class ProfileMenuButton extends ConsumerWidget {
  const ProfileMenuButton({super.key});

  /// Capitalised single-word role name (mirrors profile screen's `_roleLabel`).
  static String _roleLabel(UserRole role) {
    final name = role.name;
    return name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(currentUserProvider).valueOrNull;

    final displayName =
        (user?.displayName.trim().isNotEmpty ?? false) ? user!.displayName : 'Account';

    return Padding(
      padding: const EdgeInsets.only(right: AppTokens.xs),
      child: MenuAnchor(
        // Tuck the menu just under the app bar, right-aligned to the trigger.
        alignmentOffset: const Offset(0, AppTokens.xs),
        style: MenuStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppTokens.brField),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: AppTokens.xs),
          ),
        ),
        builder: (context, controller, _) {
          return _ProfileTrigger(
            displayName: displayName,
            photoUrl: user?.photoUrl,
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
          );
        },
        menuChildren: [
          if (user != null) ...[
            _MenuHeader(user: user, roleLabel: _roleLabel(user.role)),
            const Divider(height: AppTokens.sm),
          ],
          MenuItemButton(
            leadingIcon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/profile'),
            child: const Text('Profile'),
          ),
          const Divider(height: AppTokens.sm),
          MenuItemButton(
            leadingIcon: Icon(Icons.logout, color: scheme.error),
            style: MenuItemButton.styleFrom(foregroundColor: scheme.error),
            onPressed: () => ref.read(signOutProvider)(),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

/// The tappable app-bar affordance: avatar + name (ellipsised) + chevron.
class _ProfileTrigger extends StatelessWidget {
  const _ProfileTrigger({
    required this.displayName,
    required this.photoUrl,
    required this.onTap,
  });

  final String displayName;
  final String? photoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: 'Account menu, $displayName',
      child: Tooltip(
        message: 'Account menu',
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTokens.brField,
          child: ConstrainedBox(
            // Keep a real 48dp touch target; cap the width so the name can't
            // crowd out sibling app-bar actions on small screens.
            constraints: const BoxConstraints(
              minHeight: 48,
              maxWidth: 180,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.sm,
                vertical: AppTokens.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppAvatar(
                    displayName: displayName,
                    photoUrl: photoUrl,
                    radius: 15,
                  ),
                  // The name collapses out gracefully on very narrow widths:
                  // it lives inside Flexible, so when there isn't room the Row
                  // simply yields avatar + chevron with no overflow.
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: AppTokens.sm),
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Non-interactive identity header at the top of the menu.
class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.user, required this.roleLabel});

  final AppUser user;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name =
        user.displayName.trim().isEmpty ? 'Unnamed user' : user.displayName;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.md,
          AppTokens.sm,
          AppTokens.md,
          AppTokens.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppAvatar(
              displayName: name,
              photoUrl: user.photoUrl,
              radius: 20,
            ),
            const SizedBox(width: AppTokens.md),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (user.email.isNotEmpty)
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  const SizedBox(height: AppTokens.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(AppTokens.rPill),
                    ),
                    child: Text(
                      roleLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
