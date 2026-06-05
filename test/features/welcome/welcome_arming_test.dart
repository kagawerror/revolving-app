import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/welcome/domain/welcome_arming.dart';

/// Minimal AppUser factory — only [uid] matters to the arming decision.
AppUser _user(String uid) => AppUser(
      uid: uid,
      companyId: 'c1',
      role: UserRole.incharge,
      displayName: 'User $uid',
      email: '$uid@example.com',
    );

void main() {
  group('shouldRearmWelcome', () {
    test('re-arms when a signed-out user logs in (null -> user)', () {
      // The reported bug: after sign-out you reach /login signed-out, then a
      // successful login must bring the welcome back before the app.
      expect(shouldRearmWelcome(null, _user('a')), isTrue);
    });

    test('re-arms on cold start with a restored session (loading reads as null)',
        () {
      // currentUserProvider starts as AsyncLoading -> valueOrNull is null, then
      // resolves to the persisted user. Treated the same as a fresh login.
      expect(shouldRearmWelcome(null, _user('a')), isTrue);
    });

    test('re-arms when the signed-in identity switches (userA -> userB)', () {
      expect(shouldRearmWelcome(_user('a'), _user('b')), isTrue);
    });

    test('does NOT re-arm on a profile re-emit for the same user', () {
      // The profile stream re-emits on any doc change (theme, accent, name).
      // Re-arming here would slam the welcome over the app mid-use.
      expect(shouldRearmWelcome(_user('a'), _user('a')), isFalse);
    });

    test('does NOT re-arm on sign-out (user -> null)', () {
      // Sign-out arming is owned by signOutProvider; this edge must be inert
      // here so the two paths do not double-fire or fight.
      expect(shouldRearmWelcome(_user('a'), null), isFalse);
    });

    test('does NOT re-arm while signed out (null -> null)', () {
      expect(shouldRearmWelcome(null, null), isFalse);
    });
  });
}
