import 'package:cloud_firestore/cloud_firestore.dart';
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

  test('isUnread is false when readAt is set', () {
    final n = AppNotification.fromMap('n2', {
      'companyId': 'c1', 'recipientRoles': ['incharge'],
      'type': 'lowBalance', 'title': 'L', 'body': 'b',
      'readAt': Timestamp.fromMillisecondsSinceEpoch(1000),
    });
    expect(n.isUnread, isFalse);
  });
}
