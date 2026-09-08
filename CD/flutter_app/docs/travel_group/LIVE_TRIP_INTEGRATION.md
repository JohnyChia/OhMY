# Shared live trip map

The Figma placement is `Travel Group • Active Itinerary Map` (`2524:1335`),
with the final-stop state at `2533:1218`. It opens immediately after the group
creator starts the itinerary. Every participant sees the same session, route,
current stop and group presence; only the creator advances stop progress.

The standalone prototype keeps that UI and uses
`LiveTripLocationService`. Its default mock implementation moves all seeded
members around the Kuala Lumpur route while the signed-in prototype user can
publish the emulator/device GPS position.

## Tables to create now

For the current team database, run `docs/SUPABASE_TRAVEL_GROUP_SETUP.sql` in
the Supabase SQL editor. It creates the collaborative planning tables and these
three live-map tables:

1. `travel_group_trip_sessions` — one shared active session, route and current
   stop for the whole group.
2. `travel_group_trip_participants` — the exact members allowed into that
   session, including display data and sharing preference.
3. `travel_group_live_locations` — one replaceable last-known-location row per
   participant. It deliberately does not retain location history.

The migration is additive and leaves the existing personal itinerary, AI chat,
place and preference tables unchanged. Its trip sessions already reference the
new `travel_groups` table, and accepted `travel_group_members` should be copied
into trip participants by the start-trip transaction or RPC.

The smaller `SUPABASE_LIVE_TRIP_SETUP.sql` is retained only for a database that
already owns equivalent group, suggestion and itinerary tables. Do not run both
setup files.

## Runtime sequence

1. The creator taps **Start group itinerary**.
2. In one server transaction, create the session and copy accepted group
   members into `travel_group_trip_participants`.
3. Every client subscribes to the session row, participant rows and live
   location rows filtered by `session_id`.
4. Each client upserts only its own location approximately every 5–10 seconds
   or after moving 10–20 metres.
5. The creator updates `current_stop_id` and `current_stop_index`; Realtime
   moves every member to the same next/final-stop UI.
6. On completion or cancellation, set `ended_at`, stop device location streams,
   and delete live-location rows after a short grace period.

## Flutter adapter

Add `supabase_flutter` only after the URL, anon key and authentication flow are
ready. Implement `LiveTripLocationService` with:

- a Realtime subscription to `travel_group_live_locations` for the current
  `session_id`;
- an upsert keyed by `(session_id, user_id)` for the signed-in user;
- channel removal and a final `sharing_enabled = false` update in `dispose`.

Pass that implementation through `TravelGroupController`'s
`liveTripLocationServiceFactory`. No active-map widget needs to change.

## Privacy and prototype boundaries

- Location sharing begins only for an active session and should be opt-in.
- Show stale state after 30 seconds and remove a marker after a longer timeout.
- Do not expose the live tables to non-participants; the supplied SQL enables
  RLS for this reason.
- Do not use a Supabase service-role key in Flutter.
- The SQL allows the creator to seed participants. In the final backend, the
  start-trip RPC must verify the creator and accepted group membership before
  inserting those rows.
