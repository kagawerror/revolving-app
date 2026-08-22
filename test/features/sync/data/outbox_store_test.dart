import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/sync/data/outbox_store.dart';
import 'package:rev_app/features/sync/domain/outbox_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

OutboxEntry _entry(
  String id, {
  OutboxKind kind = OutboxKind.transition,
  OutboxState state = OutboxState.pending,
  int attempts = 0,
}) =>
    OutboxEntry(
      id: id,
      kind: kind,
      companyId: 'c1',
      entityId: 'req-$id',
      clientActionId: 'cai-$id',
      createdAtMillis: 1000,
      attempts: attempts,
      state: state,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late OutboxStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = OutboxStore(prefs);
  });

  test('enqueue then all() round-trips and persists', () async {
    final r = await store.enqueue(_entry('a'));
    expect(r.isOk, isTrue);
    expect(store.all().map((e) => e.id), ['a']);

    // A fresh store over the same prefs sees the persisted entry.
    final store2 = OutboxStore(prefs);
    expect(store2.all().map((e) => e.id), ['a']);
  });

  test('enqueue preserves insertion order', () async {
    await store.enqueue(_entry('a'));
    await store.enqueue(_entry('b'));
    await store.enqueue(_entry('c'));
    expect(store.all().map((e) => e.id), ['a', 'b', 'c']);
  });

  test('enqueue is idempotent by id (dedupe)', () async {
    await store.enqueue(_entry('a'));
    await store.enqueue(_entry('a', attempts: 9));
    expect(store.all().length, 1);
    // Dedupe keeps the first; it does not overwrite.
    expect(store.all().single.attempts, 0);
  });

  test('update by id replaces the matching entry', () async {
    await store.enqueue(_entry('a'));
    await store.enqueue(_entry('b'));
    final r = await store.update(_entry('a', state: OutboxState.failed, attempts: 3));
    expect(r.isOk, isTrue);
    final a = store.all().firstWhere((e) => e.id == 'a');
    expect(a.state, OutboxState.failed);
    expect(a.attempts, 3);
    expect(store.all().map((e) => e.id), ['a', 'b']); // order preserved
  });

  test('update of a missing id returns NotFoundFailure', () async {
    final r = await store.update(_entry('ghost'));
    expect(r, isA<Err<void>>());
    expect((r as Err<void>).failure.message, isNotEmpty);
  });

  test('remove deletes by id', () async {
    await store.enqueue(_entry('a'));
    await store.enqueue(_entry('b'));
    final r = await store.remove('a');
    expect(r.isOk, isTrue);
    expect(store.all().map((e) => e.id), ['b']);
  });

  test('markDone sets state to done', () async {
    await store.enqueue(_entry('a'));
    final r = await store.markDone('a');
    expect(r.isOk, isTrue);
    expect(store.all().single.state, OutboxState.done);
  });

  test('corrupt stored JSON is treated as empty, not a crash', () async {
    SharedPreferences.setMockInitialValues({'outbox_v1': 'not-json{{'});
    final corruptPrefs = await SharedPreferences.getInstance();
    final corruptStore = OutboxStore(corruptPrefs);
    expect(corruptStore.all(), isEmpty);
    // And it recovers: enqueue works over the corrupt key.
    await corruptStore.enqueue(_entry('a'));
    expect(corruptStore.all().map((e) => e.id), ['a']);
  });

  test('watch() emits current then after each mutation', () async {
    final emissions = <List<String>>[];
    final sub = store.watch().listen((list) {
      emissions.add(list.map((e) => e.id).toList());
    });
    await store.enqueue(_entry('a'));
    await store.enqueue(_entry('b'));
    await store.remove('a');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    // First emission is the initial snapshot (empty), then one per mutation.
    expect(emissions.first, isEmpty);
    expect(emissions.last, ['b']);
    expect(emissions, contains(equals(['a'])));
    expect(emissions, contains(equals(['a', 'b'])));
  });
}
