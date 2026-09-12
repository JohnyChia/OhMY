import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/preference_recommender/features/routes/navigation_sensor.dart';

void main() {
  group('navigation location settings', () {
    test('navigation GPS requests precise best-for-navigation updates', () {
      expect(navigationLocationSettings.accuracy.name, 'bestForNavigation');
      expect(navigationLocationSettings.distanceFilter, 1);
    });
  });
}
