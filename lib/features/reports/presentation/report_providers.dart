import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/company.dart';
import '../../companies/presentation/admin_active_company.dart';
import '../../companies/presentation/admin_company_context_bar.dart';
import '../../companies/presentation/admin_providers.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../../../services/share/report_share_service.dart';
import '../data/firestore_report_repository.dart';
import '../domain/report_export.dart';
import '../domain/report_math.dart';
import '../domain/report_models.dart';
import '../domain/report_period.dart';
import '../domain/report_repository.dart';

// Re-export the domain types the screens consume so existing presentation
// imports (`report_providers.dart`) keep resolving from one place.
export '../domain/report_export.dart'
    show
        ReportExportFormat,
        ReportExportFormatX,
        ReportKind,
        ReportShareService;
export '../domain/report_models.dart'
    show ReleasedRequestRow, ReplenishmentRow, ReportSummary;
export '../domain/report_repository.dart' show ReportPage;
export '../domain/report_period.dart' show PeriodGranularity, ReportPeriod;

// --- Period state ----------------------------------------------------------

/// The active report window. Stepping is window-aware (calendar math in the
/// pure [previousPeriod] / [nextPeriod] fns); switching granularity resets the
/// anchor to now.
class ReportPeriodNotifier extends Notifier<ReportPeriod> {
  @override
  ReportPeriod build() => ReportPeriod(
    granularity: PeriodGranularity.month,
    anchor: DateTime.now(),
  );

  void setGranularity(PeriodGranularity g) =>
      state = ReportPeriod(granularity: g, anchor: DateTime.now());

  void prev() => state = previousPeriod(state);

  /// Step forward, but never past the current period (no future data exists).
  void next() {
    if (isCurrentPeriod(state, DateTime.now())) return;
    state = nextPeriod(state);
  }
}

final reportPeriodProvider =
    NotifierProvider<ReportPeriodNotifier, ReportPeriod>(
      ReportPeriodNotifier.new,
    );

/// Human label for the active period (pure [periodLabel]).
final periodLabelProvider = Provider<String>(
  (ref) => periodLabel(ref.watch(reportPeriodProvider)),
);

/// True when the active window includes "now" — drives the disabled next button.
final isAtCurrentPeriodProvider = Provider<bool>(
  (ref) => isCurrentPeriod(ref.watch(reportPeriodProvider), DateTime.now()),
);

// --- Company scope ---------------------------------------------------------

/// The company whose reports are shown. Mirrors `dashboardCompanyIdProvider`:
/// company-scoped roles use their in-session active company; admins resolve to
/// '' (no single company) and the report providers below short-circuit to empty.
final reportCompanyIdProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return '';
  return effectiveCompanyId(user, ref.watch(adminActiveCompanyProvider));
});

/// The display NAME of the active report company, resolved from the live
/// [companiesProvider] list by id. Empty when no company is active or the id is
/// not (yet) in the streamed list — the report builders then omit the company
/// header line. Threaded into exports so a printed/shared file says which
/// company it belongs to.
final reportCompanyNameProvider = Provider<String>((ref) {
  final id = ref.watch(reportCompanyIdProvider);
  if (id.isEmpty) return '';
  final companies =
      ref.watch(companiesProvider).valueOrNull ?? const <Company>[];
  for (final c in companies) {
    if (c.id == id) return c.name;
  }
  return '';
});

// --- Data access -----------------------------------------------------------

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => FirestoreReportRepository(ref.watch(firestoreProvider)),
);

final reportShareServiceProvider = Provider<ReportShareService>(
  (ref) => const ReportShareServiceImpl(),
);

// --- Report providers ------------------------------------------------------

/// Released requests for the active period, mapped to display rows + grand
/// total. Scoped by [reportCompanyIdProvider]; an admin with no active company
/// yields an empty summary rather than a cross-tenant scan.
final releasedReportProvider =
    FutureProvider.autoDispose<ReportSummary<ReleasedRequestRow>>((ref) async {
      final period = ref.watch(reportPeriodProvider);
      final companyId = ref.watch(reportCompanyIdProvider);
      if (companyId.isEmpty) {
        return ReportSummary(rows: const [], grandTotal: _zero, period: period);
      }
      final window = periodWindow(period.granularity, period.anchor);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchReleasedForReport(companyId, window);
      return result.when(
        ok: (page) {
          final rows = releasedRowsInWindow(page.items, window);
          return ReportSummary(
            rows: rows,
            grandTotal: grandTotal(rows.map((r) => r.amount)),
            period: period,
            truncated: page.truncated,
          );
        },
        err: (failure) => throw failure,
      );
    });

/// Approved replenishments for the active period, mapped to display rows +
/// grand total. Scoped like [releasedReportProvider].
final replenishmentReportProvider =
    FutureProvider.autoDispose<ReportSummary<ReplenishmentRow>>((ref) async {
      final period = ref.watch(reportPeriodProvider);
      final companyId = ref.watch(reportCompanyIdProvider);
      if (companyId.isEmpty) {
        return ReportSummary(rows: const [], grandTotal: _zero, period: period);
      }
      final window = periodWindow(period.granularity, period.anchor);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchApprovedReplenishments(companyId, window);
      return result.when(
        ok: (page) {
          final rows = replenishmentRowsInWindow(page.items, window);
          return ReportSummary(
            rows: rows,
            grandTotal: grandTotal(rows.map((r) => r.total)),
            period: period,
            truncated: page.truncated,
          );
        },
        err: (failure) => throw failure,
      );
    });

// Local alias so the empty-summary branches don't need a money import.
const _zero = Money.zero;
