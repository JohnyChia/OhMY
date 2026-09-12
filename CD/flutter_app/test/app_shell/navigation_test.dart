import 'package:flutter/material.dart';
import 'package:flutter_app/app_shell/ohmy_app.dart';
import 'package:flutter_app/app_shell/ohmy_bottom_navigation_bar.dart';
import 'package:flutter_app/preference_recommender/features/routes/native_navigation_map.dart';
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

    expect(find.text('Search Attractions ...'), findsOneWidget);

    await _openTab(tester, 'AI Chat');
    expect(find.text('Your travel agent, ready.'), findsOneWidget);

    await _openTab(tester, 'Start Trip');
    expect(find.text('How would you like\nto travel?'), findsOneWidget);
    expect(find.text('Solo trip'), findsOneWidget);
    expect(find.text('Group trip'), findsOneWidget);

    await _openTab(tester, 'Community');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(OhMyBottomNavigationBar), findsOneWidget);

    await _openTab(tester, 'Profile');
    expect(find.text('Profile setup required'), findsWidgets);
  });

  testWidgets('Home search opens destination search before selecting a result', (
    tester,
  ) async {
    await tester.pumpWidget(const OhMyApp(supabaseEnabled: false));
    await tester.pump();

    await tester.tap(find.text('Search Attractions ...'));
    await tester.pump();
    // Nova's orb animates continuously even while the chat tab is offstage.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.widgetWithText(TextField, 'Search attractions…'),
      findsOneWidget,
    );
    expect(find.text('How would you like\nto travel?').hitTestable(), findsNothing);
  });

  testWidgets('active native navigation hides and restores the app shell bar', (
    tester,
  ) async {
    addTearDown(() => navigationExperienceActive.value = false);
    await tester.pumpWidget(const OhMyApp(supabaseEnabled: false));
    await tester.pump();

    navigationExperienceActive.value = true;
    await tester.pump();
    expect(find.byType(OhMyBottomNavigationBar), findsNothing);

    navigationExperienceActive.value = false;
    await tester.pump();
    expect(find.byType(OhMyBottomNavigationBar), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('system back returns a top-level tab to Home first', (
    tester,
  ) async {
    await tester.pumpWidget(const OhMyApp(supabaseEnabled: false));
    await tester.pump();
    await _openTab(tester, 'Profile');
    expect(find.text('Profile setup required'), findsWidgets);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Search Attractions ...'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Press back again to exit'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
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
