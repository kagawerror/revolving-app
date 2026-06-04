import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
