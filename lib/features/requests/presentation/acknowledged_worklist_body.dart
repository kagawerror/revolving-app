import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/fund_request.dart';
import 'approver_inbox_providers.dart';
import 'release_flow_controller.dart';
import 'request_detail_screen.dart';

/// Body of the acknowledged worklist: the queue of requests an approver has
/// already acknowledged / marked ready, with a one-tap RELEASE on each row.
///
/// Body-only — both the [RoleShellScreen] (Worklist tab) and the standalone
/// [AcknowledgedWorklistScreen] (deep-link route) own the Scaffold, AppBar, and
/// [CompanyContextBar] around it. Same three async surfaces as before
/// (shimmer skeleton / friendly empty / error-with-retry).
class AcknowledgedWorklistBody extends ConsumerWidget {
  const AcknowledgedWorklistBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRequests = ref.watch(acknowledgedWorklistProvider);

    return asyncRequests.when(
      loading: () => const _WorklistLoading(),
      error: (e, _) => _WorklistError(
        onRetry: () => ref.invalidate(acknowledgedWorklistProvider),
      ),
      data: (requests) => requests.isEmpty
          ? const _WorklistEmpty()
          : _WorklistList(requests: requests),
    );
  }
}

/// Shimmer placeholder that mirrors the populated list, so layout never jumps
/// from a bare spinner to content.
class _WorklistLoading extends StatelessWidget {
  const _WorklistLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppTokens.lg),
      child: SurfaceCard(child: SkeletonList(count: 4)),
    );
  }
}

/// Friendly empty state — a clear "nothing to do" that doubles as reassurance
/// the queue is clear, with no dangling action since releasing is the only verb.
class _WorklistEmpty extends StatelessWidget {
  const _WorklistEmpty();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      title: 'All clear',
      message: 'No acknowledged requests to release. Once an approver signs off '
          'on a request, it will show up here ready for cash release.',
    );
  }
}

/// Error surface with a retry affordance, matching the app's
/// invalidate-to-retry pattern.
class _WorklistError extends StatelessWidget {
  const _WorklistError({required this.onRetry});

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
            Icon(Icons.error_outline_rounded,
                size: 48, color: scheme.error),
            const SizedBox(height: AppTokens.lg),
            Text(
              'Couldn’t load the worklist',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTokens.sm),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
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

/// The scrolling list of release-ready requests, grouped into one card.
class _WorklistList extends StatelessWidget {
  const _WorklistList({required this.requests});

  final List<FundRequest> requests;

  @override
  Widget build(BuildContext context) {
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
                  const Divider(height: 1, indent: AppTokens.md, endIndent: AppTokens.md),
                _WorklistRow(key: ValueKey(requests[i].id), request: requests[i]),
              ],
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 280.ms).moveY(begin: 8, end: 0, duration: 280.ms);
  }
}

/// A single worklist row: beneficiary, tabular amount, truncated purpose, a tap
/// target into the existing detail screen, and the inline RELEASE action.
///
/// Stateful only to own the per-row in-flight flag so a double-tap can't fire
/// two releases (the second would be rejected by the transaction's re-validate
/// anyway, but disabling is honest and avoids a confusing second snackbar).
class _WorklistRow extends ConsumerStatefulWidget {
  const _WorklistRow({super.key, required this.request});

  final FundRequest request;

  @override
  ConsumerState<_WorklistRow> createState() => _WorklistRowState();
}

class _WorklistRowState extends ConsumerState<_WorklistRow> {
  bool _releasing = false;

  Future<void> _confirmAndRelease() async {
    final r = widget.request;
    final uid = ref.read(currentUserProvider).valueOrNull?.uid;
    if (uid == null) return;

    setState(() => _releasing = true);
    // The release flow controller owns the confirm dialog, photo + signature
    // capture, the uploads, and the transaction, plus its own success/cancel
    // snackbars. We only keep the per-row in-flight flag here.
    final released = await ref
        .read(releaseFlowControllerProvider.notifier)
        .run(context, r, uid);
    // On success the stream drops this row; otherwise re-enable the button.
    if (!mounted) return;
    if (!released) setState(() => _releasing = false);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final r = widget.request;
    // Defense-in-depth: only an incharge custodian (or admin superuser operating
    // this company) sees the RELEASE action — mirrors _RequestAction on the
    // incharge home screen and the isIncharge() || isAdmin() Firestore rule.
    final canRelease =
        ref.watch(currentUserProvider).valueOrNull?.role.canManageFundOrAdmin ??
            false;

    return AppListTile(
      title: r.beneficiaryName,
      subtitle: r.purpose,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            r.amount.format(),
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (canRelease) ...[
            const SizedBox(height: AppTokens.xs),
            _ReleaseButton(
              busy: _releasing,
              onPressed: _confirmAndRelease,
            ),
          ],
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RequestDetailScreen(request: r)),
      ),
    );
  }
}

/// Primary RELEASE button with an in-flight spinner. Swaps the icon for a small
/// progress indicator and nulls `onPressed` while a release is committing so
/// the action can't double-fire.
class _ReleaseButton extends StatelessWidget {
  const _ReleaseButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !busy,
      label: busy ? 'Releasing cash' : 'Release cash',
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.payments_rounded, size: 18),
        label: const Text('RELEASE'),
      ),
    );
  }
}
