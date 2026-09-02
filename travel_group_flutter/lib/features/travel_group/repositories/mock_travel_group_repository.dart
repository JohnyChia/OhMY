import '../models/travel_group_models.dart';
import 'travel_group_repository.dart';

class MockTravelGroupRepository implements TravelGroupRepository {
  MockTravelGroupRepository({
    required List<TravelGroup> groups,
    required List<JoinRequest> requests,
    required List<GroupSuggestion> suggestions,
    required List<ItineraryStop> itinerary,
  })  : _groups = groups,
        _requests = requests,
        _suggestions = suggestions,
        _itinerary = itinerary;

  factory MockTravelGroupRepository.seeded() {
    return MockTravelGroupRepository(
      groups: _seedGroups(),
      requests: [
        JoinRequest(
          id: 'REQUEST_001',
          groupId: 'GROUP_001',
          travellerId: 'USER_500',
          travellerName: 'Nur Imani',
        ),
      ],
      suggestions: _seedSuggestions(),
      itinerary: [
        ItineraryStop(
          id: 'STOP_001',
          groupId: 'GROUP_001',
          suggestionId: 'SUGGESTION_001',
          placeName: 'Petaling Street Breakfast',
          position: 0,
          estimatedDurationMinutes: 60,
          travelTimeFromPreviousMinutes: 0,
        ),
      ],
    );
  }

  final List<TravelGroup> _groups;
  final List<JoinRequest> _requests;
  final List<GroupSuggestion> _suggestions;
  final List<ItineraryStop> _itinerary;
  int _sequence = 1000;

  String _nextId(String prefix) => '${prefix}_${++_sequence}';

  TravelGroup _requireGroup(String id) {
    return _groups.firstWhere(
      (group) => group.id == id,
      orElse: () => throw const TravelGroupException(
          'Travel group not found.', 'not_found'),
    );
  }

  @override
  Future<List<TravelGroup>> getNearbyGroups({
    required double radiusKm,
    List<String> tags = const [],
    String keyword = '',
    bool openOnly = false,
  }) async {
    final query = keyword.trim().toLowerCase();
    final result = _groups.where((group) {
      final matchesKeyword = query.isEmpty ||
          group.name.toLowerCase().contains(query) ||
          group.destination.toLowerCase().contains(query);
      final matchesTags = tags.isEmpty || group.tags.any(tags.contains);
      final matchesJoinMode = !openOnly || group.joinMode == JoinMode.open;
      return group.distanceKm <= radiusKm &&
          matchesKeyword &&
          matchesTags &&
          matchesJoinMode;
    }).toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return result;
  }

  @override
  Future<TravelGroup?> getGroup(String groupId) async {
    for (final group in _groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  @override
  Future<TravelGroup> createGroup(TravelGroup group) async {
    _groups.add(group);
    return group;
  }

  @override
  Future<void> joinOpenGroup(
      {required String groupId, required String travellerId}) async {
    final group = _requireGroup(groupId);
    if (group.joinMode != JoinMode.open) {
      throw const TravelGroupException(
          'This group requires creator approval.', 'approval_required');
    }
    if (group.memberIds.contains(travellerId)) return;
    if (group.isFull) {
      throw const TravelGroupException(
          'This travel group is currently full.', 'group_full');
    }
    group.memberIds.add(travellerId);
  }

  @override
  Future<JoinRequest> requestToJoin(
      {required String groupId, required PrototypeUser traveller}) async {
    final group = _requireGroup(groupId);
    if (group.memberIds.contains(traveller.id)) {
      throw const TravelGroupException(
          'You are already a member.', 'already_member');
    }
    if (group.isFull) {
      throw const TravelGroupException(
          'This travel group is currently full.', 'group_full');
    }
    for (final request in _requests) {
      if (request.groupId == groupId &&
          request.travellerId == traveller.id &&
          request.status == JoinRequestStatus.pending) {
        return request;
      }
    }
    final request = JoinRequest(
      id: _nextId('REQUEST'),
      groupId: groupId,
      travellerId: traveller.id,
      travellerName: traveller.name,
    );
    _requests.add(request);
    return request;
  }

  @override
  Future<List<JoinRequest>> getJoinRequests(String groupId) async =>
      _requests.where((request) => request.groupId == groupId).toList();

  @override
  Future<void> respondToJoinRequest(
      {required String requestId, required bool accept}) async {
    final request = _requests.firstWhere(
      (item) => item.id == requestId,
      orElse: () => throw const TravelGroupException(
          'Join request not found.', 'not_found'),
    );
    if (request.status != JoinRequestStatus.pending) return;
    if (!accept) {
      request.status = JoinRequestStatus.declined;
      return;
    }
    final group = _requireGroup(request.groupId);
    if (group.isFull) {
      throw const TravelGroupException('The group is now full.', 'group_full');
    }
    if (!group.memberIds.contains(request.travellerId)) {
      group.memberIds.add(request.travellerId);
    }
    request.status = JoinRequestStatus.accepted;
  }

  @override
  Future<List<GroupSuggestion>> getSuggestions(String groupId) async {
    final result = _suggestions
        .where((item) => item.groupId == groupId)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return result;
  }

  @override
  Future<GroupSuggestion> addSuggestion(GroupSuggestion suggestion) async {
    final duplicate = _suggestions.any((item) =>
        item.groupId == suggestion.groupId &&
        item.placeName.toLowerCase() == suggestion.placeName.toLowerCase());
    if (duplicate) {
      throw const TravelGroupException(
          'This place is already suggested.', 'duplicate');
    }
    _suggestions.add(suggestion);
    return suggestion;
  }

  @override
  Future<void> voteSuggestion(
      {required String suggestionId,
      required String userId,
      required bool isUpvote}) async {
    final suggestion =
        _suggestions.firstWhere((item) => item.id == suggestionId);
    final target = isUpvote ? suggestion.upvoterIds : suggestion.downvoterIds;
    final opposite = isUpvote ? suggestion.downvoterIds : suggestion.upvoterIds;
    opposite.remove(userId);
    if (!target.remove(userId)) target.add(userId);
  }

  @override
  Future<ItineraryStop> confirmSuggestion(String suggestionId) async {
    final suggestion =
        _suggestions.firstWhere((item) => item.id == suggestionId);
    for (final stop in _itinerary) {
      if (stop.suggestionId == suggestionId) return stop;
    }
    suggestion.isConfirmed = true;
    final groupStops =
        _itinerary.where((stop) => stop.groupId == suggestion.groupId).toList();
    final stop = ItineraryStop(
      id: _nextId('STOP'),
      groupId: suggestion.groupId,
      suggestionId: suggestion.id,
      placeName: suggestion.placeName,
      position: groupStops.length,
      estimatedDurationMinutes: suggestion.durationMinutes,
      travelTimeFromPreviousMinutes:
          groupStops.isEmpty ? 0 : 10 + groupStops.length * 2,
    );
    _itinerary.add(stop);
    return stop;
  }

  @override
  Future<List<ItineraryStop>> getItinerary(String groupId) async {
    final result = _itinerary.where((stop) => stop.groupId == groupId).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return result;
  }

  @override
  Future<void> reorderItinerary(
      String groupId, List<String> orderedStopIds) async {
    final group = _requireGroup(groupId);
    if (group.status != GroupStatus.waiting) {
      throw const TravelGroupException(
          'The itinerary is already active.', 'itinerary_active');
    }
    for (var index = 0; index < orderedStopIds.length; index++) {
      final stop =
          _itinerary.firstWhere((item) => item.id == orderedStopIds[index]);
      stop.position = index;
      stop.travelTimeFromPreviousMinutes = index == 0 ? 0 : 8 + index * 2;
    }
  }

  @override
  Future<void> startItinerary(String groupId) async {
    final group = _requireGroup(groupId);
    final stops = await getItinerary(groupId);
    if (stops.isEmpty) {
      throw const TravelGroupException(
          'Confirm at least one stop first.', 'empty_itinerary');
    }
    group.status = GroupStatus.active;
    for (final stop in stops) {
      if (stop.status != StopStatus.completed) {
        stop.status = StopStatus.upcoming;
      }
    }
    stops.firstWhere((stop) => stop.status != StopStatus.completed).status =
        StopStatus.current;
  }

  @override
  Future<void> markStopCompleted(
      {required String groupId, required String stopId}) async {
    final group = _requireGroup(groupId);
    final stops = await getItinerary(groupId);
    final stop = stops.firstWhere((item) => item.id == stopId);
    if (stop.status != StopStatus.current) {
      throw const TravelGroupException(
          'Only the current stop can be completed.', 'not_current');
    }
    stop.status = StopStatus.completed;
    final remaining =
        stops.where((item) => item.status == StopStatus.upcoming).toList();
    if (remaining.isEmpty) {
      group.status = GroupStatus.completed;
    } else {
      remaining.first.status = StopStatus.current;
    }
  }
}

List<TravelGroup> _seedGroups() => [
      TravelGroup(
        id: 'GROUP_001',
        creatorId: 'USER_100',
        creatorName: 'Aina Sofea',
        name: 'Petaling Street Food Hunt',
        destination: 'Petaling Street',
        description:
            'Taste local favourites and explore heritage streets together.',
        meetupPoint: 'Pasar Seni MRT · Entrance A',
        meetupNote: 'Meet before 10:30 AM at the station entrance.',
        tags: ['Food', 'Cultural', 'Budget'],
        maxMembers: 8,
        distanceKm: 0.8,
        joinMode: JoinMode.open,
        status: GroupStatus.waiting,
        memberIds: ['USER_100', 'USER_101', 'USER_102', 'USER_103', 'USER_104'],
      ),
      TravelGroup(
        id: 'GROUP_002',
        creatorId: 'USER_200',
        creatorName: 'Hakim Zain',
        name: 'KLCC Evening Walk',
        destination: 'KLCC Park',
        description: 'A relaxed evening loop through the park and city lights.',
        meetupPoint: 'KLCC LRT concourse',
        tags: ['Nature', 'Casual'],
        maxMembers: 6,
        distanceKm: 1.4,
        joinMode: JoinMode.open,
        status: GroupStatus.waiting,
        memberIds: ['USER_200', 'USER_201', 'USER_202', 'USER_203'],
      ),
      TravelGroup(
        id: 'GROUP_003',
        creatorId: 'USER_300',
        creatorName: 'Priya Kumar',
        name: 'Batu Caves Quick Visit',
        destination: 'Batu Caves',
        description:
            'A short cultural visit with time for photos and breakfast.',
        meetupPoint: 'Batu Caves KTM entrance',
        tags: ['Cultural', 'Heritage'],
        maxMembers: 4,
        distanceKm: 8.2,
        joinMode: JoinMode.request,
        status: GroupStatus.waiting,
        memberIds: ['USER_300', 'USER_301'],
      ),
      TravelGroup(
        id: 'GROUP_004',
        creatorId: 'USER_400',
        creatorName: 'Daniel Lim',
        name: 'Chow Kit Market Run',
        destination: 'Chow Kit',
        description: 'A compact local market and street-food exploration.',
        meetupPoint: 'Chow Kit monorail station',
        tags: ['Food', 'Budget'],
        maxMembers: 3,
        distanceKm: 2.3,
        joinMode: JoinMode.open,
        status: GroupStatus.waiting,
        memberIds: ['USER_400', 'USER_401', 'USER_402'],
      ),
    ];

List<GroupSuggestion> _seedSuggestions() => [
      GroupSuggestion(
        id: 'SUGGESTION_001',
        groupId: 'GROUP_001',
        suggestedByUserId: 'USER_100',
        placeName: 'Petaling Street Breakfast',
        source: 'Attraction Directory',
        category: 'Food',
        distanceKm: 0.2,
        crowdLevel: 'Moderate',
        durationMinutes: 60,
        tags: ['Food', 'Budget'],
        upvoterIds: {'USER_100', 'USER_101', 'USER_102'},
        isConfirmed: true,
      ),
      GroupSuggestion(
        id: 'SUGGESTION_002',
        groupId: 'GROUP_001',
        suggestedByUserId: 'USER_101',
        placeName: 'Central Market',
        source: 'Attraction Directory',
        category: 'Cultural',
        distanceKm: 1.2,
        crowdLevel: 'Moderate',
        durationMinutes: 60,
        tags: ['Cultural', 'Heritage'],
        upvoterIds: {'USER_100', 'USER_101', 'USER_102', 'USER_103'},
        downvoterIds: {'USER_104'},
      ),
      GroupSuggestion(
        id: 'SUGGESTION_003',
        groupId: 'GROUP_001',
        suggestedByUserId: 'USER_102',
        placeName: 'Kampung Baru Food Walk',
        source: 'Community Discovery',
        category: 'Food',
        distanceKm: 2.8,
        crowdLevel: 'Busy',
        durationMinutes: 90,
        tags: ['Food', 'Budget'],
        upvoterIds: {'USER_100', 'USER_101', 'USER_102'},
      ),
      GroupSuggestion(
        id: 'SUGGESTION_004',
        groupId: 'GROUP_001',
        suggestedByUserId: 'USER_103',
        placeName: 'River of Life Night View',
        source: 'Custom suggestion',
        category: 'Nature',
        distanceKm: 0.9,
        crowdLevel: 'Low',
        durationMinutes: 45,
        tags: ['Nature', 'Casual'],
        upvoterIds: {'USER_100', 'USER_101'},
      ),
    ];
