import 'package:flutter_app/preference_recommender/features/routes/route_feature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const origin = RouteLocation(
    id: 'same-place',
    name: 'Origin',
    address: 'Kuala Lumpur',
    latitude: 3.1478,
    longitude: 101.6953,
  );

  test('rejects the same Google place as both route endpoints', () {
    const alias = RouteLocation(
      id: 'same-place',
      name: 'Different display name',
      address: 'Kuala Lumpur',
      latitude: 3.148,
      longitude: 101.6955,
    );

    expect(areDistinctRouteLocations(origin, alias), isFalse);
  });

  test('rejects endpoint coordinates representing the same location', () {
    const sameCoordinates = RouteLocation(
      name: 'Dropped pin',
      address: 'Kuala Lumpur',
      latitude: 3.1478,
      longitude: 101.6953,
    );

    expect(areDistinctRouteLocations(origin, sameCoordinates), isFalse);
  });

  test('rejects a destination within the minimum navigation distance', () {
    const nearbyDestination = RouteLocation(
      name: 'Nearby entrance',
      address: 'Kuala Lumpur',
      latitude: 3.1484,
      longitude: 101.6953,
    );

    expect(areDistinctRouteLocations(origin, nearbyDestination), isFalse);
  });

  test('accepts two genuinely different valid locations', () {
    const destination = RouteLocation(
      id: 'destination',
      name: 'Destination',
      address: 'Kuala Lumpur',
      latitude: 3.1579,
      longitude: 101.7116,
    );

    expect(areDistinctRouteLocations(origin, destination), isTrue);
  });
}
