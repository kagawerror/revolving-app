import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/fund_audit/domain/fund_audit.dart';
import 'package:rev_app/features/fund_audit/presentation/fund_audit_list_screen.dart';
import 'package:rev_app/features/fund_audit/presentation/fund_audit_providers.dart';

/// Pumps the list screen with an empty history (so the empty state renders) and
/// the given [canCreate], inside a minimal MaterialApp.
Future<void> _pump(WidgetTester tester, {required bool canCreate}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fundAuditHistoryProvider.overrideWith(
          (ref, arg) => Stream<List<FundAudit>>.value(const []),
        ),
      ],
      child: MaterialApp(
        home: FundAuditListScreen(
          companyId: 'c1',
          fundId: 'f1',
          canCreate: canCreate,
        ),
      ),
    ),
  );
  await tester.pump(); // resolve the stream
  // Let the empty-state entrance animation (flutter_animate) finish so no
  // Timer is left pending when the widget tree is disposed.
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('FundAuditListScreen create CTA', () {
    testWidgets('view-only role (canCreate:false) sees NO create entry',
        (tester) async {
      await _pump(tester, canCreate: false);

      // App-bar action, FAB, and empty-state button must all be absent.
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.text('New count'), findsNothing);
      expect(find.text('Start a cash count'), findsNothing);
    });

    testWidgets('incharge/admin (canCreate:true) sees the create CTA',
        (tester) async {
      await _pump(tester, canCreate: true);

      // Empty state renders the "Start a cash count" button (the FAB hides on
      // an empty list by design), proving the CTA is wired when allowed.
      expect(find.text('Start a cash count'), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsWidgets);
    });
  });
}
