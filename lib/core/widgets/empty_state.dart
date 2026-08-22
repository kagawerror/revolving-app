import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Friendly, centered empty placeholder. Shows the Revvy mascot, a title, an
/// optional supporting message, and an optional next-action button so an empty
/// surface always points the user somewhere useful.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.showMascot = true,
  });

  /// Same asset the welcome splash uses; declared via `assets/images/` in
  /// pubspec.yaml.
  static const String mascotAsset = 'assets/images/revvy.gif';

  final String title;
  final String? message;
  final Widget? action;
  final bool showMascot;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final msg = message;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMascot) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.rCard),
                child: Image.asset(
                  mascotAsset,
                  width: 140,
                  height: 140,
                  fit: BoxFit.cover,
                  semanticLabel: 'Revvy, the rev_app mascot',
                  errorBuilder: (context, error, stack) => Icon(
                    Icons.inbox_rounded,
                    size: 96,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.lg),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (msg != null) ...[
              const SizedBox(height: AppTokens.sm),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppTokens.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
