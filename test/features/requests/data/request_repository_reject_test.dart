import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';

/// `rejectBeforeRelease` — the incharge cancels a request that was created (and
/// possibly acted on) by mistake but whose cash was NEVER handed out.
///
/// The load-bearing assertion in every test here is the fund balance: in the
/// release-first lifecycle the fund is debited ONLY inside the release
/// transaction, so a rejection at `created` must leave
/// `availableBalanceCentavos` byte-identical. If a future refactor routes this
/// method through anything that opens the fund ref, these tests fail.
void main() {
  late FakeFirebaseFirestore fake;
  late FirestoreRequestRepository repo;

  const kReason = 'Created by mistake — duplicate of R-1042.';
  const kStartingBalance = 500000; // ₱5,000.00

  Future<void> seedFund({
    int balance = kStartingBalance,
    String status = 'active',
  }) =>
      fake.collection('funds').doc('f1').set(<String, dynamic>{
        'companyId': 'c1',
        'name': 'PC',
        'originalBudgetCentavos': 10000000,
        'availableBalanceCentavos': balance,
        'lowBalanceThresholdPct': 3,
        'status': status,
      });

  Future<FundRequest> seedRequest(String status,
      {int amountCentavos = 200000}) async {
    final map = <String, dynamic>{
      'companyId': 'c1',
      'fundId': 'f1',
      'createdByUid': 'u1',
      'beneficiaryName': 'Ben',
      'amountCentavos': amountCentavos,
      'purpose': 'x',
      'proofImageUrl': 'https://img/x.jpg',
      'status': status,
    };
    await fake.collection('requests').doc('r1').set(map);
    return FundRequest.fromMap('r1', map);
  }

  Future<Map<String, dynamic>> fundDoc() async =>
      (await fake.collection('funds').doc('f1').get()).data()!;

  Future<Map<String, dynamic>> requestDoc() async =>
      (await fake.collection('requests').doc('r1').get()).data()!;

  Future<List<Map<String, dynamic>>> history() async => (await fake
          .collection('requests')
          .doc('r1')
          .collection('history')
          .get())
      .docs
      .map((d) => d.data())
      .toList();

  setUp(() {
    fake = FakeFirebaseFirestore();
    repo = FirestoreRequestRepository(fake);
  });

  group('rejectBeforeRelease', () {
    test('moves created → rejected and stamps the rejection audit trio',
        () async {
      await seedFund();
      final req = await seedRequest('created');

      final result = await repo.rejectBeforeRelease(
        request: req,
        actorUid: 'incharge1',
        reason: kReason,
      );

      expect(result.isOk, isTrue);
      final after = await requestDoc();
      expect(after['status'], 'rejected');
      expect(after['rejectedReason'], kReason);
      expect(after['rejectedByUid'], 'incharge1');
      expect(after['rejectedAt'], isNotNull);
    });

    test('does NOT deduct the fund — balance and status are untouched',
        () async {
      await seedFund();
      final req = await seedRequest('created');

      await repo.rejectBeforeRelease(
        request: req,
        actorUid: 'incharge1',
        reason: kReason,
      );

      final fund = await fundDoc();
      expect(fund['availableBalanceCentavos'], kStartingBalance);
      expect(fund['status'], 'active');
    });

    test('never credits the fund either — a rejection is not a refund',
        () async {
      // Guards the opposite mistake: "un-deducting" an amount that was never
      // deducted would silently inflate the fund.
      await seedFund(balance: 1);
      final req = await seedRequest('created', amountCentavos: 999999);

      await repo.rejectBeforeRelease(
        request: req,
        actorUid: 'incharge1',
        reason: kReason,
      );

      expect((await fundDoc())['availableBalanceCentavos'], 1);
    });

    test('trims the reason before persisting it', () async {
      await seedFund();
      final req = await seedRequest('created');

      await repo.rejectBeforeRelease(
        request: req,
        actorUid: 'incharge1',
        reason: '   $kReason   ',
      );

      expect((await requestDoc())['rejectedReason'], kReason);
    });

    test('appends a rejected history event carrying the reason as the note',
        () async {
      await seedFund();
      final req = await seedRequest('created');

      await repo.rejectBeforeRelease(
        request: req,
        actorUid: 'incharge1',
        reason: kReason,
      );

      final events = await history();
      expect(events, hasLength(1));
      expect(events.single['event'], 'rejected');
      expect(events.single['from'], 'created');
      expect(events.single['to'], 'rejected');
      expect(events.single['actorUid'], 'incharge1');
      expect(events.single['note'], kReason);
    });

    test('refuses an empty reason without writing anything', () async {
      await seedFund();
      final req = await seedRequest('created');

      final result = await repo.rejectBeforeRelease(
        request: req,
        actorUid: 'incharge1',
        reason: '   ',
      );

      expect(result, isA<Err<void>>());
      expect((result as Err<void>).failure, isA<ValidationFailure>());
      expect((await requestDoc())['status'], 'created');
      expect(await history(), isEmpty);
    });

    test('refuses a too-short reason without writing anything', () async {
      await seedFund();
      final req = await seedRequest('created');

      final result = await repo.rejectBeforeRelease(
        request: req,
        actorUid: 'incharge1',
        reason: 'oops',
      );

      expect(result, isA<Err<void>>());
      expect((await requestDoc())['status'], 'created');
      expect(await history(), isEmpty);
    });

    test('refuses an already-released request — that cash IS out of the fund',
        () async {
      await seedFund();
      final req = await seedRequest('released');

      final result = await repo.rejectBeforeRelease(
        request: req,
        actorUid: 'incharge1',
        reason: kReason,
      );

      expect(result, isA<Err<void>>());
      expect((result as Err<void>).failure, isA<ValidationFailure>());
      expect((await requestDoc())['status'], 'released');
      expect((await fundDoc())['availableBalanceCentavos'], kStartingBalance);
    });

    test('refuses when the server doc was released by a concurrent tap',
        () async {
      // The caller holds a stale `created` snapshot while another device has
      // already released (and debited). The in-transaction re-read must win.
      await seedFund();
      final stale = await seedRequest('created');
      await fake
          .collection('requests')
          .doc('r1')
          .update(<String, dynamic>{'status': 'released'});

      final result = await repo.rejectBeforeRelease(
        request: stale,
        actorUid: 'incharge1',
        reason: kReason,
      );

      expect(result, isA<Err<void>>());
      expect((await requestDoc())['status'], 'released');
    });
  });
}
