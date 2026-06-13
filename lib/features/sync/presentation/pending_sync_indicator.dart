import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/outbox_entry.dart';
import 'sync_providers.dart';

/// ── Derived view-models over the existing outbox stream ──────────────────────
///
/// These are PRESENTATION-ONLY selectors layered on the already-wired
/// [outboxProvider]; they add no new data source. Phase 6 may lift them into
/// `sync_providers.dart` verbatim if it prefers them centralized, but they're
/// kept here so the indicator widgets are self-contained and import-clean.

/// A compact summary of the outbox the UI cares about: how many entries are
/// still in flight, and whether any of them need human attention.
@immutable
class SyncSummary {
  const SyncSummary({
    required this.pendingCount,
    required this.hasAttention,
  });

  /// Entries not yet `done` and not `failed` — i.e. genuinely "still syncing".
  /// `failed` is excluded from the *pending* count because it isn't draining on
  /// its own; it surfaces through [hasAttention] instead so it can't hide as a
  /// forever-spinning number.
  final int pendingCount;

  /// True when any entry is in `conflict` or `failed` — the badge should switch
  /// from a calm "syncing" look to a "needs attention" treatment.
  final bool hasAttention;

  bool get isClear => pendingCount == 0 && !hasAttention;

  // Value equality so the badge only rebuilds when the summary actually
  // changes — _syncSummaryProvider re-runs on every outbox tick, but most ticks
  // (e.g. an entry moving pending→uploading→replaying) leave pendingCount and
  // hasAttention unchanged.
  @override
  bool operator ==(Object other) =>
      other is SyncSummary &&
      other.pendingCount == pendingCount &&
      other.hasAttention == hasAttention;

  @override
  int get hashCode => Object.hash(pendingCount, hasAttention);
}

final _syncSummaryProvider = Provider<SyncSummary>((ref) {
  final entries = ref.watch(outboxProvider).valueOrNull ?? const <OutboxEntry>[];
  var pending = 0;
  var attention = false;
  for (final e in entries) {
    switch (e.state) {
      case OutboxState.pending:
      case OutboxState.uploading:
      case OutboxState.replaying:
        pending++;
      case OutboxState.conflict:
      case OutboxState.failed:
        attention = true;
      case OutboxState.done:
        break;
    }
  }
  return SyncSummary(pendingCount: pending, hasAttention: attention);
});

/// ── Pending-sync badge (app-bar action) ──────────────────────────────────────
///
/// Lives in the incharge home AppBar's `actions` (the natural spot — the
/// incharge is the only role that queues offline mutations). One tap opens the
/// [SyncStatusSheet]; the count + tone communicate state at rest without a tap.
///
/// Three visual states, all label-bearing (never color-only):
///   • clear      → not shown at all (zero chrome when nothing is queued).
///   • syncing    → neutral pill, animated cloud-upload, "N pending".
///   • attention  → danger pill, "N to fix" (any conflict/failed entry).
class PendingSyncBadge extends ConsumerWidget {
  const PendingSyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(_syncSummaryProvider);
    // Nothing queued and nothing wrong: render no chrome. A finance app should
    // be quiet when there's nothing to say.
    if (summary.isClear) return const SizedBox.shrink();

    final tone = summary.hasAttention ? StatusTone.danger : StatusTone.neutral;
    final label = summary.hasAttention
        ? (summary.pendingCount > 0
            ? '${summary.pendingCount} pending · needs attention'
            : 'Needs attention')
        : '${summary.pendingCount} pending';
    final icon = summary.hasAttention
        ? Icons.error_outline_rounded
        : Icons.cloud_upload_rounded;

    return Padding(
      padding: const EdgeInsets.only(right: AppTokens.sm),
      child: Semantics(
        button: true,
        label: summary.hasAttention
            ? 'Sync needs attention. $label. Open sync status.'
            : 'Sync pending. $label. Open sync status.',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.rPill),
          onTap: () => SyncStatusSheet.show(context),
          // 48dp tap target floor with the pill centred inside.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              child: _MiniPill(label: label, icon: icon, tone: tone),
            ),
          ),
        ),
      ),
    );
  }
}

/// A StatusPill-styled chip sized down for the app bar, reusing the exact
/// tone→color mapping so it matches every other status surface in the app.
class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.label, required this.icon, required this.tone});

  final String label;
  final IconData icon;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = StatusPill.colorsFor(tone, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.sm + 2, vertical: AppTokens.xs + 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: AppTokens.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

/// ── Offline banner ────────────────────────────────────────────────────────────
///
/// A slim, calm banner shown when [connectivityProvider] is false. Drop it at
/// the top of a body Column (above the list) — it self-collapses to nothing when
/// online, so it's safe to leave mounted unconditionally. Deliberately uses the
/// neutral `surfaceContainerHighest` field, NOT an error red: being offline is a
/// normal, supported state in this app, not a fault.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityProvider).valueOrNull ?? false;
    final showBanner = !online;

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !showBanner
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              label:
                  'You are offline. Changes are saved on this device and will sync when you reconnect.',
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(
                    AppTokens.lg, AppTokens.sm, AppTokens.lg, 0),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.md, vertical: AppTokens.sm + 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: AppTokens.brField,
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 20, color: scheme.onSurfaceVariant),
                    const SizedBox(width: AppTokens.sm),
                    Expanded(
                      child: Text(
                        'Offline — changes saved on this device.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// ── Sync status sheet (the "Sync now" surface) ───────────────────────────────
///
/// Opened from [PendingSyncBadge]. Shows the live online/offline state, the
/// pending count, an attention notice when anything is in conflict/failed, and a
/// single primary "Sync now" action that calls `syncEngineProvider.drain()`.
/// Owns its own transient "syncing…" flag for the duration of the drain so the
/// button reads honestly without needing a global notifier.
class SyncStatusSheet extends ConsumerStatefulWidget {
  const SyncStatusSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const SyncStatusSheet(),
      );

  @override
  ConsumerState<SyncStatusSheet> createState() => _SyncStatusSheetState();
}

class _SyncStatusSheetState extends ConsumerState<SyncStatusSheet> {
  bool _draining = false;

  Future<void> _syncNow() async {
    setState(() => _draining = true);
    try {
      await ref.read(syncEngineProvider).drain();
    } finally {
      if (mounted) setState(() => _draining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final online = ref.watch(connectivityProvider).valueOrNull ?? false;
    final summary = ref.watch(_syncSummaryProvider);

    final (headIcon, headTone, headTitle, headBody) = switch ((
      online,
      summary.hasAttention,
      summary.pendingCount
    )) {
      (_, true, _) => (
          Icons.error_outline_rounded,
          StatusTone.danger,
          'Some changes need attention',
          'One or more saved changes couldn’t sync cleanly. Open the affected '
              'items below to resolve them — your recorded cash releases are '
              'safe on this device in the meantime.',
        ),
      (false, false, final n) when n > 0 => (
          Icons.cloud_off_rounded,
          StatusTone.neutral,
          'Offline — $n change${n == 1 ? '' : 's'} waiting',
          'Your changes are saved on this device and will sync automatically '
              'the moment you’re back online.',
        ),
      (true, false, final n) when n > 0 => (
          Icons.cloud_upload_rounded,
          StatusTone.info,
          '$n change${n == 1 ? '' : 's'} waiting to sync',
          'You’re online. Tap “Sync now” to push these up immediately, or '
              'they’ll sync on their own shortly.',
        ),
      _ => (
          Icons.check_circle_rounded,
          StatusTone.success,
          'All changes synced',
          'Everything on this device is up to date with the server.',
        ),
    };

    final (bg, fg) = StatusPill.colorsFor(headTone, scheme);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.46,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.rCard)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
              AppTokens.lg, AppTokens.md, AppTokens.lg, AppTokens.xl),
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
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: bg, borderRadius: AppTokens.brField),
                  child: Icon(headIcon, color: fg),
                ),
                const SizedBox(width: AppTokens.md),
                Expanded(
                  child: Text(
                    headTitle,
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.md),
            Text(
              headBody,
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppTokens.xl),
            // Primary action — disabled when nothing is pending or while a
            // drain is already running. Offline is allowed: drain() is a no-op
            // when unreachable, but trying is honest and harmless.
            FilledButton.icon(
              onPressed: (_draining || summary.pendingCount == 0)
                  ? null
                  : _syncNow,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: _draining
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(_draining ? 'Syncing…' : 'Sync now'),
            ),
            if (online && summary.pendingCount > 0 && !_draining) ...[
              const SizedBox(height: AppTokens.sm),
              Center(
                child: Text(
                  'Changes also sync automatically.',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wires a one-shot drain on the offline→online edge for any screen that mounts
/// it. The app already wires `wireSyncOnReconnect` at the root; this is only a
/// convenience for standalone screens that want the same behavior locally.
void unawaitedDrain(WidgetRef ref) =>
    unawaited(ref.read(syncEngineProvider).drain());
