import 'package:flutter/material.dart';
import 'package:flutter_app/app_shell/ohmy_app.dart';
import 'package:flutter_app/app_shell/ohmy_bottom_navigation_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shared navigation does not cover module content', (
    tester,
  ) async {
    await tester.pumpWidget(const OhMyApp(supabaseEnabled: false));
    await tester.pump();

    final contentBottom = tester.getBottomLeft(find.byType(IndexedStack)).dy;
    final navigationTop = tester
        .getTopLeft(find.byType(OhMyBottomNavigationBar))
        .dy;

    expect(contentBottom, lessThanOrEqualTo(navigationTop));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('shared navigation opens every module root', (tester) async {
    await tester.pumpWidget(const OhMyApp(supabaseEnabled: false));
    await tester.pump();

    expect(find.text('Where would you like to go?'), findsOneWidget);

    await _openTab(tester, 'AI Chat');
    expect(find.text('Where to next?'), findsOneWidget);

    await _openTab(tester, 'Start Trip');
    expect(find.text('How would you like to travel?'), findsOneWidget);
    expect(find.text('Solo trip'), findsOneWidget);
    expect(find.text('Group trip'), findsOneWidget);

    await _openTab(tester, 'Community');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(OhMyBottomNavigationBar), findsOneWidget);

    await _openTab(tester, 'Profile');
    expect(find.text('Profile setup required'), findsWidgets);
  });
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final navigationBar = find.byType(OhMyBottomNavigationBar);
  final destination = find.descendant(
    of: navigationBar,
    matching: find.text(label),
  );
  await tester.tap(destination);
  await tester.pump();
}
