import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/fund_audit.dart';
import 'fund_audit_providers.dart';
import 'widgets/audit_shimmer.dart';
import 'widgets/verdict_chip.dart';

/// History of cash counts for a fund. Route: `/incharge/audit`
/// (companyId + fundId).
class FundAuditListScreen extends ConsumerWidget {
  const FundAuditListScreen({
    super.key,
    required this.companyId,
    required this.fundId,
    this.canCreate = true,
  });

  final String companyId;
  final String fundId;

  /// The router passes the role decision; defaults to true so the screen is
  /// usable in isolation. Hides the "New count" CTA when false.
  final bool canCreate;

  ({String companyId, String fundId}) get _key =>
      (companyId: companyId, fundId: fundId);

  void _startNew(BuildContext context) =>
      context.push('/incharge/audit/new?companyId=$companyId&fundId=$fundId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fundAuditHistoryProvider(_key));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Counts'),
        actions: [
          if (canCreate)
            IconButton(
              tooltip: 'New cash count',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _startNew(context),
            ),
        ],
      ),
      floatingActionButton: canCreate
          ? async.maybeWhen(
              data: (list) => list.isEmpty
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: () => _startNew(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New count'),
                    ),
              orElse: () => null,
            )
          : null,
      body: async.when(
        loading: () => const AuditListSkeleton(),
        error: (e, _) => _ListError(
          onRetry: () => ref.invalidate(fundAuditHistoryProvider(_key)),
        ),
        data: (list) => list.isEmpty
            ? _EmptyState(
                canCreate: canCreate, onStart: () => _startNew(context))
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(fundAuditHistoryProvider(_key)),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      AppTokens.lg, AppTokens.lg, AppTokens.lg, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppTokens.md),
                  itemBuilder: (context, i) => _AuditTile(audit: list[i])
                      .animate()
                      .fadeIn(
                          delay: (30 * i).clamp(0, 300).ms, duration: 220.ms)
                      .slideY(begin: 0.06, end: 0, curve: Curves.easeOut),
                ),
              ),
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.audit});
  final FundAudit audit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateStr = audit.createdAt == null
        ? 'Pending date'
        : DateFormat('MMM d, yyyy · h:mm a').format(audit.createdAt!);
    final variance = Money.fromCentavos(audit.varianceCentavos.abs());
    final signed = audit.varianceCentavos == 0
        ? variance.format()
        : audit.varianceCentavos > 0
            ? '+${variance.format()}'
            : '-${variance.format()}';

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: const BorderRadius.all(Radius.circular(AppTokens.rCard)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/incharge/audit/${audit.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(dateStr,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  VerdictChip(verdict: audit.verdict),
                ],
              ),
              const SizedBox(height: AppTokens.md),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Variance',
                      value: signed,
                      strong: audit.varianceCentavos != 0,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'Physical cash',
                      value: audit.physicalCash.format(),
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.strong = false,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool strong;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canCreate, required this.onStart});
  final bool canCreate;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppTokens.xl),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.point_of_sale_rounded,
                  size: 48, color: scheme.primary),
            ),
            const SizedBox(height: AppTokens.lg),
            Text('No cash counts yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppTokens.sm),
            Text(
              'Count the physical cash in this fund and reconcile it against '
              'the books. Each count is saved as a dated Proof-of-Cash record.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (canCreate) ...[
              const SizedBox(height: AppTokens.lg),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Start a cash count'),
              ),
            ],
          ],
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),
    );
  }
}

class _ListError extends StatelessWidget {
  const _ListError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: scheme.error),
            const SizedBox(height: AppTokens.md),
            Text('Could not load cash counts',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.sm),
            Text('Check your connection and try again.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: AppTokens.lg),
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
