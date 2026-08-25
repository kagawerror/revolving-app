import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/liquidation_history.dart';
import 'package:rev_app/features/requests/domain/request_breakdown.dart';
import 'package:rev_app/features/requests/presentation/widgets/request_breakdown_view.dart';

RequestBreakdown _breakdown({
  int original = 150000,
  int approvedPartial = 50000,
  int pendingPartial = 30000,
}) =>
    RequestBreakdown(
      original: Money.fromCentavos(original),
      approvedPartial: Money.fromCentavos(approvedPartial),
      pendingPartial: Money.fromCentavos(pendingPartial),
      projectedRemaining:
          Money.fromCentavos(original - approvedPartial - pendingPartial),
    );

LiquidationEntry _entry({
  String replenishmentId = 'rep1',
  DateTime? date,
  bool isPartial = true,
  int centavos = 50000,
  LiquidationEntryStatus status = LiquidationEntryStatus.approved,
}) =>
    LiquidationEntry(
      replenishmentId: replenishmentId,
      date: date,
      isPartial: isPartial,
      amount: Money.fromCentavos(centavos),
      status: status,
    );

Future<void> _pump(
  WidgetTester tester, {
  required RequestBreakdown breakdown,
  bool compact = false,
  List<LiquidationEntry>? entries,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: RequestBreakdownView(
            breakdown: breakdown,
            compact: compact,
            entries: entries,
          ),
        ),
      ),
    ));

void main() {
  group('compact variant', () {
    testWidgets('renders the lumped partial hints and ignores entries',
        (tester) async {
      await _pump(tester, breakdown: _breakdown(), compact: true);

      expect(find.text('partial · for approval'), findsOneWidget);
      expect(find.text('partial · approved'), findsOneWidget);
      expect(find.text('remaining (incl. pending)'), findsOneWidget);
    });

    testWidgets('asserts when entries are passed to the compact variant',
        (tester) async {
      expect(
        () => RequestBreakdownView(
          breakdown: _breakdown(),
          compact: true,
          entries: [_entry()],
        ),
        throwsAssertionError,
      );
    });
  });

  group('full variant', () {
    testWidgets('entries == null keeps the lumped rows (loading/error state)',
        (tester) async {
      await _pump(tester, breakdown: _breakdown());

      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Partial · for approval'), findsOneWidget);
      expect(find.text('Partial · approved'), findsOneWidget);
      expect(find.text('Remaining (incl. pending)'), findsOneWidget);
    });

    testWidgets('entries render itemized lines instead of the lumped rows',
        (tester) async {
      await _pump(
        tester,
        breakdown: _breakdown(),
        entries: [
          _entry(
            replenishmentId: 'rep1',
            date: DateTime(2026, 1, 5),
            centavos: 50000,
          ),
          _entry(
            replenishmentId: 'rep2',
            date: DateTime(2026, 2, 9),
            isPartial: false,
            centavos: 30000,
            status: LiquidationEntryStatus.forApproval,
          ),
        ],
      );

      expect(find.text('Partial · Jan 5, 2026 · approved'), findsOneWidget);
      expect(find.text('Full · Feb 9, 2026 · for approval'), findsOneWidget);
      // The lumped rows are replaced, not duplicated.
      expect(find.text('Partial · for approval'), findsNothing);
      expect(find.text('Partial · approved'), findsNothing);
      // The bookend rows are untouched.
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Remaining (incl. pending)'), findsOneWidget);
      // Amounts are rendered as debits.
      expect(find.text('− ${Money.fromCentavos(50000).format()}'),
          findsOneWidget);
      expect(find.text('− ${Money.fromCentavos(30000).format()}'),
          findsOneWidget);
    });

    testWidgets('a null-dated (legacy) entry renders a dash for its date',
        (tester) async {
      await _pump(
        tester,
        breakdown: _breakdown(),
        entries: [_entry(date: null)],
      );

      expect(find.text('Partial · — · approved'), findsOneWidget);
    });

    testWidgets('a rejected entry is labelled rejected', (tester) async {
      await _pump(
        tester,
        breakdown: _breakdown(),
        entries: [
          _entry(
            date: DateTime(2026, 3, 2),
            status: LiquidationEntryStatus.rejected,
          ),
        ],
      );

      expect(find.text('Partial · Mar 2, 2026 · rejected'), findsOneWidget);
    });

    testWidgets('an empty entry list renders the muted placeholder',
        (tester) async {
      await _pump(tester, breakdown: _breakdown(), entries: const []);

      expect(find.text('Liquidation history'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('No itemized history available.'), findsOneWidget);
      expect(find.text('Partial · approved'), findsNothing);
      // Totals still bookend the (empty) middle band.
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Remaining (incl. pending)'), findsOneWidget);
    });

    testWidgets('a request with no partials collapses to the amount line',
        (tester) async {
      await _pump(
        tester,
        breakdown: _breakdown(approvedPartial: 0, pendingPartial: 0),
      );

      expect(find.text('Original'), findsNothing);
      expect(find.text(Money.fromCentavos(150000).format()), findsOneWidget);
    });

    testWidgets(
        'reconciliation invariant: rendered debits sum to original − remaining',
        (tester) async {
      // The property a money ledger must always hold on screen. The fixture
      // mirrors what computeLiquidationHistory would emit for this breakdown:
      // one approved partial (50000, in approvedPartial) + one submitted
      // partial (30000, in pendingPartial). A pending FULL item is deliberately
      // absent — the domain excludes it precisely because projectedRemaining
      // never subtracts it.
      final breakdown = _breakdown(
        original: 150000,
        approvedPartial: 50000,
        pendingPartial: 30000,
      );
      final entries = [
        _entry(
          replenishmentId: 'rep1',
          date: DateTime(2026, 1, 5),
          centavos: 50000,
        ),
        _entry(
          replenishmentId: 'rep2',
          date: DateTime(2026, 2, 9),
          centavos: 30000,
          status: LiquidationEntryStatus.forApproval,
        ),
      ];

      await _pump(tester, breakdown: breakdown, entries: entries);

      // Scrape every rendered debit line ("− ₱x") back out of the widget tree
      // and re-add them, rather than trusting the fixture.
      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => s.startsWith('− '))
          .toList();

      expect(rendered, hasLength(entries.length));

      final sum = entries.fold<int>(0, (acc, e) => acc + e.amount.centavos);
      expect(
        rendered,
        entries
            .map((e) => '− ${e.amount.format()}')
            .toList(),
      );
      expect(
        sum,
        breakdown.original.centavos - breakdown.projectedRemaining.centavos,
      );
      // And the bookends really are on screen with those values.
      expect(find.text(breakdown.original.format()), findsOneWidget);
      expect(find.text(breakdown.projectedRemaining.format()), findsOneWidget);
    });
  });

  group('semantics', () {
    // The view wraps itself in Semantics(container: true), which absorbs the
    // descendant Texts — so the node label is "<our sentence>\n<each Text>".
    // The first line is the sentence _semanticSummary produced.
    String spokenSummary(WidgetTester tester) => tester
        .getSemantics(find.byType(RequestBreakdownView))
        .label
        .split('\n')
        .first;

    const lumped = 'Original ₱1,500.00, approved partial ₱500.00, '
        'partial for approval ₱300.00, '
        'remaining ₱700.00 including pending';

    testWidgets('narrates the lumped totals when entries are null',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, breakdown: _breakdown());

      expect(spokenSummary(tester), lumped);
      handle.dispose();
    });

    testWidgets('narrates the itemized rows when entries are rendered',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        breakdown: _breakdown(),
        entries: [
          _entry(
            replenishmentId: 'rep1',
            date: DateTime(2026, 1, 5),
            centavos: 50000,
          ),
          _entry(
            replenishmentId: 'rep2',
            date: DateTime(2026, 2, 9),
            centavos: 30000,
            status: LiquidationEntryStatus.forApproval,
          ),
        ],
      );

      // Spoken content matches the visually rendered rows, reusing their labels.
      expect(
        spokenSummary(tester),
        'Original ₱1,500.00, '
        'Partial · Jan 5, 2026 · approved, minus ₱500.00, '
        'Partial · Feb 9, 2026 · for approval, minus ₱300.00, '
        'remaining ₱700.00 including pending',
      );
      // The stale lumped wording is gone.
      expect(spokenSummary(tester), isNot(contains('approved partial')));
      handle.dispose();
    });

    testWidgets(
        'an empty entry list narrates "no itemized history", matching the '
        'visual placeholder rather than the stale lumped totals',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, breakdown: _breakdown(), entries: const []);

      expect(
        spokenSummary(tester),
        'Original ₱1,500.00, no itemized history available, '
        'remaining ₱700.00 including pending',
      );
      expect(spokenSummary(tester), isNot(contains('approved partial')));
      handle.dispose();
    });
  });
}
