import 'dart:async';
import 'dart:math' as math;

import '../models/travel_group_models.dart';

class GeoCoordinate {
  const GeoCoordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class LiveMemberLocation {
  const LiveMemberLocation({
    required this.userId,
    required this.displayName,
    required this.coordinate,
    required this.updatedAt,
    required this.isCurrentUser,
    this.accuracyMeters,
  });

  final String userId;
  final String displayName;
  final GeoCoordinate coordinate;
  final DateTime updatedAt;
  final bool isCurrentUser;
  final double? accuracyMeters;

  bool get isFresh =>
      DateTime.now().difference(updatedAt) < const Duration(seconds: 30);
}

typedef LiveTripLocationServiceFactory = LiveTripLocationService Function({
  required TravelGroup group,
  required PrototypeUser currentUser,
});

abstract interface class LiveTripLocationService {
  Stream<List<LiveMemberLocation>> watchLocations();

  void publishOwnLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  });

  Future<void> dispose();
}

/// Route used by the standalone prototype around central Kuala Lumpur.
///
/// The production adapter should replace this with the shared session route
/// stored in `travel_group_trip_sessions.route`.
const demoGroupRoute = <GeoCoordinate>[
  GeoCoordinate(3.14295, 101.69758),
  GeoCoordinate(3.14372, 101.69704),
  GeoCoordinate(3.14448, 101.69630),
  GeoCoordinate(3.14524, 101.69574),
  GeoCoordinate(3.14618, 101.69546),
  GeoCoordinate(3.14718, 101.69618),
];

LiveTripLocationService createMockLiveTripLocationService({
  required TravelGroup group,
  required PrototypeUser currentUser,
}) {
  return MockLiveTripLocationService(group: group, currentUser: currentUser);
}

/// Emits moving group members so the full multi-member map can be demoed
/// before Supabase tables and authentication are finalised.
class MockLiveTripLocationService implements LiveTripLocationService {
  MockLiveTripLocationService({
    required TravelGroup group,
    required PrototypeUser currentUser,
  })  : _memberIds = <String>{...group.memberIds, currentUser.id}.toList(),
        _currentUser = currentUser {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      _tick += 1;
      _emit();
    });
  }

  static const _demoNames = <String, String>{
    'USER_100': 'Aina Sofea',
    'USER_101': 'Farah',
    'USER_102': 'Hakim',
    'USER_103': 'Mei Lin',
    'USER_104': 'Daniel',
  };

  final List<String> _memberIds;
  final PrototypeUser _currentUser;
  final StreamController<List<LiveMemberLocation>> _controller =
      StreamController<List<LiveMemberLocation>>.broadcast();

  late final Timer _timer;
  GeoCoordinate? _deviceCoordinate;
  double? _deviceAccuracyMeters;
  int _tick = 0;

  @override
  Stream<List<LiveMemberLocation>> watchLocations() async* {
    yield _snapshot();
    yield* _controller.stream;
  }

  @override
  void publishOwnLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) {
    _deviceCoordinate = GeoCoordinate(latitude, longitude);
    _deviceAccuracyMeters = accuracyMeters;
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_snapshot());
  }

  List<LiveMemberLocation> _snapshot() {
    final now = DateTime.now();
    return List<LiveMemberLocation>.generate(_memberIds.length, (index) {
      final userId = _memberIds[index];
      final isCurrentUser = userId == _currentUser.id;
      final progress =
          (.18 + (_tick * .008) + (index * .012)).clamp(0.0, .88).toDouble();
      final simulated = _coordinateOnRoute(progress, index);
      return LiveMemberLocation(
        userId: userId,
        displayName: isCurrentUser
            ? _currentUser.name
            : (_demoNames[userId] ?? 'Traveller ${index + 1}'),
        coordinate: isCurrentUser && _deviceCoordinate != null
            ? _deviceCoordinate!
            : simulated,
        accuracyMeters: isCurrentUser ? _deviceAccuracyMeters : 8 + index * 2,
        updatedAt: now.subtract(Duration(seconds: index * 2)),
        isCurrentUser: isCurrentUser,
      );
    });
  }

  GeoCoordinate _coordinateOnRoute(double progress, int memberIndex) {
    final scaled = progress * (demoGroupRoute.length - 1);
    final segment = scaled.floor().clamp(0, demoGroupRoute.length - 2);
    final localProgress = scaled - segment;
    final start = demoGroupRoute[segment];
    final end = demoGroupRoute[segment + 1];
    final spread = memberIndex == 0 ? 0.0 : .000035;
    return GeoCoordinate(
      start.latitude +
          (end.latitude - start.latitude) * localProgress +
          math.sin(memberIndex * 1.7) * spread,
      start.longitude +
          (end.longitude - start.longitude) * localProgress +
          math.cos(memberIndex * 1.3) * spread,
    );
  }

  @override
  Future<void> dispose() async {
    _timer.cancel();
    await _controller.close();
  }
}
