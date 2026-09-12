import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/travel_group_models.dart';
import '../repositories/travel_group_repository.dart';
import '../services/live_trip_location_service.dart';
import '../utils/profanity_filter.dart';

class TravelGroupController extends ChangeNotifier {
  TravelGroupController({
    required this.repository,
    PrototypeUser? currentUser,
    this.allowDemoVerification = true,
    this.liveTripLocationServiceFactory = createMockLiveTripLocationService,
  }) {
    this.currentUser = currentUser ?? demoUsers.first;
  }

  static const minTravellersPerGroup = 2;
  static const maxTravellersPerGroup = 4;
  static const maximumJoinDistanceKm = 10.0;

  final TravelGroupRepository repository;
  final bool allowDemoVerification;
  final LiveTripLocationServiceFactory liveTripLocationServiceFactory;

  final List<PrototypeUser> demoUsers = [
    PrototypeUser(id: 'USER_100', name: 'Aina Sofea', isVerified: true),
    PrototypeUser(id: 'USER_500', name: 'Unverified Guest', isVerified: false),
  ];

  late PrototypeUser currentUser;
  List<TravelGroup> groups = [];
  TravelGroup? activeGroup;
  TravelGroup? ownedOngoingGroup;
  List<GroupMemberProfile> members = [];
  List<JoinRequest> joinRequests = [];
  List<GroupSuggestion> suggestions = [];
  List<ItineraryStop> itinerary = [];
  TravelGroupTripSession? activeSession;
  DateTime? activeTripStartedAt;
  double radiusKm = 10;
  String selectedArea = 'Finding your current area...';
  double? areaLatitude;
  double? areaLongitude;
  String keyword = '';
  bool openOnly = false;
  bool isLoading = false;
  int _localIdSequence = 0;

  bool get isCreator => activeGroup?.creatorId == currentUser.id;
  bool get isMember => activeGroup?.memberIds.contains(currentUser.id) ?? false;
  bool get hasOngoingCreatedGroup => ownedOngoingGroup != null;
  GeoCoordinate effectiveLocation(double latitude, double longitude) =>
      GeoCoordinate(latitude, longitude);

  LiveTripLocationService createLiveTripLocationService() {
    final group = activeGroup;
    if (group == null) {
      throw const TravelGroupException(
        'Open a travel group before starting live location.',
        'no_active_group',
      );
    }
    return liveTripLocationServiceFactory(
      group: group,
      currentUser: currentUser,
      sessionId: activeSession?.id,
    );
  }

  void switchUser(PrototypeUser user) {
    currentUser = user;
    notifyListeners();
  }

  void completeDemoVerification() {
    if (!allowDemoVerification) return;
    currentUser.isVerified = true;
    notifyListeners();
  }

  Future<void> loadGroups() async {
    isLoading = true;
    notifyListeners();
    var fetched = await repository.getNearbyGroups(
      radiusKm: 500,
      keyword: keyword,
      openOnly: openOnly,
    );
    final centerLatitude = areaLatitude;
    final centerLongitude = areaLongitude;
    if (centerLatitude != null && centerLongitude != null) {
      fetched = fetched
          .map((group) {
            if (group.destinationLatitude == null ||
                group.destinationLongitude == null) {
              return group;
            }
            group.distanceKm =
                _distanceBetween(
                  centerLatitude,
                  centerLongitude,
                  group.destinationLatitude!,
                  group.destinationLongitude!,
                ) /
                1000.0;
            return group;
          })
          .where((group) => group.distanceKm <= radiusKm)
          .toList();
      fetched.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    }
    groups = fetched;
    isLoading = false;
    notifyListeners();
  }

  Future<void> restoreOngoingCreatedGroup() async {
    final owned = await repository.getOngoingGroupCreatedByCurrentUser();
    ownedOngoingGroup = owned;
    if (owned != null) {
      await openGroup(owned.id);
    } else {
      notifyListeners();
    }
  }

  Future<void> setSearch(String value) async {
    keyword = value;
    await loadGroups();
  }

  Future<void> setRadius(double value) async {
    radiusKm = value;
    await loadGroups();
  }

  Future<void> toggleOpenOnly() async {
    openOnly = !openOnly;
    await loadGroups();
  }

  Future<void> setArea(
    String value, {
    double? latitude,
    double? longitude,
  }) async {
    if (selectedArea == value && latitude == null) return;
    selectedArea = value;
    if (latitude != null && longitude != null) {
      areaLatitude = latitude;
      areaLongitude = longitude;
    }
    notifyListeners();
    await loadGroups();
  }

  Future<void> openGroup(String groupId) async {
    activeGroup = await repository.getGroup(groupId);
    if (activeGroup == null) {
      throw const TravelGroupException('Travel group not found.', 'not_found');
    }
    await refreshWorkspace();
  }

  Future<void> refreshWorkspace() async {
    final group = activeGroup;
    if (group == null) return;
    members = await repository.getMembers(group.id);
    joinRequests = await repository.getJoinRequests(group.id);
    suggestions = await repository.getSuggestions(group.id);
    itinerary = await repository.getItinerary(group.id);
    activeSession = await repository.getActiveTripSession(group.id);
    final refreshedGroup = await repository.getGroup(group.id);
    if (refreshedGroup != null) activeGroup = refreshedGroup;
    notifyListeners();
  }

  void _requireVerified() {
    if (!currentUser.isVerified) {
      throw const TravelGroupException(
        'Verify your traveller profile before joining or creating a group.',
        'verification_required',
      );
    }
  }

  void _requireCreator() {
    if (!isCreator) {
      throw const TravelGroupException(
        'Only the group creator can do that.',
        'creator_only',
      );
    }
  }

  void _validateGroupText({required String name, required String description}) {
    if (name.trim().isEmpty || description.trim().isEmpty) {
      throw const TravelGroupException(
        'Complete all required fields.',
        'validation',
      );
    }
    final titleHit = ProfanityFilter.firstProfanity(name);
    if (titleHit != null) {
      throw const TravelGroupException(
        'Group titles cannot contain inappropriate language.',
        'profanity',
      );
    }
    final descriptionHit = ProfanityFilter.firstProfanity(description);
    if (descriptionHit != null) {
      throw const TravelGroupException(
        'Group descriptions cannot contain inappropriate language.',
        'profanity',
      );
    }
  }

  void _validateCapacity(int maxMembers) {
    if (maxMembers < minTravellersPerGroup ||
        maxMembers > maxTravellersPerGroup) {
      throw const TravelGroupException(
        'A travel group allows 2 to 4 travellers.',
        'invalid_capacity',
      );
    }
  }

  Future<TravelGroup> createGroup({
    required String name,
    required TravelGroupPlace destination,
    required String description,
    required List<String> tags,
    required int maxMembers,
    required JoinMode joinMode,
  }) async {
    _requireVerified();
    if (ownedOngoingGroup != null) {
      throw const TravelGroupException(
        'End your current Travel Group before creating another one.',
        'ongoing_group_exists',
      );
    }
    _validateGroupText(name: name, description: description);
    _validateCapacity(maxMembers);
    if (destination.name.trim().isEmpty) {
      throw const TravelGroupException(
        'Complete all required fields.',
        'validation',
      );
    }
    if (tags.isEmpty) {
      throw const TravelGroupException(
        'Choose at least one activity tag.',
        'validation',
      );
    }
    final centerLatitude = areaLatitude;
    final centerLongitude = areaLongitude;
    final distanceKm = centerLatitude != null && centerLongitude != null
        ? _distanceBetween(
                centerLatitude,
                centerLongitude,
                destination.latitude,
                destination.longitude,
              ) /
              1000.0
        : 0.0;
    final group = TravelGroup(
      id: _localId('GROUP'),
      creatorId: currentUser.id,
      creatorName: currentUser.name,
      name: name.trim(),
      destination: destination.name.trim(),
      description: description.trim(),
      meetupPoint: '',
      tags: tags,
      maxMembers: maxMembers,
      distanceKm: distanceKm,
      joinMode: joinMode,
      status: GroupStatus.waiting,
      memberIds: [currentUser.id],
      destinationPlaceId: destination.id,
      destinationAddress: destination.address,
      destinationLatitude: destination.latitude,
      destinationLongitude: destination.longitude,
      destinationPhotoName: destination.photoName,
    );
    final created = await repository.createGroup(group);
    ownedOngoingGroup = created;
    await loadGroups();
    await openGroup(created.id);
    return activeGroup ?? created;
  }

  Future<void> deleteActiveGroup() async {
    _requireCreator();
    final groupId = activeGroup!.id;
    await repository.deleteGroup(groupId);
    groups.removeWhere((group) => group.id == groupId);
    activeGroup = null;
    members = [];
    joinRequests = [];
    suggestions = [];
    itinerary = [];
    activeSession = null;
    if (ownedOngoingGroup?.id == groupId) {
      ownedOngoingGroup = await repository
          .getOngoingGroupCreatedByCurrentUser();
    }
    notifyListeners();
  }

  Future<void> editGroup({
    required String name,
    TravelGroupPlace? destination,
    required String description,
    required int maxMembers,
    required JoinMode joinMode,
  }) async {
    _requireCreator();
    final group = activeGroup!;
    if (group.status != GroupStatus.waiting) {
      throw const TravelGroupException(
        'Group details can only be edited before the trip starts.',
        'edit_locked',
      );
    }
    _validateGroupText(name: name, description: description);
    _validateCapacity(maxMembers);
    if (maxMembers < group.memberCount) {
      throw const TravelGroupException(
        'The group already has more travellers than the new maximum.',
        'capacity_below_members',
      );
    }
    group
      ..name = name.trim()
      ..description = description.trim()
      ..maxMembers = maxMembers
      ..joinMode = joinMode;
    if (destination != null) {
      group
        ..destination = destination.name.trim()
        ..destinationPlaceId = destination.id
        ..destinationAddress = destination.address
        ..destinationLatitude = destination.latitude
        ..destinationLongitude = destination.longitude
        ..destinationPhotoName = destination.photoName;
    }
    await repository.updateGroup(group);
    await loadGroups();
    await refreshWorkspace();
  }

  Future<void> setMeetupPoint({
    required String name,
    required double latitude,
    required double longitude,
    required List<LiveMemberLocation> members,
  }) async {
    _requireCreator();
    if (members.isEmpty) {
      throw const TravelGroupException(
        'Wait for your live location before choosing a meetup point.',
        'not_enough_locations',
      );
    }
    const maximumDistanceMeters = 5000.0;
    for (final member in members) {
      final distance = _distanceBetween(
        latitude,
        longitude,
        member.coordinate.latitude,
        member.coordinate.longitude,
      );
      if (distance > maximumDistanceMeters) {
        throw TravelGroupException(
          'This point is too far from ${member.displayName}. Choose a point within 5 km of every traveller.',
          'meetup_out_of_range',
        );
      }
    }
    await repository.updateMeetupPoint(
      groupId: activeGroup!.id,
      meetupPoint: name.trim().isEmpty ? 'Selected meetup point' : name.trim(),
      latitude: latitude,
      longitude: longitude,
    );
    await refreshWorkspace();
    if (isCreator) await _persistRecalculatedItinerary();
  }

  static double _distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    const earthRadiusMeters = 6371000.0;
    double radians(double degrees) => degrees * 0.017453292519943295;
    final latitudeDelta = radians(endLatitude - startLatitude);
    final longitudeDelta = radians(endLongitude - startLongitude);
    final startLatitudeRadians = radians(startLatitude);
    final endLatitudeRadians = radians(endLatitude);
    final a =
        (math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2)) +
        math.cos(startLatitudeRadians) *
            math.cos(endLatitudeRadians) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  Future<void> joinActiveGroup({required GeoCoordinate location}) async {
    _requireVerified();
    final group = activeGroup!;
    final ownedGroup = ownedOngoingGroup;
    if (ownedGroup != null && ownedGroup.id != group.id) {
      throw TravelGroupException(
        'End ${ownedGroup.name} before joining another travel group.',
        'creator_already_in_group',
      );
    }
    final destinationLatitude = group.destinationLatitude;
    final destinationLongitude = group.destinationLongitude;
    if (destinationLatitude == null || destinationLongitude == null) {
      throw const TravelGroupException(
        'This group has no valid destination location.',
        'destination_location_missing',
      );
    }
    final effective = location;
    final distanceKm =
        _distanceBetween(
          effective.latitude,
          effective.longitude,
          destinationLatitude,
          destinationLongitude,
        ) /
        1000;
    if (distanceKm > maximumJoinDistanceKm) {
      throw TravelGroupException(
        'You are ${distanceKm.toStringAsFixed(1)} km from ${group.destination}. Move within 10 km to join.',
        'outside_destination_radius',
      );
    }
    if (group.joinMode == JoinMode.open) {
      await repository.joinOpenGroup(
        groupId: group.id,
        travellerId: currentUser.id,
        latitude: effective.latitude,
        longitude: effective.longitude,
      );
    } else {
      await repository.requestToJoin(
        groupId: group.id,
        traveller: currentUser,
        latitude: effective.latitude,
        longitude: effective.longitude,
      );
    }
    await refreshWorkspace();
    await loadGroups();
  }

  bool hasPendingRequestForCurrentUser() => joinRequests.any(
    (request) =>
        request.travellerId == currentUser.id &&
        request.status == JoinRequestStatus.pending,
  );

  Future<void> respondToRequest(JoinRequest request, bool accept) async {
    _requireCreator();
    await repository.respondToJoinRequest(
      requestId: request.id,
      accept: accept,
    );
    await refreshWorkspace();
  }

  Future<void> addSuggestion(NearbyPlace place) async {
    if (!isMember) {
      throw const TravelGroupException(
        'Join the lobby before suggesting a stop.',
        'members_only',
      );
    }
    final group = activeGroup!;
    bool samePlace(String? placeId, String placeName) {
      final candidateId = place.placeId?.trim();
      if (candidateId != null &&
          candidateId.isNotEmpty &&
          placeId == candidateId) {
        return true;
      }
      return placeName.trim().toLowerCase() == place.name.trim().toLowerCase();
    }

    if (samePlace(group.destinationPlaceId, group.destination) ||
        suggestions.any(
          (suggestion) => samePlace(suggestion.placeId, suggestion.placeName),
        ) ||
        itinerary.any((stop) => samePlace(stop.placeId, stop.placeName))) {
      throw const TravelGroupException(
        'This place is already part of the group plan.',
        'duplicate_place',
      );
    }

    final suggestion = GroupSuggestion(
      id: _localId('SUGGESTION'),
      groupId: activeGroup!.id,
      suggestedByUserId: currentUser.id,
      placeName: place.name,
      source: place.source,
      category: place.category,
      distanceKm: place.distanceKm,
      crowdLevel: place.crowdLevel,
      durationMinutes: place.durationMinutes,
      tags: place.tags,
      placeId: place.placeId,
      latitude: place.latitude,
      longitude: place.longitude,
    );
    await repository.addSuggestion(suggestion);
    await refreshWorkspace();
  }

  Future<void> vote(GroupSuggestion suggestion, bool isUpvote) async {
    if (!isMember) {
      throw const TravelGroupException(
        'Join the lobby before voting.',
        'members_only',
      );
    }
    await repository.voteSuggestion(
      suggestionId: suggestion.id,
      userId: currentUser.id,
      isUpvote: isUpvote,
    );
    await refreshWorkspace();
  }

  Future<void> confirmSuggestion(GroupSuggestion suggestion) async {
    _requireCreator();
    await repository.confirmSuggestion(suggestion.id);
    await refreshWorkspace();
    if (activeGroup!.status == GroupStatus.waiting) {
      await _persistRecalculatedItinerary();
    }
  }

  Future<void> removeSuggestion(GroupSuggestion suggestion) async {
    if (!isCreator && suggestion.suggestedByUserId != currentUser.id) {
      throw const TravelGroupException(
        'Only the creator or the traveller who suggested this place can remove it.',
        'suggestion_remove_forbidden',
      );
    }
    await repository.removeSuggestion(suggestion.id);
    await refreshWorkspace();
    if (isCreator) await _persistRecalculatedItinerary();
  }

  Future<void> removeStop(ItineraryStop stop) async {
    _requireCreator();
    if (stop.status == StopStatus.current) {
      throw const TravelGroupException(
        'The active destination cannot be removed during navigation.',
        'active_stop',
      );
    }
    await repository.removeItineraryStop(
      groupId: activeGroup!.id,
      stopId: stop.id,
    );
    await refreshWorkspace();
    await _persistRecalculatedItinerary();
  }

  Future<void> reorderStops(int oldIndex, int newIndex) async {
    _requireCreator();
    final reordered = [...itinerary];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    _recalculateLegs(reordered);
    await repository.reorderItinerary(activeGroup!.id, reordered);
    await refreshWorkspace();
  }

  void _recalculateLegs(List<ItineraryStop> stops) {
    double? previousLatitude = activeGroup?.meetupLatitude;
    double? previousLongitude = activeGroup?.meetupLongitude;
    for (var index = 0; index < stops.length; index++) {
      final stop = stops[index];
      stop.position = index;
      final latitude = stop.latitude;
      final longitude = stop.longitude;
      if (previousLatitude == null ||
          previousLongitude == null ||
          latitude == null ||
          longitude == null) {
        stop
          ..travelDistanceFromPreviousKm = 0
          ..travelTimeFromPreviousMinutes = 0;
      } else {
        final directKm =
            _distanceBetween(
              previousLatitude,
              previousLongitude,
              latitude,
              longitude,
            ) /
            1000;
        final estimatedDrivingKm = directKm * 1.25;
        stop
          ..travelDistanceFromPreviousKm = estimatedDrivingKm
          ..travelTimeFromPreviousMinutes = math.max(
            1,
            (estimatedDrivingKm / 30 * 60).round(),
          );
      }
      previousLatitude = latitude;
      previousLongitude = longitude;
    }
  }

  Future<void> _persistRecalculatedItinerary() async {
    if (itinerary.isEmpty || activeGroup!.status != GroupStatus.waiting) return;
    _recalculateLegs(itinerary);
    await repository.reorderItinerary(activeGroup!.id, itinerary);
    await refreshWorkspace();
  }

  Future<void> startItinerary() async {
    _requireCreator();
    if (activeGroup!.memberCount < minTravellersPerGroup) {
      throw const TravelGroupException(
        'At least two travellers must join before the group trip can start.',
        'not_enough_members',
      );
    }
    await repository.startItinerary(activeGroup!.id);
    activeTripStartedAt = DateTime.now();
    await refreshWorkspace();
  }

  Future<void> confirmGroup() async {
    _requireCreator();
    activeSession = await repository.confirmGroup(activeGroup!.id);
    await refreshWorkspace();
  }

  Future<void> completeStop(ItineraryStop stop) async {
    _requireCreator();
    await repository.markStopCompleted(
      groupId: activeGroup!.id,
      stopId: stop.id,
    );
    await refreshWorkspace();
  }

  Future<void> endTrip() async {
    _requireCreator();
    final groupId = activeGroup!.id;
    await repository.endTrip(groupId);
    await refreshWorkspace();
    if (ownedOngoingGroup?.id == groupId) {
      ownedOngoingGroup = await repository
          .getOngoingGroupCreatedByCurrentUser();
    }
    notifyListeners();
  }

  String _localId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${++_localIdSequence}';
}
