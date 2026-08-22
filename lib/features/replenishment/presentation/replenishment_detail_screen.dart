import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/success_overlay.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/replenishment.dart';
import '../domain/replenishment_status.dart';
import 'rejection_reason_sheet.dart';
import 'replenishment_providers.dart';
import 'replenishment_status_ui.dart';

class ReplenishmentDetailScreen extends ConsumerStatefulWidget {
  final Replenishment replenishment;
  const ReplenishmentDetailScreen({super.key, required this.replenishment});

  @override
  ConsumerState<ReplenishmentDetailScreen> createState() =>
      _ReplenishmentDetailScreenState();
}

class _ReplenishmentDetailScreenState
    extends ConsumerState<ReplenishmentDetailScreen> {
  bool _busy = false;

  /// Confirms an approve/reject before any side effect. Both decisions are
  /// terminal business actions (approve CREDITS the fund; reject is final), so
  /// each routes through a confirmation dialog matching the app's
  /// `showDialog<bool>` + `AlertDialog` pattern (cf. request acknowledge /
  /// release cash). The dialog shows BEFORE the in-flight busy state is set, so
  /// no spinner appears underneath it; cancel returns without side effects.
  Future<bool> _confirm(bool approve) async {
    final r = widget.replenishment;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
            approve ? Icons.account_balance_wallet_rounded : Icons.cancel_rounded),
        title: Text(approve ? 'Approve & replenish?' : 'Reject replenishment?'),
        content: Text(
          approve
              ? 'This credits ${r.total.format()} back to the fund and closes '
                  'this report. It bundles ${r.itemCount} '
                  '${r.itemCount == 1 ? 'request' : 'requests'} and is final — '
                  'it cannot be undone.'
              : 'This rejects the ${r.total.format()} replenishment report. No '
                  'money moves, but the decision is final and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: Icon(approve ? Icons.check_rounded : Icons.block_rounded,
                size: 18),
            label: Text(approve ? 'Approve & replenish' : 'Reject'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _decide(bool approve) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    // Reject requires a remark the incharge will read; approve keeps its
    // existing plain confirm. Both gates show BEFORE the busy state so no
    // spinner appears beneath the dialog/sheet, and cancel aborts cleanly.
    String? reason;
    if (approve) {
      if (!await _confirm(true)) return;
    } else {
      reason = await RejectionReasonSheet.show(context, widget.replenishment);
      if (reason == null) return; // cancelled / dismissed
    }
    if (!mounted) return;

    setState(() => _busy = true);
    final repo = ref.read(replenishmentRepositoryProvider);
    final res = approve
        ? await repo.approve(
            replenishment: widget.replenishment, actorUid: user.uid)
        : await repo.reject(
            replenishment: widget.replenishment,
            actorUid: user.uid,
            reason: reason!,
          );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.showOnError(context)) {
      // Celebrate the sign-off, then complete the existing pop. The overlay
      // awaits its own dismissal, so the pop-on-success behavior is preserved.
      await SuccessOverlay.show(
          context, approve ? 'Replenishment approved' : 'Replenishment rejected');
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  /// Confirms acknowledgment before stamping it. The fund is ALREADY credited;
  /// this only records that the approver saw the report — so the copy says so.
  Future<bool> _confirmAcknowledge() async {
    final r = widget.replenishment;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.fact_check_rounded),
        title: const Text('Acknowledge replenishment?'),
        content: Text(
          'The fund was already replenished with ${r.total.format()} '
          '(${r.itemCount} ${r.itemCount == 1 ? 'request' : 'requests'}). '
          'Acknowledging confirms you have seen it.',
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
    return confirmed == true;
  }

  Future<void> _acknowledge() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    if (!await _confirmAcknowledge()) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final res = await ref.read(replenishmentRepositoryProvider).acknowledge(
          replenishment: widget.replenishment,
          actorUid: user.uid,
          actorName: user.displayName,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.showOnError(context)) {
      await SuccessOverlay.show(context, 'Replenishment acknowledged');
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canApprove =
        ref.watch(currentUserProvider).valueOrNull?.role.canApproveOrAdmin ??
            false;
    final r = widget.replenishment;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ids = r.requestIds;

    return Scaffold(
      appBar: AppBar(title: const Text('Replenishment')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.lg),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    StatusPill(
                      label: replenishmentStatusLabel(r.status),
                      tone: replenishmentStatusTone(r.status),
                      icon: replenishmentStatusIcon(r.status),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.xs),
                Text(
                  r.total.format(),
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppTokens.sm),
                Text(
                  '${r.itemCount} bundled ${r.itemCount == 1 ? 'request' : 'requests'}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                // Auto-approved + not yet acknowledged: info banner telling the
                // reader the fund is already credited and only an
                // acknowledgment remains.
                if (r.needsAcknowledgment) ...[
                  const SizedBox(height: AppTokens.md),
                  _AcknowledgmentBanner(),
                ],
                // Already acknowledged: success callout with who/when.
                if (r.status == ReplenishmentStatus.approved &&
                    r.acknowledgedByUid != null) ...[
                  const SizedBox(height: AppTokens.md),
                  _AcknowledgedCallout(
                    name: r.acknowledgedByName,
                    uid: r.acknowledgedByUid!,
                    at: r.acknowledgedAt,
                  ),
                ],
                if (r.reportNotes.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppTokens.md),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: AppTokens.brField,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notes',
                          style: textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppTokens.xs),
                        Text(r.reportNotes, style: textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
                // Rejection remarks — the approver's required reason, surfaced
                // to the incharge in an error-toned callout so the WHY of a
                // rejected report is unmissable. Shown only when rejected with
                // a non-empty reason (older reports may predate this field).
                if (r.status == ReplenishmentStatus.rejected &&
                    (r.rejectionReason?.trim().isNotEmpty ?? false)) ...[
                  const SizedBox(height: AppTokens.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppTokens.md),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: AppTokens.brField,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.cancel_rounded,
                                size: 16, color: scheme.onErrorContainer),
                            const SizedBox(width: AppTokens.xs),
                            Text(
                              'Rejection remarks',
                              style: textTheme.labelMedium?.copyWith(
                                color: scheme.onErrorContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTokens.xs),
                        Text(
                          r.rejectionReason!.trim(),
                          style: textTheme.bodyMedium
                              ?.copyWith(color: scheme.onErrorContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.06, end: 0),
          const SectionHeader(title: 'Released requests'),
          ...List.generate(ids.length, (i) {
            return AppListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  '${i + 1}',
                  style: textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: 'Request #${i + 1}',
              subtitle: ids[i],
            ).animate(delay: (40 * i).ms).fadeIn(duration: 220.ms);
          }),
          const SizedBox(height: AppTokens.xl),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: AppTokens.lg),
                child: CircularProgressIndicator(),
              ),
            ),
          // AUTO-APPROVE acknowledgment: a single full-width Acknowledge action
          // (no reject — there is nothing to reverse). Gated to approvers on a
          // report still needing acknowledgment.
          if (canApprove && r.needsAcknowledgment)
            FilledButton.icon(
              onPressed: _busy ? null : _acknowledge,
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text('Acknowledge'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          // LEGACY in-flight `submitted` reports keep the approve/reject pair.
          if (canApprove && r.status == ReplenishmentStatus.submitted)
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _decide(true),
                  child: const Text('Approve'),
                ),
              ),
              const SizedBox(width: AppTokens.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Reject'),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}

/// Info-toned banner shown on an auto-approved report that no approver has yet
/// acknowledged. Reassures the reader the fund is ALREADY credited and only an
/// acknowledgment remains.
class _AcknowledgmentBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: AppTokens.brField,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_rounded, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Needs acknowledgment',
                  style: textTheme.labelLarge?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'The fund has already been replenished. Acknowledge to confirm '
                  'you have seen this report.',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSecondaryContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Success-toned callout shown once an approver has acknowledged the report,
/// naming who and when (name → short-uid fallback).
class _AcknowledgedCallout extends StatelessWidget {
  const _AcknowledgedCallout({required this.name, required this.uid, this.at});

  final String? name;
  final String uid;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final who = (name != null && name!.trim().isNotEmpty)
        ? name!.trim()
        : (uid.length > 6 ? '#${uid.substring(0, 6)}' : '#$uid');
    final when = at == null
        ? ''
        : ' · ${at!.year}-${at!.month.toString().padLeft(2, '0')}-'
            '${at!.day.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: AppTokens.brField,
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded,
              size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Text(
              'Acknowledged by $who$when',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
