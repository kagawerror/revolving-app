import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_providers.dart';
import 'app_avatar.dart';

/// App-bar action that shows the current user's avatar and opens the profile
/// screen. Consistent entry point across all role home screens.
class ProfileAvatarButton extends ConsumerWidget {
  const ProfileAvatarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: IconButton(
        tooltip: 'Profile',
        onPressed: () => context.push('/profile'),
        icon: AppAvatar(
          displayName: user?.displayName ?? '',
          photoUrl: user?.photoUrl,
          radius: 16,
        ),
      ),
    );
  }
}
