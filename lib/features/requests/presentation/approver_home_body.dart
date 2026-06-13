import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../replenishment/presentation/replenishment_detail_screen.dart';
import '../../replenishment/presentation/replenishment_providers.dart';
import '../../sync/presentation/pending_sync_indicator.dart';
import 'approver_inbox_providers.dart';
import 'request_detail_screen.dart';
import 'request_status_visual.dart';

/// Body of the approver landing tab: the pending replenishments + requests
/// inbox for the resolved company. Body-only — the [RoleShellScreen] owns the
/// Scaffold, AppBar, and [CompanyContextBar].
class ApproverHomeBody extends ConsumerWidget {
  const ApproverHomeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final companyId = user == null
        ? ''
        : effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));

    // Admin with no company picked: prompt instead of empty inboxes.
    if (companyId.isEmpty) return const AdminSelectCompanyPrompt();
    return const _ApproverInbox();
  }
}

class _ApproverInbox extends ConsumerWidget {
  const _ApproverInbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRequestsProvider);
    final replenishments = ref.watch(pendingReplenishmentsProvider);

    return ListView(
        padding: const EdgeInsets.fromLTRB(AppTokens.lg, AppTokens.sm,
            AppTokens.lg, AppTokens.bottomNavContentInset),
        children: [
          // Approvers act offline too (acknowledge/dispute queue locally) — let
          // them see they're offline. Self-collapses when online.
          const OfflineBanner(),
          SectionHeader(
            title: 'Pending replenishments',
            trailing: replenishments.maybeWhen(
              data: (list) =>
                  list.isEmpty ? null : _CountBadge(count: list.length),
              orElse: () => null,
            ),
          ),
          replenishments.when(
            loading: () => const SurfaceCard(child: SkeletonList(count: 2)),
            error: (e, _) => _ErrorCard(message: '$e'),
            data: (list) => list.isEmpty
                ? const SurfaceCard(
                    child: EmptyState(
                      title: 'No pending replenishments',
                      message: 'Replenishment reports awaiting your sign-off '
                          'will appear here.',
                    ),
                  )
                : SurfaceCard(
                    padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
                    child: Column(
                      children: [
                        for (final r in list)
                          AppListTile(
                            leading: _LeadingIcon(
                              icon: Icons.autorenew_rounded,
                              tone: StatusTone.info,
                            ),
                            title: 'Replenishment',
                            subtitle: '${r.itemCount} item(s)',
                            trailing: _AmountTrailing(text: r.total.format()),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ReplenishmentDetailScreen(replenishment: r),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 280.ms),
          ),
          SectionHeader(
            title: 'To review',
            trailing: pending.maybeWhen(
              data: (list) =>
                  list.isEmpty ? null : _CountBadge(count: list.length),
              orElse: () => null,
            ),
          ),
          pending.when(
            loading: () => const SurfaceCard(child: SkeletonList(count: 3)),
            error: (e, _) => _ErrorCard(message: '$e'),
            data: (list) => list.isEmpty
                ? const SurfaceCard(
                    child: EmptyState(
                      title: 'Nothing to review',
                      message: 'When a custodian releases cash, it shows up '
                          'here for you to acknowledge or dispute.',
                    ),
                  )
                : SurfaceCard(
                    padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
                    child: Column(
                      children: [
                        for (final r in list)
                          Builder(builder: (context) {
                            final visual = requestStatusVisual(r.status);
                            return AppListTile(
                              leading: const _LeadingIcon(
                                icon: Icons.person_rounded,
                                tone: StatusTone.warning,
                              ),
                              title: r.beneficiaryName,
                              subtitle: r.purpose,
                              trailing: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _AmountTrailing(text: r.amount.format()),
                                  const SizedBox(height: AppTokens.xs),
                                  StatusPill(
                                    label: visual.label,
                                    tone: visual.tone,
                                  ),
                                ],
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      RequestDetailScreen(request: r),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ).animate().fadeIn(duration: 280.ms),
          ),
        ],
    );
  }
}

class _AmountTrailing extends StatelessWidget {
  const _AmountTrailing({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.icon, required this.tone});
  final IconData icon;
  final StatusTone tone;

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

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.sm + 2, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppTokens.rPill),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Text(
              'Something went wrong. $message',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
