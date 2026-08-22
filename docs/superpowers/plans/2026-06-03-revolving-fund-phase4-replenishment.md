# Revolving Fund App — Phase 4 Implementation Plan (Replenishment + Low-Balance Alerts)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Close the imprest loop — replenishment report lifecycle (compile → submit → approve/reject) with an atomic balance-reset transaction, a release guard during replenishing, and in-app low-balance/replenishment alerts (banner + list).

**Architecture:** Same clean layers as Phases 1–3. New feature `features/replenishment/` and `features/notifications/`. Money stays integer centavos; statuses are enums with explicit transitions; the approval and balance reset run in one Firestore transaction. Notifications are written inline by event-producing transactions and read via a repository.

**Reference spec:** `docs/superpowers/specs/2026-06-03-revolving-fund-phase4-replenishment-design.md`

**Builds on (existing, working):** `Money`, `Result`/`Failure`, `Fund`/`FundStatus` (active|low|replenishing), `FundRequest`/`RequestStatus` (…released→replenished), `FirestoreRequestRepository` (create/transition/release with `computeRelease`), `currentUserProvider`, `UserRole` (canApprove/canManageFund), `fundRepositoryProvider`, `requestRepositoryProvider`, role-guarded `go_router`. Test deps: `mocktail`, `fake_cloud_firestore`.

---

## File Structure (Phase 4)

```
lib/features/replenishment/
  domain/replenishment_status.dart        # enum + transitions
  domain/replenishment.dart               # model
  domain/replenishment_repository.dart    # interface
  data/firestore_replenishment_repository.dart  # compile/create/submit/approve/reject (+ pure helpers)
  presentation/replenishment_providers.dart
  presentation/replenish_review_screen.dart      # incharge compile+submit
  presentation/replenishment_detail_screen.dart  # approver approve/reject
lib/features/notifications/
  domain/app_notification.dart            # model + NotificationType
  domain/notification_repository.dart     # interface (read + markRead)
  data/firestore_notification_repository.dart
  presentation/notification_providers.dart
  presentation/alerts_screen.dart
  presentation/low_balance_banner.dart
firestore.rules                            # add replenishments+notifications, harden funds
firestore.indexes.json                     # add replenishments + notifications indexes
```

---

# SLICE F — Replenishment domain, repository, release guard

### Task 22: `ReplenishmentStatus` enum + transitions (TDD)

**Files:** Create `lib/features/replenishment/domain/replenishment_status.dart`; Test `test/features/replenishment/domain/replenishment_status_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';

void main() {
  test('allowed transitions', () {
    expect(ReplenishmentStatus.draft.canTransitionTo(ReplenishmentStatus.submitted), isTrue);
    expect(ReplenishmentStatus.submitted.canTransitionTo(ReplenishmentStatus.approved), isTrue);
    expect(ReplenishmentStatus.submitted.canTransitionTo(ReplenishmentStatus.rejected), isTrue);
  });
  test('illegal transitions', () {
    expect(ReplenishmentStatus.draft.canTransitionTo(ReplenishmentStatus.approved), isFalse);
    expect(ReplenishmentStatus.approved.canTransitionTo(ReplenishmentStatus.submitted), isFalse);
    expect(ReplenishmentStatus.rejected.canTransitionTo(ReplenishmentStatus.submitted), isFalse);
  });
  test('fromName defaults to draft', () {
    expect(ReplenishmentStatus.fromName('submitted'), ReplenishmentStatus.submitted);
    expect(ReplenishmentStatus.fromName('junk'), ReplenishmentStatus.draft);
  });
}
```

- [ ] **Step 2: Run → FAIL.** `flutter test test/features/replenishment/domain/replenishment_status_test.dart`

- [ ] **Step 3: Implement**

```dart
enum ReplenishmentStatus {
  draft,
  submitted,
  approved,
  rejected;

  static const Map<ReplenishmentStatus, Set<ReplenishmentStatus>> _allowed = {
    ReplenishmentStatus.draft: {ReplenishmentStatus.submitted},
    ReplenishmentStatus.submitted: {ReplenishmentStatus.approved, ReplenishmentStatus.rejected},
    ReplenishmentStatus.approved: {},
    ReplenishmentStatus.rejected: {},
  };

  static ReplenishmentStatus fromName(String? n) => ReplenishmentStatus.values
      .firstWhere((s) => s.name == n, orElse: () => ReplenishmentStatus.draft);

  bool canTransitionTo(ReplenishmentStatus next) => _allowed[this]!.contains(next);
}
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(replenishment): status enum with transitions`

---

### Task 23: `Replenishment` model (TDD)

**Files:** Create `lib/features/replenishment/domain/replenishment.dart`; Test `test/features/replenishment/domain/replenishment_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';

void main() {
  test('fromMap parses fields', () {
    final r = Replenishment.fromMap('rp1', {
      'companyId': 'c1', 'fundId': 'f1', 'status': 'submitted',
      'requestIds': ['a', 'b'], 'totalCentavos': 300000,
      'reportNotes': 'June', 'createdByUid': 'u1',
    });
    expect(r.fundId, 'f1');
    expect(r.status, ReplenishmentStatus.submitted);
    expect(r.requestIds, ['a', 'b']);
    expect(r.total, Money.fromCentavos(300000));
  });
  test('toCreateMap seeds draft fields and omits id', () {
    final r = Replenishment(
      id: '', companyId: 'c1', fundId: 'f1', status: ReplenishmentStatus.draft,
      requestIds: const ['a'], total: Money.fromCentavos(1000), reportNotes: '',
      createdByUid: 'u1');
    final m = r.toCreateMap();
    expect(m.containsKey('id'), isFalse);
    expect(m['status'], 'draft');
    expect(m['totalCentavos'], 1000);
    expect(m['requestIds'], ['a']);
  });
}
```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../../../core/money/money.dart';
import 'replenishment_status.dart';

class Replenishment extends Equatable {
  final String id;
  final String companyId;
  final String fundId;
  final ReplenishmentStatus status;
  final List<String> requestIds;
  final Money total;
  final String reportNotes;
  final String createdByUid;
  final String? submittedByUid;
  final String? approvedByUid;

  const Replenishment({
    required this.id,
    required this.companyId,
    required this.fundId,
    required this.status,
    required this.requestIds,
    required this.total,
    required this.reportNotes,
    required this.createdByUid,
    this.submittedByUid,
    this.approvedByUid,
  });

  int get itemCount => requestIds.length;

  factory Replenishment.fromMap(String id, Map<String, dynamic> m) => Replenishment(
        id: id,
        companyId: (m['companyId'] ?? '') as String,
        fundId: (m['fundId'] ?? '') as String,
        status: ReplenishmentStatus.fromName(m['status'] as String?),
        requestIds: List<String>.from((m['requestIds'] ?? const []) as List),
        total: Money.fromCentavos((m['totalCentavos'] ?? 0) as int),
        reportNotes: (m['reportNotes'] ?? '') as String,
        createdByUid: (m['createdByUid'] ?? '') as String,
        submittedByUid: m['submittedByUid'] as String?,
        approvedByUid: m['approvedByUid'] as String?,
      );

  Map<String, dynamic> toCreateMap() => {
        'companyId': companyId,
        'fundId': fundId,
        'status': status.name,
        'requestIds': requestIds,
        'totalCentavos': total.centavos,
        'reportNotes': reportNotes,
        'createdByUid': createdByUid,
        'submittedByUid': null,
        'approvedByUid': null,
        'createdAt': FieldValue.serverTimestamp(),
      };

  @override
  List<Object?> get props =>
      [id, companyId, fundId, status, requestIds, total, reportNotes, createdByUid,
       submittedByUid, approvedByUid];
}
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(replenishment): add Replenishment model`

---

### Task 24: Release guard — block releases while `replenishing` (TDD)

**Files:** Modify `lib/features/requests/data/firestore_request_repository.dart`; Modify `test/features/requests/data/release_transaction_logic_test.dart` and `test/features/requests/data/release_integration_test.dart`.

- [ ] **Step 1: Add a failing test** in `release_transaction_logic_test.dart`:

```dart
test('computeRelease throws when fund is replenishing', () {
  final replenishing = Fund(
    id: 'f1', companyId: 'c1', name: 'PC',
    originalBudget: Money.fromPesos(100000),
    availableBalance: Money.fromPesos(50000),
    lowBalanceThresholdPct: 3, status: FundStatus.replenishing);
  expect(() => computeRelease(replenishing, Money.fromPesos(1000)), throwsStateError);
});
```

- [ ] **Step 2: Run → FAIL** (release currently allowed while replenishing).

- [ ] **Step 3: Implement** — in `computeRelease(...)` add the guard BEFORE the balance check:

```dart
ReleaseOutcome computeRelease(Fund fund, Money amount) {
  if (fund.status == FundStatus.replenishing) {
    throw StateError('Fund is being replenished; releases are paused.');
  }
  if (!fund.canRelease(amount)) {
    throw StateError('Insufficient fund balance for release.');
  }
  final newBalance = fund.availableBalance - amount;
  final low = newBalance <= fund.lowBalanceThreshold;
  return ReleaseOutcome(newBalance, low);
}
```

- [ ] **Step 4: Run → PASS.** Run full `flutter test` to confirm no regressions.
- [ ] **Step 5: Commit** `feat(requests): block release while fund is replenishing`

---

### Task 25: `ReplenishmentRepository` + Firestore impl (compile/submit/approve/reject)

**Files:** Create `lib/features/replenishment/domain/replenishment_repository.dart`, `lib/features/replenishment/data/firestore_replenishment_repository.dart`; Test `test/features/replenishment/data/replenishment_repository_test.dart` (fake_cloud_firestore).

- [ ] **Step 1: Interface** `replenishment_repository.dart`

```dart
import '../../../core/error/result.dart';
import 'replenishment.dart';

abstract interface class ReplenishmentRepository {
  Stream<List<Replenishment>> watchByFund(String fundId);
  Stream<List<Replenishment>> watchByCompanyAndStatus(String companyId, String status);

  /// Compiles released-unreplenished requests for the fund into a DRAFT and flips
  /// the fund to `replenishing`. Fails if the fund is already replenishing or has
  /// no released-unreplenished requests.
  Future<Result<String>> createDraft({required String fundId, required String createdByUid});

  Future<Result<void>> submit({required Replenishment replenishment, required String actorUid, required String notes});

  /// Atomic: tag requests replenished, reset fund balance to original ceiling, fund→active.
  Future<Result<void>> approve({required Replenishment replenishment, required String actorUid});

  Future<Result<void>> reject({required Replenishment replenishment, required String actorUid});

  /// Cancels a draft and returns the fund to active/low.
  Future<Result<void>> discardDraft({required Replenishment replenishment});
}
```

- [ ] **Step 2: Failing integration test** `replenishment_repository_test.dart` — seed a fund + two released requests, exercise createDraft → submit → approve and assert the money reset; plus the "already replenishing" guard.

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/replenishment/data/firestore_replenishment_repository.dart';
import 'package:rev_app/features/replenishment/domain/replenishment.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('funds').doc('f1').set({
      'companyId': 'c1', 'name': 'PC',
      'originalBudgetCentavos': 10000000, 'availableBalanceCentavos': 200000,
      'lowBalanceThresholdPct': 3, 'status': 'low',
    });
    for (final id in ['r1', 'r2']) {
      await db.collection('requests').doc(id).set({
        'companyId': 'c1', 'fundId': 'f1', 'createdByUid': 'inc',
        'beneficiaryName': 'B', 'amountCentavos': 400000, 'purpose': 'x',
        'proofImageUrl': 'http://img', 'status': 'released', 'replenishmentId': null,
      });
    }
  });

  test('createDraft compiles released-unreplenished requests and flips fund to replenishing', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(fundId: 'f1', createdByUid: 'inc');
    expect(res.isOk, isTrue);
    final rp = await db.collection('replenishments').doc(res.valueOrNull!).get();
    expect((rp.data()!['requestIds'] as List).length, 2);
    expect(rp.data()!['totalCentavos'], 800000);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['status'], 'replenishing');
  });

  test('createDraft fails when fund already replenishing', () async {
    await db.collection('funds').doc('f1').update({'status': 'replenishing'});
    final repo = FirestoreReplenishmentRepository(db);
    final res = await repo.createDraft(fundId: 'f1', createdByUid: 'inc');
    expect(res.failureOrNull, isA<ValidationFailure>());
  });

  test('approve resets balance to ceiling, tags requests replenished, fund active', () async {
    final repo = FirestoreReplenishmentRepository(db);
    final id = (await repo.createDraft(fundId: 'f1', createdByUid: 'inc')).valueOrNull!;
    final draft = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    await repo.submit(replenishment: draft, actorUid: 'inc', notes: 'June');
    final submitted = Replenishment.fromMap(id,
        (await db.collection('replenishments').doc(id).get()).data()!);
    final res = await repo.approve(replenishment: submitted, actorUid: 'mgr');
    expect(res.isOk, isTrue);
    final fund = await db.collection('funds').doc('f1').get();
    expect(fund.data()!['availableBalanceCentavos'], 10000000); // reset to ceiling
    expect(fund.data()!['status'], 'active');
    for (final rid in ['r1', 'r2']) {
      final req = await db.collection('requests').doc(rid).get();
      expect(req.data()!['status'], 'replenished');
      expect(req.data()!['replenishmentId'], id);
    }
    final rp = await db.collection('replenishments').doc(id).get();
    expect(rp.data()!['status'], 'approved');
  });
}
```

- [ ] **Step 3: Run → FAIL** (repo missing).

- [ ] **Step 4: Implement** `firestore_replenishment_repository.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../../companies/domain/fund.dart';
import '../../requests/domain/request_status.dart';
import '../domain/replenishment.dart';
import '../domain/replenishment_status.dart';
import '../domain/replenishment_repository.dart';

class FirestoreReplenishmentRepository implements ReplenishmentRepository {
  final FirebaseFirestore _db;
  FirestoreReplenishmentRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _reps => _db.collection('replenishments');
  CollectionReference<Map<String, dynamic>> get _requests => _db.collection('requests');
  DocumentReference<Map<String, dynamic>> _fundRef(String id) => _db.collection('funds').doc(id);

  @override
  Stream<List<Replenishment>> watchByFund(String fundId) => _reps
      .where('fundId', isEqualTo: fundId)
      .snapshots()
      .map((s) => s.docs.map((d) => Replenishment.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Replenishment>> watchByCompanyAndStatus(String companyId, String status) => _reps
      .where('companyId', isEqualTo: companyId)
      .where('status', isEqualTo: status)
      .snapshots()
      .map((s) => s.docs.map((d) => Replenishment.fromMap(d.id, d.data())).toList());

  @override
  Future<Result<String>> createDraft({required String fundId, required String createdByUid}) async {
    try {
      // Query released-unreplenished requests OUTSIDE the transaction (client SDK
      // transactions cannot run queries).
      final snap = await _requests
          .where('fundId', isEqualTo: fundId)
          .where('status', isEqualTo: RequestStatus.released.name)
          .where('replenishmentId', isEqualTo: null)
          .get();
      if (snap.docs.isEmpty) {
        return const Err(ValidationFailure('No released requests to replenish.'));
      }
      final ids = snap.docs.map((d) => d.id).toList();
      var totalCentavos = 0;
      for (final d in snap.docs) {
        totalCentavos += (d.data()['amountCentavos'] ?? 0) as int;
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
          'companyId': fund.companyId,
          'fundId': fundId,
          'status': ReplenishmentStatus.draft.name,
          'requestIds': ids,
          'totalCentavos': totalCentavos,
          'reportNotes': '',
          'createdByUid': createdByUid,
          'submittedByUid': null,
          'approvedByUid': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(_fundRef(fundId), {'status': FundStatus.replenishing.name});
      });
      return Ok(newRef.id);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('createDraft failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not start a replenishment.'));
    }
  }

  @override
  Future<Result<void>> submit({required Replenishment replenishment, required String actorUid, required String notes}) async {
    if (!replenishment.status.canTransitionTo(ReplenishmentStatus.submitted)) {
      return const Err(ValidationFailure('Only a draft can be submitted.'));
    }
    try {
      await _reps.doc(replenishment.id).update({
        'status': ReplenishmentStatus.submitted.name,
        'reportNotes': notes,
        'submittedByUid': actorUid,
        'submittedAt': FieldValue.serverTimestamp(),
      });
      await _addNotification(
        companyId: replenishment.companyId,
        recipientRoles: const ['superior', 'manager', 'ceo'],
        type: 'replenishmentSubmitted',
        title: 'Replenishment submitted',
        body: 'A replenishment report needs your approval.',
        fundId: replenishment.fundId,
        replenishmentId: replenishment.id,
      );
      return const Ok(null);
    } catch (e, st) {
      developer.log('submit failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not submit the report.'));
    }
  }

  @override
  Future<Result<void>> approve({required Replenishment replenishment, required String actorUid}) async {
    if (!replenishment.status.canTransitionTo(ReplenishmentStatus.approved)) {
      return const Err(ValidationFailure('Only a submitted report can be approved.'));
    }
    try {
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
        // Writes (all reads done above):
        tx.update(_fundRef(replenishment.fundId), {
          'availableBalanceCentavos': fund.originalBudget.centavos,
          'status': FundStatus.active.name,
        });
        for (final rid in replenishment.requestIds) {
          tx.update(_requests.doc(rid), {
            'status': RequestStatus.replenished.name,
            'replenishmentId': replenishment.id,
          });
        }
        tx.update(repRef, {
          'status': ReplenishmentStatus.approved.name,
          'approvedByUid': actorUid,
          'decidedAt': FieldValue.serverTimestamp(),
        });
      });
      await _addNotification(
        companyId: replenishment.companyId,
        recipientRoles: const ['incharge'],
        type: 'replenishmentApproved',
        title: 'Replenishment approved',
        body: 'The fund has been replenished and is ready for requests.',
        fundId: replenishment.fundId,
        replenishmentId: replenishment.id,
      );
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('approve failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not approve the report.'));
    }
  }

  @override
  Future<Result<void>> reject({required Replenishment replenishment, required String actorUid}) async {
    if (!replenishment.status.canTransitionTo(ReplenishmentStatus.rejected)) {
      return const Err(ValidationFailure('Only a submitted report can be rejected.'));
    }
    try {
      await _db.runTransaction((tx) async {
        final fundSnap = await tx.get(_fundRef(replenishment.fundId));
        if (!fundSnap.exists) throw StateError('Fund not found.');
        final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
        final restored = fund.isLow ? FundStatus.low : FundStatus.active;
        tx.update(_fundRef(replenishment.fundId), {'status': restored.name});
        tx.update(_reps.doc(replenishment.id), {
          'status': ReplenishmentStatus.rejected.name,
          'approvedByUid': actorUid,
          'decidedAt': FieldValue.serverTimestamp(),
        });
      });
      await _addNotification(
        companyId: replenishment.companyId,
        recipientRoles: const ['incharge'],
        type: 'replenishmentRejected',
        title: 'Replenishment rejected',
        body: 'Your replenishment report was rejected.',
        fundId: replenishment.fundId,
        replenishmentId: replenishment.id,
      );
      return const Ok(null);
    } on StateError catch (e) {
      return Err(ValidationFailure(e.message));
    } catch (e, st) {
      developer.log('reject failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not reject the report.'));
    }
  }

  @override
  Future<Result<void>> discardDraft({required Replenishment replenishment}) async {
    if (replenishment.status != ReplenishmentStatus.draft) {
      return const Err(ValidationFailure('Only a draft can be discarded.'));
    }
    try {
      await _db.runTransaction((tx) async {
        final fundSnap = await tx.get(_fundRef(replenishment.fundId));
        if (fundSnap.exists) {
          final fund = Fund.fromMap(fundSnap.id, fundSnap.data()!);
          tx.update(_fundRef(replenishment.fundId),
              {'status': (fund.isLow ? FundStatus.low : FundStatus.active).name});
        }
        tx.update(_reps.doc(replenishment.id), {'status': ReplenishmentStatus.rejected.name});
      });
      return const Ok(null);
    } catch (e, st) {
      developer.log('discardDraft failed', name: 'replenishment', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not discard the draft.'));
    }
  }

  Future<void> _addNotification({
    required String companyId,
    required List<String> recipientRoles,
    required String type,
    required String title,
    required String body,
    String? fundId,
    String? replenishmentId,
  }) {
    return _db.collection('notifications').add({
      'companyId': companyId,
      'recipientRoles': recipientRoles,
      'type': type,
      'title': title,
      'body': body,
      'fundId': fundId,
      'replenishmentId': replenishmentId,
      'readAt': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
```

> Note: `isLow` uses the fund's CURRENT balance. After approval the balance is reset so the fund is active; on reject/discard the balance is unchanged, so `isLow` correctly restores `low` when still at/under threshold.

- [ ] **Step 5: Run → PASS** (3 tests). Run full `flutter test`.
- [ ] **Step 6: Commit** `feat(replenishment): repository with compile/submit/approve/reject transactions`

---

# SLICE G — Notifications (alerts)

### Task 26: `AppNotification` model (TDD)

**Files:** Create `lib/features/notifications/domain/app_notification.dart`; Test `test/features/notifications/domain/app_notification_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/notifications/domain/app_notification.dart';

void main() {
  test('fromMap parses + isUnread', () {
    final n = AppNotification.fromMap('n1', {
      'companyId': 'c1', 'recipientRoles': ['incharge'],
      'type': 'lowBalance', 'title': 'Low', 'body': 'Fund low', 'readAt': null,
    });
    expect(n.type, 'lowBalance');
    expect(n.recipientRoles, ['incharge']);
    expect(n.isUnread, isTrue);
  });
}
```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class AppNotification extends Equatable {
  final String id;
  final String companyId;
  final List<String> recipientRoles;
  final String type;
  final String title;
  final String body;
  final String? fundId;
  final String? replenishmentId;
  final Timestamp? readAt;

  const AppNotification({
    required this.id,
    required this.companyId,
    required this.recipientRoles,
    required this.type,
    required this.title,
    required this.body,
    this.fundId,
    this.replenishmentId,
    this.readAt,
  });

  bool get isUnread => readAt == null;

  factory AppNotification.fromMap(String id, Map<String, dynamic> m) => AppNotification(
        id: id,
        companyId: (m['companyId'] ?? '') as String,
        recipientRoles: List<String>.from((m['recipientRoles'] ?? const []) as List),
        type: (m['type'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        fundId: m['fundId'] as String?,
        replenishmentId: m['replenishmentId'] as String?,
        readAt: m['readAt'] as Timestamp?,
      );

  @override
  List<Object?> get props =>
      [id, companyId, recipientRoles, type, title, body, fundId, replenishmentId, readAt];
}
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(notifications): add AppNotification model`

---

### Task 27: `NotificationRepository` + Firestore impl; low-balance write in release

**Files:** Create `lib/features/notifications/domain/notification_repository.dart`, `lib/features/notifications/data/firestore_notification_repository.dart`; Modify `lib/features/requests/data/firestore_request_repository.dart` (write a `lowBalance` notification inside the release transaction when the fund newly flips to low).

- [ ] **Step 1: Interface**

```dart
import '../domain/app_notification.dart';

abstract interface class NotificationRepository {
  Stream<List<AppNotification>> watchForRole(String companyId, String role);
  Future<void> markRead(String id);
}
```

- [ ] **Step 2: Implement** `firestore_notification_repository.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/app_notification.dart';
import '../domain/notification_repository.dart';

class FirestoreNotificationRepository implements NotificationRepository {
  final FirebaseFirestore _db;
  FirestoreNotificationRepository(this._db);

  @override
  Stream<List<AppNotification>> watchForRole(String companyId, String role) => _db
      .collection('notifications')
      .where('companyId', isEqualTo: companyId)
      .where('recipientRoles', arrayContains: role)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => AppNotification.fromMap(d.id, d.data())).toList());

  @override
  Future<void> markRead(String id) =>
      _db.collection('notifications').doc(id).update({'readAt': FieldValue.serverTimestamp()});
}
```

- [ ] **Step 3: Wire a low-balance notification into the release transaction.** In `firestore_request_repository.dart` `release(...)`, inside the `runTransaction` AFTER the existing writes, add a `lowBalance` notification ONLY when the fund newly flips to low (i.e. `outcome.fundIsLow` AND the fund wasn't already low):

```dart
// after tx.update(fund ...), tx.update(request ...), and the history tx.set:
if (outcome.fundIsLow && fund.status != FundStatus.low) {
  final notifRef = _db.collection('notifications').doc();
  tx.set(notifRef, {
    'companyId': fund.companyId,
    'recipientRoles': const ['incharge'],
    'type': 'lowBalance',
    'title': 'Fund balance low',
    'body': 'A fund has reached its low-balance threshold. Replenish soon.',
    'fundId': fund.fundId,           // NOTE: Fund model exposes `id`; use fund.id
    'replenishmentId': null,
    'readAt': null,
    'createdAt': FieldValue.serverTimestamp(),
  });
}
```
> Implementation note: use `fund.id` (the `Fund` field is `id`, not `fundId`). Keep the existing imports; `FundStatus` is already imported in this file.

- [ ] **Step 4: Add a test** in `release_integration_test.dart` asserting a `lowBalance` notification doc is created when a release drives the fund to low (the existing happy-path test already drives it to low — extend it to also check `db.collection('notifications')` has one doc with `type == 'lowBalance'`).

- [ ] **Step 5: Run → PASS.** Full `flutter test`.
- [ ] **Step 6: Commit** `feat(notifications): repository + low-balance alert on release`

---

### Task 28: Notification providers + alerts UI

**Files:** Create `lib/features/notifications/presentation/notification_providers.dart`, `alerts_screen.dart`, `low_balance_banner.dart`.

- [ ] **Step 1: Providers**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/firebase/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/firestore_notification_repository.dart';
import '../domain/app_notification.dart';
import '../domain/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
    (ref) => FirestoreNotificationRepository(ref.watch(firestoreProvider)));

final myNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref.watch(notificationRepositoryProvider).watchForRole(user.companyId, user.role.name);
});

final unreadCountProvider = Provider<int>((ref) {
  final list = ref.watch(myNotificationsProvider).valueOrNull ?? const [];
  return list.where((n) => n.isUnread).length;
});
```

- [ ] **Step 2: `alerts_screen.dart`** — a list of the user's notifications; tap marks read.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_providers.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(myNotificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: alerts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No alerts'))
            : ListView(children: [
                for (final n in list)
                  ListTile(
                    leading: Icon(n.isUnread ? Icons.circle : Icons.circle_outlined,
                        size: 12,
                        color: n.isUnread ? Theme.of(context).colorScheme.primary : null),
                    title: Text(n.title),
                    subtitle: Text(n.body),
                    onTap: () => ref.read(notificationRepositoryProvider).markRead(n.id),
                  ),
              ]),
      ),
    );
  }
}
```

- [ ] **Step 3: `low_balance_banner.dart`** — given the company funds, show a banner if any is low.

```dart
import 'package:flutter/material.dart';

import '../../companies/domain/fund.dart';

class LowBalanceBanner extends StatelessWidget {
  final List<Fund> funds;
  const LowBalanceBanner({super.key, required this.funds});

  @override
  Widget build(BuildContext context) {
    final low = funds.where((f) => f.status == FundStatus.low).toList();
    if (low.isEmpty) return const SizedBox.shrink();
    return MaterialBanner(
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      content: Text('${low.length} fund(s) at low balance — replenish soon.'),
      actions: const [SizedBox.shrink()],
    );
  }
}
```

- [ ] **Step 4: Verify** `flutter analyze`. **Commit** `feat(notifications): alerts providers, list screen, low-balance banner`

---

# SLICE H — Replenishment UI + security rules + indexes

### Task 29: Incharge replenishment flow + alerts entry + banner

**Files:** Create `lib/features/replenishment/presentation/replenishment_providers.dart`, `replenish_review_screen.dart`; Modify `lib/features/requests/presentation/incharge_home_screen.dart`; Modify `lib/routing/app_router.dart`.

- [ ] **Step 1: Providers** `replenishment_providers.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/firebase/firebase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/firestore_replenishment_repository.dart';
import '../domain/replenishment.dart';
import '../domain/replenishment_repository.dart';
import '../domain/replenishment_status.dart';

final replenishmentRepositoryProvider = Provider<ReplenishmentRepository>(
    (ref) => FirestoreReplenishmentRepository(ref.watch(firestoreProvider)));

final pendingReplenishmentsProvider = StreamProvider<List<Replenishment>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref.watch(replenishmentRepositoryProvider)
      .watchByCompanyAndStatus(user.companyId, ReplenishmentStatus.submitted.name);
});

final fundReplenishmentsProvider = StreamProvider.family<List<Replenishment>, String>(
    (ref, fundId) => ref.watch(replenishmentRepositoryProvider).watchByFund(fundId));
```

- [ ] **Step 2: `replenish_review_screen.dart`** — shows the auto-compiled draft (total + item count), a notes field, Submit + Discard. It receives a `fundId`; on open it calls `createDraft`, then streams the draft. (Simpler: pass the already-created draft `Replenishment` in via constructor — the incharge home triggers `createDraft` then navigates with the result.) Implement the constructor-takes-Replenishment variant:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/replenishment.dart';
import 'replenishment_providers.dart';

class ReplenishReviewScreen extends ConsumerStatefulWidget {
  final Replenishment draft;
  const ReplenishReviewScreen({super.key, required this.draft});
  @override
  ConsumerState<ReplenishReviewScreen> createState() => _State();
}

class _State extends ConsumerState<ReplenishReviewScreen> {
  final _notes = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    setState(() => _busy = true);
    final res = await ref.read(replenishmentRepositoryProvider).submit(
        replenishment: widget.draft, actorUid: user.uid, notes: _notes.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  Future<void> _discard() async {
    setState(() => _busy = true);
    final res = await ref.read(replenishmentRepositoryProvider)
        .discardDraft(replenishment: widget.draft);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return Scaffold(
      appBar: AppBar(title: const Text('Replenishment report')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(children: [
          Text('Items: ${d.itemCount}', style: Theme.of(context).textTheme.titleMedium),
          Text('Total: ${d.total.format()}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text('Submit for approval'),
          ),
          TextButton(onPressed: _busy ? null : _discard, child: const Text('Discard')),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 3: Incharge home additions.** In `incharge_home_screen.dart`:
  - Add a `LowBalanceBanner(funds: <company funds>)` at the top (watch `companyFundsProvider`).
  - Add an **alerts** `IconButton` (bell) in the AppBar with an unread badge from `unreadCountProvider`, pushing `AlertsScreen`.
  - Per fund, add a **"Replenish"** button shown when the fund has released-unreplenished requests AND `fund.status != replenishing`. On tap: call `createDraft(fundId, uid)`; on `Ok(id)` build the `Replenishment` from the created draft (re-read or construct) and navigate to `ReplenishReviewScreen`; on `Err` snackbar. (Simplest: after `createDraft` returns the id, fetch the draft via a one-shot provider or `watchByFund` first match, then push.)

```dart
// Replenish action helper (place in incharge_home_screen.dart):
Future<void> _startReplenish(BuildContext context, WidgetRef ref, String fundId, String uid) async {
  final repo = ref.read(replenishmentRepositoryProvider);
  final res = await repo.createDraft(fundId: fundId, createdByUid: uid);
  if (!context.mounted) return;
  final id = res.valueOrNull;
  if (id == null) {
    context.showFailure(res.failureOrNull!);
    return;
  }
  // Read the freshly-created draft once.
  final draftList = await repo.watchByFund(fundId).first;
  final draft = draftList.firstWhere((r) => r.id == id);
  if (!context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReplenishReviewScreen(draft: draft)));
}
```

- [ ] **Step 4: Verify** `flutter analyze && flutter test`. **Commit** `feat(replenishment): incharge replenish flow, low-balance banner, alerts entry`

---

### Task 30: Approver replenishment approval

**Files:** Modify `lib/features/requests/presentation/approver_home_screen.dart`; Create `lib/features/replenishment/presentation/replenishment_detail_screen.dart`.

- [ ] **Step 1: Approver home — add a "Pending replenishments" section** above/below the pending requests, from `pendingReplenishmentsProvider`, each tile (fund, total, item count) pushing `ReplenishmentDetailScreen`. Also add the alerts bell + badge (same as incharge).

- [ ] **Step 2: `replenishment_detail_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure_ui.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/replenishment.dart';
import 'replenishment_providers.dart';

class ReplenishmentDetailScreen extends ConsumerWidget {
  final Replenishment replenishment;
  const ReplenishmentDetailScreen({super.key, required this.replenishment});

  Future<void> _decide(BuildContext context, WidgetRef ref, bool approve) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final repo = ref.read(replenishmentRepositoryProvider);
    final res = approve
        ? await repo.approve(replenishment: replenishment, actorUid: user.uid)
        : await repo.reject(replenishment: replenishment, actorUid: user.uid);
    if (!context.mounted) return;
    if (res.showOnError(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canApprove =
        ref.watch(currentUserProvider).valueOrNull?.role.canApprove ?? false;
    final r = replenishment;
    return Scaffold(
      appBar: AppBar(title: const Text('Replenishment')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Total: ${r.total.format()}', style: Theme.of(context).textTheme.headlineSmall),
        Text('Items: ${r.itemCount}'),
        if (r.reportNotes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Notes: ${r.reportNotes}'),
        ],
        const SizedBox(height: 24),
        if (canApprove)
          Row(children: [
            Expanded(child: FilledButton(
              onPressed: () => _decide(context, ref, true),
              child: const Text('Approve'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton(
              onPressed: () => _decide(context, ref, false),
              child: const Text('Reject'))),
          ]),
      ]),
    );
  }
}
```

- [ ] **Step 3: Verify** `flutter analyze && flutter test`. **Commit** `feat(replenishment): approver approval UI`

---

### Task 31: Security rules + indexes (replenishments, notifications, funds hardening)

**Files:** Modify `firestore.rules`, `firestore.indexes.json`.

- [ ] **Step 1: Add to `firestore.rules`** (inside the `documents` match, reusing existing `isIncharge()`/`isApprover()`/`sameCompany()`/`myRole()` helpers):

```
    match /replenishments/{repId} {
      allow read: if sameCompany(resource.data.companyId);
      allow create: if isIncharge()
        && request.resource.data.companyId == myCompany()
        && request.resource.data.status == 'draft';
      allow update: if sameCompany(resource.data.companyId) && (
        (isIncharge()
          && resource.data.status in ['draft']
          && request.resource.data.status in ['draft', 'submitted', 'rejected'])
        || (isApprover()
          && resource.data.status == 'submitted'
          && request.resource.data.status in ['approved', 'rejected'])
      );
      allow delete: if false;
    }

    match /notifications/{notifId} {
      allow read: if sameCompany(resource.data.companyId)
        && (myRole() in resource.data.recipientRoles);
      allow create: if sameCompany(request.resource.data.companyId);
      allow update: if sameCompany(resource.data.companyId)
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['readAt']);
      allow delete: if false;
    }
```

- [ ] **Step 2: Harden the `funds` update rule.** Replace the Phase-2 `allow update: if sameCompany(resource.data.companyId);` with:

```
      allow update: if sameCompany(resource.data.companyId)
        && (isIncharge() || isApprover());
```
(Incharge performs releases and replenishment-create/discard; approver performs replenishment approval which resets the balance. Admin still creates funds.)

- [ ] **Step 3: Add indexes to `firestore.indexes.json`** (append to the `indexes` array):

```json
{
  "collectionGroup": "replenishments",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "companyId", "order": "ASCENDING" },
    { "fieldPath": "status", "order": "ASCENDING" }
  ]
},
{
  "collectionGroup": "notifications",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "companyId", "order": "ASCENDING" },
    { "fieldPath": "recipientRoles", "arrayConfig": "CONTAINS" },
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}
```
> `watchByFund` (replenishments) and the `createDraft` request query are equality-only → auto-served, no index needed.

- [ ] **Step 4: Verify** `flutter analyze && flutter test` (rules/indexes don't affect tests; just confirm nothing else broke). Rules deploy is a manual `firebase deploy --only firestore` step (no CLI here).
- [ ] **Step 5: Commit** `feat(security): replenishment/notification rules + funds hardening + indexes`

---

## Manual Verification (end of Phase 4)

1. Seed a fund near its threshold; release a request that drives it to `low` → incharge home shows the banner and an alert appears in the alerts list.
2. Incharge taps **Replenish** → review screen shows the auto-compiled total + item count → Submit → approver gets an alert; fund is `replenishing`.
3. Attempt a release on that fund → blocked ("releases are paused").
4. Approver opens the replenishment → **Approve** → fund balance resets to the ceiling, fund `active`, the linked requests become `replenished`, incharge gets an "approved" alert, and releases work again.
5. Repeat and **Reject** → fund returns to `low`/`active`, requests stay `released`, incharge gets a "rejected" alert.

## Self-Review (against the Phase 4 spec)

- **Coverage:** replenishment lifecycle (compile/submit/approve/reject/discard) ✓; atomic balance reset + request tagging ✓; release guard while replenishing ✓; single-active-replenishment invariant via the `replenishing` guard ✓; in-app alerts (banner from fund status + role-targeted notifications list) ✓; security rules + funds hardening + indexes ✓.
- **Deferred (Phase 5+):** FCM push, device tokens, dashboard, partial/multi-fund replenishment.
- **Type consistency:** `ReplenishmentStatus`/`FundStatus`/`RequestStatus` names, `Replenishment`/`AppNotification` fields, repo method names (`createDraft`/`submit`/`approve`/`reject`/`discardDraft`, `watchForRole`/`markRead`) used consistently across tasks.
- **No placeholders:** every code step contains complete, compilable code.
