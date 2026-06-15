import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/features/companies/data/firestore_company_repository.dart';

void main() {
  test('update renames an existing company', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('companies').doc('c1').set({'name': 'Old Co'});
    final repo = FirestoreCompanyRepository(db);

    final res = await repo.update('c1', 'New Co');

    expect(res.isOk, isTrue);
    final data = (await db.collection('companies').doc('c1').get()).data()!;
    expect(data['name'], 'New Co');
  });

  test('getById returns Ok for an existing company', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('companies').doc('c1').set({'name': 'Acme'});
    final repo = FirestoreCompanyRepository(db);

    final res = await repo.getById('c1');

    expect(res.isOk, isTrue);
    expect(res.valueOrNull!.id, 'c1');
    expect(res.valueOrNull!.name, 'Acme');
  });

  test('getById returns NotFoundFailure for a missing company', () async {
    final db = FakeFirebaseFirestore();
    final repo = FirestoreCompanyRepository(db);

    final res = await repo.getById('nope');

    expect(res.failureOrNull, isA<NotFoundFailure>());
  });
}
