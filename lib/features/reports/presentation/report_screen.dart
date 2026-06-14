import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/failure_ui.dart';
import '../../../core/error/result.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../domain/report_math.dart';
import '../domain/report_models.dart';
import '../domain/report_period.dart';
import 'export_format_sheet.dart';
import 'report_providers.dart';
import 'released_report_body.dart';
import 'replenishment_report_body.dart';

/// Standalone route `/reports`: a two-tab (Released / Replenishments) report
/// surface over a shared period control. The screen owns the [Scaffold],
/// [AppBar], the per-tab Export action, the period header, and the role gate;
/// the two tab bodies render the rows + grand total for their dataset.
///
/// State lives in providers (Riverpod) — no `setState`-driven data here. The
/// only local state is the [TabController] index, which decides *which* dataset
/// the Export action and period header act on.
///
/// Role-gated: re-checks `canViewReports` against [currentUserProvider] and
/// shows a non-authorized fallback if any non-(admin/ceo/incharge) role somehow
/// reaches the route. The router redirect is the first line of defense; this is
/// the belt-and-suspenders second one, mirroring how [RoleShellScreen] re-reads
/// the live user for action gating.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      // Rebuild the AppBar action when the tab changes so Export targets the
      // dataset the user is actually looking at.
      ..addListener(() {
        if (!_tabs.indexIsChanging) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _onReleasedTab => _tabs.index == 0;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).valueOrNull;

    // Role gate. While auth is still resolving we render the full scaffold so
    // the layout doesn't flash a fallback then the real screen; the bodies show
    // their own loading state. Only deny once we positively know the role can't
    // view reports.
    if (me != null && !me.role.canViewReports) {
      return const _NotAuthorizedScaffold();
    }

    // The reports are company-scoped. An admin (and any multi-company user) must
    // first pick a company in the context bar; until then `reportCompanyIdProvider`
    // resolves to '' and the providers short-circuit to empty. Rather than show a
    // misleading "no data" empty state, we surface the company picker + an explicit
    // "select a company" prompt — mirroring the incharge / approval shells.
    final hasCompany = ref.watch(reportCompanyIdProvider).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        scrolledUnderElevation: 0.5,
        actions: [
          // Nothing is exportable until a company is selected.
          if (hasCompany) _ExportAction(onReleasedTab: _onReleasedTab),
          const SizedBox(width: AppTokens.xs),
        ],
        // The Released/Replenishments tabs only make sense once a company is
        // chosen; hide them in the select-company state.
        bottom: hasCompany
            ? TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Released'),
                  Tab(text: 'Replenishments'),
                ],
              )
            : null,
      ),
      body: Column(
        children: [
          // Picker for admins / multi-company users; renders nothing for a
          // single-company custodian (their scope is fixed).
          const CompanyContextBar(),
          Expanded(
            child: hasCompany
                ? Column(
                    children: [
                      const ReportPeriodHeader(),
                      Expanded(
                        child: TabBarView(
                          controller: _tabs,
                          children: const [
                            ReleasedReportBody(),
                            ReplenishmentReportBody(),
                          ],
                        ),
                      ),
                    ],
                  )
                : const AdminSelectCompanyPrompt(
                    message: 'Choose a company in the bar above to view its '
                        'released requests and replenishment reports.',
                  ),
          ),
        ],
      ),
    );
  }
}

/// Fallback shown when a role without [UserRole.canViewReports] reaches the
/// route. Uses the shared [EmptyState] so it reads like every other dead-end in
/// the app rather than a raw error.
class _NotAuthorizedScaffold extends StatelessWidget {
  const _NotAuthorizedScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: const EmptyState(
        title: 'Not available for your role',
        message: 'Reports are visible to administrators, the CEO, and fund '
            'custodians.',
        showMascot: false,
      ),
    );
  }
}

// --- Export action ---------------------------------------------------------

/// AppBar Export action, scoped to the active tab. Reads the relevant report
/// summary so it can (a) disable itself while there is nothing exportable and
/// (b) hand the confirm dialog an accurate period label + row count.
class _ExportAction extends ConsumerWidget {
  const _ExportAction({required this.onReleasedTab});

  final bool onReleasedTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref.watch(periodLabelProvider);

    // Only the active tab's provider is read, so switching tabs swaps which
    // dataset gates the button — no cross-tab rebuild churn.
    final rowCount = onReleasedTab
        ? ref.watch(releasedReportProvider).valueOrNull?.rows.length
        : ref.watch(replenishmentReportProvider).valueOrNull?.rows.length;

    final canExport = (rowCount ?? 0) > 0;

    return IconButton(
      icon: const Icon(Icons.ios_share_rounded),
      tooltip: 'Export report',
      // Semantics: the tooltip already names it; this keeps the announcement
      // explicit about scope for screen-reader users.
      onPressed: canExport
          ? () => _onExport(context, ref, label: label, rowCount: rowCount!)
          : null,
    );
  }

  Future<void> _onExport(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required int rowCount,
  }) async {
    final kind = onReleasedTab ? ReportKind.released : ReportKind.replenishments;

    // Step 1 — pick a file format. Dismissing the sheet (null) aborts before
    // any confirm, so nothing leaves the app.
    final format = await showExportFormatSheet(context);
    if (format == null || !context.mounted) return;

    // Step 2 — house rule: every business action passes through a confirm step.
    // The chosen format is echoed back so the user knows exactly what (and in
    // which format) leaves the app.
    final confirmed = await _confirmExport(
      context,
      periodLabel: label,
      rowCount: rowCount,
      kind: kind,
      format: format,
    );
    if (confirmed != true || !context.mounted) return;

    // Hand the settled summary + chosen format to the share service. The pure
    // per-format builders + the share service are the testable seams; the widget
    // only orchestrates and reports the outcome.
    final share = ref.read(reportShareServiceProvider);

    if (onReleasedTab) {
      final summary = ref.read(releasedReportProvider).valueOrNull;
      if (summary == null) return;
      final result =
          await share.shareReport(format, ReportKind.released, summary, label);
      if (!context.mounted) return;
      _reportResult(context, result,
          rowCount: summary.rows.length, format: format, label: label);
      return;
    }

    // Replenishments tab → fetch per-request line-item detail on demand. The
    // on-screen summary only has bundle-level rows; the detail export joins each
    // bundle's items to their request + fund docs, so we read it fresh here
    // (after confirm) rather than keep it resident.
    final companyId = ref.read(reportCompanyIdProvider);
    final period = ref.read(reportPeriodProvider);
    final window = periodWindow(period.granularity, period.anchor);

    // Brief blocking spinner while the join reads run. Capture the root
    // navigator BEFORE the await so we can always tear the spinner down — even
    // if the screen unmounts mid-fetch (e.g. hardware back behind the modal
    // barrier), which would otherwise orphan the dialog on the root navigator.
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final pageRes = await ref
        .read(reportRepositoryProvider)
        .fetchReplenishmentLineItems(companyId, window);
    if (rootNavigator.canPop()) rootNavigator.pop(); // dismiss spinner
    if (!context.mounted) return;

    final page = pageRes.valueOrNull;
    if (page == null) {
      context.showFailure(pageRes.failureOrNull ??
          const UnexpectedFailure('Could not export the report.'));
      return;
    }
    final summary = ReportSummary<ReplenishedLineRow>(
      rows: page.items,
      grandTotal: grandTotal(page.items.map((r) => r.amount)),
      period: period,
      truncated: page.truncated,
    );
    final result = await share.shareReplenishmentDetail(format, summary, label);
    if (!context.mounted) return;
    _reportResult(context, result,
        rowCount: page.items.length, format: format, label: label);
  }

  void _reportResult(
    BuildContext context,
    Result<void> result, {
    required int rowCount,
    required ReportExportFormat format,
    required String label,
  }) {
    switch (result) {
      case Ok():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported $rowCount rows · ${format.label} · $label'),
          ),
        );
      case Err(:final failure):
        context.showFailure(failure);
    }
  }
}

/// Confirmation dialog for an export. Mirrors the adjust-fund confirm style:
/// rounded card, tinted icon badge, label/value summary rows, Cancel + a tinted
/// primary action. States the exact period, row count, and chosen format so the
/// user knows precisely what leaves the app.
Future<bool?> _confirmExport(
  BuildContext context, {
  required String periodLabel,
  required int rowCount,
  required ReportKind kind,
  required ReportExportFormat format,
}) {
  final scheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final kindLabel = kind == ReportKind.released
      ? 'Released requests'
      : 'Replenishments (line-item detail)';
  final rowsLabel = rowCount == 1 ? '1 row' : '$rowCount rows';

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: AppTokens.brField,
        ),
        child: Icon(
          Icons.ios_share_rounded,
          color: scheme.onPrimaryContainer,
          semanticLabel: 'Export',
        ),
      ),
      title: const Text('Export this report?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'A ${format.label} file will be created for sharing. Amounts are '
            'exported in pesos.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppTokens.md),
          _ConfirmRow(label: 'Report', value: kindLabel),
          const SizedBox(height: AppTokens.sm),
          _ConfirmRow(label: 'Period', value: periodLabel),
          const SizedBox(height: AppTokens.sm),
          _ConfirmRow(label: 'Rows', value: rowsLabel),
          const SizedBox(height: AppTokens.sm),
          _ConfirmRow(label: 'Format', value: format.label),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        0,
        AppTokens.lg,
        AppTokens.lg,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('Export'),
        ),
      ],
    ),
  );
}

/// Label/value summary row reused by the export confirm dialog. Value is
/// right-aligned with a bold weight, matching the adjust-fund confirm rows.
class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: AppTokens.md),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// --- Shared period header ---------------------------------------------------

/// The shared control above both tabs: a Day/Week/Month/Year granularity
/// selector and a ‹ label › stepper. The next button is disabled at the current
/// period so the user can never page into the future (where there is no data).
///
/// Lives in this file because it is the screen's primary chrome and is shared
/// verbatim by both tabs; it reads/writes [reportPeriodProvider] and the derived
/// [periodLabelProvider] / [isAtCurrentPeriodProvider].
class ReportPeriodHeader extends ConsumerWidget {
  const ReportPeriodHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final period = ref.watch(reportPeriodProvider);
    final label = ref.watch(periodLabelProvider);
    final atCurrent = ref.watch(isAtCurrentPeriodProvider);
    final notifier = ref.read(reportPeriodProvider.notifier);

    return Container(
      // A distinct surface tier so the control reads as fixed chrome over the
      // scrolling list below, without a hard divider (the app is flat).
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(
        AppTokens.lg,
        AppTokens.sm,
        AppTokens.lg,
        AppTokens.md,
      ),
      child: Column(
        children: [
          SegmentedButton<PeriodGranularity>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape:
                  const RoundedRectangleBorder(borderRadius: AppTokens.brField),
            ),
            segments: const [
              ButtonSegment(
                value: PeriodGranularity.day,
                label: Text('Day'),
              ),
              ButtonSegment(
                value: PeriodGranularity.week,
                label: Text('Week'),
              ),
              ButtonSegment(
                value: PeriodGranularity.month,
                label: Text('Month'),
              ),
              ButtonSegment(
                value: PeriodGranularity.year,
                label: Text('Year'),
              ),
            ],
            selected: {period.granularity},
            onSelectionChanged: (s) => notifier.setGranularity(s.first),
          ),
          const SizedBox(height: AppTokens.sm),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous period',
                onPressed: notifier.prev,
                // 48dp target is the IconButton default; explicit for clarity.
                iconSize: 28,
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: 'Showing $label',
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: atCurrent ? 'Already at latest' : 'Next period',
                // Disabled at the current period — no future data exists.
                onPressed: atCurrent ? null : notifier.next,
                iconSize: 28,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
