import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_breakdown.dart';
import '../domain/request_status.dart';
import 'conflict_worklist_body.dart';
import 'post_release_review_body.dart';
import 'request_providers.dart';
import 'request_status_visual.dart';
import 'widgets/release_signature_tile.dart';
import 'widgets/request_breakdown_view.dart';

class RequestDetailScreen extends ConsumerWidget {
  final FundRequest request;
  const RequestDetailScreen({super.key, required this.request});

  /// Release-first post-hoc approver ACKNOWLEDGE — behind a confirmation dialog
  /// (every money/state decision is confirmed). Dispute uses the dedicated
  /// [DisputeReasonSheet] (its required-reason form is itself the confirmation).
  Future<void> _acknowledge(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.verified_rounded),
        title: const Text('Acknowledge this release?'),
        content: Text(
          'Confirm that the ${request.amount.format()} release to '
          '${request.beneficiaryName} looks correct. This records your '
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
    if (confirmed != true || !context.mounted) return;
    final res = await ref.read(requestRepositoryProvider).acknowledgePostRelease(
          request: request,
          actorUid: user.uid,
        );
    if (!context.mounted) return;
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  /// DISPUTE — collects a REQUIRED reason via [DisputeReasonSheet] and passes
  /// the real reason to `dispute(reason:)`. No hard-coded reason string.
  Future<void> _dispute(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final reason = await DisputeReasonSheet.show(context, request);
    if (reason == null || !context.mounted) return; // cancelled
    final res = await ref.read(requestRepositoryProvider).dispute(
          request: request,
          actorUid: user.uid,
          reason: reason,
        );
    if (!context.mounted) return;
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final role = ref.watch(currentUserProvider).valueOrNull?.role;
    final canApprove = role?.canApproveOrAdmin ?? false;
    final canManage = role?.canManageFundOrAdmin ?? false;
    final visual = requestStatusVisual(request.status);
    final canDecide =
        canApprove && request.status == RequestStatus.released;
    // An offline release captured on this device but not yet server-confirmed.
    final isLocalPending = request.releaseState == 'localPending';
    // A conflicted (overdraft-on-sync) release the incharge can resolve.
    final isConflict = request.status == RequestStatus.conflict;
    final isDisputed = request.status == RequestStatus.disputed;
    final breakdown = computeRequestBreakdown(
      request,
      pendingPartial:
          ref.watch(pendingPartialByRequestProvider)[request.id] ?? Money.zero,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Request')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.lg),
        children: [
          // Hero proof image with loading + error placeholders.
          _ProofHero(request: request)
              .animate()
              .fadeIn(duration: 280.ms)
              .moveY(begin: 8, end: 0, duration: 280.ms),
          // Release proof photo + recipient signature captured at release
          // (proof reads first, then sign). Both self-hide when empty —
          // legacy/unreleased requests show nothing.
          if (request.hasReleaseProof) ...[
            const SizedBox(height: AppTokens.lg),
            ReleaseProofTile(proofUrl: request.releaseProofUrl)
                .animate()
                .fadeIn(delay: 40.ms, duration: 280.ms),
          ],
          if (request.hasReleaseSignature) ...[
            const SizedBox(height: AppTokens.lg),
            ReleaseSignatureTile(signatureUrl: request.releaseSignatureUrl)
                .animate()
                .fadeIn(delay: 60.ms, duration: 280.ms),
          ],
          // Offline release captured on this device, not yet synced: the proof
          // + signature images live locally and upload on reconnect. Explain
          // WHY the artefacts are missing rather than showing empty frames.
          if (isLocalPending) ...[
            const SizedBox(height: AppTokens.lg),
            _PendingSyncTile()
                .animate()
                .fadeIn(delay: 40.ms, duration: 280.ms),
          ],
          const SizedBox(height: AppTokens.lg),

          // Headline amount + status.
          SurfaceCard(
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
                          Text(
                            'Amount',
                            style: textTheme.labelMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            request.amount.format(),
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      label: visual.label,
                      tone: visual.tone,
                      icon: visual.icon,
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.lg),
                const Divider(height: 1),
                const SizedBox(height: AppTokens.md),
                _DetailRow(
                  icon: Icons.person_rounded,
                  label: 'Beneficiary',
                  value: request.beneficiaryName,
                ),
                const SizedBox(height: AppTokens.md),
                _DetailRow(
                  icon: Icons.notes_rounded,
                  label: 'Purpose',
                  value: request.purpose,
                ),
              ],
            ),
          ).animate().fadeIn(delay: 60.ms, duration: 280.ms),

          // Amount breakdown — only when this request has any partial
          // replenishment (approved and/or submitted-for-approval). Plain
          // requests skip this card entirely, leaving the screen unchanged.
          if (breakdown.hasAnyPartial) ...[
            const SizedBox(height: AppTokens.lg),
            SurfaceCard(
              child: RequestBreakdownView(
                breakdown: breakdown,
                compact: false,
              ),
            ).animate().fadeIn(delay: 90.ms, duration: 280.ms),
          ],

          const SizedBox(height: AppTokens.lg),

          // Status block.
          SurfaceCard(
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: StatusPill.colorsFor(visual.tone, scheme).$1,
                    borderRadius: AppTokens.brField,
                  ),
                  child: Icon(
                    visual.icon,
                    color: StatusPill.colorsFor(visual.tone, scheme).$2,
                  ),
                ),
                const SizedBox(width: AppTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current status',
                        style: textTheme.labelMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        visual.label,
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 120.ms, duration: 280.ms),

          // Conflict explainer: this release overdrew the fund when it synced.
          // For the incharge it carries the resolve action; everyone else just
          // sees why it's flagged.
          if (isConflict) ...[
            const SizedBox(height: AppTokens.lg),
            _ConflictCard(request: request, canResolve: canManage)
                .animate()
                .fadeIn(delay: 150.ms, duration: 280.ms),
          ],

          // Dispute audit: the recorded reason + who/when, so anyone opening a
          // disputed release sees the follow-up note (cash is NOT reversed).
          if (isDisputed && (request.disputedReason?.isNotEmpty ?? false)) ...[
            const SizedBox(height: AppTokens.lg),
            _DisputeCard(request: request)
                .animate()
                .fadeIn(delay: 150.ms, duration: 280.ms),
          ],

          if (canDecide) ...[
            const SizedBox(height: AppTokens.xl),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _acknowledge(context, ref),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Acknowledge'),
                ),
              ),
              const SizedBox(width: AppTokens.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _dispute(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                  ),
                  icon: const Icon(Icons.report_problem_rounded),
                  label: const Text('Dispute'),
                ),
              ),
            ]).animate().fadeIn(delay: 160.ms, duration: 280.ms),
          ],
        ],
      ),
    );
  }
}

/// Hero proof image, full-bleed within a rounded card, with shimmer-free
/// loading and a friendly error placeholder. Falls back to a "no proof" card
/// when the request has no attached image.
class _ProofHero extends StatelessWidget {
  const _ProofHero({required this.request});

  final FundRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const height = 240.0;

    Widget framed(Widget child) => ClipRRect(
          borderRadius: AppTokens.brCard,
          child: SizedBox(height: height, width: double.infinity, child: child),
        );

    if (!request.hasProof) {
      return framed(
        ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_not_supported_rounded,
                    size: 48, color: scheme.onSurfaceVariant),
                const SizedBox(height: AppTokens.sm),
                Text('No proof photo',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    return framed(
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
                size: 48, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

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

/// "Pending sync" tile for an offline release captured on this device whose
/// proof + signature images haven't uploaded yet. Neutral tones (being offline
/// is a supported state, not a fault) and an honest explanation.
class _PendingSyncTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SurfaceCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: AppTokens.brField,
            ),
            child: Icon(Icons.cloud_off_rounded, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Release pending sync',
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  'Recorded on this device. The proof photo and signature '
                  'upload automatically when you reconnect.',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Conflict explainer card — surfaces WHY a release is in conflict (overdrew
/// the fund on sync). For the incharge it carries the resolve action, which
/// opens the shared [ConflictResolutionSheet] (re-release / void, each
/// confirmed). Read-only for everyone else.
class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.request, required this.canResolve});
  final FundRequest request;
  final bool canResolve;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: scheme.error),
              const SizedBox(width: AppTokens.sm),
              Expanded(
                child: Text('Overdrew the fund on sync',
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.sm),
          Text(
            'The cash was already handed out, but the balance couldn’t cover '
            'it when this release reached the server. Resolve it by '
            're-releasing once funds allow, or voiding it.',
            style: textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (canResolve) ...[
            const SizedBox(height: AppTokens.md),
            FilledButton.icon(
              onPressed: () =>
                  ConflictResolutionSheet.show(context, request),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.build_rounded, size: 18),
              label: const Text('Resolve conflict'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dispute audit card — shows the recorded reason for a disputed release. The
/// honest line (cash is NOT reversed) lives in the dispute flow; here it's a
/// read-only record of the follow-up note.
class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.request});
  final FundRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: AppTokens.brCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.report_problem_rounded,
                  color: scheme.onErrorContainer),
              const SizedBox(width: AppTokens.sm),
              Text('Disputed',
                  style: textTheme.titleSmall?.copyWith(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: AppTokens.sm),
          Text(
            request.disputedReason ?? '',
            style: textTheme.bodyMedium
                ?.copyWith(color: scheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}
