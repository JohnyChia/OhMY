import 'dart:async';

import 'live_trip_location_service.dart';

/// Accelerated, straight-line demo movement, not a walking/driving route.
/// Only publishes through the signed-in member's existing location adapter.
class MeetupArrivalSimulation {
  MeetupArrivalSimulation({
    required this.start,
    required this.target,
    required this.publish,
    required this.onUpdate,
    required this.onError,
  });

  final GeoCoordinate start;
  final GeoCoordinate target;
  final Future<void> Function(GeoCoordinate) publish;
  final void Function() onUpdate;
  final void Function(Object) onError;
  Timer? _timer;
  bool _busy = false;
  bool _stopped = false;
  int _step = 0;
  GeoCoordinate get coordinate => GeoCoordinate(
    start.latitude + (target.latitude - start.latitude) * (_step / 20),
    start.longitude + (target.longitude - start.longitude) * (_step / 20),
  );
  bool get arrived => _step == 20;

  Future<void> begin() async {
    await publish(coordinate);
    if (_stopped) return;
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(advance()),
    );
  }

  Future<void> advance() async {
    if (_stopped || _busy) return;
    _busy = true;
    try {
      if (_step < 20) _step++;
      await publish(coordinate);
      if (!_stopped) onUpdate();
    } catch (error) {
      onError(error);
    } finally {
      _busy = false;
    }
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
  }
}

/// Suppresses real GPS writes from all open maps while demo movement is active.
class SimulationAwareLocationService implements LiveTripLocationService {
  SimulationAwareLocationService(this.delegate, this.simulating);
  final LiveTripLocationService delegate;
  final bool Function() simulating;
  @override
  Stream<List<LiveMemberLocation>> watchLocations() =>
      delegate.watchLocations();
  @override
  Future<void> publishOwnLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) {
    if (simulating()) return Future<void>.value();
    return delegate.publishOwnLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
    );
  }

  @override
  Future<void> dispose() => delegate.dispose();
}
