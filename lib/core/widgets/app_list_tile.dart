import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A themed, rounded list row. Wraps the leading/title/subtitle/trailing layout
/// in a tappable, ink-rippling surface with comfortable (>=48dp) touch targets.
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.subtitleMaxLines = 1,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Lines the subtitle may occupy before it ellipsizes. Defaults to 1; raise it
  /// when the caller passes a multi-line subtitle (e.g. `'purpose\ndate'`),
  /// which would otherwise have everything after the first `\n` clipped away.
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final sub = subtitle;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTokens.brField,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.md,
              vertical: AppTokens.sm,
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: AppTokens.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (sub != null && sub.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            sub,
                            maxLines: subtitleMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppTokens.md),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
