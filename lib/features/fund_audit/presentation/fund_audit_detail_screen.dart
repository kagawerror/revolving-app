import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/denomination.dart';
import '../domain/fund_audit.dart';
import 'fund_audit_providers.dart';
import 'widgets/audit_shimmer.dart';
import 'widgets/reconciliation_card.dart';
import 'widgets/verdict_chip.dart';

/// Read-only Proof-of-Cash certificate. Route: `/incharge/audit/:id`.
class FundAuditDetailScreen extends ConsumerWidget {
  const FundAuditDetailScreen({super.key, required this.auditId});

  final String auditId;

  Future<void> _export(
      BuildContext context, WidgetRef ref, FundAudit audit) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Preparing PDF…'), duration: Duration(seconds: 1)),
    );
    final res = await ref.read(fundAuditPdfShareProvider).share(audit);
    if (!context.mounted) return;
    res.showOnError(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fundAuditByIdProvider(auditId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Count'),
        actions: [
          async.maybeWhen(
            data: (audit) => IconButton(
              tooltip: 'Export PDF certificate',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => _export(context, ref, audit),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const _DetailSkeleton(),
        error: (e, _) => _DetailError(
          onRetry: () => ref.invalidate(fundAuditByIdProvider(auditId)),
        ),
        data: (audit) => _Certificate(audit: audit),
      ),
    );
  }
}

class _Certificate extends StatelessWidget {
  const _Certificate({required this.audit});
  final FundAudit audit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateStr = audit.createdAt == null
        ? '—'
        : DateFormat('MMMM d, yyyy').format(audit.createdAt!);

    return ListView(
      padding: const EdgeInsets.all(AppTokens.lg),
      children: [
        // Certificate header.
        Container(
          padding: const EdgeInsets.all(AppTokens.lg),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius:
                const BorderRadius.all(Radius.circular(AppTokens.rCard)),
            border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CASH COUNT & FUND RECONCILIATION',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
              ),
              const SizedBox(height: 2),
              Text('Proof of Cash',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      )),
              const SizedBox(height: AppTokens.md),
              Text(audit.companyName,
                  style: Theme.of(context).textTheme.titleLarge),
              Text(audit.fundName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                      )),
              const SizedBox(height: AppTokens.sm),
              _MetaRow(label: 'As of', value: dateStr),
              _MetaRow(label: 'Custodian', value: audit.custodianName),
              const SizedBox(height: AppTokens.md),
              VerdictChip(verdict: audit.verdict, large: true),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.lg),

        // Denomination table (read-only).
        const _SectionLabel(text: 'Denomination count'),
        const SizedBox(height: AppTokens.xs),
        Card(
          margin: EdgeInsets.zero,
          child: _DenominationTable(audit: audit),
        ),
        const SizedBox(height: AppTokens.lg),

        // Reconciliation block (reuses the live card, static here) built from
        // the persisted audit fields directly.
        ReconciliationCard.fromValues(
          effectiveBudget: audit.effectiveBudget,
          physicalCash: audit.physicalCash,
          outstanding: audit.outstanding,
          varianceCentavos: audit.varianceCentavos,
          verdict: audit.verdict,
          elevated: false,
        ),
        const SizedBox(height: AppTokens.lg),

        // Note.
        if (audit.note.isNotEmpty) ...[
          const _SectionLabel(text: 'Note'),
          const SizedBox(height: AppTokens.xs),
          Text(audit.note, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppTokens.lg),
        ],

        // Proof photo with tap-to-zoom.
        const _SectionLabel(text: 'Count-sheet photo'),
        const SizedBox(height: AppTokens.xs),
        _ProofPhoto(url: audit.proofImageUrl),
        const SizedBox(height: AppTokens.xl),
      ],
    );
  }
}

class _DenominationTable extends StatelessWidget {
  const _DenominationTable({required this.audit});
  final FundAudit audit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Index counts by denomination so we can render all 13 rows descending,
    // including zeros (auditors expect the full sheet).
    final byDenom = {for (final d in audit.denominations) d.denomination: d};

    final mono = const [FontFeature.tabularFigures()];

    Widget row(Denomination d) {
      final entry = byDenom[d];
      final count = entry?.count ?? 0;
      final subtotal = Money.fromCentavos(entry?.subtotalCentavos ?? 0);
      final muted = count == 0;
      final color = muted ? scheme.onSurfaceVariant : scheme.onSurface;
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.lg, vertical: AppTokens.sm),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(d.label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontFeatures: mono,
                      )),
            ),
            Expanded(
              flex: 3,
              child: Text('x $count',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontFeatures: mono,
                      )),
            ),
            Expanded(
              flex: 4,
              child: Text(subtotal.format(),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontFeatures: mono,
                      )),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < kDenominationsDescending.length; i++) ...[
          row(kDenominationsDescending[i]),
          if (i != kDenominationsDescending.length - 1)
            Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ],
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppTokens.rCard)),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.lg, vertical: AppTokens.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Physical cash counted',
                  style: Theme.of(context).textTheme.titleSmall),
              Text(audit.physicalCash.format(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: mono,
                      )),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProofPhoto extends StatelessWidget {
  const _ProofPhoto({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (url.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius:
              const BorderRadius.all(Radius.circular(AppTokens.rField)),
        ),
        child: Text('No photo attached',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return GestureDetector(
      onTap: () => _openZoom(context, url),
      child: Hero(
        tag: 'audit-proof-$url',
        child: ClipRRect(
          borderRadius:
              const BorderRadius.all(Radius.circular(AppTokens.rField)),
          child: CachedNetworkImage(
            imageUrl: url,
            height: 240,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (_, _) => const ShimmerBox(height: 240),
            errorWidget: (_, _, _) => Container(
              height: 240,
              color: scheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined, size: 40),
            ),
          ),
        ),
      ),
    );
  }

  void _openZoom(BuildContext context, String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _PhotoZoom(url: url),
      ),
    );
  }
}

class _PhotoZoom extends StatelessWidget {
  const _PhotoZoom({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Hero(
          tag: 'audit-proof-$url',
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    )),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.lg),
      children: const [
        ShimmerBox(height: 160, radius: AppTokens.rCard),
        SizedBox(height: AppTokens.lg),
        ShimmerBox(height: 18, width: 160),
        SizedBox(height: AppTokens.md),
        ShimmerBox(height: 300, radius: AppTokens.rCard),
        SizedBox(height: AppTokens.lg),
        ShimmerBox(height: 200, radius: AppTokens.rCard),
      ],
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: scheme.error),
            const SizedBox(height: AppTokens.md),
            Text('Could not load this cash count',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.sm),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppTokens.lg),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
