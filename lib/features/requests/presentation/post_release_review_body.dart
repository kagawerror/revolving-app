import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'conflict_worklist_providers.dart';
import 'request_detail_screen.dart';
import 'request_providers.dart';

/// Body of the approver "To review" surface (release-first). Lists `released`
/// requests not yet acknowledged/disputed — cash is ALREADY out; the approver
/// reviews after the fact. Each card shows the release proof photo + signature
/// thumbnails alongside amount/payee so the approver can verify the handover at
/// a glance, then Acknowledge or Dispute (each confirmed).
///
/// Body-only — the host (role shell tab or standalone screen) owns the Scaffold
/// and AppBar. Three async surfaces match the app: skeleton / empty / error.
class PostReleaseReviewBody extends ConsumerWidget {
  const PostReleaseReviewBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(postReleaseReviewProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppTokens.lg),
        child: SurfaceCard(child: SkeletonList(count: 3)),
      ),
      error: (e, _) => _ReviewError(
          onRetry: () => ref.invalidate(postReleaseReviewProvider)),
      data: (requests) => requests.isEmpty
          ? const _ReviewEmpty()
          : _ReviewList(requests: requests),
    );
  }
}

class _ReviewEmpty extends StatelessWidget {
  const _ReviewEmpty();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      title: 'Nothing to review',
      message: 'When a custodian releases cash, it shows up here for you to '
          'acknowledge or dispute. You’re all caught up.',
    );
  }
}

class _ReviewError extends StatelessWidget {
  const _ReviewError({required this.onRetry});
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
            Text('Couldn’t load the review list',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppTokens.sm),
            Text('Check your connection and try again.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
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

class _ReviewList extends StatelessWidget {
  const _ReviewList({required this.requests});
  final List<FundRequest> requests;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppTokens.lg, AppTokens.md,
          AppTokens.lg, AppTokens.bottomNavContentInset),
      itemCount: requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppTokens.md),
      itemBuilder: (context, i) =>
          _ReviewCard(key: ValueKey(requests[i].id), request: requests[i]),
    ).animate().fadeIn(duration: 280.ms).moveY(begin: 8, end: 0, duration: 280.ms);
  }
}

/// A review card: amount + payee + purpose, the two release artefact thumbnails
/// (proof photo + signature), and the inline Acknowledge / Dispute actions.
/// Card layout (not a list tile) because each item carries imagery the approver
/// needs to inspect — a denser tile would bury the evidence.
class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({super.key, required this.request});
  final FundRequest request;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _busy = false;

  Future<void> _acknowledge() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.verified_rounded),
        title: const Text('Acknowledge this release?'),
        content: Text(
          'Confirm that the ${widget.request.amount.format()} release to '
          '${widget.request.beneficiaryName} looks correct. This records your '
          'sign-off — it doesn’t move any money.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Acknowledge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final res = await ref.read(requestRepositoryProvider).acknowledgePostRelease(
          request: widget.request,
          actorUid: user.uid,
        );
    if (!mounted) return;
    if (res.showOnError(context)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Release acknowledged')));
      // The stream drops this row on the status change; no local removal needed.
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _dispute() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final reason = await DisputeReasonSheet.show(context, widget.request);
    if (reason == null || !mounted) return; // cancelled
    setState(() => _busy = true);
    final res = await ref.read(requestRepositoryProvider).dispute(
          request: widget.request,
          actorUid: user.uid,
          reason: reason,
        );
    if (!mounted) return;
    if (res.showOnError(context)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
            content: Text('Release flagged for follow-up')));
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final r = widget.request;
    final canDecide =
        ref.watch(currentUserProvider).valueOrNull?.role.canApproveOrAdmin ??
            false;

    return SurfaceCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RequestDetailScreen(request: r)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.beneficiaryName,
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(r.purpose,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.md),
              Text(
                r.amount.format(),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.md),
          // Release artefacts: proof photo + signature thumbnails side by side.
          Row(
            children: [
              Expanded(
                child: _ArtefactThumb(
                  url: r.releaseProofUrl,
                  label: 'Release photo',
                  icon: Icons.photo_camera_rounded,
                  onWhite: false,
                ),
              ),
              const SizedBox(width: AppTokens.md),
              Expanded(
                child: _ArtefactThumb(
                  url: r.releaseSignatureUrl,
                  label: 'Signature',
                  icon: Icons.draw_rounded,
                  onWhite: true,
                ),
              ),
            ],
          ),
          if (canDecide) ...[
            const SizedBox(height: AppTokens.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _acknowledge,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Acknowledge'),
                  ),
                ),
                const SizedBox(width: AppTokens.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _dispute,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 52),
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error),
                    ),
                    icon: const Icon(Icons.report_problem_rounded, size: 18),
                    label: const Text('Dispute'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact tappable thumbnail for one release artefact. Falls back to a
/// labelled placeholder when the URL is empty (e.g. an offline release whose
/// images haven't synced yet) so the approver understands WHY there's no image
/// rather than seeing a broken frame.
class _ArtefactThumb extends StatelessWidget {
  const _ArtefactThumb({
    required this.url,
    required this.label,
    required this.icon,
    required this.onWhite,
  });

  final String url;
  final String label;
  final IconData icon;
  final bool onWhite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget frame(Widget child) => Container(
          height: 84,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: onWhite ? Colors.white : scheme.surfaceContainerHighest,
            borderRadius: AppTokens.brField,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: child,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppTokens.xs),
            Text(label,
                style: textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: AppTokens.xs),
        if (url.isEmpty)
          Semantics(
            label: '$label not yet synced',
            child: frame(
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 20, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 2),
                    Text('Pending sync',
                        style: textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          )
        else
          Semantics(
            button: true,
            label: 'View $label full size',
            child: InkWell(
              borderRadius: AppTokens.brField,
              onTap: () => _openFullSize(context),
              child: frame(
                CachedNetworkImage(
                  imageUrl: url,
                  width: double.infinity,
                  fit: onWhite ? BoxFit.contain : BoxFit.cover,
                  placeholder: (context, _) => const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (context, _, _) => Icon(
                      Icons.broken_image_rounded,
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openFullSize(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(label)),
          backgroundColor: onWhite ? Colors.white : null,
          body: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (context, _) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (context, _, _) => const Center(
                    child: Icon(Icons.broken_image_rounded, size: 48)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dispute reason collector — a confirmation sheet that REQUIRES a short reason
/// (the backend `dispute(reason:)` takes one) and makes explicit that disputing
/// does NOT reverse the cash; it flags the release for follow-up. Returns the
/// trimmed reason on confirm, or null on cancel.
///
/// Submit stays disabled until the reason is non-empty (disabled-until-valid),
/// with inline guidance — no silent no-op on an empty field.
class DisputeReasonSheet extends StatefulWidget {
  const DisputeReasonSheet({super.key, required this.request});
  final FundRequest request;

  static Future<String?> show(BuildContext context, FundRequest request) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Padding(
          // Lift above the keyboard so the field and submit stay visible. Read
          // the inset from the sheet's OWN context (viewInsetsOf) so it tracks
          // the keyboard animating in/out, rather than capturing it once from
          // the launching context.
          padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: DisputeReasonSheet(request: request),
        ),
      );

  @override
  State<DisputeReasonSheet> createState() => _DisputeReasonSheetState();
}

class _DisputeReasonSheetState extends State<DisputeReasonSheet> {
  final _controller = TextEditingController();
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final v = _controller.text.trim().isNotEmpty;
      if (v != _valid) setState(() => _valid = v);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final r = widget.request;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppTokens.rCard)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppTokens.lg, AppTokens.md, AppTokens.lg, AppTokens.lg),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppTokens.rPill),
                ),
              ),
            ),
            const SizedBox(height: AppTokens.lg),
            Row(
              children: [
                Icon(Icons.report_problem_rounded, color: scheme.error),
                const SizedBox(width: AppTokens.sm),
                Expanded(
                  child: Text('Dispute this release',
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.sm),
            // The honest, load-bearing line: a dispute does NOT claw back cash.
            Container(
              padding: const EdgeInsets.all(AppTokens.md),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: AppTokens.brField,
              ),
              child: Text(
                'The ${r.amount.format()} to ${r.beneficiaryName} has already '
                'been released — disputing does NOT reverse it. This flags the '
                'release for follow-up and records your reason.',
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: AppTokens.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 280,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: 'Reason for dispute',
                hintText: 'e.g. amount doesn’t match the receipt',
              ),
            ),
            const SizedBox(height: AppTokens.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppTokens.md),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    ),
                    onPressed: _valid
                        ? () => Navigator.of(context)
                            .pop(_controller.text.trim())
                        : null,
                    icon: const Icon(Icons.flag_rounded, size: 18),
                    label: const Text('Submit dispute'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// At-a-glance review-state chip for `released` / `acknowledged` / `disputed`,
/// for use in revisit lists (e.g. the approver "Approved" / "Disputed" tabs).
/// Thin wrapper over the shared status visual so the chip reads identically to
/// everywhere else; exposed here so list rows don't each re-derive it.
class ReviewStateChip extends StatelessWidget {
  const ReviewStateChip({super.key, required this.status});
  final RequestStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = switch (status) {
      RequestStatus.released => ('To review', StatusTone.warning,
          Icons.fact_check_rounded),
      RequestStatus.acknowledged =>
        ('Acknowledged', StatusTone.info, Icons.verified_rounded),
      RequestStatus.disputed =>
        ('Disputed', StatusTone.danger, Icons.report_problem_rounded),
      _ => ('—', StatusTone.neutral, Icons.help_outline_rounded),
    };
    return StatusPill(label: label, tone: tone, icon: icon);
  }
}
