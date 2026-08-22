import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';

void main() {
  test('allowed transitions', () {
    // Auto-approve: a draft now lands directly in approved (incharge submit
    // credits the fund). Legacy submitted edges are retained for in-flight docs.
    expect(ReplenishmentStatus.draft.canTransitionTo(ReplenishmentStatus.approved), isTrue);
    expect(ReplenishmentStatus.draft.canTransitionTo(ReplenishmentStatus.rejected), isTrue);
    expect(ReplenishmentStatus.submitted.canTransitionTo(ReplenishmentStatus.approved), isTrue);
    expect(ReplenishmentStatus.submitted.canTransitionTo(ReplenishmentStatus.rejected), isTrue);
  });
  test('illegal transitions', () {
    // draft can no longer go to submitted (the submit path is auto-approve).
    expect(ReplenishmentStatus.draft.canTransitionTo(ReplenishmentStatus.submitted), isFalse);
    expect(ReplenishmentStatus.approved.canTransitionTo(ReplenishmentStatus.submitted), isFalse);
    expect(ReplenishmentStatus.approved.canTransitionTo(ReplenishmentStatus.rejected), isFalse);
    expect(ReplenishmentStatus.rejected.canTransitionTo(ReplenishmentStatus.submitted), isFalse);
  });
  test('fromName defaults to draft', () {
    expect(ReplenishmentStatus.fromName('submitted'), ReplenishmentStatus.submitted);
    expect(ReplenishmentStatus.fromName('junk'), ReplenishmentStatus.draft);
  });
}
