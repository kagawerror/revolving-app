import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Read-only proof tile for the request detail view: shows the captured
/// release signature thumbnail (mirrors how [_ProofHero] shows the proof photo)
/// with a "Signed on release" caption. Tap to view full size.
///
/// Renders nothing when [signatureUrl] is empty — legacy requests released
/// before this feature, and any request not yet released, simply don't show it.
/// The caller can drop it straight into the detail `ListView`; it self-hides.
class ReleaseSignatureTile extends StatelessWidget {
  const ReleaseSignatureTile({
    super.key,
    required this.signatureUrl,
    this.signedOnLabel,
  });

  /// The uploaded signature image URL (e.g. `request.releaseSignatureUrl`).
  /// Empty string -> the widget collapses to `SizedBox.shrink()`.
  final String signatureUrl;

  /// Optional caption detail, e.g. a formatted release date. When null the
  /// caption is just "Signed on release".
  final String? signedOnLabel;

  @override
  Widget build(BuildContext context) {
    final caption = signedOnLabel == null
        ? 'Signed on release'
        : 'Signed on release · $signedOnLabel';
    // Signatures are dark ink, so the thumbnail/viewer sit on white and use
    // BoxFit.contain regardless of theme brightness.
    return _ReleaseImageTile(
      url: signatureUrl,
      title: 'Recipient signature',
      caption: caption,
      icon: Icons.draw_rounded,
      onWhite: true,
    );
  }
}

/// Read-only proof tile for the request detail view: shows the release proof
/// photo captured at release time with a "Captured at release" caption. Tap to
/// view full size. Self-hides when [proofUrl] is empty (legacy/unreleased
/// requests show nothing), so the caller can drop it straight into the list.
class ReleaseProofTile extends StatelessWidget {
  const ReleaseProofTile({
    super.key,
    required this.proofUrl,
    this.capturedOnLabel,
  });

  /// The uploaded release-proof image URL (e.g. `request.releaseProofUrl`).
  /// Empty string -> the widget collapses to `SizedBox.shrink()`.
  final String proofUrl;

  /// Optional caption detail, e.g. a formatted release date. When null the
  /// caption is just "Captured at release".
  final String? capturedOnLabel;

  @override
  Widget build(BuildContext context) {
    final caption = capturedOnLabel == null
        ? 'Captured at release'
        : 'Captured at release · $capturedOnLabel';
    // A real photo, so it fills the thumbnail (BoxFit.cover) on the normal
    // surface — not the white ink field used for signatures.
    return _ReleaseImageTile(
      url: proofUrl,
      title: 'Release proof photo',
      caption: caption,
      icon: Icons.photo_camera_rounded,
      onWhite: false,
    );
  }
}

/// Shared row tile for the two release artefacts (proof photo + signature). A
/// tappable thumbnail on the left opens a pinch-zoomable full-size viewer.
/// Self-hides when [url] is empty so legacy/unreleased requests render nothing.
class _ReleaseImageTile extends StatelessWidget {
  const _ReleaseImageTile({
    required this.url,
    required this.title,
    required this.caption,
    required this.icon,
    required this.onWhite,
  });

  final String url;
  final String title;
  final String caption;
  final IconData icon;

  /// Signatures are dark ink and read best on a white field, contained rather
  /// than cropped. Photos use the normal surface and fill the thumbnail.
  final bool onWhite;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppTokens.brCard,
        boxShadow: AppTokens.softShadow(scheme.shadow),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.lg),
        child: Row(
          children: [
            // Thumbnail on the left. Tappable to open the full-size viewer.
            Semantics(
              button: true,
              label: 'View $title full size',
              child: InkWell(
                borderRadius: AppTokens.brField,
                onTap: () => _openFullSize(context),
                child: Container(
                  width: 96,
                  height: 64,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: onWhite ? Colors.white : scheme.surfaceContainerHighest,
                    borderRadius: AppTokens.brField,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: onWhite ? BoxFit.contain : BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Icon(
                      Icons.broken_image_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: scheme.primary),
                      const SizedBox(width: AppTokens.xs),
                      Expanded(
                        child: Text(
                          title,
                          style: textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_full_rounded,
                size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _openFullSize(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ImageViewer(url: url, title: title, onWhite: onWhite),
      ),
    );
  }
}

/// Full-size, pinch-zoomable view of a release artefact. Signatures sit on a
/// white field (dark ink reads best in either theme); photos use the default
/// scaffold background.
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({
    required this.url,
    required this.title,
    required this.onWhite,
  });

  final String url;
  final String title;
  final bool onWhite;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      backgroundColor: onWhite ? Colors.white : null,
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Center(
              child: Icon(Icons.broken_image_rounded, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}
