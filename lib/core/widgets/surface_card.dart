import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A rounded container over `surfaceContainerLow` with an optional soft shadow.
/// The default building block for grouping content. Becomes tappable (with an
/// ink ripple clipped to the radius) when [onTap] is provided.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// Whether to draw the token soft shadow. Disable inside already-elevated
  /// surfaces to avoid double shadows.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedPadding =
        padding ?? const EdgeInsets.all(AppTokens.lg);

    final content = Padding(padding: resolvedPadding, child: child);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppTokens.brCard,
        boxShadow: shadow ? AppTokens.softShadow(scheme.shadow) : null,
      ),
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: AppTokens.brCard,
                child: content,
              ),
            ),
    );
  }
}
