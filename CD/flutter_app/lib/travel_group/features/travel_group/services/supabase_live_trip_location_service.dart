import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/travel_group_models.dart';
import 'live_trip_location_service.dart';

LiveTripLocationService createSupabaseLiveTripLocationService({
  required TravelGroup group,
  required PrototypeUser currentUser,
  required String? sessionId,
}) {
  if (sessionId == null) {
    throw const TravelGroupException(
      'Confirm the group before sharing live locations.',
      'group_not_confirmed',
    );
  }
  return SupabaseLiveTripLocationService(
    client: Supabase.instance.client,
    sessionId: sessionId,
    currentUser: currentUser,
  );
}

class SupabaseLiveTripLocationService implements LiveTripLocationService {
  SupabaseLiveTripLocationService({
    required SupabaseClient client,
    required this.sessionId,
    required this.currentUser,
  }) : _client = client;

  final SupabaseClient _client;
  final String sessionId;
  final PrototypeUser currentUser;
  bool _disposed = false;

  @override
  Stream<List<LiveMemberLocation>> watchLocations() async* {
    final participantRows = await _client
        .from('travel_group_trip_participants')
        .select('user_id, display_name')
        .eq('session_id', sessionId);
    final names = <String, String>{
      for (final row in participantRows)
        row['user_id'].toString():
            row['display_name']?.toString() ?? 'Traveller',
    };
    yield* _client
        .from('travel_group_live_locations')
        .stream(primaryKey: ['session_id', 'user_id'])
        .eq('session_id', sessionId)
        .map(
          (rows) => rows
              .map(
                (row) => LiveMemberLocation(
                  userId: row['user_id'].toString(),
                  displayName: names[row['user_id'].toString()] ?? 'Traveller',
                  coordinate: GeoCoordinate(
                    (row['latitude'] as num).toDouble(),
                    (row['longitude'] as num).toDouble(),
                  ),
                  accuracyMeters: (row['accuracy_m'] as num?)?.toDouble(),
                  updatedAt:
                      DateTime.tryParse(
                        row['recorded_at']?.toString() ?? '',
                      )?.toLocal() ??
                      DateTime.now(),
                  isCurrentUser: row['user_id'].toString() == currentUser.id,
                ),
              )
              .toList(growable: false),
        );
  }

  @override
  void publishOwnLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) {
    if (_disposed) return;
    unawaited(
      _client.from('travel_group_live_locations').upsert({
        'session_id': sessionId,
        'user_id': currentUser.id,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_m': accuracyMeters,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'session_id,user_id'),
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _client
        .from('travel_group_trip_participants')
        .update({'last_seen_at': DateTime.now().toUtc().toIso8601String()})
        .eq('session_id', sessionId)
        .eq('user_id', currentUser.id);
  }
}
