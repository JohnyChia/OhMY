enum TravelHistoryType { solo, group }

class TravelHistoryStop {
  const TravelHistoryStop({required this.name, this.visitedAt});

  final String name;
  final DateTime? visitedAt;

  factory TravelHistoryStop.fromJson(Map<String, dynamic> json) {
    return TravelHistoryStop(
      name: json['name']?.toString() ?? 'Journey stop',
      visitedAt: DateTime.tryParse(json['visited_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (visitedAt != null) 'visited_at': visitedAt!.toUtc().toIso8601String(),
  };
}

class TravelHistoryEntry {
  const TravelHistoryEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.destination,
    required this.startedAt,
    required this.completedAt,
    required this.stops,
    required this.distanceKm,
    required this.durationMinutes,
    required this.tags,
    required this.travelMode,
  });

  final String id;
  final TravelHistoryType type;
  final String title;
  final String destination;
  final DateTime startedAt;
  final DateTime completedAt;
  final List<TravelHistoryStop> stops;
  final double distanceKm;
  final int durationMinutes;
  final List<String> tags;
  final String travelMode;

  factory TravelHistoryEntry.fromSupabase(Map<String, dynamic> row) {
    if (row['source_type'] == null && row['travel_groups'] is Map) {
      return TravelHistoryEntry.fromLegacyGroup(row);
    }
    final rawStops = row['itinerary'];
    return TravelHistoryEntry(
      id: row['id'].toString(),
      type: row['source_type'] == 'group'
          ? TravelHistoryType.group
          : TravelHistoryType.solo,
      title: row['title']?.toString() ?? 'Completed trip',
      destination: row['destination']?.toString() ?? 'Unknown destination',
      startedAt: DateTime.parse(row['started_at'].toString()),
      completedAt: DateTime.parse(row['ended_at'].toString()),
      stops: rawStops is List
          ? rawStops
                .whereType<Map>()
                .map(
                  (item) => TravelHistoryStop.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      distanceKm: (row['distance_km'] as num?)?.toDouble() ?? 0,
      durationMinutes: (row['duration_minutes'] as num?)?.round() ?? 0,
      tags:
          (row['tags'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const [],
      travelMode: row['travel_mode']?.toString() ?? 'Not recorded',
    );
  }

  factory TravelHistoryEntry.fromLegacyGroup(Map<String, dynamic> row) {
    final group = row['travel_groups'];
    final groupData = group is Map
        ? Map<String, dynamic>.from(group)
        : const <String, dynamic>{};
    final startedAt = DateTime.parse(row['started_at'].toString());
    final completedAt = DateTime.parse(row['ended_at'].toString());
    return TravelHistoryEntry(
      id: row['id'].toString(),
      type: TravelHistoryType.group,
      title: groupData['name']?.toString() ?? 'Completed group trip',
      destination:
          groupData['destination']?.toString() ?? 'Unknown destination',
      startedAt: startedAt,
      completedAt: completedAt,
      stops: const [],
      distanceKm: 0,
      durationMinutes: completedAt.difference(startedAt).inMinutes,
      tags:
          (groupData['tags'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const [],
      travelMode: 'Group journey',
    );
  }
}

class CompletedTravelDraft {
  const CompletedTravelDraft({
    required this.type,
    required this.sourceReference,
    required this.title,
    required this.destination,
    required this.startedAt,
    required this.completedAt,
    required this.stops,
    required this.distanceKm,
    required this.durationMinutes,
    required this.tags,
    required this.travelMode,
  });

  final TravelHistoryType type;
  final String sourceReference;
  final String title;
  final String destination;
  final DateTime startedAt;
  final DateTime completedAt;
  final List<TravelHistoryStop> stops;
  final double distanceKm;
  final int durationMinutes;
  final List<String> tags;
  final String travelMode;

  Map<String, dynamic> toSupabase(String userId) => {
    'user_id': userId,
    'source_type': type.name,
    'source_reference': sourceReference,
    'title': title,
    'destination': destination,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': completedAt.toUtc().toIso8601String(),
    'itinerary': stops.map((stop) => stop.toJson()).toList(growable: false),
    'distance_km': distanceKm,
    'duration_minutes': durationMinutes,
    'tags': tags,
    'travel_mode': travelMode,
  };
}
