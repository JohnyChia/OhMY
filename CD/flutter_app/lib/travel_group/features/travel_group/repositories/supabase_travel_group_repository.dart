import 'travel_group_repository.dart';

/// Integration seam for the future Supabase implementation.
///
/// Keep this adapter abstract until the project has its Supabase tables and
/// generated row types. The screens and controller only depend on
/// [TravelGroupRepository], so the app bootstrap can later replace
/// `MockTravelGroupRepository.seeded()` with a concrete implementation of
/// this class without changing any UI code.
abstract class SupabaseTravelGroupRepository implements TravelGroupRepository {
  const SupabaseTravelGroupRepository(this.client);

  /// Deliberately typed as Object so this prototype does not require
  /// `supabase_flutter` before the backend contract is ready.
  final Object client;

  /// Suggested table mapping:
  ///
  /// - travel_groups -> [TravelGroup]
  /// - travel_group_members -> TravelGroup.memberIds
  /// - travel_group_tags -> TravelGroup.tags
  /// - travel_group_join_requests -> [JoinRequest]
  /// - travel_group_suggestions -> [GroupSuggestion]
  /// - travel_group_suggestion_votes -> vote sets
  /// - travel_group_itinerary_stops -> [ItineraryStop]
}
