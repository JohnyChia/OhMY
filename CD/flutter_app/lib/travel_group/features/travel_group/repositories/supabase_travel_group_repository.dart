import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/travel_group_models.dart';
import 'travel_group_repository.dart';

class SupabaseTravelGroupRepository implements TravelGroupRepository {
  SupabaseTravelGroupRepository(this._client);

  final SupabaseClient _client;

  User get _user {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const TravelGroupException(
        'Please sign in before using Travel Groups.',
        'authentication_required',
      );
    }
    return user;
  }

  String get _displayName {
    final metadata = _user.userMetadata ?? const <String, dynamic>{};
    return (metadata['username'] ?? metadata['full_name'] ?? 'Traveller')
        .toString()
        .trim();
  }

  @override
  Future<List<TravelGroup>> getNearbyGroups({
    required double radiusKm,
    List<String> tags = const [],
    String keyword = '',
    bool openOnly = false,
  }) async {
    try {
      final rows = await _client
          .from('travel_groups')
          .select()
          .neq('status', 'completed')
          .neq('status', 'cancelled')
          .order('created_at', ascending: false)
          .limit(100);
      final query = keyword.trim().toLowerCase();
      return rows
          .map(_groupFromRow)
          .where((group) {
            final matchesQuery =
                query.isEmpty ||
                group.name.toLowerCase().contains(query) ||
                group.destination.toLowerCase().contains(query);
            final matchesTags = tags.isEmpty || group.tags.any(tags.contains);
            final matchesMode = !openOnly || group.joinMode == JoinMode.open;
            return matchesQuery && matchesTags && matchesMode;
          })
          .toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TravelGroup?> getGroup(String groupId) async {
    try {
      final row = await _client
          .from('travel_groups')
          .select()
          .eq('id', groupId)
          .maybeSingle();
      if (row == null) return null;
      final members = await _client
          .from('travel_group_members')
          .select('user_id')
          .eq('group_id', groupId);
      return _groupFromRow(
        row,
        memberIds: members
            .map((member) => member['user_id'].toString())
            .toList(growable: false),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TravelGroup?> getOngoingGroupCreatedByCurrentUser() async {
    try {
      final row = await _client
          .from('travel_groups')
          .select()
          .eq('creator_id', _user.id)
          .inFilter('status', const ['waiting', 'active'])
          .order('status')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row == null ? null : _groupFromRow(row);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<GroupMemberProfile>> getMembers(String groupId) async {
    try {
      final memberRows = await _client
          .from('travel_group_members')
          .select('user_id, display_name, avatar_url, role, joined_at')
          .eq('group_id', groupId)
          .order('joined_at');
      final userIds = memberRows
          .map((row) => row['user_id'].toString())
          .toList(growable: false);
      final profileRows = userIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _client
                .from('traveler_profiles')
                .select(
                  'user_id, preferred_language, travel_style, '
                  'favorite_categories, budget_preference',
                )
                .inFilter('user_id', userIds);
      final profilesByUser = {
        for (final row in profileRows) row['user_id'].toString(): row,
      };
      return memberRows
          .map((member) {
            final userId = member['user_id'].toString();
            final profile = profilesByUser[userId];
            return GroupMemberProfile(
              userId: userId,
              displayName:
                  member['display_name']?.toString().trim().isNotEmpty == true
                  ? member['display_name'].toString().trim()
                  : 'Traveller',
              avatarUrl: member['avatar_url']?.toString(),
              role: member['role']?.toString() ?? 'member',
              interests: List<String>.from(
                (profile?['favorite_categories'] as List? ?? const []).map(
                  (item) => item.toString(),
                ),
              ),
              preferredLanguage: profile?['preferred_language']?.toString(),
              travelStyle: profile?['travel_style']?.toString(),
              budgetPreference: profile?['budget_preference']?.toString(),
            );
          })
          .toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TravelGroup> createGroup(TravelGroup group) async {
    try {
      final groupId = await _client.rpc(
        'create_travel_group_with_destination',
        params: {
          'group_name': group.name,
          'destination_name': group.destination,
          'group_description': group.description,
          'group_tags': group.tags,
          'group_max_members': group.maxMembers,
          'group_join_mode': group.joinMode.name,
          'creator_display_name': _displayName,
          'external_destination_id': group.destinationPlaceId,
          'destination_formatted_address': group.destinationAddress,
          'destination_lat': group.destinationLatitude,
          'destination_lng': group.destinationLongitude,
          'destination_photo': group.destinationPhotoName,
        },
      );
      return (await getGroup(groupId.toString()))!;
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    try {
      await _client
          .from('travel_groups')
          .delete()
          .eq('id', groupId)
          .eq('creator_id', _user.id);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> updateGroup(TravelGroup updated) async {
    try {
      await _client
          .from('travel_groups')
          .update({
            'name': updated.name,
            'destination': updated.destination,
            'description': updated.description,
            'tags': updated.tags,
            'max_members': updated.maxMembers,
            'join_mode': updated.joinMode.name,
            'destination_place_id': updated.destinationPlaceId,
            'destination_address': updated.destinationAddress,
            'destination_latitude': updated.destinationLatitude,
            'destination_longitude': updated.destinationLongitude,
            'destination_photo_name': updated.destinationPhotoName,
          })
          .eq('id', updated.id);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> updateMeetupPoint({
    required String groupId,
    required String meetupPoint,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _client
          .from('travel_groups')
          .update({
            'meetup_name': meetupPoint,
            'meetup_latitude': latitude,
            'meetup_longitude': longitude,
          })
          .eq('id', groupId);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> joinOpenGroup({
    required String groupId,
    required String travellerId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _client.rpc(
        'join_open_travel_group',
        params: {
          'target_group_id': groupId,
          'member_display_name': _displayName,
          'member_latitude': latitude,
          'member_longitude': longitude,
        },
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<JoinRequest> requestToJoin({
    required String groupId,
    required PrototypeUser traveller,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final row = await _client
          .from('travel_group_join_requests')
          .insert({
            'group_id': groupId,
            'user_id': traveller.id,
            'traveller_name': traveller.name,
            'request_latitude': latitude,
            'request_longitude': longitude,
          })
          .select()
          .single();
      return _requestFromRow(row);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        final row = await _client
            .from('travel_group_join_requests')
            .select()
            .eq('group_id', groupId)
            .eq('user_id', traveller.id)
            .eq('status', 'pending')
            .single();
        return _requestFromRow(row);
      }
      throw _failure(error);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<JoinRequest>> getJoinRequests(String groupId) async {
    try {
      final rows = await _client
          .from('travel_group_join_requests')
          .select()
          .eq('group_id', groupId)
          .order('created_at');
      return rows.map(_requestFromRow).toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> respondToJoinRequest({
    required String requestId,
    required bool accept,
  }) async {
    try {
      await _client.rpc(
        'respond_travel_group_join_request',
        params: {'target_request_id': requestId, 'accept_request': accept},
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<GroupSuggestion>> getSuggestions(String groupId) async {
    try {
      final rows = await _client
          .from('travel_group_suggestions')
          .select()
          .eq('group_id', groupId)
          .neq('status', 'rejected')
          .order('created_at');
      final ids = rows.map((row) => row['id'].toString()).toList();
      final votes = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await _client
                .from('travel_group_suggestion_votes')
                .select()
                .inFilter('suggestion_id', ids);
      final result = rows.map((row) => _suggestionFromRow(row, votes)).toList();
      result.sort((a, b) => b.score.compareTo(a.score));
      return result;
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<GroupSuggestion> addSuggestion(GroupSuggestion suggestion) async {
    try {
      final row = await _client
          .from('travel_group_suggestions')
          .insert({
            'group_id': suggestion.groupId,
            'suggested_by': _user.id,
            'external_place_id': suggestion.placeId,
            'place_name': suggestion.placeName,
            'source': suggestion.source,
            'category': suggestion.category,
            'distance_km': suggestion.distanceKm,
            'crowd_level': suggestion.crowdLevel,
            'duration_minutes': suggestion.durationMinutes,
            'tags': suggestion.tags,
            'latitude': suggestion.latitude,
            'longitude': suggestion.longitude,
          })
          .select()
          .single();
      return _suggestionFromRow(row, const []);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> removeSuggestion(String suggestionId) async {
    try {
      await _client.rpc(
        'remove_travel_group_suggestion',
        params: {'target_suggestion_id': suggestionId},
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> voteSuggestion({
    required String suggestionId,
    required String userId,
    required bool isUpvote,
  }) async {
    try {
      final existing = await _client
          .from('travel_group_suggestion_votes')
          .select('vote')
          .eq('suggestion_id', suggestionId)
          .eq('user_id', userId)
          .maybeSingle();
      final vote = isUpvote ? 1 : -1;
      if (existing != null && existing['vote'] == vote) {
        await _client
            .from('travel_group_suggestion_votes')
            .delete()
            .eq('suggestion_id', suggestionId)
            .eq('user_id', userId);
      } else {
        await _client.from('travel_group_suggestion_votes').upsert({
          'suggestion_id': suggestionId,
          'user_id': userId,
          'vote': vote,
        });
      }
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ItineraryStop> confirmSuggestion(String suggestionId) async {
    try {
      final stopId = await _client.rpc(
        'confirm_travel_group_suggestion',
        params: {'target_suggestion_id': suggestionId},
      );
      final row = await _client
          .from('travel_group_itinerary_stops')
          .select()
          .eq('id', stopId.toString())
          .single();
      return _stopFromRow(row);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<ItineraryStop>> getItinerary(String groupId) async {
    try {
      final rows = await _client
          .from('travel_group_itinerary_stops')
          .select()
          .eq('group_id', groupId)
          .order('position');
      return rows.map(_stopFromRow).toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> removeItineraryStop({
    required String groupId,
    required String stopId,
  }) async {
    try {
      await _client.rpc(
        'remove_travel_group_itinerary_stop',
        params: {'target_group_id': groupId, 'target_stop_id': stopId},
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> reorderItinerary(
    String groupId,
    List<ItineraryStop> stops,
  ) async {
    try {
      await _client.rpc(
        'reorder_travel_group_itinerary',
        params: {
          'target_group_id': groupId,
          'ordered_stop_ids': stops.map((stop) => stop.id).toList(),
          'leg_minutes': stops
              .map((stop) => stop.travelTimeFromPreviousMinutes)
              .toList(),
          'leg_distances_km': stops
              .map((stop) => stop.travelDistanceFromPreviousKm)
              .toList(),
        },
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TravelGroupTripSession> confirmGroup(String groupId) async {
    try {
      final sessionId = await _client.rpc(
        'confirm_travel_group',
        params: {'target_group_id': groupId},
      );
      return (await getActiveTripSession(groupId)) ??
          TravelGroupTripSession(
            id: sessionId.toString(),
            groupId: groupId,
            phase: GroupTripPhase.gathering,
          );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TravelGroupTripSession?> getActiveTripSession(String groupId) async {
    try {
      final row = await _client
          .from('travel_group_trip_sessions')
          .select()
          .eq('group_id', groupId)
          .inFilter('status', ['active', 'paused'])
          .maybeSingle();
      return row == null ? null : _sessionFromRow(row);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> startItinerary(String groupId) async {
    try {
      await _client.rpc(
        'begin_travel_group_journey',
        params: {'target_group_id': groupId},
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> markStopCompleted({
    required String groupId,
    required String stopId,
  }) async {
    try {
      await _client.rpc(
        'complete_travel_group_stop',
        params: {'target_group_id': groupId, 'target_stop_id': stopId},
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> endTrip(String groupId) async {
    try {
      await _client.rpc(
        'end_travel_group_journey',
        params: {'target_group_id': groupId},
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  TravelGroup _groupFromRow(
    Map<String, dynamic> row, {
    List<String>? memberIds,
  }) {
    final ids = memberIds ?? const <String>[];
    return TravelGroup(
      id: row['id'].toString(),
      creatorId: row['creator_id'].toString(),
      creatorName: row['creator_name']?.toString() ?? 'Traveller',
      name: row['name']?.toString() ?? '',
      destination: row['destination']?.toString() ?? '',
      description: row['description']?.toString() ?? '',
      meetupPoint: row['meetup_name']?.toString() ?? '',
      meetupNote: row['meetup_note']?.toString() ?? '',
      tags: List<String>.from(row['tags'] as List? ?? const []),
      maxMembers: (row['max_members'] as num?)?.round() ?? 4,
      memberCount: (row['member_count'] as num?)?.round() ?? ids.length,
      distanceKm: 0,
      joinMode: _joinMode(row['join_mode']),
      status: _groupStatus(row['status']),
      tripPhase: _tripPhase(row['trip_phase']),
      confirmedAt: DateTime.tryParse(row['confirmed_at']?.toString() ?? ''),
      memberIds: ids,
      destinationPlaceId: row['destination_place_id']?.toString(),
      destinationAddress: row['destination_address']?.toString() ?? '',
      destinationLatitude: (row['destination_latitude'] as num?)?.toDouble(),
      destinationLongitude: (row['destination_longitude'] as num?)?.toDouble(),
      destinationPhotoName: row['destination_photo_name']?.toString(),
      meetupLatitude: (row['meetup_latitude'] as num?)?.toDouble(),
      meetupLongitude: (row['meetup_longitude'] as num?)?.toDouble(),
    );
  }

  JoinRequest _requestFromRow(Map<String, dynamic> row) => JoinRequest(
    id: row['id'].toString(),
    groupId: row['group_id'].toString(),
    travellerId: row['user_id'].toString(),
    travellerName: row['traveller_name']?.toString() ?? 'Traveller',
    status: _requestStatus(row['status']),
  );

  GroupSuggestion _suggestionFromRow(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> votes,
  ) {
    final suggestionVotes = votes
        .where(
          (vote) => vote['suggestion_id'].toString() == row['id'].toString(),
        )
        .toList();
    return GroupSuggestion(
      id: row['id'].toString(),
      groupId: row['group_id'].toString(),
      suggestedByUserId: row['suggested_by'].toString(),
      placeName: row['place_name']?.toString() ?? '',
      source: row['source']?.toString() ?? 'member',
      category: row['category']?.toString() ?? 'Place',
      distanceKm: (row['distance_km'] as num?)?.toDouble() ?? 0,
      crowdLevel: row['crowd_level']?.toString() ?? 'Unknown',
      durationMinutes: (row['duration_minutes'] as num?)?.round() ?? 60,
      tags: List<String>.from(row['tags'] as List? ?? const []),
      placeId: row['external_place_id']?.toString(),
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      isConfirmed: row['status'] == 'confirmed',
      upvoterIds: suggestionVotes
          .where((vote) => vote['vote'] == 1)
          .map((vote) => vote['user_id'].toString())
          .toSet(),
      downvoterIds: suggestionVotes
          .where((vote) => vote['vote'] == -1)
          .map((vote) => vote['user_id'].toString())
          .toSet(),
    );
  }

  ItineraryStop _stopFromRow(Map<String, dynamic> row) => ItineraryStop(
    id: row['id'].toString(),
    groupId: row['group_id'].toString(),
    suggestionId: row['suggestion_id']?.toString() ?? '',
    placeName: row['place_name']?.toString() ?? 'Destination',
    placeId: row['external_place_id']?.toString(),
    latitude: (row['latitude'] as num?)?.toDouble(),
    longitude: (row['longitude'] as num?)?.toDouble(),
    position: (row['position'] as num?)?.round() ?? 0,
    estimatedDurationMinutes: (row['duration_minutes'] as num?)?.round() ?? 60,
    travelTimeFromPreviousMinutes:
        (row['travel_minutes_from_previous'] as num?)?.round() ?? 0,
    travelDistanceFromPreviousKm:
        (row['travel_distance_from_previous_km'] as num?)?.toDouble() ?? 0,
    status: _stopStatus(row['status']),
  );

  TravelGroupTripSession _sessionFromRow(Map<String, dynamic> row) =>
      TravelGroupTripSession(
        id: row['id'].toString(),
        groupId: row['group_id'].toString(),
        phase: _tripPhase(row['phase']),
        currentStopId: row['current_stop_id']?.toString(),
        currentStopIndex: (row['current_stop_index'] as num?)?.round() ?? 0,
      );

  JoinMode _joinMode(Object? value) =>
      value == 'request' ? JoinMode.request : JoinMode.open;

  GroupStatus _groupStatus(Object? value) => switch (value) {
    'active' => GroupStatus.active,
    'completed' => GroupStatus.completed,
    'cancelled' => GroupStatus.cancelled,
    _ => GroupStatus.waiting,
  };

  GroupTripPhase _tripPhase(Object? value) => switch (value) {
    'gathering' => GroupTripPhase.gathering,
    'navigating' => GroupTripPhase.navigating,
    'choosing_next' => GroupTripPhase.choosingNext,
    'completed' => GroupTripPhase.completed,
    'cancelled' => GroupTripPhase.cancelled,
    _ => GroupTripPhase.recruiting,
  };

  JoinRequestStatus _requestStatus(Object? value) => switch (value) {
    'accepted' => JoinRequestStatus.accepted,
    'declined' || 'cancelled' => JoinRequestStatus.declined,
    _ => JoinRequestStatus.pending,
  };

  StopStatus _stopStatus(Object? value) => switch (value) {
    'current' => StopStatus.current,
    'completed' || 'skipped' => StopStatus.completed,
    _ => StopStatus.upcoming,
  };

  TravelGroupException _failure(Object error) {
    if (error is TravelGroupException) return error;
    if (error is PostgrestException) {
      if (error.code == '23505' &&
          (error.message.contains('one_ongoing_travel_group_per_creator') ||
              (error.details?.toString().contains(
                    'one_ongoing_travel_group_per_creator',
                  ) ??
                  false))) {
        return const TravelGroupException(
          'End your current Travel Group before creating another one.',
          'ongoing_group_exists',
        );
      }
      return TravelGroupException(
        error.message,
        error.code ?? 'supabase_error',
      );
    }
    return TravelGroupException(error.toString(), 'supabase_error');
  }
}
