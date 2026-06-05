import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/surface_card.dart';
import '../domain/fund_request.dart';
import 'aging_providers.dart';
import 'aging_row.dart';

/// Body of the incharge Aging view: a flat, newest-first list of this company's
/// released requests, each showing how long the cash has been outstanding via
/// an [AgingChip].
///
/// Body-only — the surrounding shell owns the Scaffold, AppBar, and company
/// context bar. Same three async surfaces the rest of the app uses (shimmer
/// skeleton / friendly empty / error-with-retry).
class AgingBody extends ConsumerWidget {
  const AgingBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRequests = ref.watch(agingRequestsProvider);

    return asyncRequests.when(
      loading: () => const _AgingLoading(),
      error: (e, _) => AgingErrorView(
        onRetry: () => ref.invalidate(agingRequestsProvider),
      ),
      data: (requests) => requests.isEmpty
          ? const _AgingEmpty()
          : _AgingList(requests: requests),
    );
  }
}

/// Shimmer placeholder that mirrors the populated list so layout never jumps
/// from a bare spinner to content.
class _AgingLoading extends StatelessWidget {
  const _AgingLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppTokens.lg),
      child: SurfaceCard(child: SkeletonList(count: 5)),
    );
  }
}

/// Friendly empty state — nothing released yet, so nothing is aging.
class _AgingEmpty extends StatelessWidget {
  const _AgingEmpty();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      title: 'Nothing outstanding',
      message: 'No released requests yet. Once you release cash on a request, '
          'it will appear here with a running days-outstanding count.',
    );
  }
}

/// The scrolling, newest-first list of aging rows, grouped into one card.
class _AgingList extends StatelessWidget {
  const _AgingList({required this.requests});

  final List<FundRequest> requests;

  @override
  Widget build(BuildContext context) {
    // One "now" for the whole render so every row counts against the same day.
    final today = DateTime.now();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        AppTokens.md,
        AppTokens.lg,
        AppTokens.bottomNavContentInset,
      ),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.xs),
          child: Column(
            children: [
              for (var i = 0; i < requests.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    indent: AppTokens.md,
                    endIndent: AppTokens.md,
                  ),
                AgingRow(
                  key: ValueKey(requests[i].id),
                  request: requests[i],
                  today: today,
                ),
              ],
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 280.ms).moveY(begin: 8, end: 0, duration: 280.ms);
  }
}

/// Error surface with a retry affordance, matching the app's
/// invalidate-to-retry pattern. Exposed so the admin aging body reuses the
/// identical layout instead of duplicating it.
class AgingErrorView extends StatelessWidget {
  const AgingErrorView({super.key, required this.onRetry});

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
            Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
            const SizedBox(height: AppTokens.lg),
            Text(
              'Couldn’t load aging',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.sm),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTokens.xl),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
