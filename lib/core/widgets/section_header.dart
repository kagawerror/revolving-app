import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A bold section title with optional trailing widget (e.g. a "See all" action
/// or a count). Provides consistent vertical rhythm above grouped content.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(
        top: AppTokens.lg,
        bottom: AppTokens.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
