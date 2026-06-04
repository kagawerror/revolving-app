import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_providers.dart';
import 'request_status_visual.dart';

class RequestDetailScreen extends ConsumerWidget {
  final FundRequest request;
  const RequestDetailScreen({super.key, required this.request});

  Future<void> _decide(
      BuildContext context, WidgetRef ref, RequestStatus to) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final res = await ref.read(requestRepositoryProvider).transition(
          request: request,
          to: to,
          actorUid: user.uid,
        );
    if (!context.mounted) return;
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final canApprove =
        ref.watch(currentUserProvider).valueOrNull?.role.canApproveOrAdmin ??
            false;
    final visual = requestStatusVisual(request.status);
    final canDecide =
        canApprove && request.status == RequestStatus.pendingAck;

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

          if (canDecide) ...[
            const SizedBox(height: AppTokens.xl),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      _decide(context, ref, RequestStatus.acknowledged),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: AppTokens.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _decide(context, ref, RequestStatus.rejected),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Reject'),
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
