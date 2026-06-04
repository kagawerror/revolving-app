import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/widgets/app_avatar.dart';

void main() {
  testWidgets('shows initials when no photoUrl', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppAvatar(displayName: 'Ana Reyes', photoUrl: null, radius: 24)),
    ));
    expect(find.text('AR'), findsOneWidget);
  });
  testWidgets('falls back to a single initial for one-word names', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppAvatar(displayName: 'Ana', photoUrl: null, radius: 24)),
    ));
    expect(find.text('A'), findsOneWidget);
  });
}
