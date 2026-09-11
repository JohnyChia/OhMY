import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final routeSource = File(
    'lib/preference_recommender/features/routes/route_feature.dart',
  ).readAsStringSync();
  final soloMapSource = File(
    'lib/preference_recommender/pages/place_map_page.dart',
  ).readAsStringSync();

  test('active navigation does not animate the camera from compass events', () {
    expect(routeSource, isNot(contains('FlutterCompass.events')));
    expect(routeSource, isNot(contains('StreamSubscription<CompassEvent>')));
    expect(routeSource, contains('await mapController.moveCamera('));
  });

  test('active navigation starts fullscreen with traffic visible', () {
    expect(routeSource, contains('rootNavigator: true'));
    expect(routeSource, contains('bool trafficEnabled = true'));
    expect(routeSource, contains('color: _routeBlue.withValues(alpha: 0.68)'));
  });

  test('solo map does not render the MY logo badge', () {
    expect(soloMapSource, isNot(contains("'MY',")));
  });
}
