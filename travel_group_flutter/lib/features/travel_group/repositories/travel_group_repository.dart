import '../models/travel_group_models.dart';

abstract interface class TravelGroupRepository {
  Future<List<TravelGroup>> getNearbyGroups({
    required double radiusKm,
    List<String> tags = const [],
    String keyword = '',
    bool openOnly = false,
  });

  Future<TravelGroup?> getGroup(String groupId);
  Future<TravelGroup> createGroup(TravelGroup group);
  Future<void> joinOpenGroup(
      {required String groupId, required String travellerId});
  Future<JoinRequest> requestToJoin(
      {required String groupId, required PrototypeUser traveller});
  Future<List<JoinRequest>> getJoinRequests(String groupId);
  Future<void> respondToJoinRequest(
      {required String requestId, required bool accept});
  Future<List<GroupSuggestion>> getSuggestions(String groupId);
  Future<GroupSuggestion> addSuggestion(GroupSuggestion suggestion);
  Future<void> voteSuggestion(
      {required String suggestionId,
      required String userId,
      required bool isUpvote});
  Future<ItineraryStop> confirmSuggestion(String suggestionId);
  Future<List<ItineraryStop>> getItinerary(String groupId);
  Future<void> reorderItinerary(String groupId, List<String> orderedStopIds);
  Future<void> startItinerary(String groupId);
  Future<void> markStopCompleted(
      {required String groupId, required String stopId});
}
