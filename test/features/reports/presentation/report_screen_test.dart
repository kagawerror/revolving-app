import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/reports/data/firestore_report_repository.dart';
import 'package:rev_app/features/reports/domain/report_math.dart';
import 'package:rev_app/features/reports/domain/report_models.dart';
import 'package:rev_app/features/reports/domain/report_period.dart';

/// Reproduces the summary the export action ([ReportScreen]'s `_onExport`) builds
/// for the Replenishments line-item export: fetch the detail page from the repo,
/// then sum the LINE-ITEM amounts into the grand total. Drives real production
/// code (the repository join + `grandTotal`), not a stub, so it pins the
/// export's money contract: the exported grand total equals the sum of the
/// per-request line amounts (full + partial installments alike).
void main() {
  test('export summary grand total == sum of line-item amounts (full + partial)',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('funds').doc('f1').set({'companyId': 'c1', 'name': 'AUDIT'});
    await db.collection('requests').doc('r1').set({
      'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'u',
      'beneficiaryName': 'Alice', 'amountCentavos': 5000, 'purpose': 'Laptop',
      'proofImageUrl': 'http://x', 'status': 'replenished',
    });
    await db.collection('requests').doc('r2').set({
      'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'u',
      'beneficiaryName': 'Bob', 'amountCentavos': 1000, 'purpose': 'Load',
      'proofImageUrl': 'http://x', 'status': 'released',
    });
    await db.collection('replenishments').doc('rep1').set({
      'companyId': 'c1', 'fundId': 'f1', 'status': 'approved',
      'requestIds': ['r1', 'r2'], 'totalCentavos': 5400, 'reportNotes': '',
      'createdByUid': 'u',
      'items': [
        {'requestId': 'r1', 'isPartial': false, 'amountCentavos': 5000, 'remarks': ''},
        {'requestId': 'r2', 'isPartial': true, 'amountCentavos': 400, 'remarks': 'first'},
      ],
      'decidedAt': Timestamp.fromDate(DateTime(2026, 6, 10)),
    });

    final repo = FirestoreReportRepository(db);
    final period = ReportPeriod(
        granularity: PeriodGranularity.month, anchor: DateTime(2026, 6, 1));
    final window = periodWindow(period.granularity, period.anchor);

    final pageRes = await repo.fetchReplenishmentLineItems('c1', window);
    expect(pageRes.isOk, isTrue);
    final page = pageRes.valueOrNull!;

    // The exact summary _onExport hands to shareReplenishmentDetail.
    final summary = ReportSummary<ReplenishedLineRow>(
      rows: page.items,
      grandTotal: grandTotal(page.items.map((r) => r.amount)),
      period: period,
      truncated: page.truncated,
    );

    expect(summary.rows.length, 2); // one row per (bundle, item)
    expect(summary.grandTotal.centavos, 5400); // 5000 full + 400 installment
  });
}
