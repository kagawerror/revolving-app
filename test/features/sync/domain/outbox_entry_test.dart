import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/sync/domain/outbox_entry.dart';

void main() {
  group('OutboxEntry', () {
    const entry = OutboxEntry(
      id: 'o1',
      kind: OutboxKind.release,
      companyId: 'c1',
      entityId: 'r1',
      clientActionId: 'cid-1',
      createdAtMillis: 1234,
      attempts: 2,
      state: OutboxState.replaying,
      payload: {'amountCentavos': 5000, 'note': 'x'},
      localImagePaths: ['/tmp/a.jpg', '/tmp/b.jpg'],
    );

    test('toJson/fromJson round-trips losslessly', () {
      final round = OutboxEntry.fromJson(entry.toJson());
      expect(round, entry);
    });

    test('fromJson tolerates missing optional fields with defaults', () {
      final e = OutboxEntry.fromJson({
        'id': 'o2',
        'kind': 'createRequest',
        'companyId': 'c1',
        'entityId': 'r2',
        'clientActionId': 'cid-2',
        'createdAtMillis': 1,
      });
      expect(e.attempts, 0);
      expect(e.state, OutboxState.pending);
      expect(e.payload, isEmpty);
      expect(e.localImagePaths, isEmpty);
    });

    test('unknown enum names fall back to safe defaults', () {
      final e = OutboxEntry.fromJson({
        'id': 'o3',
        'kind': 'wat',
        'companyId': 'c1',
        'entityId': 'r3',
        'clientActionId': 'cid-3',
        'createdAtMillis': 1,
        'state': 'wat',
      });
      expect(e.kind, OutboxKind.transition);
      expect(e.state, OutboxState.pending);
    });

    test('copyWith overrides only named fields', () {
      final next = entry.copyWith(
        attempts: 3,
        state: OutboxState.done,
      );
      expect(next.attempts, 3);
      expect(next.state, OutboxState.done);
      expect(next.id, entry.id);
      expect(next.clientActionId, entry.clientActionId);
      expect(next.payload, entry.payload);
    });
  });
}
