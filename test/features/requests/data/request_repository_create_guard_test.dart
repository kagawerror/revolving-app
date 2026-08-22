import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/requests/data/firestore_request_repository.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

class _MockDb extends Mock implements FirebaseFirestore {}

void main() {
  test('create rejects a created request without proof or pendingImageRef', () async {
    final repo = FirestoreRequestRepository(_MockDb());
    final res = await repo.create(FundRequest(
      id: '', companyId: 'c1', fundId: 'f1', createdByUid: 'u1',
      beneficiaryName: 'Ben', amount: Money.fromPesos(100), purpose: 'x',
      proofImageUrl: '', status: RequestStatus.created));
    expect(res.failureOrNull, isA<ValidationFailure>());
  });
}
