import '../models/travel_group_models.dart';

abstract interface class TravelGroupRepository {
  Future<List<TravelGroup>> getNearbyGroups({
    required double radiusKm,
    List<String> tags = const [],
    String keyword = '',
    bool openOnly = false,
  });

  Future<TravelGroup?> getGroup(String groupId);
  Future<List<GroupMemberProfile>> getMembers(String groupId);
  Future<TravelGroup> createGroup(TravelGroup group);
  Future<void> deleteGroup(String groupId);
  Future<void> updateGroup(TravelGroup updated);
  Future<void> updateMeetupPoint({
    required String groupId,
    required String meetupPoint,
    required double latitude,
    required double longitude,
  });
  Future<int> simulateDemoMembersTowardMeetup({
    required String sessionId,
    required double latitude,
    required double longitude,
    bool resetPositions = false,
  });
  Future<void> joinOpenGroup({
    required String groupId,
    required String travellerId,
    required double latitude,
    required double longitude,
  });
  Future<JoinRequest> requestToJoin({
    required String groupId,
    required PrototypeUser traveller,
    required double latitude,
    required double longitude,
  });
  Future<List<JoinRequest>> getJoinRequests(String groupId);
  Future<void> respondToJoinRequest({
    required String requestId,
    required bool accept,
  });
  Future<List<GroupSuggestion>> getSuggestions(String groupId);
  Future<GroupSuggestion> addSuggestion(GroupSuggestion suggestion);
  Future<void> removeSuggestion(String suggestionId);
  Future<void> voteSuggestion({
    required String suggestionId,
    required String userId,
    required bool isUpvote,
  });
  Future<ItineraryStop> confirmSuggestion(String suggestionId);
  Future<List<ItineraryStop>> getItinerary(String groupId);
  Future<void> removeItineraryStop({
    required String groupId,
    required String stopId,
  });
  Future<void> reorderItinerary(String groupId, List<ItineraryStop> stops);
  Future<TravelGroupTripSession> confirmGroup(String groupId);
  Future<TravelGroupTripSession?> getActiveTripSession(String groupId);
  Future<void> startItinerary(String groupId);
  Future<void> markStopCompleted({
    required String groupId,
    required String stopId,
  });
  Future<void> endTrip(String groupId);
}
