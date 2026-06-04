import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../domain/app_notification.dart';
import 'notification_providers.dart';

/// Visual treatment for an alert: a tone (drives icon/pill colors), an icon,
/// and a short pill label. Pure mapping from the notification `type` string so
/// the same alert kind always reads the same way.
class _AlertVisual {
  const _AlertVisual(this.tone, this.icon, this.label);
  final StatusTone tone;
  final IconData icon;
  final String label;
}

_AlertVisual _visualFor(AppNotification n) {
  switch (n.type) {
    case 'lowBalance':
      return const _AlertVisual(
        StatusTone.warning,
        Icons.warning_amber_rounded,
        'Low balance',
      );
    case 'replenishmentSubmitted':
      return const _AlertVisual(
        StatusTone.info,
        Icons.outbox_rounded,
        'Submitted',
      );
    case 'replenishmentApproved':
      return const _AlertVisual(
        StatusTone.success,
        Icons.verified_rounded,
        'Approved',
      );
    case 'replenishmentRejected':
      return const _AlertVisual(
        StatusTone.danger,
        Icons.cancel_rounded,
        'Rejected',
      );
    default:
      return const _AlertVisual(
        StatusTone.neutral,
        Icons.notifications_rounded,
        'Alert',
      );
  }
}

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(myNotificationsProvider);
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
                        onTap: n.isUnread
                            ? () => ref
                                .read(notificationRepositoryProvider)
                                .markRead(n.id)
                                .ignore()
                            : null,
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

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.notification, this.onTap});

  final AppNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(notification);
    final unread = notification.isUnread;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.xs),
      child: AppListTile(
        leading: _AlertLeading(tone: visual.tone, icon: visual.icon),
        title: notification.title,
        subtitle: notification.body,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusPill(label: visual.label, tone: visual.tone),
            if (unread) ...[
              const SizedBox(height: AppTokens.xs),
              _UnreadDot(tone: visual.tone),
            ],
          ],
        ),
        onTap: onTap,
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
