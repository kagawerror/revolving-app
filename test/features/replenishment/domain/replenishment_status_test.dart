import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/replenishment/domain/replenishment_status.dart';

void main() {
  test('allowed transitions', () {
    expect(ReplenishmentStatus.draft.canTransitionTo(ReplenishmentStatus.submitted), isTrue);
    expect(ReplenishmentStatus.submitted.canTransitionTo(ReplenishmentStatus.approved), isTrue);
    expect(ReplenishmentStatus.submitted.canTransitionTo(ReplenishmentStatus.rejected), isTrue);
  });
  test('illegal transitions', () {
    expect(ReplenishmentStatus.draft.canTransitionTo(ReplenishmentStatus.approved), isFalse);
    expect(ReplenishmentStatus.approved.canTransitionTo(ReplenishmentStatus.submitted), isFalse);
    expect(ReplenishmentStatus.rejected.canTransitionTo(ReplenishmentStatus.submitted), isFalse);
  });
  test('fromName defaults to draft', () {
    expect(ReplenishmentStatus.fromName('submitted'), ReplenishmentStatus.submitted);
    expect(ReplenishmentStatus.fromName('junk'), ReplenishmentStatus.draft);
  });
}
