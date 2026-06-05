import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/error/result.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/cloudinary_config.dart';
import '../domain/resolve_cloudinary_config.dart';
import 'cloudinary_config_controller.dart';
import 'config_providers.dart';

/// Admin-only screen to configure the app-wide Cloudinary settings stored at
/// Firestore `appConfig/cloudinary`. Editing here changes how *every* image
/// upload (proof photos, signatures, avatars) is stored, so the Save action is
/// gated behind a confirmation dialog that spells out the blast radius.
///
/// The API *secret* is deliberately absent: it lives on the server-side relay
/// and is never entered, displayed, or logged here.
///
/// Class name is referenced by the router and must stay `CloudinaryConfigScreen`.
class CloudinaryConfigScreen extends ConsumerStatefulWidget {
  const CloudinaryConfigScreen({super.key});

  @override
  ConsumerState<CloudinaryConfigScreen> createState() =>
      _CloudinaryConfigScreenState();
}

class _CloudinaryConfigScreenState
    extends ConsumerState<CloudinaryConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  final _cloudName = TextEditingController();
  final _uploadPreset = TextEditingController();
  final _signaturePreset = TextEditingController();
  final _uploadFolder = TextEditingController();
  final _signatureFolder = TextEditingController();
  final _apiKey = TextEditingController();

  /// Controllers are seeded exactly once from the first resolved stream value
  /// (the saved doc, or the effective defaults when the doc is absent) so admin
  /// keystrokes are never clobbered by a later stream rebuild.
  bool _seeded = false;

  @override
  void dispose() {
    _cloudName.dispose();
    _uploadPreset.dispose();
    _signaturePreset.dispose();
    _uploadFolder.dispose();
    _signatureFolder.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  /// One-time seed. When a saved doc exists we mirror its fields; otherwise we
  /// prefill from the build-time effective config so the admin starts from the
  /// values currently in force rather than an empty form.
  void _seed(CloudinaryConfig? saved, EffectiveCloudinaryConfig effective) {
    if (_seeded) return;
    _seeded = true;
    if (saved != null) {
      _cloudName.text = saved.cloudName;
      _uploadPreset.text = saved.uploadPreset;
      _signaturePreset.text = saved.signaturePreset;
      _uploadFolder.text = saved.uploadFolder;
      _signatureFolder.text = saved.signatureFolder;
      _apiKey.text = saved.apiKey;
    } else {
      _cloudName.text = effective.cloudName;
      _uploadPreset.text = effective.uploadPreset;
      _signaturePreset.text = effective.signaturePreset;
      _uploadFolder.text = effective.uploadFolder;
      _signatureFolder.text = effective.signatureFolder;
      // apiKey has no effective placeholder source; leave blank.
    }
  }

  Future<void> _onSavePressed(CloudinaryConfig? saved) async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final confirmed = await _confirmSave();
    if (confirmed != true || !mounted) return;

    final uid = ref.read(currentUserProvider).valueOrNull?.uid ?? '';
    final draft = CloudinaryConfig(
      cloudName: _cloudName.text.trim(),
      uploadPreset: _uploadPreset.text.trim(),
      signaturePreset: _signaturePreset.text.trim(),
      uploadFolder: _uploadFolder.text.trim(),
      signatureFolder: _signatureFolder.text.trim(),
      apiKey: _apiKey.text.trim(),
      // updatedAt / updatedByUid are stamped server-side by the controller;
      // we carry the prior audit metadata through unchanged.
      updatedAt: saved?.updatedAt,
      updatedByUid: saved?.updatedByUid ?? '',
    );

    final controller = ref.read(cloudinaryConfigControllerProvider.notifier);
    final result = await controller.save(draft, uid);
    if (!mounted) return;

    switch (result) {
      case Ok():
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Cloudinary configuration saved.')),
          );
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  Future<bool?> _confirmSave() {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: AppTokens.brField,
          ),
          child: Icon(
            Icons.cloud_sync_rounded,
            color: scheme.onPrimaryContainer,
            semanticLabel: 'Save configuration',
          ),
        ),
        title: const Text('Save Cloudinary configuration?'),
        content: const Text(
          'This changes how all image uploads are stored, for everyone.',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
            AppTokens.lg, 0, AppTokens.lg, AppTokens.lg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(cloudinaryConfigStreamProvider);
    final effective = ref.watch(effectiveCloudinaryConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cloudinary')),
      body: configAsync.when(
        loading: () => const _LoadingBody(),
        error: (error, _) => _ErrorBody(
          onRetry: () => ref.invalidate(cloudinaryConfigStreamProvider),
        ),
        data: (saved) {
          _seed(saved, effective);
          return _Form(
            formKey: _formKey,
            saved: saved,
            effective: effective,
            cloudName: _cloudName,
            uploadPreset: _uploadPreset,
            signaturePreset: _signaturePreset,
            uploadFolder: _uploadFolder,
            signatureFolder: _signatureFolder,
            apiKey: _apiKey,
            onSave: () => _onSavePressed(saved),
          );
        },
      ),
    );
  }
}

/// Skeleton-style loading body: a hero placeholder plus a tall card so the
/// layout doesn't jump when real content arrives (matches the dashboard's
/// no-flicker convention rather than a bare centered spinner).
class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget block(double height) => Container(
          height: height,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: AppTokens.brCard,
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(AppTokens.lg),
      children: [
        block(116),
        const SizedBox(height: AppTokens.xl),
        block(360),
      ],
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: 600.ms)
        .then()
        .fade(begin: 1, end: 0.55, duration: 700.ms);
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 48,
                color: scheme.error,
                semanticLabel: 'Could not load configuration'),
            const SizedBox(height: AppTokens.lg),
            Text(
              "Couldn't load the Cloudinary configuration.",
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: AppTokens.sm),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppTokens.xl),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.formKey,
    required this.saved,
    required this.effective,
    required this.cloudName,
    required this.uploadPreset,
    required this.signaturePreset,
    required this.uploadFolder,
    required this.signatureFolder,
    required this.apiKey,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final CloudinaryConfig? saved;
  final EffectiveCloudinaryConfig effective;
  final TextEditingController cloudName;
  final TextEditingController uploadPreset;
  final TextEditingController signaturePreset;
  final TextEditingController uploadFolder;
  final TextEditingController signatureFolder;
  final TextEditingController apiKey;
  final VoidCallback onSave;

  /// Build-time defaults shown as placeholders only when non-empty, so an
  /// empty hint never reads as a misleading "(blank)".
  String? _hint(String value) => value.trim().isEmpty ? null : value;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppTokens.lg),
        children: [
          const _Hero(),
          if (saved == null) ...[
            const SizedBox(height: AppTokens.lg),
            const _DefaultsBanner(),
          ],
          const SectionHeader(title: 'Upload destination'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: cloudName,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Cloud name',
                    hintText: _hint(effective.cloudName),
                    prefixIcon: const Icon(Icons.cloud_outlined),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppTokens.lg),
                TextFormField(
                  controller: uploadPreset,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Upload preset',
                    hintText: _hint(effective.uploadPreset),
                    prefixIcon: const Icon(Icons.tune_rounded),
                    helperText:
                        'Unsigned preset used for proof photos and avatars.',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppTokens.lg),
                TextFormField(
                  controller: uploadFolder,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Upload folder (optional)',
                    hintText: _hint(effective.uploadFolder),
                    prefixIcon: const Icon(Icons.folder_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Signatures'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: signaturePreset,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Signature preset (optional)',
                    hintText: _hint(effective.signaturePreset),
                    prefixIcon: const Icon(Icons.draw_outlined),
                    helperText: 'Defaults to upload preset',
                  ),
                ),
                const SizedBox(height: AppTokens.lg),
                TextFormField(
                  controller: signatureFolder,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Signature folder (optional)',
                    hintText: _hint(effective.signatureFolder),
                    prefixIcon: const Icon(Icons.folder_special_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Credentials'),
          SurfaceCard(
            child: TextFormField(
              controller: apiKey,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Public API key (optional)',
                prefixIcon: Icon(Icons.key_outlined),
                helperText:
                    'This is the public API key — never paste the API secret here.',
                helperMaxLines: 2,
              ),
            ),
          ),
          if (saved?.updatedAt != null) ...[
            const SizedBox(height: AppTokens.lg),
            _AuditFooter(
              updatedAt: saved!.updatedAt!,
              updatedByUid: saved!.updatedByUid,
            ),
          ],
          const SizedBox(height: AppTokens.xl),
          _SaveButton(onSave: onSave),
          const SizedBox(height: AppTokens.lg),
        ],
      ),
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0);
  }
}

/// Save action is its own [ConsumerWidget] so only the button rebuilds while
/// the controller's `isSaving` bool toggles — the form fields don't churn.
class _SaveButton extends ConsumerWidget {
  const _SaveButton({required this.onSave});

  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaving = ref.watch(cloudinaryConfigControllerProvider);
    return FilledButton.icon(
      onPressed: isSaving ? null : onSave,
      icon: isSaving
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save_rounded),
      label: Text(isSaving ? 'Saving…' : 'Save configuration'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    );
  }
}

/// Gradient banner that frames the screen and states the secret-handling policy
/// up front — consistent with the create-fund hero.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.xl),
      decoration: BoxDecoration(
        gradient: AppTokens.heroGradient(scheme.primary),
        borderRadius: AppTokens.brCard,
        boxShadow: AppTokens.softShadow(scheme.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_done_rounded,
                color: Colors.white,
                size: 32,
                semanticLabel: 'Cloudinary',
              ),
              const SizedBox(width: AppTokens.lg),
              Expanded(
                child: Text(
                  'Image storage',
                  style: textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.md),
          Text(
            'Controls where proof photos, signatures, and avatars are uploaded '
            'for every user. The API secret is managed separately on the '
            'server and is never entered here.',
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle info banner shown when no doc has been saved yet.
class _DefaultsBanner extends StatelessWidget {
  const _DefaultsBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.lg,
        vertical: AppTokens.md,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: AppTokens.brField,
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 20,
              color: scheme.onSecondaryContainer,
              semanticLabel: 'Information'),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Text(
              'Using build-time defaults — not yet customized.',
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only audit line: when the config was last saved and by whom.
class _AuditFooter extends StatelessWidget {
  const _AuditFooter({required this.updatedAt, required this.updatedByUid});

  final DateTime updatedAt;
  final String updatedByUid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final when = DateFormat('d MMM y').format(updatedAt.toLocal());
    final editor = updatedByUid.isEmpty ? 'unknown' : updatedByUid;

    return Row(
      children: [
        Icon(Icons.history_rounded,
            size: 18,
            color: scheme.onSurfaceVariant,
            semanticLabel: 'Last updated'),
        const SizedBox(width: AppTokens.sm),
        Expanded(
          child: Text(
            'Last saved $when by $editor',
            style: textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
