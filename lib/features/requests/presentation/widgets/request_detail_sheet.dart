import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../../replenishment/presentation/replenishment_providers.dart';
import '../../domain/fund_request.dart';
import '../../domain/request_breakdown.dart';
import '../request_status_visual.dart';
import 'release_signature_tile.dart';
import 'request_breakdown_view.dart';

/// Opens the read-only [FundRequest] detail sheet — the "glance" view shown
/// when a recent-activity row on the dashboard is tapped.
///
/// This is intentionally action-free: it shows the same content as
/// [RequestDetailScreen] (proof photo, release proof, recipient signature,
/// partial-liquidation breakdown) but carries no approve/reject/release
/// buttons. Dismiss by dragging down, tapping the scrim, or the close button.
///
/// The [breakdown] is passed in (not computed here) so the caller controls the
/// pending-partial source — mirroring how the detail screen reads
/// `pendingPartialByRequestProvider`. Pass
/// `computeRequestBreakdown(request, pendingPartial: ...)`.
///
/// TESTING: when `breakdown.hasAnyPartial` is `true` this sheet subscribes to
/// [liquidationHistoryProvider], which resolves
/// `replenishmentRepositoryProvider` → `firestoreProvider` → the live
/// `FirebaseFirestore.instance`. Any widget test that opens the sheet with such
/// a breakdown MUST override `liquidationHistoryProvider` (or
/// `replenishmentRepositoryProvider`) in its `ProviderScope`, or the pump throws
/// on uninitialised Firebase. See
/// `test/features/requests/presentation/widgets/request_detail_sheet_test.dart`
/// for the override pattern.
Future<void> showRequestDetailSheet(
  BuildContext context, {
  required FundRequest request,
  required RequestBreakdown breakdown,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // The sheet draws its own rounded top via DraggableScrollableSheet, so the
    // modal itself stays transparent and shape-less to avoid a double corner.
    backgroundColor: Colors.transparent,
    barrierLabel: 'Request details',
    useSafeArea: true,
    builder: (context) => _RequestDetailSheet(
      request: request,
      breakdown: breakdown,
    ),
  );
}

class _RequestDetailSheet extends ConsumerWidget {
  const _RequestDetailSheet({
    required this.request,
    required this.breakdown,
  });

  final FundRequest request;
  final RequestBreakdown breakdown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Itemized liquidation ledger, subscribed only when this request actually
    // has a partial. Null while loading / on error → the breakdown view falls
    // back to its lumped (still correct) totals.
    final entries = breakdown.hasAnyPartial
        ? ref
            .watch(liquidationHistoryProvider(
                (companyId: request.companyId, requestId: request.id)))
            .valueOrNull
        : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      // Snap to the comfortable middle when the user lets go between extents,
      // so the sheet never rests at an awkward half-drag height.
      expand: false,
      snap: true,
      snapSizes: const [0.7],
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.rCard),
            ),
            boxShadow: AppTokens.softShadow(scheme.shadow),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.rCard),
            ),
            child: Column(
              children: [
                // Drag handle + close affordance. Kept outside the scroll view
                // so it's always reachable; the handle doubles as the visual
                // "grab here" cue.
                _SheetHeader(request: request),
                Expanded(
                  child: ListView(
                    // Wiring the inner list to the sheet's controller is what
                    // makes drag-to-expand/collapse work: scrolling past the
                    // top edge drives the sheet extent.
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      AppTokens.lg,
                      0,
                      AppTokens.lg,
                      AppTokens.xl,
                    ),
                    children: [
                      // Headline amount + status + key facts.
                      _SummaryCard(request: request),

                      // Initial proof photo (or a friendly fallback). Always
                      // shown — even a just-created request has this, and the
                      // fallback keeps the minimal case looking intentional.
                      const SizedBox(height: AppTokens.lg),
                      _ProofHero(request: request),

                      // Release artefacts. Both self-hide on empty URLs, so an
                      // unreleased/legacy request renders nothing here.
                      if (request.hasReleaseProof) ...[
                        const SizedBox(height: AppTokens.lg),
                        ReleaseProofTile(proofUrl: request.releaseProofUrl),
                      ],
                      if (request.hasReleaseSignature) ...[
                        const SizedBox(height: AppTokens.lg),
                        ReleaseSignatureTile(
                          signatureUrl: request.releaseSignatureUrl,
                        ),
                      ],

                      // Partial-liquidation breakdown — only when present.
                      if (breakdown.hasAnyPartial) ...[
                        const SizedBox(height: AppTokens.lg),
                        SurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(
                                icon: Icons.receipt_long_rounded,
                                label: 'Liquidation',
                              ),
                              const SizedBox(height: AppTokens.md),
                              RequestBreakdownView(
                                breakdown: breakdown,
                                compact: false,
                                entries: entries,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Sticky top region: a centered drag handle, the beneficiary title with its
/// status pill, and a close button. Sits above the scroll view so it stays put
/// while the body scrolls.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.request});

  final FundRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final visual = requestStatusVisual(request.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        AppTokens.sm,
        AppTokens.sm,
        AppTokens.md,
      ),
      child: Column(
        children: [
          // Drag handle — purely decorative; the gesture is on the sheet.
          Semantics(
            label: 'Drag handle. Drag down to dismiss.',
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppTokens.md),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppTokens.rPill),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request details',
                      style: textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      request.beneficiaryName,
                      style: textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppTokens.sm),
                    StatusPill(
                      label: visual.label,
                      tone: visual.tone,
                      icon: visual.icon,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.sm),
              // 48dp touch target via IconButton's default constraints.
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close',
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerHighest,
                  foregroundColor: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Headline amount, then the supporting label/value rows. Mirrors the detail
/// screen's first SurfaceCard, minus the duplicated status pill (the header
/// already carries status, so we lead with the amount here).
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.request});

  final FundRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount',
            style:
                textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            request.amount.format(),
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppTokens.lg),
          const Divider(height: 1),
          const SizedBox(height: AppTokens.md),
          _DetailRow(
            icon: Icons.notes_rounded,
            label: 'Purpose',
            value: request.purpose.isEmpty ? '—' : request.purpose,
          ),
          const SizedBox(height: AppTokens.md),
          _DetailRow(
            icon: Icons.schedule_rounded,
            label: 'Created',
            value: _formatCreatedAt(request.createdAt),
          ),
        ],
      ),
    );
  }
}

/// "d MMM y · h:mm a" in local time, matching the app's `d MMM y` convention
/// (see approver_approved_body) plus the time, since activity rows care about
/// when. Null (timestamp not yet materialized / legacy doc) reads as a dash.
String _formatCreatedAt(DateTime? createdAt) {
  if (createdAt == null) return '—';
  final local = createdAt.toLocal();
  return DateFormat('d MMM y · h:mm a').format(local);
}

/// Small section header (icon + muted uppercase-ish label) for grouping
/// content inside a [SurfaceCard]. Used for the Liquidation section.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: AppTokens.xs),
        Text(
          label,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Hero proof image, full-bleed within a rounded card, with a friendly error /
/// "no proof" fallback. Adapted from [RequestDetailScreen]'s `_ProofHero`,
/// trimmed for the sheet (slightly shorter so the summary stays above the fold)
/// and with a caption so the artefact is self-describing.
class _ProofHero extends StatelessWidget {
  const _ProofHero({required this.request});

  final FundRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const height = 200.0;

    Widget framed(Widget child) => ClipRRect(
          borderRadius: AppTokens.brCard,
          child: SizedBox(height: height, width: double.infinity, child: child),
        );

    final Widget media;
    if (!request.hasProof) {
      media = framed(
        ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_not_supported_rounded,
                    size: 44, color: scheme.onSurfaceVariant),
                const SizedBox(height: AppTokens.sm),
                Text('No proof photo',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    } else {
      media = Semantics(
        button: true,
        label: 'View request proof photo full size',
        child: InkWell(
          borderRadius: AppTokens.brCard,
          onTap: () => _openFullSize(context),
          child: framed(
            Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: request.proofImageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Center(
                      child: Icon(Icons.broken_image_rounded,
                          size: 44, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                // Affordance hint that the photo is tappable.
                Positioned(
                  right: AppTokens.sm,
                  bottom: AppTokens.sm,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.scrim.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(AppTokens.rPill),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(AppTokens.xs + 2),
                      child: Icon(Icons.open_in_full_rounded,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(icon: Icons.photo_rounded, label: 'Request proof'),
        const SizedBox(height: AppTokens.sm),
        media,
      ],
    );
  }

  void _openFullSize(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ProofViewer(url: request.proofImageUrl),
      ),
    );
  }
}

/// Full-screen pinch-zoom viewer for the request proof photo. Mirrors the
/// `_ImageViewer` in release_signature_tile so the gesture/look is identical.
class _ProofViewer extends StatelessWidget {
  const _ProofViewer({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request proof photo')),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Center(
              child: Icon(Icons.broken_image_rounded, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}

/// Label/value row matching [RequestDetailScreen]'s `_DetailRow`.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppTokens.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(value, style: textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
