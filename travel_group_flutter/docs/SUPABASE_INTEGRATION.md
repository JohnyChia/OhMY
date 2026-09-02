# Supabase integration

The standalone prototype still runs without Supabase. For the shared team
database, run `docs/SUPABASE_TRAVEL_GROUP_SETUP.sql`. It is additive: it keeps
the existing personal `itineraries`, `trip_states`, AI chat tables, places and
tag tables unchanged.

Then add `supabase_flutter`, make a concrete
`SupabaseTravelGroupRepository`, and pass it to `TravelGroupController` in
`lib/main.dart`.

## Suggested tables

| Table | Purpose | Important constraint |
| --- | --- | --- |
| `travel_groups` | Group metadata, join mode and status | Creator references `auth.users` |
| `travel_group_members` | Membership and builder role | Unique `(group_id, user_id)` |
| `travel_group_join_requests` | Pending/accepted/declined requests | One pending request per traveller/group |
| `travel_group_suggestions` | Suggested locations | Unique normalized place per group |
| `travel_group_suggestion_votes` | One up/down vote per user | Unique `(suggestion_id, user_id)` |
| `travel_group_itinerary_stops` | Visit/Eat/Rest builder cards | Unique `(group_id, position)` |

## Repository-to-query mapping

- `getNearbyGroups` -> group select/RPC with distance, keyword and tag filters
- `joinOpenGroup` -> transaction/RPC checking capacity and membership
- `requestToJoin` -> insert with pending-request uniqueness
- `respondToJoinRequest` -> transaction/RPC updating request and membership
- `voteSuggestion` -> upsert one vote row
- `confirmSuggestion` -> transaction/RPC confirming and appending a stop
- `reorderItinerary` -> transaction/RPC updating every position
- `startItinerary` and `markStopCompleted` -> transaction/RPC state transitions

Use Row Level Security so only verified users can create/join, only members can
read a lobby and vote, and only the creator can accept requests or mutate the
itinerary.

The unified migration also creates the active-map session, participant and
live-location tables, their RLS policies, and Realtime publication entries.
`docs/SUPABASE_LIVE_TRIP_SETUP.sql` remains available only for teams that
already have their own group/planning tables; do not run both migrations.
