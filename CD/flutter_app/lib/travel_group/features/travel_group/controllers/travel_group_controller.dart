import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/travel_group_models.dart';
import '../repositories/travel_group_repository.dart';
import '../services/live_trip_location_service.dart';

class TravelGroupController extends ChangeNotifier {
  TravelGroupController({
    required this.repository,
    this.liveTripLocationServiceFactory = createMockLiveTripLocationService,
  }) {
    currentUser = demoUsers.first;
  }

  final TravelGroupRepository repository;
  final LiveTripLocationServiceFactory liveTripLocationServiceFactory;

  final List<PrototypeUser> demoUsers = [
    PrototypeUser(id: 'USER_100', name: 'Aina Sofea', isVerified: true),
    PrototypeUser(id: 'USER_500', name: 'Unverified Guest', isVerified: false),
  ];

  late PrototypeUser currentUser;
  List<TravelGroup> groups = [];
  TravelGroup? activeGroup;
  List<JoinRequest> joinRequests = [];
  List<GroupSuggestion> suggestions = [];
  List<ItineraryStop> itinerary = [];
  DateTime? activeTripStartedAt;
  double radiusKm = 10;
  String selectedArea = 'Bukit Bintang, Kuala Lumpur';
  String keyword = '';
  bool openOnly = false;
  bool isLoading = false;

  bool get isCreator => activeGroup?.creatorId == currentUser.id;
  bool get isMember => activeGroup?.memberIds.contains(currentUser.id) ?? false;

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
    );
  }

  void switchUser(PrototypeUser user) {
    currentUser = user;
    notifyListeners();
  }

  void completeDemoVerification() {
    currentUser.isVerified = true;
    notifyListeners();
  }

  Future<void> loadGroups() async {
    isLoading = true;
    notifyListeners();
    groups = await repository.getNearbyGroups(
      radiusKm: radiusKm,
      keyword: keyword,
      openOnly: openOnly,
    );
    isLoading = false;
    notifyListeners();
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

  Future<void> setArea(String value) async {
    if (selectedArea == value) return;
    selectedArea = value;
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
    joinRequests = await repository.getJoinRequests(group.id);
    suggestions = await repository.getSuggestions(group.id);
    itinerary = await repository.getItinerary(group.id);
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

  Future<TravelGroup> createGroup({
    required String name,
    required TravelGroupPlace destination,
    required String description,
    required List<String> tags,
    required int maxMembers,
    required JoinMode joinMode,
  }) async {
    _requireVerified();
    if (name.trim().isEmpty ||
        destination.name.trim().isEmpty ||
        description.trim().isEmpty) {
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
    final group = TravelGroup(
      id: 'GROUP_${DateTime.now().microsecondsSinceEpoch}',
      creatorId: currentUser.id,
      creatorName: currentUser.name,
      name: name.trim(),
      destination: destination.name.trim(),
      description: description.trim(),
      meetupPoint: '',
      tags: tags,
      maxMembers: maxMembers,
      distanceKm: 0.6,
      joinMode: joinMode,
      status: GroupStatus.waiting,
      memberIds: [currentUser.id],
      destinationPlaceId: destination.id,
      destinationAddress: destination.address,
      destinationLatitude: destination.latitude,
      destinationLongitude: destination.longitude,
      destinationPhotoName: destination.photoName,
    );
    await repository.createGroup(group);
    await loadGroups();
    await openGroup(group.id);
    return group;
  }

  Future<void> setMeetupPoint({
    required String name,
    required double latitude,
    required double longitude,
    required List<LiveMemberLocation> members,
  }) async {
    _requireCreator();
    if (members.length < 2) {
      throw const TravelGroupException(
        'Wait for at least one other traveller to share their location.',
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

  Future<void> joinActiveGroup() async {
    _requireVerified();
    final group = activeGroup!;
    if (group.joinMode == JoinMode.open) {
      await repository.joinOpenGroup(
        groupId: group.id,
        travellerId: currentUser.id,
      );
    } else {
      await repository.requestToJoin(groupId: group.id, traveller: currentUser);
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
    final suggestion = GroupSuggestion(
      id: 'SUGGESTION_${DateTime.now().microsecondsSinceEpoch}',
      groupId: activeGroup!.id,
      suggestedByUserId: currentUser.id,
      placeName: place.name,
      source: place.source,
      category: place.category,
      distanceKm: place.distanceKm,
      crowdLevel: place.crowdLevel,
      durationMinutes: place.durationMinutes,
      tags: place.tags,
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
  }

  Future<void> reorderStops(int oldIndex, int newIndex) async {
    _requireCreator();
    final reordered = [...itinerary];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    await repository.reorderItinerary(
      activeGroup!.id,
      reordered.map((stop) => stop.id).toList(),
    );
    await refreshWorkspace();
  }

  Future<void> startItinerary() async {
    _requireCreator();
    await repository.startItinerary(activeGroup!.id);
    activeTripStartedAt = DateTime.now();
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
}
