import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

void main() {
  test('allowed transitions follow the lifecycle', () {
    expect(RequestStatus.draft.canTransitionTo(RequestStatus.pendingAck), isTrue);
    expect(RequestStatus.pendingAck.canTransitionTo(RequestStatus.acknowledged), isTrue);
    expect(RequestStatus.pendingAck.canTransitionTo(RequestStatus.rejected), isTrue);
    expect(RequestStatus.acknowledged.canTransitionTo(RequestStatus.readyForRelease), isTrue);
    // One-tap release: acknowledged may move straight to released (the two-step
    // acknowledged -> readyForRelease -> released path still works above).
    expect(RequestStatus.acknowledged.canTransitionTo(RequestStatus.released), isTrue);
    expect(RequestStatus.readyForRelease.canTransitionTo(RequestStatus.released), isTrue);
    expect(RequestStatus.released.canTransitionTo(RequestStatus.replenished), isTrue);
  });

  test('illegal transitions are rejected', () {
    expect(RequestStatus.draft.canTransitionTo(RequestStatus.released), isFalse);
    // Unlocking acknowledged -> released must NOT open earlier statuses.
    expect(RequestStatus.pendingAck.canTransitionTo(RequestStatus.released), isFalse);
    expect(RequestStatus.released.canTransitionTo(RequestStatus.draft), isFalse);
    expect(RequestStatus.rejected.canTransitionTo(RequestStatus.acknowledged), isFalse);
  });

  test('ensureTransition throws on illegal move', () {
    expect(() => RequestStatus.draft.ensureTransition(RequestStatus.released),
        throwsStateError);
  });
}
