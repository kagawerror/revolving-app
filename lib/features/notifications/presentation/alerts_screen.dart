import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../replenishment/domain/replenishment.dart';
import '../../replenishment/domain/replenishment_fill.dart';
import '../../replenishment/presentation/replenishment_detail_screen.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../../requests/domain/fund_request.dart';
import '../../requests/presentation/request_detail_screen.dart';
import '../../requests/presentation/request_providers.dart';
import '../domain/app_notification.dart';
import 'notification_providers.dart';

/// Visual treatment for an alert: a tone (drives icon/pill colors), an icon, a
/// short pill label, and a kind label for the enriched header. Pure mapping
/// from the notification `type` so the same alert kind always reads the same.
class _AlertVisual {
  const _AlertVisual(this.tone, this.icon, this.label, this.kindLabel);
  final StatusTone tone;
  final IconData icon;
  final String label;
  final String kindLabel;
}

_AlertVisual _visualFor(AppNotification n) {
  switch (n.type) {
    case 'lowBalance':
      return const _AlertVisual(
        StatusTone.warning,
        Icons.warning_amber_rounded,
        'Low balance',
        'Low balance',
      );
    case 'replenishmentSubmitted':
      return const _AlertVisual(
        StatusTone.info,
        Icons.outbox_rounded,
        'Submitted',
        'Replenishment',
      );
    case 'replenishmentNeedsAck':
      return const _AlertVisual(
        StatusTone.info,
        Icons.fact_check_rounded,
        'To acknowledge',
        'Replenishment',
      );
    case 'replenishmentAcknowledged':
      return const _AlertVisual(
        StatusTone.success,
        Icons.verified_rounded,
        'Acknowledged',
        'Replenishment',
      );
    case 'replenishmentApproved':
      return const _AlertVisual(
        StatusTone.success,
        Icons.verified_rounded,
        'Approved',
        'Replenishment',
      );
    case 'replenishmentRejected':
      return const _AlertVisual(
        StatusTone.danger,
        Icons.cancel_rounded,
        'Rejected',
        'Replenishment',
      );
    case 'requestReleased':
      return const _AlertVisual(
        StatusTone.info,
        Icons.payments_rounded,
        'To review',
        'Release',
      );
    case 'requestAcknowledged':
      return const _AlertVisual(
        StatusTone.success,
        Icons.verified_rounded,
        'Acknowledged',
        'Release',
      );
    case 'requestDisputed':
      return const _AlertVisual(
        StatusTone.warning,
        Icons.report_problem_rounded,
        'Disputed',
        'Release',
      );
    case 'requestRejected':
      return const _AlertVisual(
        StatusTone.danger,
        Icons.cancel_rounded,
        'Rejected',
        'Request',
      );
    default:
      return const _AlertVisual(
        StatusTone.neutral,
        Icons.notifications_rounded,
        'Alert',
        'Alert',
      );
  }
}

/// Fill chip label for an enriched replenishment alert.
String _fillLabel(ReplenishmentFill fill) => switch (fill) {
      ReplenishmentFill.full => 'Full',
      ReplenishmentFill.partial => 'Partial',
      ReplenishmentFill.mixed => 'Mixed',
    };

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(myNotificationsProvider);
    // canApproveOrAdmin (not canApprove) so admins — who act on the same
    // requestReleased / replenishmentSubmitted alerts — get the tap-to-open
    // affordance. Incharge is false for both, so its behavior is unchanged.
    final isApprover =
        ref.watch(currentUserProvider).valueOrNull?.role.canApproveOrAdmin ??
            false;
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: SafeArea(
        child: alerts.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppTokens.lg),
            child: SurfaceCard(child: SkeletonList(count: 6)),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.xl),
              child: EmptyState(
                title: 'Couldn’t load alerts',
                message: 'Something went wrong fetching your alerts. '
                    'Pull down or come back in a moment.',
                showMascot: false,
              ),
            ),
          ),
          data: (list) => list.isEmpty
              ? const EmptyState(
                  title: 'You’re all caught up',
                  message: 'No alerts right now. We’ll let you know when '
                      'something needs your attention.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppTokens.lg),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final n = list[i];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: i == list.length - 1 ? 0 : AppTokens.md,
                      ),
                      child: _AlertCard(
                        notification: n,
                        isApprover: isApprover,
                      ),
                    ).animate().fadeIn(
                          duration: 260.ms,
                          delay: (40 * i).clamp(0, 280).ms,
                        );
                  },
                ),
        ),
      ),
    );
  }
}

/// One alert row. Stateful only to track its own "opening…" busy flag while the
/// approver's tap-to-review loads the replenishment. Renders the enriched layout
/// when the notification carries a denormalized amount, else falls back to the
/// legacy [AppListTile] (kept pixel-identical for old/lowBalance docs).
class _AlertCard extends ConsumerStatefulWidget {
  const _AlertCard({required this.notification, required this.isApprover});

  final AppNotification notification;
  final bool isApprover;

  @override
  ConsumerState<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends ConsumerState<_AlertCard> {
  bool _busy = false;

  AppNotification get _n => widget.notification;

  /// Approver tap on a replenishment alert opens the detail screen — to
  /// acknowledge an auto-approved report (`replenishmentNeedsAck`) or to review
  /// a legacy in-flight `submitted` one.
  bool get _isReviewable =>
      widget.isApprover &&
      (_n.type == 'replenishmentNeedsAck' ||
          _n.type == 'replenishmentSubmitted') &&
      _n.replenishmentId != null;

  /// A request alert that opens the request detail screen on tap.
  ///  - `requestReleased` is the approver's "to review" affordance.
  ///  - the incharge-facing decision alerts (acknowledged/disputed/rejected)
  ///    open the incharge's own request for context.
  /// Both load the [FundRequest] by id and push [RequestDetailScreen].
  bool get _isOpenableRequest {
    if (_n.requestId == null) return false;
    if (_n.type == 'requestReleased') return widget.isApprover;
    return !widget.isApprover &&
        (_n.type == 'requestAcknowledged' ||
            _n.type == 'requestDisputed' ||
            _n.type == 'requestRejected');
  }

  /// Whether a tap loads + navigates (vs. just marking read). Drives the busy
  /// spinner affordance and the disabled-while-busy guard.
  bool get _isActionable => _isReviewable || _isOpenableRequest;

  void _markReadOnly() {
    if (_n.isUnread) {
      ref.read(notificationRepositoryProvider).markRead(_n.id).ignore();
    }
  }

  Future<void> _openReview() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Preserve the existing mark-read behavior on tap.
    if (_n.isUnread) {
      ref.read(notificationRepositoryProvider).markRead(_n.id).ignore();
    }
    final res = await ref
        .read(replenishmentRepositoryProvider)
        .getById(_n.replenishmentId!);
    if (!mounted) return;
    setState(() => _busy = false);
    final Replenishment? rep = res.valueOrNull;
    if (rep == null) {
      // A missing doc is a clean "gone" case; anything else is a load/offline
      // failure that's worth a retry.
      final gone = res.failureOrNull is NotFoundFailure;
      final msg = gone
          ? 'This replenishment is no longer available.'
          : 'Can’t open this right now. Check your connection and try again.';
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReplenishmentDetailScreen(replenishment: rep),
      ),
    );
  }

  /// Loads the [FundRequest] by id and opens [RequestDetailScreen]. Mirrors
  /// [_openReview] (busy flag, mark-read, NotFound-vs-offline SnackBar split,
  /// mounted guards). Used by both the approver's "to review" release alert and
  /// the incharge's decision alerts.
  Future<void> _openRequest() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_n.isUnread) {
      ref.read(notificationRepositoryProvider).markRead(_n.id).ignore();
    }
    final res =
        await ref.read(requestRepositoryProvider).getById(_n.requestId!);
    if (!mounted) return;
    setState(() => _busy = false);
    final FundRequest? req = res.valueOrNull;
    if (req == null) {
      final gone = res.failureOrNull is NotFoundFailure;
      final msg = gone
          ? 'This request is no longer available.'
          : 'Can’t open this right now. Check your connection and try again.';
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RequestDetailScreen(request: req),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(_n);
    // Enriched layout when the alert carries a denormalized hero amount — either
    // a replenishment total or a request amount.
    final hasEnriched =
        _n.replenishAmount != null || _n.requestAmount != null;

    final VoidCallback? onTap = _isReviewable
        ? (_busy ? null : _openReview)
        : _isOpenableRequest
            ? (_busy ? null : _openRequest)
            : (_n.isUnread ? _markReadOnly : null);

    if (!hasEnriched) {
      // Legacy / lowBalance layout — unchanged.
      return SurfaceCard(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.xs),
        child: AppListTile(
          leading: _AlertLeading(tone: visual.tone, icon: visual.icon),
          title: _n.title,
          subtitle: _n.body,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusPill(label: visual.label, tone: visual.tone),
              if (_n.isUnread) ...[
                const SizedBox(height: AppTokens.xs),
                _UnreadDot(tone: visual.tone),
              ],
            ],
          ),
          onTap: onTap,
        ),
      );
    }

    return _EnrichedAlertCard(
      notification: _n,
      visual: visual,
      // Show the open/review affordance for any alert whose tap navigates —
      // replenishment review OR request open.
      showAffordance: _isActionable,
      // The puck reads "Review" for the approver's release queue, "Open"
      // otherwise (incharge decision alerts).
      affordanceIsReview: _isReviewable,
      busy: _busy,
      onTap: onTap,
    );
  }
}

/// The rich replenishment alert: a hero amount, a fill chip, fund/company
/// context, a "by {actor}" + fund-balance meta line, and (for approvers) a
/// Review affordance.
class _EnrichedAlertCard extends StatelessWidget {
  const _EnrichedAlertCard({
    required this.notification,
    required this.visual,
    required this.showAffordance,
    required this.affordanceIsReview,
    required this.busy,
    required this.onTap,
  });

  final AppNotification notification;
  final _AlertVisual visual;
  final bool showAffordance;
  final bool affordanceIsReview;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final n = notification;
    // Hero amount = replenishment total, else request amount. One of the two is
    // non-null here (the enriched branch requires it).
    final amount = n.replenishAmount ?? n.requestAmount!;
    // A request alert renders beneficiary/purpose instead of a fill chip +
    // fund-balance meta (which are null on request docs and self-hide).
    final isRequestRow = n.requestAmount != null;
    // Original (pre-partial) total line, for partial/mixed replenishments only.
    final showOriginal = !isRequestRow &&
        n.fill != null &&
        n.fill != ReplenishmentFill.full &&
        n.originalAmount != null;

    return SurfaceCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: leading icon + kind/status + unread dot.
          Row(
            children: [
              _AlertLeading(tone: visual.tone, icon: visual.icon),
              const SizedBox(width: AppTokens.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visual.kindLabel,
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusPill(label: visual.label, tone: visual.tone),
                  if (n.isUnread) ...[
                    const SizedBox(height: AppTokens.xs),
                    _UnreadDot(tone: visual.tone),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: AppTokens.md),
          // Hero amount + fill chip.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  amount.format(),
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Replenishment rows carry a fill chip; request rows don't.
              if (n.fill != null) ...[
                const SizedBox(width: AppTokens.sm),
                _FillChip(label: _fillLabel(n.fill!)),
              ],
            ],
          ),
          // Original (pre-partial) total, under a partial/mixed hero only.
          if (showOriginal) ...[
            const SizedBox(height: 2),
            Text(
              'of ${n.originalAmount!.format()}',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          // Context line: for replenishments, fund · company; for requests,
          // beneficiary · fund (beneficiary surfaced via companyName slot of
          // the same two-part line for layout parity).
          if (isRequestRow) ...[
            if (n.requestBeneficiaryName != null || n.fundName != null) ...[
              const SizedBox(height: AppTokens.sm),
              _ContextLine(
                fundName: n.requestBeneficiaryName,
                companyName: n.fundName,
              ),
            ],
            // Purpose line (request rows only).
            if (n.requestPurpose != null && n.requestPurpose!.isNotEmpty) ...[
              const SizedBox(height: AppTokens.xs),
              Text(
                n.requestPurpose!,
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ] else if (n.fundName != null || n.companyName != null) ...[
            const SizedBox(height: AppTokens.sm),
            _ContextLine(fundName: n.fundName, companyName: n.companyName),
          ],
          // Meta line: by {actor} · fund balance {x}. For request decision rows
          // this carries the "by {approver}"; availableBalance is null there.
          if (n.actorName != null || n.availableBalance != null) ...[
            const SizedBox(height: AppTokens.xs),
            _MetaLine(
              actorName: n.actorName,
              balanceText: n.availableBalance?.format(),
            ),
          ],
          if (showAffordance) ...[
            const SizedBox(height: AppTokens.md),
            Align(
              alignment: Alignment.centerLeft,
              child: _ReviewAffordance(busy: busy, isReview: affordanceIsReview),
            ),
          ],
        ],
      ),
    );
  }
}

/// Neutral outlined chip naming the fill type (Full / Partial / Mixed).
class _FillChip extends StatelessWidget {
  const _FillChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.sm,
        vertical: AppTokens.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rPill),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// "fund · company", each part independently ellipsized.
class _ContextLine extends StatelessWidget {
  const _ContextLine({this.fundName, this.companyName});
  final String? fundName;
  final String? companyName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final parts = <Widget>[];
    if (fundName != null && fundName!.isNotEmpty) {
      parts.add(Flexible(
        child: Text(fundName!,
            style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ));
    }
    if (companyName != null && companyName!.isNotEmpty) {
      if (parts.isNotEmpty) {
        parts.add(Text(' · ', style: style));
      }
      parts.add(Flexible(
        child: Text(companyName!,
            style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ));
    }
    return Row(children: parts);
  }
}

/// "by {actor} · 🪙 Fund balance {x}". Each element null-guarded.
class _MetaLine extends StatelessWidget {
  const _MetaLine({this.actorName, this.balanceText});
  final String? actorName;
  final String? balanceText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final children = <Widget>[];
    if (actorName != null && actorName!.isNotEmpty) {
      children.add(Flexible(
        child: Text('by ${actorName!}',
            style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ));
    }
    if (balanceText != null) {
      if (children.isNotEmpty) {
        children.add(Text(' · ', style: style));
      }
      children
        ..add(Icon(Icons.account_balance_wallet_outlined,
            size: 14, color: scheme.onSurfaceVariant))
        ..add(const SizedBox(width: AppTokens.xs))
        ..add(Text('Fund balance $balanceText', style: style));
    }
    return Row(children: children);
  }
}

/// Primary-container puck inviting the user to open the report/request. Reads
/// "Review" for the approver's queue, "Open" for an incharge's own item.
class _ReviewAffordance extends StatelessWidget {
  const _ReviewAffordance({required this.busy, this.isReview = true});
  final bool busy;
  final bool isReview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: AppTokens.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppTokens.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            busy ? 'Opening…' : (isReview ? 'Review' : 'Open'),
            style: textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: AppTokens.xs),
          if (busy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onPrimaryContainer,
              ),
            )
          else
            Icon(Icons.chevron_right_rounded,
                size: 18, color: scheme.onPrimaryContainer),
        ],
      ),
    );
  }
}

/// Tone-colored rounded leading icon, matching the sibling list screens.
class _AlertLeading extends StatelessWidget {
  const _AlertLeading({required this.tone, required this.icon});

  final StatusTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = StatusPill.colorsFor(tone, scheme);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: bg, borderRadius: AppTokens.brField),
      child: Icon(icon, color: fg, size: 22),
    );
  }
}

/// Small "unread" marker. Text-labelled via [Semantics] so it isn't color-only.
class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.tone});

  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (_, fg) = StatusPill.colorsFor(tone, scheme);
    return Semantics(
      label: 'Unread',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
      ),
    );
  }
}
