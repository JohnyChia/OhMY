import 'package:geolocator/geolocator.dart';
import 'live_trip_location_service.dart';

/// Count nearby members together without changing their recorded coordinates.
List<List<LiveMemberLocation>> clusterMemberLocations(
  List<LiveMemberLocation> members,
) {
  final clusters = <List<LiveMemberLocation>>[];
  for (final member in members.where((member) => member.isFresh)) {
    final cluster = clusters
        .where(
          (c) =>
              Geolocator.distanceBetween(
                c.first.coordinate.latitude,
                c.first.coordinate.longitude,
                member.coordinate.latitude,
                member.coordinate.longitude,
              ) <
              20,
        )
        .firstOrNull;
    if (cluster == null) {
      clusters.add([member]);
    } else {
      cluster.add(member);
    }
  }
  return clusters;
}
