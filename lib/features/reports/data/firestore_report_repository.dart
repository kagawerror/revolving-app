import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../replenishment/domain/replenishment.dart';
import '../../replenishment/domain/replenishment_status.dart';
import '../../requests/domain/fund_request.dart';
import '../domain/report_math.dart';
import '../domain/report_models.dart';
import '../domain/report_period.dart';
import '../domain/report_repository.dart';

/// Read-only Firestore implementation of [ReportRepository]. Company-scoped,
/// returns [Result], catches and logs the real cause (never the data). No
/// writes, no transactions.
class FirestoreReportRepository implements ReportRepository {
  FirestoreReportRepository(this._db);

  final FirebaseFirestore _db;

  /// Defensive cap so a runaway window never streams the whole collection into
  /// memory. A single company's released history in any window is far smaller.
  static const _limit = 500;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('requests');
  CollectionReference<Map<String, dynamic>> get _reps =>
      _db.collection('replenishments');
  CollectionReference<Map<String, dynamic>> get _funds =>
      _db.collection('funds');

  @override
  Future<Result<ReportPage<FundRequest>>> fetchReleasedForReport(
    String companyId,
    DateRange window,
  ) async {
    try {
      // Range on releasedAt: docs that never materialized a releasedAt
      // (offline-pending / legacy releases) are intentionally excluded — the
      // server has no release timestamp to date them by. Needs the
      // (companyId ASC, releasedAt DESC) composite index.
      final snap = await _requests
          .where('companyId', isEqualTo: companyId)
          .where('releasedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(window.start))
          .where('releasedAt',
              isLessThan: Timestamp.fromDate(window.endExclusive))
          .orderBy('releasedAt', descending: true)
          .limit(_limit)
          .get();
      final truncated = snap.docs.length >= _limit;
      if (truncated) {
        // No PII/amounts — just the generic cap signal so the report can warn
        // it is showing a capped slice rather than silently undercounting.
        developer.log(
          'fetchReleasedForReport hit the $_limit-row cap; report is truncated',
          name: 'FirestoreReportRepository',
        );
      }
      final all =
          snap.docs.map((d) => FundRequest.fromMap(d.id, d.data())).toList();
      // Re-apply the pure window filter defensively (timezone/edge safety).
      final rows = releasedRowsInWindow(all, window);
      final ids = rows.map((r) => r.requestId).toSet();
      return Ok(ReportPage(
        all.where((r) => ids.contains(r.id)).toList(),
        truncated: truncated,
      ));
    } catch (e, st) {
      developer.log(
        'fetchReleasedForReport failed',
        name: 'FirestoreReportRepository',
        error: e,
        stackTrace: st,
      );
      return const Err(
        UnexpectedFailure('Could not load the released-requests report.'),
      );
    }
  }

  @override
  Future<Result<ReportPage<Replenishment>>> fetchApprovedReplenishments(
    String companyId,
    DateRange window,
  ) async {
    try {
      // Needs the (companyId ASC, status ASC, decidedAt DESC) composite index.
      final snap = await _reps
          .where('companyId', isEqualTo: companyId)
          .where('status', isEqualTo: ReplenishmentStatus.approved.name)
          .where('decidedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(window.start))
          .where('decidedAt',
              isLessThan: Timestamp.fromDate(window.endExclusive))
          .orderBy('decidedAt', descending: true)
          .limit(_limit)
          .get();
      final truncated = snap.docs.length >= _limit;
      if (truncated) {
        developer.log(
          'fetchApprovedReplenishments hit the $_limit-row cap; '
          'report is truncated',
          name: 'FirestoreReportRepository',
        );
      }
      final all =
          snap.docs.map((d) => Replenishment.fromMap(d.id, d.data())).toList();
      // Re-apply the pure filter (approved + window) defensively.
      final rows = replenishmentRowsInWindow(all, window);
      final ids = rows.map((r) => r.replenishmentId).toSet();
      return Ok(ReportPage(
        all.where((r) => ids.contains(r.id)).toList(),
        truncated: truncated,
      ));
    } catch (e, st) {
      developer.log(
        'fetchApprovedReplenishments failed',
        name: 'FirestoreReportRepository',
        error: e,
        stackTrace: st,
      );
      return const Err(
        UnexpectedFailure('Could not load the replenishments report.'),
      );
    }
  }

  @override
  Future<Result<ReportPage<ReplenishedLineRow>>> fetchReplenishmentLineItems(
    String companyId,
    DateRange window,
  ) async {
    try {
      // Reuse the approved-bundles query (same composite index, no new deploy).
      final bundlesRes = await fetchApprovedReplenishments(companyId, window);
      final page = bundlesRes.valueOrNull;
      if (page == null) {
        return Err(bundlesRes.failureOrNull ??
            const UnexpectedFailure(
                'Could not load the replenishment detail report.'));
      }
      final bundles = page.items;

      // Unique requests/funds referenced by the bundles, resolved via single-doc
      // gets (allowed by the sameCompany read rule). Parallelized.
      final requestIds = <String>{
        for (final b in bundles)
          for (final it in b.items) it.requestId,
      };
      final fundIds = <String>{for (final b in bundles) b.fundId};

      final reqSnaps = await Future.wait(
          requestIds.map((id) => _requests.doc(id).get()));
      final fundSnaps =
          await Future.wait(fundIds.map((id) => _funds.doc(id).get()));

      final requestById = <String, FundRequest>{
        for (final s in reqSnaps)
          if (s.exists) s.id: FundRequest.fromMap(s.id, s.data()!),
      };
      final fundNameById = <String, String>{
        for (final s in fundSnaps)
          if (s.exists) s.id: (s.data()?['name'] ?? '') as String,
      };

      final allRows =
          replenishmentLineRows(bundles, requestById, fundNameById);
      final truncated = page.truncated || allRows.length > _limit;
      final rows = truncated ? allRows.take(_limit).toList() : allRows;
      return Ok(ReportPage(rows, truncated: truncated));
    } catch (e, st) {
      developer.log(
        'fetchReplenishmentLineItems failed',
        name: 'FirestoreReportRepository',
        error: e,
        stackTrace: st,
      );
      return const Err(
        UnexpectedFailure('Could not load the replenishment detail report.'),
      );
    }
  }
}
