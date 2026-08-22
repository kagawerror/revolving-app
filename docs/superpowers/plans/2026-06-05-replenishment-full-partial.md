# Full / Partial replenishment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the incharge mark each released request in the replenishment popup as Full or Partial; on approval, full requests close (`replenished`) while partial requests credit the fund, shrink their outstanding, stay `released`, and record a `partialReplenishments` audit row — an installment model.

**Architecture:** Additive data-model changes first (`FundRequest.replenishedCentavos`, `Replenishment.items` of a new `ReplenishmentItem`), then the repository switches `createDraft`/`createAndSubmit` to take items and `approve` applies them per-item in one transaction, then `firestore.rules` gains a partial request-update branch + a `partialReplenishments` collection, then the dialog and monitoring UI. Twice-enforced lifecycle: `RequestStatus` graph is unchanged (a partial is a same-status field update), so only the rules grow a new branch.

**Tech Stack:** Flutter, Riverpod, Cloud Firestore (`cloud_firestore`), `fake_cloud_firestore` + `flutter_test`. Money is integer centavos via `lib/core/money/money.dart`.

---

## File Structure

- **Modify** `lib/features/requests/domain/fund_request.dart` — add `replenishedCentavos` + `replenished`/`remaining` getters.
- **Modify** `lib/features/replenishment/domain/replenishment.dart` — add `ReplenishmentItem` value type + `items` field.
- **Modify** `lib/features/replenishment/domain/replenishment_repository.dart` — `createDraft`/`createAndSubmit` take `List<ReplenishmentItem> items`.
- **Modify** `lib/features/replenishment/data/firestore_replenishment_repository.dart` — build/validate items in `createDraft`; apply items (full vs partial, write `partialReplenishments`) in `approve`.
- **Modify** `firestore.rules` — partial request-update branch + `partialReplenishments` collection rules.
- **Modify** `lib/features/replenishment/presentation/replenish_select_dialog.dart` — per-row Full/Partial control + amount/remarks; build items.
- **Modify** `lib/features/requests/presentation/incharge_home_body.dart` — show `remaining` for released requests; releasable filter `status == released && remaining > 0`.
- **Modify** tests: `test/features/replenishment/data/replenishment_repository_test.dart`, `test/features/replenishment/presentation/replenish_select_dialog_test.dart`, `test/features/dashboard/presentation/dashboard_providers_test.dart`.
- **Create** `test/features/replenishment/domain/replenishment_item_test.dart`, `test/features/requests/domain/fund_request_remaining_test.dart`.

YAGNI note: the `partialReplenishments` records are written and rules-readable, but there is **no** Dart read-model / provider / history screen yet (no consumer). Add one when a view needs it.

TDD ordering note: Task 1 is purely additive (new field defaults, new type, `items` defaults to `[]`) so it lands green without touching the repo. Task 2 changes the `createDraft`/`createAndSubmit` signatures — which breaks the dialog call-site, the dashboard fake, and existing repo tests at once — so Task 2 bundles those edits (the dialog keeps its current all-Full behavior until Task 4 adds the per-row UI).

---

## Task 1: Domain models — `replenishedCentavos`, `ReplenishmentItem`, `Replenishment.items`

**Files:**
- Modify: `lib/features/requests/domain/fund_request.dart`
- Modify: `lib/features/replenishment/domain/replenishment.dart`
- Create: `test/features/requests/domain/fund_request_remaining_test.dart`
- Create: `test/features/replenishment/domain/replenishment_item_test.dart`

- [ ] **Step 1: Write the failing `FundRequest.remaining` test**

Create `test/features/requests/domain/fund_request_remaining_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

void main() {
  test('remaining = amount - replenished; defaults replenished to 0', () {
    final r = FundRequest.fromMap('r1', {
      'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'inc',
      'beneficiaryName': 'B', 'amountCentavos': 400000, 'purpose': 'x',
      'proofImageUrl': 'http://img', 'status': 'released', 'replenishmentId': null,
      // no replenishedCentavos -> legacy default 0
    });
    expect(r.replenished.centavos, 0);
    expect(r.remaining.centavos, 400000);
  });

  test('remaining shrinks by replenishedCentavos', () {
    final r = FundRequest.fromMap('r1', {
      'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'inc',
      'beneficiaryName': 'B', 'amountCentavos': 400000, 'purpose': 'x',
      'proofImageUrl': 'http://img', 'status': 'released',
      'replenishmentId': null, 'replenishedCentavos': 150000,
    });
    expect(r.replenished.centavos, 150000);
    expect(r.remaining.centavos, 250000);
  });

  test('toCreateMap writes replenishedCentavos: 0', () {
    final r = FundRequest(
      id: 'r1', companyId: 'c1', fundId: 'f1', createdByUid: 'inc',
      beneficiaryName: 'B', amount: Money.fromCentavos(400000), purpose: 'x',
      proofImageUrl: 'http://img', status: RequestStatus.released,
    );
    expect(r.toCreateMap()['replenishedCentavos'], 0);
  });
}
```

- [ ] **Step 2: Run it to verify failure**

Run: `flutter test test/features/requests/domain/fund_request_remaining_test.dart`
Expected: FAIL — `replenished`/`remaining` getters undefined.

- [ ] **Step 3: Add the field + getters to `FundRequest`**

In `lib/features/requests/domain/fund_request.dart`:

Add the field after `replenishmentId`:
```dart
  final String? replenishmentId;

  /// Centavos of this request's [amount] already returned to the fund via
  /// replenishment (full or one-or-more partials). Default 0; legacy docs read
  /// as 0. The request closes (`replenished`) when a Full covers the remainder.
  final int replenishedCentavos;
```

Add `this.replenishedCentavos = 0,` to the constructor (after `this.replenishmentId,`):
```dart
    this.replenishmentId,
    this.replenishedCentavos = 0,
    this.createdAt,
```

Add getters after `bool get hasProof => proofImageUrl.isNotEmpty;`:
```dart
  Money get replenished => Money.fromCentavos(replenishedCentavos);

  /// Outstanding amount still owed back to the fund (amount − replenished).
  Money get remaining => amount - replenished;
```

In `fromMap`, add after `replenishmentId:`:
```dart
        replenishmentId: m['replenishmentId'] as String?,
        replenishedCentavos: (m['replenishedCentavos'] ?? 0) as int,
```

In `toCreateMap`, add after `'replenishmentId': null,`:
```dart
        'replenishmentId': null,
        'replenishedCentavos': 0,
```

In `props`, add `replenishedCentavos`:
```dart
        status, replenishmentId, replenishedCentavos, createdAt,
```

(`Money` is already imported.)

- [ ] **Step 4: Run the FundRequest test — green**

Run: `flutter test test/features/requests/domain/fund_request_remaining_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Write the failing `ReplenishmentItem` test**

Create `test/features/replenishment/domain/replenishment_item_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';

void main() {
  test('ReplenishmentItem round-trips through map', () {
    const item = ReplenishmentItem(
      requestId: 'r1', isPartial: true,
      amount: Money.zero, remarks: 'partial pay',
    );
    final back = ReplenishmentItem.fromMap(item.copyWithAmount(150000).toMap());
    expect(back.requestId, 'r1');
    expect(back.isPartial, isTrue);
    expect(back.amount.centavos, 150000);
    expect(back.remarks, 'partial pay');
  });

  test('Replenishment.fromMap parses items; legacy doc yields empty items', () {
    final withItems = Replenishment.fromMap('a', {
      'companyId': 'c1', 'fundId': 'f1', 'status': 'draft',
      'requestIds': ['r1'], 'totalCentavos': 150000, 'reportNotes': '',
      'createdByUid': 'inc',
      'items': [
        {'requestId': 'r1', 'isPartial': true, 'amountCentavos': 150000, 'remarks': 'x'}
      ],
    });
    expect(withItems.items.length, 1);
    expect(withItems.items.single.amount.centavos, 150000);

    final legacy = Replenishment.fromMap('b', {
      'companyId': 'c1', 'fundId': 'f1', 'status': 'approved',
      'requestIds': ['r1', 'r2'], 'totalCentavos': 800000, 'reportNotes': '',
      'createdByUid': 'inc',
    });
    expect(legacy.items, isEmpty);
    expect(legacy.requestIds, ['r1', 'r2']);
    expect(legacy.total.centavos, 800000);
  });
}
```

(`copyWithAmount` is a tiny test convenience defined on `ReplenishmentItem` in Step 7 — it returns a copy with the given centavos. It keeps the round-trip test from hard-coding a second constructor call.)

- [ ] **Step 6: Run it to verify failure**

Run: `flutter test test/features/replenishment/domain/replenishment_item_test.dart`
Expected: FAIL — `ReplenishmentItem` undefined.

- [ ] **Step 7: Add `ReplenishmentItem` + `items` to `replenishment.dart`**

In `lib/features/replenishment/domain/replenishment.dart`, add this class at the top of the file (after the imports, before `class Replenishment`):

```dart
/// One line of a replenishment report: a released request being replenished
/// either in full or by a partial amount (with remarks).
class ReplenishmentItem extends Equatable {
  final String requestId;
  final bool isPartial;
  final Money amount;
  final String remarks;

  const ReplenishmentItem({
    required this.requestId,
    required this.isPartial,
    required this.amount,
    this.remarks = '',
  });

  ReplenishmentItem copyWithAmount(int centavos) => ReplenishmentItem(
        requestId: requestId,
        isPartial: isPartial,
        amount: Money.fromCentavos(centavos),
        remarks: remarks,
      );

  factory ReplenishmentItem.fromMap(Map<String, dynamic> m) => ReplenishmentItem(
        requestId: (m['requestId'] ?? '') as String,
        isPartial: (m['isPartial'] ?? false) as bool,
        amount: Money.fromCentavos((m['amountCentavos'] ?? 0) as int),
        remarks: (m['remarks'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {
        'requestId': requestId,
        'isPartial': isPartial,
        'amountCentavos': amount.centavos,
        'remarks': remarks,
      };

  @override
  List<Object?> get props => [requestId, isPartial, amount, remarks];
}
```

Add the `items` field to `Replenishment`. After `final String? approvedByUid;`:
```dart
  final String? approvedByUid;
  final List<ReplenishmentItem> items;
```

Add `this.items = const [],` to the constructor (after `this.approvedByUid,`):
```dart
    this.submittedByUid,
    this.approvedByUid,
    this.items = const [],
  });
```

In `fromMap`, add after the `approvedByUid:` line:
```dart
        approvedByUid: m['approvedByUid'] as String?,
        items: ((m['items'] ?? const []) as List)
            .map((e) => ReplenishmentItem.fromMap(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
```

In `toCreateMap`, add before the `'createdAt'` line:
```dart
        'items': items.map((i) => i.toMap()).toList(),
        'createdAt': FieldValue.serverTimestamp(),
```

In `props`, append `items`:
```dart
       submittedByUid, approvedByUid, items];
```

- [ ] **Step 8: Run both domain tests — green**

Run: `flutter test test/features/replenishment/domain/replenishment_item_test.dart test/features/requests/domain/fund_request_remaining_test.dart`
Expected: PASS.

- [ ] **Step 9: Confirm nothing else broke (additive change)**

Run: `flutter analyze lib/features/requests/domain/fund_request.dart lib/features/replenishment/domain/replenishment.dart`
Expected: No issues.

- [ ] **Step 10: Commit**

```bash
git checkout -- linux/ windows/ macos/Flutter/GeneratedPluginRegistrant.swift 2>/dev/null
git add lib/features/requests/domain/fund_request.dart \
        lib/features/replenishment/domain/replenishment.dart \
        test/features/requests/domain/fund_request_remaining_test.dart \
        test/features/replenishment/domain/replenishment_item_test.dart
git commit -m "feat(replenishment): FundRequest.remaining + ReplenishmentItem model

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Repository — items in `createDraft`/`createAndSubmit`, per-item `approve` + partial records

**Files:**
- Modify: `lib/features/replenishment/domain/replenishment_repository.dart`
- Modify: `lib/features/replenishment/data/firestore_replenishment_repository.dart`
- Modify: `lib/features/replenishment/presentation/replenish_select_dialog.dart` (call-site only, keep current all-Full UI)
- Modify: `test/features/dashboard/presentation/dashboard_providers_test.dart`
- Modify: `test/features/replenishment/data/replenishment_repository_test.dart`

- [ ] **Step 1: Update existing repo tests to the items signature + add new behavior tests (red first)**

In `test/features/replenishment/data/replenishment_repository_test.dart`:

(a) Add these import + helpers at the top of `main()` body (after the existing imports add the item import, and define helpers just inside `main()` before the first `test(`):

At the imports block, ensure this import is present:
```dart
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
```
(It already imports `Replenishment`; `ReplenishmentItem` comes from the same file — no new import needed.)

Add helpers right after `void main() {`:
```dart
  ReplenishmentItem full(String id) =>
      ReplenishmentItem(requestId: id, isPartial: false, amount: Money.zero);
  ReplenishmentItem partial(String id, int centavos, String remarks) =>
      ReplenishmentItem(
          requestId: id,
          isPartial: true,
          amount: Money.fromCentavos(centavos),
          remarks: remarks);
```

(b) Replace EVERY `createDraft(fundId: ..., requestIds: [...], createdByUid: 'inc')` call with the items form. Specifically:
- "compiles the selected released requests" test:
```dart
    final res = await repo.createDraft(
        fundId: 'f1', items: [full('r1'), full('r2')], createdByUid: 'inc');
```
- "fails when fund already replenishing": `items: [full('r1'), full('r2')]`.
- approve test: `items: [full('r1'), full('r2')]`.
- double-approval test: `items: [full('r1'), full('r2')]`.
- reject test: `items: [full('r1'), full('r2')]`.
- "no released requests for the fund" (f2): `items: [full('rX')]`.
- "sums only the selected requests": `items: [full('r1')]`.
- "rejects an empty selection": `items: const <ReplenishmentItem>[]`.
- "rejects a selection that includes a non-releasable id": `items: [full('r1'), full('ghost')]`.
- "createAndSubmit creates a submitted report": `items: [full('r1'), full('r2')]`.
- "createAndSubmit propagates a createDraft failure": `items: const <ReplenishmentItem>[]`.
- end-to-end test: `items: [full('r1')]`.

(c) Add NEW tests before the closing `}` of `main()`:
```dart
  test('createDraft: a full item ignores client amount and uses remaining', () async {
    // r1 already partly replenished: amount 400000, replenished 150000 -> remaining 250000.
    await db.collection('requests').doc('r1').update({'replenishedCentavos': 150000});
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1',
        // pass a bogus client amount on the full item; server must override.
        items: [full('r1').copyWithAmount(999999)],
        createdByUid: 'inc');
    expect(res.isOk, isTrue);
    expect(res.valueOrNull!.items.single.isPartial, isFalse);
    expect(res.valueOrNull!.items.single.amount.centavos, 250000); // remaining, not 999999
    expect(res.valueOrNull!.total.centavos, 250000);
  });

  test('createDraft: partial must be > 0 and < remaining', () async {
    final repo = FirestoreReplenishmentRepository(db);
    // r1 remaining is 400000.
    final tooBig = await repo.createDraft(
        fundId: 'f1', items: [partial('r1', 400000, 'x')], createdByUid: 'inc');
    expect(tooBig.failureOrNull, isA<ValidationFailure>());
    final zero = await repo.createDraft(
        fundId: 'f1', items: [partial('r1', 0, 'x')], createdByUid: 'inc');
    expect(zero.failureOrNull, isA<ValidationFailure>());
  });

  test('createDraft: partial requires remarks', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', items: [partial('r1', 100000, '')], createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
  });

  test('approve: a partial credits the fund, keeps the request released, writes a partial record', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final draft = (await repo.createDraft(
            fundId: 'f1',
            items: [partial('r1', 100000, 'first installment')],
            createdByUid: 'inc'))
        .valueOrNull!;
    await repo.submit(replenishment: draft, actorUid: 'inc', notes: '');
    final submitted = Replenishment.fromMap(draft.id,
        (await db.collection('replenishments').doc(draft.id).get()).data()!);
    final res = await repo.approve(replenishment: submitted, actorUid: 'mgr');
    expect(res.isOk, isTrue);

    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 300000); // 200000 + 100000

    final r1 = await db.collection('requests').doc('r1').get();
    expect(r1.data()!['status'], 'released'); // stays released
    expect(r1.data()!['replenishedCentavos'], 100000);
    expect(r1.data()!['replenishmentId'], isNull);

    final partials = await db
        .collection('partialReplenishments')
        .where('requestId', isEqualTo: 'r1')
        .get();
    expect(partials.docs.length, 1);
    expect(partials.docs.single.data()['amountCentavos'], 100000);
    expect(partials.docs.single.data()['remarks'], 'first installment');
    expect(partials.docs.single.data()['replenishmentId'], draft.id);
  });

  test('installments: two partials then a full closes the request; fund fully restored', () async {
    // Fresh fund at full budget, one released request of 400000 (fund debited).
    db = FakeFirebaseFirestore();
    await db.collection('funds').doc('f1').set({
      'companyId': 'c1', 'name': 'PC',
      'originalBudgetCentavos': 10000000, 'availableBalanceCentavos': 9600000,
      'lowBalanceThresholdPct': 3, 'status': 'active',
    });
    await db.collection('requests').doc('r1').set({
      'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'inc',
      'beneficiaryName': 'B', 'amountCentavos': 400000, 'purpose': 'x',
      'proofImageUrl': 'http://img', 'status': 'released',
      'replenishmentId': null, 'replenishedCentavos': 0,
    });
    final repo = FirestoreReplenishmentRepository(db);

    Future<void> approvePartial(int c) async {
      final d = (await repo.createDraft(
              fundId: 'f1', items: [partial('r1', c, 'inst')], createdByUid: 'inc'))
          .valueOrNull!;
      await repo.submit(replenishment: d, actorUid: 'inc', notes: '');
      final s = Replenishment.fromMap(
          d.id, (await db.collection('replenishments').doc(d.id).get()).data()!);
      expect((await repo.approve(replenishment: s, actorUid: 'mgr')).isOk, isTrue);
    }

    await approvePartial(100000); // remaining 300000
    await approvePartial(150000); // remaining 150000
    // Full on the remainder closes it.
    final d = (await repo.createDraft(
            fundId: 'f1', items: [full('r1')], createdByUid: 'inc'))
        .valueOrNull!;
    expect(d.items.single.amount.centavos, 150000); // remaining
    await repo.submit(replenishment: d, actorUid: 'inc', notes: '');
    final s = Replenishment.fromMap(
        d.id, (await db.collection('replenishments').doc(d.id).get()).data()!);
    expect((await repo.approve(replenishment: s, actorUid: 'mgr')).isOk, isTrue);

    final r1 = await db.collection('requests').doc('r1').get();
    expect(r1.data()!['status'], 'replenished');
    expect(r1.data()!['replenishedCentavos'], 400000);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 10000000); // fully restored
    final partials = await db
        .collection('partialReplenishments')
        .where('requestId', isEqualTo: 'r1')
        .get();
    expect(partials.docs.length, 2);
  });
```

- [ ] **Step 2: Run the repo tests — expect failures (signature + new behavior)**

Run: `flutter test test/features/replenishment/data/replenishment_repository_test.dart`
Expected: FAIL (compile error — `createDraft` has no `items` param yet).

- [ ] **Step 3: Change the repository interface**

In `lib/features/replenishment/domain/replenishment_repository.dart`, replace the `createDraft` + `createAndSubmit` declarations:

```dart
  /// Compiles the SELECTED released requests for the fund into a DRAFT report
  /// of line [items] (each Full or Partial) and flips the fund to `replenishing`.
  /// Full items' amounts are recomputed server-side from each request's
  /// remaining; partial items must satisfy 0 < amount < remaining and carry
  /// remarks. Fails if the fund is already replenishing, the selection is empty,
  /// or any item is invalid / no longer releasable.
  Future<Result<Replenishment>> createDraft({
    required String fundId,
    required List<ReplenishmentItem> items,
    required String createdByUid,
  });

  Future<Result<void>> submit({required Replenishment replenishment, required String actorUid, required String notes});

  /// One-tap selection→submit for the incharge popup: creates the draft from
  /// [items], then submits it for approval. Rolls the draft back (so the fund is
  /// not left locked in `replenishing`) if the submit step fails.
  Future<Result<void>> createAndSubmit({
    required String fundId,
    required List<ReplenishmentItem> items,
    required String actorUid,
    required String notes,
  });
```

(The file already imports `replenishment.dart`, so `ReplenishmentItem` is in scope.)

- [ ] **Step 4: Rewrite `createDraft` in the data impl**

In `lib/features/replenishment/data/firestore_replenishment_repository.dart`, add a collection getter near the other getters (after `_requests`):
```dart
  CollectionReference<Map<String, dynamic>> get _partials =>
      _db.collection('partialReplenishments');
```

Replace the whole `createDraft` method body with:
```dart
  @override
  Future<Result<Replenishment>> createDraft({
    required String fundId,
    required List<ReplenishmentItem> items,
    required String createdByUid,
  }) async {
    try {
      if (items.isEmpty) {
        return const Err(ValidationFailure('Select at least one request to replenish.'));
      }
      // Reject duplicate requestIds (a request may appear at most once).
      final ids = items.map((i) => i.requestId).toList();
      if (ids.toSet().length != ids.length) {
        return const Err(ValidationFailure('A request was selected more than once.'));
      }
      if (items.length > 200) {
        return const Err(ValidationFailure(
            'Too many requests to replenish at once (max 200). Replenish in smaller batches.'));
      }
      // Read the fund first to learn its companyId (single-doc get is allowed by
      // the sameCompany read rule).
      final fundSnap0 = await _fundRef(fundId).get();
      if (!fundSnap0.exists) {
        return const Err(ValidationFailure('Fund not found.'));
      }
      final companyId = (fundSnap0.data()!['companyId'] ?? '') as String;
      // COMPANY-SCOPED query (permission-denied fix). Released requests with a
      // positive remaining balance are replenishable.
      final snap = await _requests
          .where('companyId', isEqualTo: companyId)
          .where('fundId', isEqualTo: fundId)
          .where('status', isEqualTo: RequestStatus.released.name)
          .get();
      final remainingById = <String, int>{};
      for (final d in snap.docs) {
        if (d.data()['replenishmentId'] != null) continue;
        final amount = (d.data()['amountCentavos'] ?? 0) as int;
        final repl = (d.data()['replenishedCentavos'] ?? 0) as int;
        final remaining = amount - repl;
        if (remaining > 0) remainingById[d.id] = remaining;
      }
      // Validate each item and recompute amounts.
      final resolved = <ReplenishmentItem>[];
      var total = Money.zero;
      for (final item in items) {
        final remaining = remainingById[item.requestId];
        if (remaining == null) {
          return const Err(ValidationFailure(
              'Some selected requests are no longer available to replenish.'));
        }
        if (item.isPartial) {
          final c = item.amount.centavos;
          if (c <= 0 || c >= remaining) {
            return const Err(ValidationFailure(
                'A partial amount must be more than zero and less than the remaining balance.'));
          }
          if (item.remarks.trim().isEmpty) {
            return const Err(ValidationFailure('A partial replenishment needs remarks.'));
          }
          resolved.add(ReplenishmentItem(
              requestId: item.requestId,
              isPartial: true,
              amount: Money.fromCentavos(c),
              remarks: item.remarks.trim()));
          total += Money.fromCentavos(c);
        } else {
          // Full: server authority = current remaining (ignore client amount).
          resolved.add(ReplenishmentItem(
              requestId: item.requestId,
              isPartial: false,
              amount: Money.fromCentavos(remaining)));
          total += Money.fromCentavos(remaining);
        }
      }
      final newRef = _reps.doc();
      await _db.runTransaction((tx) async {
        final fundSnap = await tx.get(_fundRef(fundId));
        if (!fundSnap.exists) throw StateError('Fund not found.');
        final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
        if (fund.status == FundStatus.replenishing) {
          throw StateError('This fund is already being replenished.');
        }
        tx.set(newRef, {
          'companyId': companyId,
          'fundId': fundId,
          'status': ReplenishmentStatus.draft.name,
          'requestIds': resolved.map((i) => i.requestId).toList(),
          'items': resolved.map((i) => i.toMap()).toList(),
          'totalCentavos': total.centavos,
          'reportNotes': '',
          'createdByUid': createdByUid,
          'submittedByUid': null,
          'approvedByUid': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(_fundRef(fundId), {'status': FundStatus.replenishing.name});
      });
      return Ok(Replenishment(
        id: newRef.id,
        companyId: companyId,
        fundId: fundId,
        status: ReplenishmentStatus.draft,
        requestIds: resolved.map((i) => i.requestId).toList(),
        total: total,
        reportNotes: '',
        createdByUid: createdByUid,
        items: resolved,
      ));
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('createDraft failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not start a replenishment.'));
    }
  }
```

- [ ] **Step 5: Update `createAndSubmit` to pass items**

```dart
  @override
  Future<Result<void>> createAndSubmit({
    required String fundId,
    required List<ReplenishmentItem> items,
    required String actorUid,
    required String notes,
  }) async {
    final draftRes =
        await createDraft(fundId: fundId, items: items, createdByUid: actorUid);
    final draft = draftRes.valueOrNull;
    if (draft == null) return Err(draftRes.failureOrNull!);
    final submitRes = await submit(replenishment: draft, actorUid: actorUid, notes: notes);
    if (submitRes.failureOrNull != null) {
      await discardDraft(replenishment: draft);
      return submitRes;
    }
    return const Ok(null);
  }
```

- [ ] **Step 6: Rewrite the `approve` write section to apply items**

In `approve`, the transaction currently: reads rep + fund, writes fund, then loops `replenishment.requestIds` setting `replenished`. Replace the request loop AND add a request read-pass BEFORE the writes. The full transaction body becomes:

```dart
      await _db.runTransaction((tx) async {
        final repRef = _reps.doc(replenishment.id);
        final repSnap = await tx.get(repRef);
        if (!repSnap.exists) throw StateError('Replenishment not found.');
        final current = ReplenishmentStatus.fromName(repSnap.data()!['status'] as String?);
        if (!current.canTransitionTo(ReplenishmentStatus.approved)) {
          throw StateError('This report was already decided.');
        }
        final fundSnap = await tx.get(_fundRef(replenishment.fundId));
        if (!fundSnap.exists) throw StateError('Fund not found.');
        final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
        // Read every line-item's request BEFORE any write (tx reads-before-writes).
        final reqData = <String, Map<String, dynamic>>{};
        for (final item in replenishment.items) {
          final rs = await tx.get(_requests.doc(item.requestId));
          if (rs.exists) reqData[item.requestId] = rs.data()!;
        }
        // --- writes ---
        final newBalance = fund.availableBalance + replenishment.total;
        final replenished = Fund(
          id: fund.id,
          companyId: fund.companyId,
          name: fund.name,
          originalBudget: fund.originalBudget,
          availableBalance: newBalance,
          lowBalanceThresholdPct: fund.lowBalanceThresholdPct,
          status: fund.status,
        );
        tx.update(_fundRef(replenishment.fundId), {
          'availableBalanceCentavos': newBalance.centavos,
          'status': _restoredStatus(replenished).name,
        });
        for (final item in replenishment.items) {
          final reqRef = _requests.doc(item.requestId);
          final prior = (reqData[item.requestId]?['replenishedCentavos'] ?? 0) as int;
          final nextReplenished = prior + item.amount.centavos;
          if (item.isPartial) {
            tx.set(_partials.doc(), {
              'companyId': replenishment.companyId,
              'fundId': replenishment.fundId,
              'requestId': item.requestId,
              'replenishmentId': replenishment.id,
              'amountCentavos': item.amount.centavos,
              'remarks': item.remarks,
              'createdByUid': replenishment.createdByUid,
              'approvedByUid': actorUid,
              'createdAt': FieldValue.serverTimestamp(),
            });
            tx.update(reqRef, {'replenishedCentavos': nextReplenished});
          } else {
            tx.update(reqRef, {
              'status': RequestStatus.replenished.name,
              'replenishmentId': replenishment.id,
              'replenishedCentavos': nextReplenished,
            });
          }
        }
        tx.update(repRef, {
          'status': ReplenishmentStatus.approved.name,
          'approvedByUid': actorUid,
          'decidedAt': FieldValue.serverTimestamp(),
        });
      });
```

(Delete the old `for (final rid in replenishment.requestIds) { ... }` loop and the old fund-write block they are replaced by the above.)

- [ ] **Step 7: Update the dashboard fake repo signatures**

In `test/features/dashboard/presentation/dashboard_providers_test.dart`, update the fake's `createDraft`/`createAndSubmit` overrides:
```dart
  @override
  Future<Result<Replenishment>> createDraft(
          {required String fundId,
          required List<ReplenishmentItem> items,
          required String createdByUid}) async =>
      const Err(ValidationFailure('unused'));
  @override
  Future<Result<void>> createAndSubmit(
          {required String fundId,
          required List<ReplenishmentItem> items,
          required String actorUid,
          required String notes}) async =>
      const Ok(null);
```
(`ReplenishmentItem` comes from the already-imported `replenishment.dart`.)

- [ ] **Step 8: Update the dialog call-site to build all-Full items (keep current UI)**

In `lib/features/replenishment/presentation/replenish_select_dialog.dart`, the `_submit` method currently calls `createAndSubmit(..., requestIds: _selected.toList(), ...)`. Change ONLY that call to build Full items (the per-row Partial UI arrives in Task 4):
```dart
    final items = _selected
        .map((id) => ReplenishmentItem(
            requestId: id, isPartial: false, amount: Money.zero))
        .toList();
    final res = await ref.read(replenishmentRepositoryProvider).createAndSubmit(
          fundId: widget.fund.id,
          items: items,
          actorUid: user.uid,
          notes: _notes.text.trim(),
        );
```
Add the import at the top: `import '../domain/replenishment.dart';` (for `ReplenishmentItem`). `Money` is already imported.

- [ ] **Step 9: Run the repo + dashboard tests — expect green**

Run: `flutter test test/features/replenishment/data/replenishment_repository_test.dart test/features/dashboard/presentation/dashboard_providers_test.dart test/features/replenishment/presentation/replenish_select_dialog_test.dart`
Expected: PASS. If `fake_cloud_firestore` rejects any `FieldValue` used, note it — but this code uses only `FieldValue.serverTimestamp()` (already used elsewhere in this file) and plain integer writes, no `FieldValue.increment`, so it is supported.

Also `flutter analyze lib/features/replenishment test/features/replenishment test/features/dashboard` — expect no issues.

- [ ] **Step 10: Commit**

```bash
git checkout -- linux/ windows/ macos/Flutter/GeneratedPluginRegistrant.swift 2>/dev/null
git add lib/features/replenishment/domain/replenishment_repository.dart \
        lib/features/replenishment/data/firestore_replenishment_repository.dart \
        lib/features/replenishment/presentation/replenish_select_dialog.dart \
        test/features/dashboard/presentation/dashboard_providers_test.dart \
        test/features/replenishment/data/replenishment_repository_test.dart
git commit -m "feat(replenishment): per-item full/partial draft + approve with partial records

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Firestore rules — partial request update + partialReplenishments collection

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Add the partial branch to the `requests` update rule**

In `firestore.rules`, inside `match /requests/{requestId}`, the `allow update` block currently ends with the released→replenished disjunct. Add a new disjunct for a partial (status stays `released`, only `replenishedCentavos` grows, `amountCentavos` immutable). Change the closing of the update rule from:
```
        || ((isApprover() || isAdmin())
          && resource.data.status == 'released'
          && request.resource.data.status == 'replenished'
          && request.resource.data.replenishmentId is string)
      );
```
to:
```
        || ((isApprover() || isAdmin())
          && resource.data.status == 'released'
          && request.resource.data.status == 'replenished'
          && request.resource.data.replenishmentId is string)
        || ((isApprover() || isAdmin())
          && resource.data.status == 'released'
          && request.resource.data.status == 'released'
          && request.resource.data.replenishedCentavos
              > resource.data.get('replenishedCentavos', 0)
          && request.resource.data.amountCentavos == resource.data.amountCentavos)
      );
```

- [ ] **Step 2: Add the `partialReplenishments` collection rules**

Immediately after the closing `}` of `match /replenishments/{repId} { ... }` (and before `match /notifications/{notifId}`), insert:
```
    match /partialReplenishments/{partialId} {
      // Audit rows written when a replenishment with partial line items is
      // approved. Created by the approving approver (or admin superuser);
      // immutable thereafter.
      allow read: if isAdmin() || sameCompany(resource.data.companyId);
      allow create: if (isApprover() || isAdmin())
        && (sameCompany(request.resource.data.companyId) || isAdmin());
      allow update, delete: if false;
    }
```

- [ ] **Step 3: Validate the rules compile (no deploy yet)**

Run: `firebase deploy --only firestore:rules --dry-run` if supported; otherwise validate syntax with:
Run: `firebase emulators:exec --only firestore "true"` is heavy — instead just confirm the file parses by running the analyzer-equivalent: open the file and re-read the two edits for balanced braces. The authoritative validation is the deploy in Task 6 (the MCP `firebase_validate_security_rules` tool may also be used here if available).

Expected: braces balanced; the `requests` update rule has exactly the two original disjuncts plus the new partial disjunct; the new `match` block sits between `replenishments` and `notifications`.

- [ ] **Step 4: Commit**

```bash
git add firestore.rules
git commit -m "feat(replenishment): rules for partial request update + partialReplenishments

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Dialog — per-row Full/Partial with amount + remarks

**Files:**
- Modify: `lib/features/replenishment/presentation/replenish_select_dialog.dart`
- Modify: `test/features/replenishment/presentation/replenish_select_dialog_test.dart`

- [ ] **Step 1: Add the failing widget tests**

Append to `test/features/replenishment/presentation/replenish_select_dialog_test.dart` inside `main()`:
```dart
  testWidgets('switching a row to Partial reveals amount + remarks and gates submit',
      (tester) async {
    await tester.pumpWidget(_host([_req('r1', 400000)]));
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    // Default Full -> submit enabled.
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit for approval'))
            .onPressed,
        isNotNull);

    // Switch to Partial.
    await tester.tap(find.text('Partial'));
    await tester.pump();
    // Amount + remarks fields appear; submit disabled until valid.
    expect(find.widgetWithText(TextField, 'Partial amount'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Remarks'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit for approval'))
            .onPressed,
        isNull);

    // Enter a valid partial (< 4000) + remarks -> enabled.
    await tester.enterText(
        find.widgetWithText(TextField, 'Partial amount'), '1000');
    await tester.enterText(find.widgetWithText(TextField, 'Remarks'), 'half');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit for approval'))
            .onPressed,
        isNotNull);
  });

  testWidgets('a partial amount equal to or above remaining keeps submit disabled',
      (tester) async {
    await tester.pumpWidget(_host([_req('r1', 400000)]));
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.text('Partial'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Partial amount'), '4000'); // == remaining
    await tester.enterText(find.widgetWithText(TextField, 'Remarks'), 'all');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit for approval'))
            .onPressed,
        isNull);
  });
```

- [ ] **Step 2: Run — expect failure**

Run: `flutter test test/features/replenishment/presentation/replenish_select_dialog_test.dart`
Expected: FAIL — no 'Partial' control / 'Partial amount' field yet.

- [ ] **Step 3: Replace the dialog with the per-row Full/Partial version**

Replace the whole body of `lib/features/replenishment/presentation/replenish_select_dialog.dart` with:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/fund.dart';
import '../../requests/domain/fund_request.dart';
import '../domain/replenishment.dart';
import 'replenishment_providers.dart';

/// Popup for the incharge to pick released requests to replenish — each Full or
/// Partial (amount + remarks) — and submit them for approval in one tap. Pops
/// `true` on a successful submit so the caller can show the success overlay.
/// [releasable] is the already-filtered released list (remaining > 0).
class ReplenishSelectDialog extends ConsumerStatefulWidget {
  final Fund fund;
  final List<FundRequest> releasable;
  const ReplenishSelectDialog({
    super.key,
    required this.fund,
    required this.releasable,
  });

  @override
  ConsumerState<ReplenishSelectDialog> createState() =>
      _ReplenishSelectDialogState();
}

class _ReplenishSelectDialogState extends ConsumerState<ReplenishSelectDialog> {
  final _selected = <String>{};
  final _partial = <String>{};
  final _amount = <String, String>{}; // requestId -> raw pesos text
  final _remarks = <String, String>{};
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Parsed partial centavos for a row, or null if blank/invalid.
  int? _partialCentavos(String id) {
    final t = (_amount[id] ?? '').trim();
    if (t.isEmpty) return null;
    final pesos = num.tryParse(t);
    if (pesos == null) return null;
    return (pesos * 100).round();
  }

  bool _rowValid(FundRequest r) {
    if (!_partial.contains(r.id)) return true; // Full is always valid
    final c = _partialCentavos(r.id);
    if (c == null || c <= 0 || c >= r.remaining.centavos) return false;
    return (_remarks[r.id] ?? '').trim().isNotEmpty;
  }

  bool get _canSubmit =>
      !_busy &&
      _selected.isNotEmpty &&
      widget.releasable.where((r) => _selected.contains(r.id)).every(_rowValid);

  Money get _total {
    var sum = Money.zero;
    for (final r in widget.releasable) {
      if (!_selected.contains(r.id)) continue;
      if (_partial.contains(r.id)) {
        final c = _partialCentavos(r.id);
        if (c != null && c > 0 && c < r.remaining.centavos) {
          sum += Money.fromCentavos(c);
        }
      } else {
        sum += r.remaining;
      }
    }
    return sum;
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || !_canSubmit) return;
    final items = <ReplenishmentItem>[];
    for (final r in widget.releasable) {
      if (!_selected.contains(r.id)) continue;
      if (_partial.contains(r.id)) {
        items.add(ReplenishmentItem(
          requestId: r.id,
          isPartial: true,
          amount: Money.fromCentavos(_partialCentavos(r.id)!),
          remarks: (_remarks[r.id] ?? '').trim(),
        ));
      } else {
        items.add(ReplenishmentItem(
            requestId: r.id, isPartial: false, amount: r.remaining));
      }
    }
    setState(() => _busy = true);
    final res = await ref.read(replenishmentRepositoryProvider).createAndSubmit(
          fundId: widget.fund.id,
          items: items,
          actorUid: user.uid,
          notes: _notes.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.showOnError(context)) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final empty = widget.releasable.isEmpty;
    return AlertDialog(
      title: Text('Replenish ${widget.fund.name}'),
      content: SizedBox(
        width: double.maxFinite,
        child: empty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: AppTokens.lg),
                child: Text('No released requests to replenish.'),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in widget.releasable) _row(r, textTheme),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Selected: ${_total.format()} • ${_selected.length} item(s)',
                      style: textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: AppTokens.sm),
                  TextField(
                    controller: _notes,
                    enabled: !_busy,
                    decoration:
                        const InputDecoration(labelText: 'Notes (optional)'),
                    maxLines: 2,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit for approval'),
        ),
      ],
    );
  }

  Widget _row(FundRequest r, TextTheme textTheme) {
    final checked = _selected.contains(r.id);
    final isPartial = _partial.contains(r.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          dense: true,
          value: checked,
          onChanged: _busy
              ? null
              : (v) => setState(() {
                    if (v ?? false) {
                      _selected.add(r.id);
                    } else {
                      _selected.remove(r.id);
                      _partial.remove(r.id);
                    }
                  }),
          title: Text(r.beneficiaryName),
          subtitle: Text(
            r.purpose,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          secondary: Text(
            r.remaining.format(),
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (checked)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.lg, 0, AppTokens.md, AppTokens.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Full')),
                    ButtonSegment(value: true, label: Text('Partial')),
                  ],
                  selected: {isPartial},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() {
                            if (s.first) {
                              _partial.add(r.id);
                            } else {
                              _partial.remove(r.id);
                            }
                          }),
                ),
                if (isPartial) ...[
                  const SizedBox(height: AppTokens.sm),
                  TextField(
                    enabled: !_busy,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    decoration: InputDecoration(
                      labelText: 'Partial amount',
                      helperText: 'Less than ${r.remaining.format()}',
                    ),
                    onChanged: (v) => setState(() => _amount[r.id] = v),
                  ),
                  const SizedBox(height: AppTokens.xs),
                  TextField(
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'Remarks'),
                    onChanged: (v) => setState(() => _remarks[r.id] = v),
                  ),
                ],
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the dialog tests — green**

Run: `flutter test test/features/replenishment/presentation/replenish_select_dialog_test.dart`
Expected: PASS (all, including the 3 original tests — note the original "selected total reflects the checked requests" still passes because Full rows contribute `remaining`, and for a fresh request `remaining == amount`).

Run: `flutter analyze lib/features/replenishment/presentation/replenish_select_dialog.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git checkout -- linux/ windows/ macos/Flutter/GeneratedPluginRegistrant.swift 2>/dev/null
git add lib/features/replenishment/presentation/replenish_select_dialog.dart \
        test/features/replenishment/presentation/replenish_select_dialog_test.dart
git commit -m "feat(replenishment): per-row Full/Partial selection in the popup

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Monitoring — show remaining; releasable filter

**Files:**
- Modify: `lib/features/requests/presentation/incharge_home_body.dart`

- [ ] **Step 1: Update the releasable filter in `_replenish`**

In `lib/features/requests/presentation/incharge_home_body.dart`, the `_replenish` method filters the requests for the dialog. Change the filter from:
```dart
      final releasable = all
          .where((r) =>
              r.status == RequestStatus.released && r.replenishmentId == null)
          .toList();
```
to:
```dart
      final releasable = all
          .where((r) =>
              r.status == RequestStatus.released && r.remaining.centavos > 0)
          .toList();
```

- [ ] **Step 2: Show `remaining` (with a replenished hint) for released requests in the list**

In the per-request `AppListTile` trailing column, the amount currently renders `r.amount.format()`. For a `released` request that has been partly replenished, show the remaining and a hint. Find the trailing `Text(r.amount.format(), ...)` inside `_FundSectionState.build`'s request list and replace that single `Text` with:
```dart
                              Text(
                                (r.status == RequestStatus.released
                                        ? r.remaining
                                        : r.amount)
                                    .format(),
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              if (r.status == RequestStatus.released &&
                                  r.replenishedCentavos > 0)
                                Text(
                                  '${r.replenished.format()} of ${r.amount.format()} replenished',
                                  style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant),
                                ),
```
(The surrounding `Column` already supplies `scheme`/`textTheme` from `build`. `FontFeature` is from `dart:ui`, already used in this file.)

- [ ] **Step 3: Analyze + full test**

Run: `flutter analyze lib/features/requests/presentation/incharge_home_body.dart`
Expected: No issues.
Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git checkout -- linux/ windows/ macos/Flutter/GeneratedPluginRegistrant.swift 2>/dev/null
git add lib/features/requests/presentation/incharge_home_body.dart
git commit -m "feat(replenishment): incharge list shows remaining + replenished hint

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Full verification + deploy rules

**Files:** none (verification + deploy)

- [ ] **Step 1: Full analyze**

Run: `flutter analyze`
Expected: No new issues beyond the pre-existing `unnecessary_underscores` lints in `app_router.dart` noted in project memory.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 3: Revert desktop plugin churn**

Run: `git checkout -- linux/ windows/ macos/Flutter/GeneratedPluginRegistrant.swift`
Expected: working tree clean of that churn.

- [ ] **Step 4: Deploy the rules (required for partials to work on device)**

Run: `firebase deploy --only firestore:rules`
Expected: "Deploy complete!" Verify the live rules include the `partialReplenishments` match block and the new `requests` partial-update disjunct. (If the project uses the Firebase MCP `firebase_deploy` tool instead of the CLI, use that against project `rev-app-75af7`.)

- [ ] **Step 5: Final confirmation**

Run: `git status` and `git log --oneline -8`
Expected: clean tree (aside from pre-existing unrelated changes); six feature commits present.

---

## Self-review notes

- **Spec coverage:** `FundRequest.replenishedCentavos`/`remaining` → Task 1; `Replenishment.items`/`ReplenishmentItem` → Task 1; `createDraft`/`createAndSubmit` items + validation → Task 2 Steps 3-5; per-item `approve` + `partialReplenishments` write → Task 2 Step 6; rules (partial branch + collection) → Task 3; dialog per-row Full/Partial → Task 4; monitoring `remaining` + filter → Task 5; deploy → Task 6 Step 4. The spec's optional `PartialReplenishment` Dart read-model/`watchByRequest` is intentionally dropped (YAGNI — no consumer); records are still written and rules-readable.
- **Placeholder scan:** none — every code step shows full code; the rules-validation step (Task 3 Step 3) is explicit about relying on the Task 6 deploy for authoritative validation.
- **Type/name consistency:** `ReplenishmentItem({requestId, isPartial, amount, remarks})`, `createDraft({fundId, items, createdByUid})`, `createAndSubmit({fundId, items, actorUid, notes})`, `FundRequest.remaining`/`replenished`/`replenishedCentavos`, and the `partialReplenishments` field set (`companyId, fundId, requestId, replenishmentId, amountCentavos, remarks, createdByUid, approvedByUid, createdAt`) are used identically across the interface, data impl, dialog, rules, and tests.
- **Money:** integer centavos throughout; partial parsing rounds pesos→centavos once in the dialog; the repo treats the partial amount as authoritative centavos and full as server `remaining`.
- **Transaction safety:** `approve` reads every line-item's request before any write (reads-before-writes), re-derives `replenishedCentavos` from server state, and the fund lock prevents concurrent reports on the same fund.
