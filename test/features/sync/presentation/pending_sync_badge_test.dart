import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/sync/domain/outbox_entry.dart';
import 'package:rev_app/features/sync/presentation/pending_sync_indicator.dart';
import 'package:rev_app/features/sync/presentation/sync_providers.dart';

OutboxEntry _entry(String id, OutboxState state) => OutboxEntry(
      id: id,
      kind: OutboxKind.release,
      companyId: 'c1',
      entityId: 'r$id',
      clientActionId: 'cid$id',
      createdAtMillis: 0,
      state: state,
    );

void main() {
  Future<void> pump(WidgetTester tester, List<OutboxEntry> entries) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          outboxProvider.overrideWith((ref) => Stream.value(entries)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            appBar: null,
            body: Center(child: PendingSyncBadge()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders nothing when the outbox is empty', (tester) async {
    await pump(tester, const []);
    expect(find.byType(SizedBox), findsWidgets); // shrink placeholder
    expect(find.textContaining('pending'), findsNothing);
  });

  testWidgets('renders nothing when every entry is done', (tester) async {
    await pump(tester, [_entry('1', OutboxState.done)]);
    expect(find.textContaining('pending'), findsNothing);
  });

  testWidgets('shows the pending count from the outbox', (tester) async {
    await pump(tester, [
      _entry('1', OutboxState.pending),
      _entry('2', OutboxState.uploading),
      _entry('3', OutboxState.done), // excluded from count
    ]);
    expect(find.text('2 pending'), findsOneWidget);
  });

  testWidgets('switches to a needs-attention label on conflict/failed',
      (tester) async {
    await pump(tester, [
      _entry('1', OutboxState.pending),
      _entry('2', OutboxState.conflict),
    ]);
    expect(find.textContaining('needs attention'), findsOneWidget);
  });
}
