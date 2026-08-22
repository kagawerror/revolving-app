import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/status_pill.dart';
import '../../companies/domain/fund.dart';

/// Prominent, themed warning banner shown when one or more funds have dropped
/// to a low balance. Trigger condition and content are unchanged: it counts the
/// funds whose [FundStatus] is `low` and renders nothing when there are none.
class LowBalanceBanner extends StatelessWidget {
  final List<Fund> funds;
  const LowBalanceBanner({super.key, required this.funds});

  @override
  Widget build(BuildContext context) {
    final low = funds.where((f) => f.status == FundStatus.low).toList();
    if (low.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (bg, fg) = StatusPill.colorsFor(StatusTone.warning, scheme);

    return Semantics(
      container: true,
      label: '${low.length} fund(s) at low balance. Replenish soon.',
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg,
          vertical: AppTokens.sm,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.lg,
          vertical: AppTokens.md,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppTokens.brCard,
          border: Border.all(color: fg.withValues(alpha: 0.24)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: fg, size: 26),
            const SizedBox(width: AppTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    low.length == 1
                        ? '1 fund at low balance'
                        : '${low.length} funds at low balance',
                    style: textTheme.titleSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Replenish soon to keep cash available.',
                    style: textTheme.bodySmall?.copyWith(
                      color: fg.withValues(alpha: 0.86),
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
