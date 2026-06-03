import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/features/notifications/domain/app_notification.dart';

void main() {
  test('fromMap parses + isUnread', () {
    final n = AppNotification.fromMap('n1', {
      'companyId': 'c1', 'recipientRoles': ['incharge'],
      'type': 'lowBalance', 'title': 'Low', 'body': 'Fund low', 'readAt': null,
    });
    expect(n.type, 'lowBalance');
    expect(n.recipientRoles, ['incharge']);
    expect(n.isUnread, isTrue);
  });
}
