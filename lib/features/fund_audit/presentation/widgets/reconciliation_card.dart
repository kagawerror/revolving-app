import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/money/money.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../domain/fund_audit_math.dart';
import 'verdict_chip.dart';

/// Proof-of-Cash reconciliation summary:
///
///   TOTAL FUND  −  physical cash counted  −  outstanding released  =  VARIANCE
///
/// Used both as the live sticky footer on the create screen and as a static
/// block on the detail certificate. The verdict color/label come from the
/// shared [VerdictChip] so it reads identically everywhere.
class ReconciliationCard extends StatelessWidget {
  /// Live path (create screen): binds directly to the recomputed outcome.
  ReconciliationCard({
    super.key,
    required FundAuditOutcome outcome,
    this.elevated = true,
  })  : effectiveBudget = outcome.effectiveBudget,
        physicalCash = outcome.physicalCash,
        outstanding = outcome.outstanding,
        varianceCentavos = outcome.varianceCentavos,
        verdict = outcome.verdict;

  /// Static path (detail certificate): built from the persisted [FundAudit]
  /// fields directly, so it needs no [FundAuditOutcome] constructor.
  const ReconciliationCard.fromValues({
    super.key,
    required this.effectiveBudget,
    required this.physicalCash,
    required this.outstanding,
    required this.varianceCentavos,
    required this.verdict,
    this.elevated = true,
  });

  final Money effectiveBudget;
  final Money physicalCash;
  final Money outstanding;
  final int varianceCentavos;
  final AuditVerdict verdict;

  /// Sticky footer on create uses a soft shadow + opaque fill so the grid
  /// scrolls under it cleanly; the detail block sits flat in the page.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = VerdictColors.of(scheme, verdict);
    final variance = Money.fromCentavos(varianceCentavos.abs());

    final varianceCaption = switch (verdict) {
      AuditVerdict.shortage => 'Cash is short of the fund',
      AuditVerdict.overage => 'Cash exceeds the fund',
      AuditVerdict.balanced => 'Cash matches the fund exactly',
    };

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(AppTokens.rCard)),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: elevated ? AppTokens.softShadow(scheme.shadow) : null,
      ),
      padding: const EdgeInsets.all(AppTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'RECONCILIATION',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: AppTokens.sm),
          _Line(label: 'Total fund', value: effectiveBudget),
          _Line(label: 'Physical cash counted', value: physicalCash, sign: '−'),
          _Line(label: 'Outstanding released', value: outstanding, sign: '−'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
            child: Divider(height: 1, color: scheme.outlineVariant),
          ),
          // Variance: the headline number, animated when it changes.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Variance',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      varianceCaption,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.md),
              Text(
                // Signed for clarity: +short / −over. ASCII-safe.
                _signed(varianceCentavos, variance),
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: c.fg,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              )
                  .animate(key: ValueKey(varianceCentavos))
                  .fadeIn(duration: 200.ms)
                  .slideY(begin: 0.25, end: 0, curve: Curves.easeOutCubic),
            ],
          ),
          const SizedBox(height: AppTokens.md),
          Align(
            alignment: Alignment.centerLeft,
            child: VerdictChip(verdict: verdict, large: true),
          ),
        ],
      ),
    );
  }

  String _signed(int centavos, Money abs) {
    if (centavos == 0) return abs.format();
    return centavos > 0 ? '+${abs.format()}' : '-${abs.format()}';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.sign});

  final String label;
  final Money value;
  final String? sign;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amount = sign == null ? value.format() : '$sign ${value.format()}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(width: AppTokens.md),
          Text(
            amount,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}
