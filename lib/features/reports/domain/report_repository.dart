import '../../../core/error/result.dart';
import '../../replenishment/domain/replenishment.dart';
import '../../requests/domain/fund_request.dart';
import 'report_models.dart';
import 'report_period.dart';

/// A page of report rows plus whether the underlying query hit its defensive
/// row cap. When [truncated] is true the [items] are only the most-recent capped
/// slice of the window, so any total derived from them is a lower bound — the UI
/// must say so rather than present it as complete.
class ReportPage<T> {
  const ReportPage(this.items, {this.truncated = false});

  final List<T> items;
  final bool truncated;
}

/// Read-only data source for the Reports feature. All methods are company-scoped
/// and return [Result] — failures surface as user-safe [Failure]s, never raw
/// exceptions. No writes, no transactions: reports never mutate state.
abstract class ReportRepository {
  /// Released requests for [companyId] whose `releasedAt` falls inside [window].
  /// Docs without a materialized `releasedAt` (offline-pending / legacy) are
  /// excluded by the query and re-validated defensively by the caller.
  Future<Result<ReportPage<FundRequest>>> fetchReleasedForReport(
    String companyId,
    DateRange window,
  );

  /// Approved replenishments for [companyId] whose `decidedAt` falls inside
  /// [window].
  Future<Result<ReportPage<Replenishment>>> fetchApprovedReplenishments(
    String companyId,
    DateRange window,
  );

  /// Detailed (per-request) view of approved replenishments for [companyId]
  /// whose `decidedAt` falls inside [window]. Joins each bundle's items to their
  /// request + fund docs. Capped + [ReportPage.truncated] like the other reports.
  Future<Result<ReportPage<ReplenishedLineRow>>> fetchReplenishmentLineItems(
    String companyId,
    DateRange window,
  );
}
