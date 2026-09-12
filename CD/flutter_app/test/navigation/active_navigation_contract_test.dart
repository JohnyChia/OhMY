import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final routeSource = File(
    'lib/preference_recommender/features/routes/route_feature.dart',
  ).readAsStringSync();
  final soloMapSource = File(
    'lib/preference_recommender/pages/place_map_page.dart',
  ).readAsStringSync();
  final nativeNavigationSource = File(
    'lib/preference_recommender/features/routes/native_navigation_map.dart',
  ).readAsStringSync();

  test('active navigation does not animate the camera from compass events', () {
    expect(routeSource, isNot(contains('FlutterCompass.events')));
    expect(routeSource, isNot(contains('StreamSubscription<CompassEvent>')));
    expect(nativeNavigationSource, contains('followMyLocation('));
  });

  test('active navigation uses the SDK map with traffic visible', () {
    expect(nativeNavigationSource, contains('GoogleMapsNavigationView('));
    expect(routeSource, contains('bool trafficEnabled = true'));
    expect(
      nativeNavigationSource,
      contains('setTrafficEnabled(widget.trafficEnabled)'),
    );
    expect(
      nativeNavigationSource,
      contains('setNavigationFooterEnabled(false)'),
    );
    expect(nativeNavigationSource, contains('setTrafficPromptsEnabled(false)'));
    expect(
      nativeNavigationSource,
      contains('setTrafficIncidentCardsEnabled(false)'),
    );
  });

  test(
    'traffic suggestions use sustained heavy traffic and a five minute delay',
    () {
      expect(routeSource, contains('_minimumTrafficDelayMinutes = 5'));
      expect(routeSource, contains('Duration(seconds: 20)'));
      expect(routeSource, contains('getCurrentRouteSegment()'));
      expect(routeSource, isNot(contains('_maximumTrafficPrompts')));
    },
  );

  test('solo map does not render the MY logo badge', () {
    expect(soloMapSource, isNot(contains("'MY',")));
  });
}
