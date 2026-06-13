import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

void main() {
  group('allowed transitions (release-first lifecycle)', () {
    test('created → released | rejected', () {
      expect(RequestStatus.created.canTransitionTo(RequestStatus.released), isTrue);
      expect(RequestStatus.created.canTransitionTo(RequestStatus.rejected), isTrue);
    });

    test('released → acknowledged | disputed | replenished | conflict', () {
      expect(RequestStatus.released.canTransitionTo(RequestStatus.acknowledged), isTrue);
      expect(RequestStatus.released.canTransitionTo(RequestStatus.disputed), isTrue);
      expect(RequestStatus.released.canTransitionTo(RequestStatus.replenished), isTrue);
      expect(RequestStatus.released.canTransitionTo(RequestStatus.conflict), isTrue);
    });

    test('acknowledged → disputed | replenished', () {
      expect(RequestStatus.acknowledged.canTransitionTo(RequestStatus.disputed), isTrue);
      expect(RequestStatus.acknowledged.canTransitionTo(RequestStatus.replenished), isTrue);
    });

    test('acknowledged allowed set is EXACTLY {disputed, replenished} — '
        'never released (regression for rules/Dart RELEASE-source drift)', () {
      for (final to in RequestStatus.values) {
        final expected = to == RequestStatus.disputed ||
            to == RequestStatus.replenished;
        expect(RequestStatus.acknowledged.canTransitionTo(to), expected,
            reason: 'acknowledged → ${to.name} should be $expected');
      }
      // Pin the negative explicitly: post-release acknowledged cash is already
      // deducted; it must never re-enter the release path.
      expect(RequestStatus.acknowledged.canTransitionTo(RequestStatus.released),
          isFalse);
    });

    test('conflict → released | rejected (incharge resolves overdraft)', () {
      expect(RequestStatus.conflict.canTransitionTo(RequestStatus.released), isTrue);
      expect(RequestStatus.conflict.canTransitionTo(RequestStatus.rejected), isTrue);
    });

    test('disputed → replenished', () {
      expect(RequestStatus.disputed.canTransitionTo(RequestStatus.replenished), isTrue);
    });
  });

  group('terminal / disallowed transitions', () {
    test('rejected and replenished are terminal', () {
      for (final to in RequestStatus.values) {
        expect(RequestStatus.rejected.canTransitionTo(to), isFalse,
            reason: 'rejected → ${to.name} must be illegal');
        expect(RequestStatus.replenished.canTransitionTo(to), isFalse,
            reason: 'replenished → ${to.name} must be illegal');
      }
    });

    test('created cannot skip straight to post-hoc states', () {
      expect(RequestStatus.created.canTransitionTo(RequestStatus.acknowledged), isFalse);
      expect(RequestStatus.created.canTransitionTo(RequestStatus.disputed), isFalse);
      expect(RequestStatus.created.canTransitionTo(RequestStatus.replenished), isFalse);
      expect(RequestStatus.created.canTransitionTo(RequestStatus.conflict), isFalse);
    });

    test('released cannot go back to created or rejected', () {
      expect(RequestStatus.released.canTransitionTo(RequestStatus.created), isFalse);
      expect(RequestStatus.released.canTransitionTo(RequestStatus.rejected), isFalse);
    });

    test('acknowledged cannot revert to released or conflict', () {
      expect(RequestStatus.acknowledged.canTransitionTo(RequestStatus.released), isFalse);
      expect(RequestStatus.acknowledged.canTransitionTo(RequestStatus.conflict), isFalse);
      expect(RequestStatus.acknowledged.canTransitionTo(RequestStatus.rejected), isFalse);
    });

    test('conflict cannot jump to acknowledged/disputed/replenished', () {
      expect(RequestStatus.conflict.canTransitionTo(RequestStatus.acknowledged), isFalse);
      expect(RequestStatus.conflict.canTransitionTo(RequestStatus.disputed), isFalse);
      expect(RequestStatus.conflict.canTransitionTo(RequestStatus.replenished), isFalse);
    });

    test('disputed cannot acknowledge or re-release', () {
      expect(RequestStatus.disputed.canTransitionTo(RequestStatus.acknowledged), isFalse);
      expect(RequestStatus.disputed.canTransitionTo(RequestStatus.released), isFalse);
    });
  });

  group('ensureTransition', () {
    test('throws StateError on an illegal move', () {
      expect(() => RequestStatus.created.ensureTransition(RequestStatus.acknowledged),
          throwsStateError);
    });

    test('does not throw on a legal move', () {
      expect(() => RequestStatus.created.ensureTransition(RequestStatus.released),
          returnsNormally);
    });
  });

  group('fromName legacy mapping', () {
    test('legacy pre-release statuses → created (re-enter the release flow)', () {
      // All three legacy statuses named cash that was NEVER debited in the old
      // model, so they must re-enter the release path, not be shown as released.
      expect(RequestStatus.fromName('draft'), RequestStatus.created);
      expect(RequestStatus.fromName('pendingAck'), RequestStatus.created);
      expect(RequestStatus.fromName('readyForRelease'), RequestStatus.created);
    });

    test('readyForRelease must NOT map to released (would strand un-deducted '
        'cash as if handed out)', () {
      expect(RequestStatus.fromName('readyForRelease'),
          isNot(RequestStatus.released));
      expect(RequestStatus.fromName('readyForRelease'), RequestStatus.created);
    });

    test('acknowledged maps to itself (new post-release meaning)', () {
      expect(RequestStatus.fromName('acknowledged'), RequestStatus.acknowledged);
    });

    test('current names round-trip', () {
      for (final s in RequestStatus.values) {
        expect(RequestStatus.fromName(s.name), s);
      }
    });

    test('unknown / null → created', () {
      expect(RequestStatus.fromName('garbage'), RequestStatus.created);
      expect(RequestStatus.fromName(null), RequestStatus.created);
    });
  });
}
