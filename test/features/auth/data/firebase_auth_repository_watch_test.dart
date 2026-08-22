import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rev_app/features/auth/data/firebase_auth_repository.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  test('watchCurrentUser re-emits when the user document changes', () async {
    final auth = _MockAuth();
    final firestore = FakeFirebaseFirestore();
    final user = _MockUser();
    when(() => user.uid).thenReturn('u1');
    // Signed in for the whole test; auth state itself never changes.
    when(() => auth.authStateChanges())
        .thenAnswer((_) => Stream<User?>.value(user));

    await firestore.collection('users').doc('u1').set({
      'role': 'incharge',
      'companyId': 'c1',
      'displayName': 'Pat',
      'email': 'pat@acme.com',
      'accentId': 'forest',
      'themeMode': 'system',
    });

    final repo = FirebaseAuthRepository(auth, firestore);
    final emitted = <String?>[];
    final sub =
        repo.watchCurrentUser().listen((u) => emitted.add(u?.accentId));

    // Let the initial emission land.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emitted, ['forest']);

    // Simulate the profile screen saving a new accent. The source-of-truth
    // stream must reflect this WITHOUT an auth-state change, or the UI (accent
    // selection + theme seed) never updates and the control looks dead.
    await firestore
        .collection('users')
        .doc('u1')
        .set({'accentId': 'ocean'}, SetOptions(merge: true));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await sub.cancel();

    expect(
      emitted,
      ['forest', 'ocean'],
      reason: 'watchCurrentUser must listen to the doc live (snapshots), '
          'not a one-shot get()',
    );
  });

  test('AppUser parses accentId so a live re-read reflects the saved value',
      () {
    final parsed = AppUser.fromMap('u1', const {
      'role': 'incharge',
      'companyId': 'c1',
      'displayName': 'Pat',
      'email': 'pat@acme.com',
      'accentId': 'ocean',
      'themeMode': 'dark',
    });
    expect(parsed.accentId, 'ocean');
  });
}
