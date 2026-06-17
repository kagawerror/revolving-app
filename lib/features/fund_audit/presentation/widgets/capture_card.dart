import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/theme/app_tokens.dart';

/// Count-sheet capture affordance for the create screen.
///
/// Empty: a dashed-feel prompt inviting a photo of the paper count sheet.
/// Captured: a thumbnail with a "retake" affordance.
/// OCR running: a shimmer veil + "Reading sheet…" so it's clear the app is
/// assisting and the values it fills are editable.
class CaptureCard extends StatelessWidget {
  const CaptureCard({
    super.key,
    required this.imagePath,
    required this.ocrRunning,
    required this.onCapture,
  });

  final String? imagePath;
  final bool ocrRunning;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = imagePath != null && imagePath!.isNotEmpty;

    return Semantics(
      button: true,
      label: hasImage
          ? 'Count sheet photo captured. Tap to retake.'
          : 'Capture a photo of the cash count sheet',
      child: InkWell(
        onTap: ocrRunning ? null : onCapture,
        borderRadius:
            const BorderRadius.all(Radius.circular(AppTokens.rCard)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: hasImage ? 200 : 150,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius:
                const BorderRadius.all(Radius.circular(AppTokens.rCard)),
            border: Border.all(
              color: hasImage
                  ? scheme.outlineVariant
                  : scheme.primary.withValues(alpha: 0.4),
              width: hasImage ? 1 : 1.4,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                Image.file(File(imagePath!), fit: BoxFit.cover)
              else
                _EmptyPrompt(scheme: scheme),
              if (hasImage && !ocrRunning) _RetakeOverlay(scheme: scheme),
              if (ocrRunning) _OcrVeil(scheme: scheme),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.document_scanner_rounded,
              size: 40, color: scheme.primary),
          const SizedBox(height: AppTokens.sm),
          Text(
            'Photograph the count sheet',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            'We’ll pre-fill the counts — you can edit every row',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _RetakeOverlay extends StatelessWidget {
  const _RetakeOverlay({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: AppTokens.sm,
      bottom: AppTokens.sm,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: ShapeDecoration(
          color: scheme.scrim.withValues(alpha: 0.55),
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text('Retake',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _OcrVeil extends StatelessWidget {
  const _OcrVeil({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: scheme.scrim.withValues(alpha: 0.45),
      highlightColor: scheme.scrim.withValues(alpha: 0.20),
      child: Container(
        color: scheme.scrim.withValues(alpha: 0.45),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(
              'Reading sheet…',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 150.ms);
  }
}
