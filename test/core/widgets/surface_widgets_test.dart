import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/widgets/app_list_tile.dart';
import 'package:rev_app/core/widgets/section_header.dart';
import 'package:rev_app/core/widgets/surface_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('SurfaceCard renders its child and reacts to tap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(SurfaceCard(
        onTap: () => tapped = true,
        child: const Text('card-body'),
      )),
    );

    expect(find.text('card-body'), findsOneWidget);
    await tester.tap(find.text('card-body'));
    expect(tapped, isTrue);
  });

  testWidgets('SectionHeader renders title and trailing', (tester) async {
    await tester.pumpWidget(
      _wrap(const SectionHeader(
        title: 'Recent',
        trailing: Text('See all'),
      )),
    );

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('AppListTile renders title and subtitle', (tester) async {
    await tester.pumpWidget(
      _wrap(const AppListTile(
        title: 'Office supplies',
        subtitle: 'Released',
      )),
    );

    expect(find.text('Office supplies'), findsOneWidget);
    expect(find.text('Released'), findsOneWidget);
  });
}
