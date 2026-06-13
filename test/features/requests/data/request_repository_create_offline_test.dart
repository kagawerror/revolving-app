import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

// These mocks model the ONE behaviour fake_cloud_firestore can't: with offline
// persistence, a write Future does not complete until the SERVER acks it. Each
// write here returns a Future that never completes — exactly like a queued
// offline write. A correct offline `create` must NOT await those Futures.
class _MockFirestore extends Mock implements FirebaseFirestore {}

// ignore: subtype_of_sealed_class — mocktail double of a sealed Firestore type.
class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class — mocktail double of a sealed Firestore type.
class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  test(
      'offline create returns the doc id WITHOUT awaiting writes that never '
      'complete (regression: spinner looped forever)', () async {
    final db = _MockFirestore();
    final requests = _MockCollection();
    final newDoc = _MockDoc();
    final historyCol = _MockCollection();

    final never = Completer<void>().future; // never completes == offline write

    when(() => db.collection('requests')).thenReturn(requests);
    // Offline create mints a client-side id via doc() (no arg).
    when(() => requests.doc()).thenReturn(newDoc);
    when(() => requests.doc(any())).thenReturn(newDoc);
    when(() => newDoc.id).thenReturn('r-offline-1');
    when(() => newDoc.set(any())).thenAnswer((_) => never);
    when(() => newDoc.collection('history')).thenReturn(historyCol);
    when(() => historyCol.add(any()))
        .thenAnswer((_) => Completer<DocumentReference<Map<String, dynamic>>>()
            .future); // also never completes

    final repo = FirestoreRequestRepository(db);

    final offlineRequest = FundRequest(
      id: '',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Ben',
      amount: Money.fromPesos(100),
      purpose: 'x',
      proofImageUrl: '', // deferred — offline create carries pendingImageRef
      status: RequestStatus.created,
      pendingImageRef: 'cli-123',
    );

    // If create() awaits the (never-completing) write, this hangs and the test
    // times out — which is precisely the looping spinner on-device.
    final res = await repo.create(offlineRequest).timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('create() hung on an offline write Future'),
        );

    expect(res.valueOrNull, 'r-offline-1');
    verify(() => newDoc.set(any())).called(1);
  });
}
