import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/liquidation_history.dart';
import 'package:rev_app/features/replenishment/presentation/replenishment_providers.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_breakdown.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/widgets/release_signature_tile.dart';
import 'package:rev_app/features/requests/presentation/widgets/request_detail_sheet.dart';

/// Builds a [FundRequest] with sensible defaults; override only what a test
/// cares about. Mirrors the artefact-presence flags the sheet branches on.
FundRequest _request({
  String beneficiaryName = 'Juan dela Cruz',
  String purpose = 'Office supplies',
  int amountCentavos = 150000, // ₱1,500.00
  String proofImageUrl = 'https://example.test/proof.jpg',
  String releaseProofUrl = '',
  String releaseSignatureUrl = '',
  int replenishedCentavos = 0,
  RequestStatus status = RequestStatus.released,
  bool nullCreatedAt = false,
}) {
  return FundRequest(
    id: 'r1',
    companyId: 'c1',
    fundId: 'f1',
    createdByUid: 'u1',
    beneficiaryName: beneficiaryName,
    amount: Money.fromCentavos(amountCentavos),
    purpose: purpose,
    proofImageUrl: proofImageUrl,
    status: status,
    releaseProofUrl: releaseProofUrl,
    releaseSignatureUrl: releaseSignatureUrl,
    replenishedCentavos: replenishedCentavos,
    createdAt: nullCreatedAt ? null : DateTime(2026, 6, 13, 9, 30),
  );
}

/// Pumps a button that, when tapped, opens the detail sheet for [request] with
/// a breakdown computed from [pendingPartial]. Returns after the modal route's
/// transition settles. We deliberately use timed [pump]s rather than
/// [pumpAndSettle]: the sheet contains CachedNetworkImage placeholders with a
/// perpetual CircularProgressIndicator, which would make pumpAndSettle time out.
///
/// The sheet is a ConsumerWidget that watches [liquidationHistoryProvider], so
/// a ProviderScope with that family stubbed out is required — [entries] feeds
/// it (defaults to an empty ledger).
Future<void> _openSheet(
  WidgetTester tester, {
  required FundRequest request,
  required Money pendingPartial,
  List<LiquidationEntry> entries = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        liquidationHistoryProvider.overrideWith((ref, arg) =>
            Stream<List<LiquidationEntry>>.value(entries)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showRequestDetailSheet(
                  context,
                  request: request,
                  breakdown: computeRequestBreakdown(
                    request,
                    pendingPartial: pendingPartial,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  // Let the modal-bottom-sheet route animate in (≈ a few frames), without
  // settling the perpetual image spinners.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('showRequestDetailSheet', () {
    testWidgets('renders beneficiary name and amount', (tester) async {
      final request = _request();

      await _openSheet(
        tester,
        request: request,
        pendingPartial: Money.fromCentavos(0),
      );

      // Header carries the beneficiary name and the summary card the amount.
      expect(find.text('Juan dela Cruz'), findsOneWidget);
      expect(find.text(Money.fromCentavos(150000).format()), findsWidgets);
    });

    testWidgets(
        'full case shows proof, release proof, signature and liquidation',
        (tester) async {
      final request = _request(
        releaseProofUrl: 'https://example.test/release.jpg',
        releaseSignatureUrl: 'https://example.test/sig.png',
        // ₱500 of the ₱1,500 already approved → liquidation section present.
        replenishedCentavos: 50000,
      );

      await _openSheet(
        tester,
        request: request,
        // ₱300 submitted-but-not-approved → pending partial present too.
        pendingPartial: Money.fromCentavos(30000),
      );

      // Request proof hero (always present when proofImageUrl set).
      expect(find.text('Request proof'), findsOneWidget);

      // The sheet's body is a lazy ListView; the release/liquidation sections
      // live below the fold. Scroll them into view (driving the sheet's own
      // scroll controller) so they build before we assert their presence.
      final sheetList = find.byType(Scrollable).last;
      await tester.dragUntilVisible(
        find.byType(ReleaseProofTile),
        sheetList,
        const Offset(0, -120),
      );
      await tester.pump();

      // Release artefacts.
      expect(find.byType(ReleaseProofTile), findsOneWidget);
      expect(find.text('Release proof photo'), findsOneWidget);

      await tester.dragUntilVisible(
        find.byType(ReleaseSignatureTile),
        sheetList,
        const Offset(0, -120),
      );
      await tester.pump();
      expect(find.byType(ReleaseSignatureTile), findsOneWidget);
      expect(find.text('Recipient signature'), findsOneWidget);

      // Liquidation breakdown section.
      await tester.dragUntilVisible(
        find.text('Liquidation'),
        sheetList,
        const Offset(0, -120),
      );
      await tester.pump();
      expect(find.text('Liquidation'), findsOneWidget);
    });

    testWidgets('renders the itemized liquidation history when it resolves',
        (tester) async {
      final request = _request(replenishedCentavos: 50000);

      await _openSheet(
        tester,
        request: request,
        pendingPartial: Money.fromCentavos(30000),
        entries: [
          LiquidationEntry(
            replenishmentId: 'rep1',
            date: DateTime(2026, 1, 5),
            isPartial: true,
            amount: Money.fromCentavos(50000),
            status: LiquidationEntryStatus.approved,
          ),
          LiquidationEntry(
            replenishmentId: 'rep2',
            date: DateTime(2026, 2, 9),
            isPartial: true,
            amount: Money.fromCentavos(30000),
            status: LiquidationEntryStatus.forApproval,
          ),
        ],
      );

      final sheetList = find.byType(Scrollable).last;
      await tester.dragUntilVisible(
        find.text('Liquidation'),
        sheetList,
        const Offset(0, -120),
      );
      await tester.pump();

      expect(find.text('Partial · Jan 5, 2026 · approved'), findsOneWidget);
      expect(find.text('Partial · Feb 9, 2026 · for approval'), findsOneWidget);
      // The lumped rows are gone once the ledger resolves.
      expect(find.text('Partial · approved'), findsNothing);
    });

    testWidgets(
        'minimal case shows proof but hides release tiles and liquidation',
        (tester) async {
      // Only an initial proof: no release proof, no signature, no partials.
      final request = _request(status: RequestStatus.released);

      await _openSheet(
        tester,
        request: request,
        pendingPartial: Money.fromCentavos(0),
      );

      // Proof hero still present.
      expect(find.text('Request proof'), findsOneWidget);

      // Release artefacts and liquidation section are absent.
      expect(find.byType(ReleaseProofTile), findsNothing);
      expect(find.byType(ReleaseSignatureTile), findsNothing);
      expect(find.text('Release proof photo'), findsNothing);
      expect(find.text('Recipient signature'), findsNothing);
      expect(find.text('Liquidation'), findsNothing);
    });

    testWidgets('null createdAt renders a dash in the Created row',
        (tester) async {
      // Timestamp not yet materialized (serverTimestamp) / legacy doc.
      final request = _request(nullCreatedAt: true);

      await _openSheet(
        tester,
        request: request,
        pendingPartial: Money.fromCentavos(0),
      );

      // The 'Created' row is present and, since the default purpose is
      // non-empty, the only em-dash value on screen is the created date.
      expect(find.text('Created'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });
  });
}
