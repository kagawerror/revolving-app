import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/core/widgets/surface_card.dart';
import 'package:rev_app/features/requests/presentation/aging_row.dart';

void main() {
  // Pump a BracketTotalRow inside the same host shape it ships in (a
  // SurfaceCard, last child of a Column) so Theme/Directionality resolve and
  // the bottom-rounded wash has its real context, mirroring aging_row_test.dart.
  Future<void> pumpRow(
    WidgetTester tester, {
    required Money total,
    required int count,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BracketTotalRow(total: total, count: count),
              ],
            ),
          ),
        ),
      ),
    );
  }

  group('BracketTotalRow', () {
    testWidgets('renders the formatted peso total', (tester) async {
      final total = Money.fromCentavos(123450);
      await pumpRow(tester, total: total, count: 3);

      // Derive the expected string from format() so the assertion stays locale-
      // agnostic (matches whatever NumberFormat produces on this machine).
      expect(find.textContaining(total.format()), findsOneWidget);
    });

    testWidgets('shows "1 item" (singular) when count == 1', (tester) async {
      await pumpRow(tester, total: Money.fromCentavos(5000), count: 1);

      expect(find.textContaining('1 item'), findsOneWidget);
      expect(find.textContaining('1 items'), findsNothing);
    });

    testWidgets('shows "N items" (plural) when count > 1', (tester) async {
      await pumpRow(tester, total: Money.fromCentavos(5000), count: 4);

      expect(find.textContaining('4 items'), findsOneWidget);
    });

    testWidgets(
        'exposes a merged Semantics label combining the total and item count',
        (tester) async {
      final total = Money.fromCentavos(99900);
      await pumpRow(tester, total: total, count: 2);

      // The widget contracts to a single 'Total: <amount>, <items>' a11y node so
      // screen readers announce the summary once. Match leniently (Total: …item)
      // to avoid brittleness on the exact amount/spacing.
      expect(
        find.bySemanticsLabel(RegExp('Total:.*item')),
        findsOneWidget,
      );
      // And assert the exact contracted label too, derived from format().
      expect(
        find.bySemanticsLabel('Total: ${total.format()}, 2 items'),
        findsOneWidget,
      );
    });
  });
}
