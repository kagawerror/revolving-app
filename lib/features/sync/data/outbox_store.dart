import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/outbox_entry.dart';

/// Durable, replayable queue of [OutboxEntry] backed by a single
/// shared_preferences key. The outbox is tens of entries for one incharge, so a
/// JSON list in one key is plenty (no Hive/sqlite).
///
/// Local-only: this never touches Firestore. The sync engine (Phase 5) drains
/// it. Mutations read the whole list, change it, write it back atomically-ish,
/// and push the new snapshot to [watch].
///
/// The [SharedPreferences] instance is injected so tests can pass an in-memory
/// one (`SharedPreferences.setMockInitialValues`). The Riverpod
/// `outboxStoreProvider` supplies the real instance.
class OutboxStore {
  OutboxStore(this._prefs);

  static const String _key = 'outbox_v1';

  final SharedPreferences _prefs;
  final StreamController<List<OutboxEntry>> _controller =
      StreamController<List<OutboxEntry>>.broadcast();

  /// Current queue snapshot (in insertion order). Reads the persisted list each
  /// call; shared_preferences keeps values in memory so this is cheap.
  List<OutboxEntry> all() => _read();

  /// Live stream of the queue. Emits the current snapshot first, then a fresh
  /// snapshot after every successful mutation. Feeds `outboxProvider`.
  ///
  /// We subscribe to the broadcast controller first, then emit the current
  /// value, so a mutation racing the subscription is never dropped (it queues
  /// behind the leading snapshot rather than slipping through a gap).
  Stream<List<OutboxEntry>> watch() {
    final out = StreamController<List<OutboxEntry>>();
    late final StreamSubscription<List<OutboxEntry>> sub;
    out.onListen = () {
      sub = _controller.stream.listen(out.add,
          onError: out.addError, onDone: out.close);
      out.add(List.unmodifiable(_read()));
    };
    out.onCancel = () => sub.cancel();
    return out.stream;
  }

  /// Idempotent enqueue: appends unless an entry with the same id already
  /// exists, in which case it is a no-op (first write wins). Preserves order.
  Future<Result<void>> enqueue(OutboxEntry entry) async {
    final list = _read();
    if (list.any((e) => e.id == entry.id)) {
      return const Ok(null);
    }
    list.add(entry);
    return _write(list);
  }

  /// Replaces the entry sharing [updated]'s id. Fails if none exists.
  Future<Result<void>> update(OutboxEntry updated) async {
    final list = _read();
    final i = list.indexWhere((e) => e.id == updated.id);
    if (i < 0) {
      return const Err(NotFoundFailure('Queued action no longer exists.'));
    }
    list[i] = updated;
    return _write(list);
  }

  /// Removes the entry with [id]. Removing a missing id is a no-op success.
  Future<Result<void>> remove(String id) async {
    final list = _read()..removeWhere((e) => e.id == id);
    return _write(list);
  }

  /// Marks the entry with [id] as [OutboxState.done]. Fails if none exists.
  Future<Result<void>> markDone(String id) async {
    final list = _read();
    final i = list.indexWhere((e) => e.id == id);
    if (i < 0) {
      return const Err(NotFoundFailure('Queued action no longer exists.'));
    }
    list[i] = list[i].copyWith(state: OutboxState.done);
    return _write(list);
  }

  List<OutboxEntry> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => OutboxEntry.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      // Corruption safety: never crash on a bad blob. Log generically (NO
      // contents — the payload can carry amounts) and treat as empty so the
      // next write heals the key.
      developer.log(
        'Outbox store: failed to parse persisted queue; treating as empty.',
        name: 'OutboxStore',
      );
      return [];
    }
  }

  Future<Result<void>> _write(List<OutboxEntry> list) async {
    try {
      final raw = jsonEncode(list.map((e) => e.toJson()).toList());
      await _prefs.setString(_key, raw);
      _controller.add(List.unmodifiable(list));
      return const Ok(null);
    } catch (e) {
      developer.log('Outbox store: write failed.',
          name: 'OutboxStore', error: e);
      return const Err(UnexpectedFailure('Could not save the offline queue.'));
    }
  }
}
