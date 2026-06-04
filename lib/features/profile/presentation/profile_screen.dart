import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/failure_ui.dart';
import '../../../core/theme/app_accents.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../messaging/presentation/messaging_providers.dart';
import 'profile_providers.dart';

/// Human-readable label for a [UserRole] (capitalised single word in v1).
String _roleLabel(UserRole role) {
  final name = role.name;
  return name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploading = false;

  // ── Avatar capture: pick → crop (1:1 circle) → compress → upload → save ──
  Future<void> _pickAvatar(ImageSource source) async {
    // 1. Pick the source file (we need a path for the cropper).
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return; // user cancelled the picker

    // 2. Crop to a 1:1 square with a circular mask (avatar shape).
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop photo',
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
          hideBottomControls: true,
        ),
        IOSUiSettings(
          title: 'Crop photo',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped == null || !mounted) return; // user cancelled the cropper

    setState(() => _uploading = true);
    try {
      // 3. Compress the cropped result (mirrors ImagePickCompress sizing).
      final raw = await cropped.readAsBytes();
      final bytes = await FlutterImageCompress.compressWithList(
        raw,
        quality: 80,
        minWidth: 512,
        minHeight: 512,
        format: CompressFormat.jpeg,
      );

      // 4. Upload to the dedicated avatars folder.
      final upload =
          await ref.read(avatarUploaderProvider).uploadJpeg(bytes);
      final url = upload.valueOrNull;
      if (url == null) {
        if (mounted) {
          context.showFailure(
              upload.failureOrNull ?? const UnexpectedFailure('Upload failed.'));
        }
        return;
      }

      // 5. Persist; the auth stream re-emits and the avatar updates itself.
      final save = await ref.read(profileControllerProvider).savePhotoUrl(url);
      if (mounted && save.showOnError(context)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo updated')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _openAvatarSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAvatar(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editName(String current) async {
    final controller = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || !mounted) return;

    final res = await ref.read(profileControllerProvider).saveDisplayName(newName);
    if (mounted && res.showOnError(context)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _CenteredMessage(
          icon: Icons.error_outline,
          text: 'Could not load your profile.',
        ),
        data: (user) => user == null
            ? const _CenteredMessage(
                icon: Icons.person_off_outlined,
                text: 'You are not signed in.',
              )
            : _ProfileBody(
                user: user,
                uploading: _uploading,
                onAvatarTap: _openAvatarSheet,
                onEditName: () => _editName(user.displayName),
              ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({
    required this.user,
    required this.uploading,
    required this.onAvatarTap,
    required this.onEditName,
  });

  final AppUser user;
  final bool uploading;
  final VoidCallback onAvatarTap;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final seed = ref.watch(themeControllerProvider).seed;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _GradientHeader(
          user: user,
          seed: seed,
          uploading: uploading,
          onAvatarTap: onAvatarTap,
        ),
        Padding(
          padding: const EdgeInsets.all(AppTokens.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionCard(
                title: 'Display name',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        user.displayName.isEmpty
                            ? 'No name set'
                            : user.displayName,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onEditName,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.08, end: 0),
              const SizedBox(height: AppTokens.md),
              _SectionCard(
                title: 'Role & company',
                child: Wrap(
                  spacing: AppTokens.sm,
                  runSpacing: AppTokens.sm,
                  children: [
                    Chip(
                      avatar: Icon(Icons.badge_outlined,
                          size: 18, color: scheme.onSecondaryContainer),
                      label: Text(_roleLabel(user.role)),
                      backgroundColor: scheme.secondaryContainer,
                      labelStyle: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                    Chip(
                      avatar: Icon(Icons.business_outlined,
                          size: 18, color: scheme.onSurfaceVariant),
                      label: Text(user.companyId.isEmpty
                          ? 'No company'
                          : user.companyId),
                    ),
                  ],
                ),
              )
                  .animate(delay: 60.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.08, end: 0),
              const SizedBox(height: AppTokens.md),
              _SectionCard(
                title: 'Appearance',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ThemeModeControl(current: user.themeMode),
                    const SizedBox(height: AppTokens.lg),
                    Text('Accent', style: theme.textTheme.labelLarge),
                    const SizedBox(height: AppTokens.sm),
                    _AccentGrid(selectedId: user.accentId),
                  ],
                ),
              )
                  .animate(delay: 120.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.08, end: 0),
              const SizedBox(height: AppTokens.xl),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(signOutProvider)();
                },
                icon: Icon(Icons.logout, color: scheme.error),
                label: Text('Sign out',
                    style: TextStyle(color: scheme.error)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                ),
              ).animate(delay: 160.ms).fadeIn(duration: 280.ms),
            ],
          ),
        ),
      ],
    );
  }
}

class _GradientHeader extends StatelessWidget {
  const _GradientHeader({
    required this.user,
    required this.seed,
    required this.uploading,
    required this.onAvatarTap,
  });

  final AppUser user;
  final Color seed;
  final bool uploading;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const onHero = Colors.white;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppTokens.heroGradient(seed),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppTokens.rCard),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppTokens.lg, AppTokens.xl, AppTokens.lg, AppTokens.xl),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: 'Change profile photo',
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                GestureDetector(
                  onTap: uploading ? null : onAvatarTap,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: onHero, width: 3),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AppAvatar(
                          displayName: user.displayName,
                          photoUrl: user.photoUrl,
                          radius: 48,
                        ),
                        if (uploading)
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.4),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: onHero,
                                strokeWidth: 3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Material(
                  color: seed,
                  shape: CircleBorder(
                    side: BorderSide(color: onHero, width: 2),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: uploading ? null : onAvatarTap,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.camera_alt, size: 16, color: onHero),
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 320.ms).scale(
                begin: const Offset(0.9, 0.9),
                end: const Offset(1, 1),
              ),
          const SizedBox(height: AppTokens.md),
          Text(
            user.displayName.isEmpty ? 'Unnamed user' : user.displayName,
            style: textTheme.headlineSmall
                ?.copyWith(color: onHero, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.xs),
          Text(
            user.email,
            style: textTheme.bodyMedium
                ?.copyWith(color: onHero.withValues(alpha: 0.85)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTokens.sm),
            child,
          ],
        ),
      ),
    );
  }
}

class _ThemeModeControl extends ConsumerWidget {
  const _ThemeModeControl({required this.current});

  final ThemeMode current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          label: Text('System'),
          icon: Icon(Icons.brightness_auto_outlined),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          label: Text('Light'),
          icon: Icon(Icons.light_mode_outlined),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          label: Text('Dark'),
          icon: Icon(Icons.dark_mode_outlined),
        ),
      ],
      selected: {current},
      showSelectedIcon: false,
      onSelectionChanged: (selection) async {
        final mode = selection.first;
        if (mode == current) return;
        final res =
            await ref.read(profileControllerProvider).setThemeMode(mode);
        if (context.mounted) res.showOnError(context);
      },
    );
  }
}

class _AccentGrid extends ConsumerWidget {
  const _AccentGrid({required this.selectedId});

  final String selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: AppTokens.md,
      runSpacing: AppTokens.md,
      children: [
        for (final option in AppAccents.all)
          _AccentSwatch(
            option: option,
            selected: option.id == selectedId,
            onTap: () async {
              if (option.id == selectedId) return;
              final res =
                  await ref.read(profileControllerProvider).setAccent(option.id);
              if (context.mounted) res.showOnError(context);
            },
          ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AccentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label} accent',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: option.seed,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 3,
            ),
            boxShadow: selected ? AppTokens.softShadow(option.seed) : null,
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 22)
              : null,
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: AppTokens.md),
          Text(text, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
