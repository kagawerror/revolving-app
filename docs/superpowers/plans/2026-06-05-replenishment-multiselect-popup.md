# Replenishment multi-select popup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the incharge "Replenish" auto-bundle with a popup that lists released-unreplenished requests, lets the incharge check a subset and submit it for approval in one tap; on approval the selected amounts are added back to the fund balance.

**Architecture:** All logic lives in Dart — no `firestore.rules` or index changes. `createDraft` is fixed to query company-scoped (the cause of the on-device `permission-denied`) and to accept an explicit selection; a new `createAndSubmit` composes draft→submit with rollback; `approve` switches from reset-to-original-budget to add-back-the-bundled-total with a balance-derived status. A new `ReplenishSelectDialog` is the UI; the old `ReplenishReviewScreen` is removed.

**Tech Stack:** Flutter, Riverpod, Cloud Firestore (`cloud_firestore`), `fake_cloud_firestore` + `flutter_test` for tests. Money is integer centavos via `lib/core/money/money.dart`.

---

## File Structure

- **Modify** `lib/features/replenishment/domain/replenishment_repository.dart` — change `createDraft` signature, add `createAndSubmit`, update doc comment on `approve`.
- **Modify** `lib/features/replenishment/data/firestore_replenishment_repository.dart` — rewrite `createDraft` (company-scoped query + `requestIds`), add `createAndSubmit`, change `approve` arithmetic.
- **Modify** `test/features/replenishment/data/replenishment_repository_test.dart` — update existing tests to the new signature + incremental refund; add subset and `createAndSubmit` tests.
- **Modify** `test/features/dashboard/presentation/dashboard_providers_test.dart` — update the fake repo to the new interface.
- **Create** `lib/features/replenishment/presentation/replenish_select_dialog.dart` — the popup.
- **Create** `test/features/replenishment/presentation/replenish_select_dialog_test.dart` — widget test for selection/total/enablement/empty state.
- **Modify** `lib/features/requests/presentation/incharge_home_body.dart` — open the dialog; remove `_startReplenish` + the `ReplenishReviewScreen` import.
- **Delete** `lib/features/replenishment/presentation/replenish_review_screen.dart` — dead once auto-bundle is gone.

A note on TDD ordering: changing `createDraft`'s signature breaks the data impl, the dashboard fake, and the existing tests all at once (Dart won't compile a partial change). So Task 1 lands the interface + data + mock + existing-test edits together, ending green; Task 2 then adds *new* tests; UI follows.

---

## Task 1: Repository — company-scoped `createDraft(requestIds)`, `createAndSubmit`, incremental `approve`

**Files:**
- Modify: `lib/features/replenishment/domain/replenishment_repository.dart`
- Modify: `lib/features/replenishment/data/firestore_replenishment_repository.dart`
- Modify: `test/features/dashboard/presentation/dashboard_providers_test.dart:166-178` (the fake repo's `createDraft`)
- Test: `test/features/replenishment/data/replenishment_repository_test.dart`

- [ ] **Step 1: Update the existing repo tests to the NEW behavior first (they will fail)**

In `test/features/replenishment/data/replenishment_repository_test.dart`, make these exact edits.

(a) First test — pass an explicit selection:

```dart
  test('createDraft compiles the selected released requests and flips fund to replenishing', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', requestIds: const ['r1', 'r2'], createdByUid: 'inc');
    expect(res.isOk, isTrue);
    final rp = await db.collection('replenishments').doc(res.valueOrNull!.id).get();
    expect((rp.data()!['requestIds'] as List).length, 2);
    expect(rp.data()!['totalCentavos'], 800000);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['status'], 'replenishing');
  });
```

(b) "already replenishing" test — add `requestIds`:

```dart
    final res = await repo.createDraft(
        fundId: 'f1', requestIds: const ['r1', 'r2'], createdByUid: 'inc');
```

(c) Approve test — rename + expect the added-back total (200000 + 800000 = 1000000), status derived (1000000 > 3% of 10000000 = 300000 → active):

```dart
  test('approve adds the bundled total back to the balance, tags requests replenished', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = (await repo.createDraft(
            fundId: 'f1', requestIds: const ['r1', 'r2'], createdByUid: 'inc'))
        .valueOrNull!
        .id;
    final draft = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    await repo.submit(replenishment: draft, actorUid: 'inc', notes: 'June');
    final submitted = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final res = await repo.approve(replenishment: submitted, actorUid: 'mgr');
    expect(res.isOk, isTrue);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 1000000); // 200000 + 800000
    expect(fund.data()!['status'], 'active');
    for (final rid in ['r1', 'r2']) {
      final req = await db.collection('requests').doc(rid).get();
      expect(req.data()!['status'], 'replenished');
      expect(req.data()!['replenishmentId'], id);
    }
    final rp = await db.collection('replenishments').doc(id).get();
    expect(rp.data()!['status'], 'approved');
  });
```

(d) Double-approval test — add `requestIds` and change the final balance assertion to `1000000`:

```dart
    final id = (await repo.createDraft(
            fundId: 'f1', requestIds: const ['r1', 'r2'], createdByUid: 'inc'))
        .valueOrNull!
        .id;
```
```dart
    expect(fund.data()!['availableBalanceCentavos'], 1000000); // stays after first approve
```

(e) Reject test — add `requestIds`:

```dart
    final id = (await repo.createDraft(
            fundId: 'f1', requestIds: const ['r1', 'r2'], createdByUid: 'inc'))
        .valueOrNull!
        .id;
```

(f) "no released requests for the fund" test — pass a (non-releasable) id; message is unchanged:

```dart
    final res = await repo.createDraft(
        fundId: 'f2', requestIds: const ['rX'], createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
    expect((res.failureOrNull as ValidationFailure).message,
        'No released requests to replenish.');
```

(g) End-to-end test — add `requestIds: const ['r1']`, and change the two final-balance assertions from `10000000` to `500000` (release left 100000; add back 400000 → 500000 > 300000 → active):

```dart
    final draftRes = await replenishRepo.createDraft(
        fundId: 'f1', requestIds: const ['r1'], createdByUid: 'inc');
```
```dart
    // 4. Balance restored by the released amount; request 'replenished' and tagged.
    fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 500000); // 100000 + 400000
    expect(fund.data()!['status'], 'active');
```

- [ ] **Step 2: Run the repo tests to confirm they fail to compile/assert**

Run: `flutter test test/features/replenishment/data/replenishment_repository_test.dart`
Expected: FAIL — `createDraft` doesn't accept `requestIds` yet (compile error).

- [ ] **Step 3: Change the repository interface**

In `lib/features/replenishment/domain/replenishment_repository.dart`, replace the `createDraft` declaration and the `approve` doc comment, and add `createAndSubmit`:

```dart
  /// Compiles the SELECTED released-unreplenished requests for the fund into a
  /// DRAFT and flips the fund to `replenishing`. Fails if the fund is already
  /// replenishing, the selection is empty, or any selected request is no longer
  /// released-and-unreplenished.
  Future<Result<Replenishment>> createDraft({
    required String fundId,
    required List<String> requestIds,
    required String createdByUid,
  });

  Future<Result<void>> submit({required Replenishment replenishment, required String actorUid, required String notes});

  /// One-tap selection→submit for the incharge popup: creates the draft from
  /// [requestIds], then submits it for approval. Rolls the draft back (so the
  /// fund is not left locked in `replenishing`) if the submit step fails.
  Future<Result<void>> createAndSubmit({
    required String fundId,
    required List<String> requestIds,
    required String actorUid,
    required String notes,
  });

  /// Atomic: tag the bundled requests `replenished`, ADD their total back to the
  /// fund balance, and set fund status from the new balance (active/low).
  Future<Result<void>> approve({required Replenishment replenishment, required String actorUid});
```

- [ ] **Step 4: Rewrite `createDraft` in the data impl (company-scoped + selection)**

In `lib/features/replenishment/data/firestore_replenishment_repository.dart`, replace the entire `createDraft` method (currently lines 50-116) with:

```dart
  @override
  Future<Result<Replenishment>> createDraft({
    required String fundId,
    required List<String> requestIds,
    required String createdByUid,
  }) async {
    try {
      if (requestIds.isEmpty) {
        return const Err(ValidationFailure('Select at least one request to replenish.'));
      }
      // Read the fund first to learn its companyId. A single-doc get is allowed
      // by the sameCompany read rule.
      final fundSnap0 = await _fundRef(fundId).get();
      if (!fundSnap0.exists) {
        return const Err(ValidationFailure('Fund not found.'));
      }
      final companyId = (fundSnap0.data()!['companyId'] ?? '') as String;
      // COMPANY-SCOPED query (the permission-denied fix): a fundId+status-only
      // query is rejected on device because the sameCompany read rule cannot be
      // proven. The released-unreplenished filter is applied client-side
      // (equality-on-null is unsupported by the fake test double, and a
      // `replenished` request leaves the `released` set anyway).
      final snap = await _requests
          .where('companyId', isEqualTo: companyId)
          .where('fundId', isEqualTo: fundId)
          .where('status', isEqualTo: RequestStatus.released.name)
          .get();
      final releasable = <String, Map<String, dynamic>>{
        for (final d in snap.docs)
          if (d.data()['replenishmentId'] == null) d.id: d.data(),
      };
      final selected = requestIds.where(releasable.containsKey).toList();
      if (selected.isEmpty) {
        return const Err(ValidationFailure('No released requests to replenish.'));
      }
      if (selected.length != requestIds.length) {
        return const Err(ValidationFailure(
            'Some selected requests are no longer available to replenish.'));
      }
      if (selected.length > 450) {
        return const Err(ValidationFailure(
            'Too many requests to replenish at once (max 450). Replenish in smaller batches.'));
      }
      var total = Money.zero;
      for (final id in selected) {
        total += Money.fromCentavos((releasable[id]!['amountCentavos'] ?? 0) as int);
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
          'requestIds': selected,
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
        requestIds: selected,
        total: total,
        reportNotes: '',
        createdByUid: createdByUid,
      ));
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('createDraft failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not start a replenishment.'));
    }
  }
```

- [ ] **Step 5: Add `createAndSubmit` directly after `createDraft` in the data impl**

```dart
  @override
  Future<Result<void>> createAndSubmit({
    required String fundId,
    required List<String> requestIds,
    required String actorUid,
    required String notes,
  }) async {
    final draftRes =
        await createDraft(fundId: fundId, requestIds: requestIds, createdByUid: actorUid);
    final draft = draftRes.valueOrNull;
    if (draft == null) return Err(draftRes.failureOrNull!);
    final submitRes = await submit(replenishment: draft, actorUid: actorUid, notes: notes);
    if (submitRes.failureOrNull != null) {
      // Roll the draft back so the fund isn't left locked in `replenishing`.
      await discardDraft(replenishment: draft);
      return submitRes;
    }
    return const Ok(null);
  }
```

- [ ] **Step 6: Switch `approve` to incremental add-back + balance-derived status**

In the same file, inside `approve`'s transaction, replace the fund-update block (currently lines 164-167):

```dart
        // Writes (all reads done above):
        tx.update(_fundRef(replenishment.fundId), {
          'availableBalanceCentavos': fund.originalBudget.centavos,
          'status': FundStatus.active.name,
        });
```

with:

```dart
        // Writes (all reads done above). ADD BACK exactly the bundled total
        // (the inverse of the releases that deducted it); derive status from the
        // new balance so a partial replenishment can still read as `low`.
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
```

(`_restoredStatus(Fund)` already exists at the bottom of the file: `fund.isLow ? low : active`. Passing a `Fund` whose `availableBalance` is the new balance makes `isLow` evaluate against it.)

- [ ] **Step 7: Update the dashboard fake repo to the new interface**

In `test/features/dashboard/presentation/dashboard_providers_test.dart`, replace the fake's `createDraft` override (currently lines 168-171) and add `createAndSubmit`:

```dart
  @override
  Future<Result<Replenishment>> createDraft(
          {required String fundId,
          required List<String> requestIds,
          required String createdByUid}) async =>
      const Err(ValidationFailure('unused'));
  @override
  Future<Result<void>> createAndSubmit(
          {required String fundId,
          required List<String> requestIds,
          required String actorUid,
          required String notes}) async =>
      const Ok(null);
```

- [ ] **Step 8: Run the updated tests — expect green**

Run: `flutter test test/features/replenishment/data/replenishment_repository_test.dart test/features/dashboard/presentation/dashboard_providers_test.dart`
Expected: PASS (all tests).

- [ ] **Step 9: Commit**

```bash
git add lib/features/replenishment/domain/replenishment_repository.dart \
        lib/features/replenishment/data/firestore_replenishment_repository.dart \
        test/features/replenishment/data/replenishment_repository_test.dart \
        test/features/dashboard/presentation/dashboard_providers_test.dart
git commit -m "feat(replenishment): company-scoped selectable createDraft + incremental approve

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: New repo tests — subset selection + createAndSubmit

**Files:**
- Test: `test/features/replenishment/data/replenishment_repository_test.dart`

- [ ] **Step 1: Add the new tests (before the final closing `}` of `main`)**

```dart
  test('createDraft sums only the selected requests', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', requestIds: const ['r1'], createdByUid: 'inc');
    expect(res.isOk, isTrue);
    expect(res.valueOrNull!.requestIds, const ['r1']);
    expect(res.valueOrNull!.total.centavos, 400000); // not 800000
  });

  test('createDraft rejects an empty selection without touching the fund', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', requestIds: const [], createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['status'], 'low'); // unchanged
  });

  test('createDraft rejects a selection that includes a non-releasable id', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(
        fundId: 'f1', requestIds: const ['r1', 'ghost'], createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
    expect((res.failureOrNull as ValidationFailure).message,
        'Some selected requests are no longer available to replenish.');
  });

  test('createAndSubmit creates a submitted report and locks the fund', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createAndSubmit(
        fundId: 'f1', requestIds: const ['r1', 'r2'], actorUid: 'inc', notes: 'June');
    expect(res.isOk, isTrue);
    final reps = await db
        .collection('replenishments')
        .where('fundId', isEqualTo: 'f1')
        .get();
    expect(reps.docs.length, 1);
    expect(reps.docs.single.data()['status'], 'submitted');
    expect(reps.docs.single.data()['reportNotes'], 'June');
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['status'], 'replenishing');
  });

  test('createAndSubmit propagates a createDraft failure and creates nothing', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createAndSubmit(
        fundId: 'f1', requestIds: const [], actorUid: 'inc', notes: '');
    expect(res.failureOrNull, isA<ValidationFailure>());
    final reps = await db.collection('replenishments').get();
    expect(reps.docs, isEmpty);
  });
```

(Note: the submit-failure rollback branch in `createAndSubmit` cannot be triggered with `fake_cloud_firestore` — a fresh draft's `submit` update always succeeds there. It is exercised only on a real backend; the branch is left as defensive cleanup.)

- [ ] **Step 2: Run the new tests — expect green**

Run: `flutter test test/features/replenishment/data/replenishment_repository_test.dart`
Expected: PASS (all tests, old and new).

- [ ] **Step 3: Commit**

```bash
git add test/features/replenishment/data/replenishment_repository_test.dart
git commit -m "test(replenishment): subset selection + createAndSubmit coverage

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `ReplenishSelectDialog` widget + test

**Files:**
- Create: `lib/features/replenishment/presentation/replenish_select_dialog.dart`
- Test: `test/features/replenishment/presentation/replenish_select_dialog_test.dart`

- [ ] **Step 1: Write the widget test first**

Create `test/features/replenishment/presentation/replenish_select_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/replenishment/presentation/replenish_select_dialog.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

Fund _fund() => Fund(
      id: 'f1',
      companyId: 'c1',
      name: 'Revolving Fund',
      originalBudget: Money.fromCentavos(10000000),
      availableBalance: Money.fromCentavos(200000),
      lowBalanceThresholdPct: 3,
      status: FundStatus.low,
    );

FundRequest _req(String id, int centavos) => FundRequest(
      id: id,
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'inc',
      beneficiaryName: 'Bene $id',
      amount: Money.fromCentavos(centavos),
      purpose: 'Purpose $id',
      proofImageUrl: 'http://img',
      status: RequestStatus.released,
    );

Widget _host(List<FundRequest> releasable) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ReplenishSelectDialog(fund: _fund(), releasable: releasable),
        ),
      ),
    );

void main() {
  testWidgets('submit is disabled until a request is selected', (tester) async {
    await tester.pumpWidget(_host([_req('r1', 400000), _req('r2', 300000)]));
    final submit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit for approval'));
    expect(submit.onPressed, isNull); // disabled

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();

    final submit2 = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit for approval'));
    expect(submit2.onPressed, isNotNull); // enabled
  });

  testWidgets('selected total reflects the checked requests', (tester) async {
    await tester.pumpWidget(_host([_req('r1', 400000), _req('r2', 300000)]));
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.textContaining('₱4,000.00'), findsWidgets);
  });

  testWidgets('shows an empty state when nothing is releasable', (tester) async {
    await tester.pumpWidget(_host(const []));
    expect(find.text('No released requests to replenish.'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/replenishment/presentation/replenish_select_dialog_test.dart`
Expected: FAIL — `replenish_select_dialog.dart` / `ReplenishSelectDialog` does not exist.

- [ ] **Step 3: Implement the dialog**

Create `lib/features/replenishment/presentation/replenish_select_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_tokens.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../companies/domain/fund.dart';
import '../../requests/domain/fund_request.dart';
import 'replenishment_providers.dart';

/// Popup for the incharge to pick which released requests to replenish, then
/// submit them for approval in one tap. Pops `true` on a successful submit so
/// the caller can show the success overlay; stays open (with a snackbar) on
/// failure. [releasable] is the already-filtered released-unreplenished list.
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
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Money get _total {
    var sum = Money.zero;
    for (final r in widget.releasable) {
      if (_selected.contains(r.id)) sum += r.amount;
    }
    return sum;
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || _selected.isEmpty) return;
    setState(() => _busy = true);
    final res = await ref.read(replenishmentRepositoryProvider).createAndSubmit(
          fundId: widget.fund.id,
          requestIds: _selected.toList(),
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
                        for (final r in widget.releasable)
                          CheckboxListTile(
                            dense: true,
                            value: _selected.contains(r.id),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                      if (v ?? false) {
                                        _selected.add(r.id);
                                      } else {
                                        _selected.remove(r.id);
                                      }
                                    }),
                            title: Text(r.beneficiaryName),
                            subtitle: Text(
                              r.purpose,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            secondary: Text(
                              r.amount.format(),
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
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
          onPressed: (_busy || _selected.isEmpty) ? null : _submit,
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
}
```

- [ ] **Step 4: Run the widget test — expect green**

Run: `flutter test test/features/replenishment/presentation/replenish_select_dialog_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/replenishment/presentation/replenish_select_dialog.dart \
        test/features/replenishment/presentation/replenish_select_dialog_test.dart
git commit -m "feat(replenishment): ReplenishSelectDialog multi-select popup

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Wire the dialog into the incharge home; remove the old review path

**Files:**
- Modify: `lib/features/requests/presentation/incharge_home_body.dart`
- Delete: `lib/features/replenishment/presentation/replenish_review_screen.dart`

- [ ] **Step 1: Replace the import and the `_startReplenish` helper**

In `lib/features/requests/presentation/incharge_home_body.dart`, change the import on line 19 from:

```dart
import '../../replenishment/presentation/replenish_review_screen.dart';
```

to:

```dart
import '../../replenishment/presentation/replenish_select_dialog.dart';
```

Then delete the entire `_startReplenish` function (currently lines 34-48, the doc comment + function).

- [ ] **Step 2: Rewrite `_replenish` to open the dialog**

Replace the `_replenish` method (currently lines 130-137) with:

```dart
  Future<void> _replenish(String uid) async {
    setState(() => _busy = true);
    try {
      final all = ref
              .read(_fundRequestsProvider(
                  (widget.fund.companyId, widget.fund.id)))
              .valueOrNull ??
          const <FundRequest>[];
      final releasable = all
          .where((r) =>
              r.status == RequestStatus.released && r.replenishmentId == null)
          .toList();
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => ReplenishSelectDialog(
          fund: widget.fund,
          releasable: releasable,
        ),
      );
      if (ok == true && mounted) {
        await SuccessOverlay.show(context, 'Submitted for approval');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
```

- [ ] **Step 3: Add the `SuccessOverlay` import**

In the same file's import block, add (keeping imports sorted near the other `core/widgets` imports):

```dart
import '../../../core/widgets/success_overlay.dart';
```

- [ ] **Step 4: Delete the dead review screen**

```bash
git rm lib/features/replenishment/presentation/replenish_review_screen.dart
```

- [ ] **Step 5: Analyze to confirm no dangling references**

Run: `flutter analyze lib/features/requests/presentation/incharge_home_body.dart lib/features/replenishment`
Expected: No errors. (`uid` param of `_replenish` is still used via `user!.uid` at the call site on the Replenish button; no unused-import or undefined-name errors.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/requests/presentation/incharge_home_body.dart
git commit -m "feat(replenishment): open ReplenishSelectDialog from incharge home; drop review screen

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the entire analyzer**

Run: `flutter analyze`
Expected: No NEW errors/warnings beyond the 6 pre-existing `unnecessary_underscores` lints in `app_router.dart` noted in project memory. If anything in the touched files is flagged, fix it.

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: All tests pass (the prior green count plus the new dialog + repo tests; no failures).

- [ ] **Step 3: Revert any desktop plugin-registrant churn before finishing**

Running `flutter` regenerates tracked `linux/`, `windows/`, and `macos/Flutter/GeneratedPluginRegistrant.swift` files. If they show as modified and you didn't intend to change them:

Run: `git checkout -- linux/flutter/generated_plugins.cmake windows/flutter/generated_plugins.cmake macos/Flutter/GeneratedPluginRegistrant.swift`
Expected: working tree clean of that churn.

- [ ] **Step 4: Final confirmation**

Run: `git status` and `git log --oneline -5`
Expected: clean tree (aside from intentional, unrelated pre-existing changes), four new feature commits present.

---

## Self-review notes

- **Spec coverage:** §Changes 1 (company-scoped + selection) → Task 1 Steps 3-4; §2 (`createAndSubmit`) → Task 1 Step 5 + Task 2; §3 (incremental approve) → Task 1 Step 6; §4 (dialog) → Task 3; §5 (wiring + delete review screen) → Task 4; §6 (tests) → Tasks 1-3. No rule/index/state-machine changes — none planned. ✅
- **No new Firestore rules/indexes** — confirmed in the spec's "no rule changes" property; nothing in this plan edits `firestore.rules` or `firestore.indexes.json`.
- **Type/name consistency:** `createDraft({fundId, requestIds, createdByUid})`, `createAndSubmit({fundId, requestIds, actorUid, notes})`, and `_restoredStatus(Fund)` are used identically in the interface, the data impl, the dashboard fake, and every test call. `ReplenishSelectDialog({fund, releasable})` matches between the widget, its test, and the call site in `_replenish`.
- **Known untestable branch:** `createAndSubmit`'s submit-failure rollback is documented as not reproducible under `fake_cloud_firestore`; left as defensive code (Task 2 Step 1 note).
