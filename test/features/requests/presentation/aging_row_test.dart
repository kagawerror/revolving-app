import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';
import 'package:rev_app/features/requests/presentation/aging_row.dart';
import 'package:rev_app/features/requests/presentation/request_status_visual.dart';

void main() {
  group('RequestStatusBadge.visualFor', () {
    test(
        'delegates to requestStatusVisual for the three outstanding statuses '
        '(no parallel mapping drift)', () {
      for (final status in const [
        RequestStatus.released,
        RequestStatus.acknowledged,
        RequestStatus.disputed,
      ]) {
        final badge = RequestStatusBadge.visualFor(status);
        final canonical = requestStatusVisual(status);
        expect(badge.label, canonical.label, reason: status.name);
        expect(badge.tone, canonical.tone, reason: status.name);
        expect(badge.icon, canonical.icon, reason: status.name);
      }
    });

    test('asserts in debug for non-outstanding statuses', () {
      // Aging rows are contracted to only ever receive released / acknowledged
      // / disputed; anything else trips the defensive `assert(false, ...)`.
      expect(
        () => RequestStatusBadge.visualFor(RequestStatus.created),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => RequestStatusBadge.visualFor(RequestStatus.rejected),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
