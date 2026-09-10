# Community Discovery integration

This package contains the Flutter Community Discovery feature, its private Node.js validation service, and additive Supabase migrations. It contains no login UI, sample Trip History, review-only screen, or standalone test navigation. The host application owns authentication, Profile, Trip History, Start Journey, and bottom navigation.

## 1. Apply Supabase migrations

Apply every file in `supabase/migrations/` in filename order. The migrations create only `community_*` structures, except for read-only references to the existing shared trip and `tags` tables. `202609100004_filter_tags_rpc.sql` exposes existing shared tags through `get_filter_tags_v1()` without inserting, updating, deleting, or changing RLS on `tags`.

`202609100005_remove_legacy_review_rpcs.sql` removes the obsolete SQL review-preview and v2/v3 client write functions after the private Node/v4 path is installed. Apply it even when earlier migrations were already run.

The final write path is service-only:

- Flutter cannot execute `community_create_post_v4` or `community_update_post_v4`.
- Node verifies the user's bearer JWT and calls the private v4 RPCs with the server secret.
- Supabase enforces completed-trip participation, one post per trip, and author-only editing.

Enable Supabase Realtime for `community_posts`, `community_post_likes`, `community_post_bookmarks`, and `community_post_comments`.

## 2. Deploy the Node service

The Community validator is an isolated service under
`backend/community_validation/`. From that folder run:

```text
npm install
npm test
npm run build
npm start
```

Configure only server-side values in an uncommitted environment file or the deployment platform's secret manager:

```text
PORT=3000
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVER_ONLY_SECRET
GOOGLE_PLACES_API_KEY=YOUR_RESTRICTED_SERVER_KEY  # optional
ALLOWED_ORIGINS=https://your-web-app.example      # optional for mobile-only use
```

The Community service does not consume Groq, Maps Browser, Weather, or Routes keys. Never place the Supabase server secret or Google server key in Flutter, Android resources, source control, or Figma. Confirm `GET /health` returns `{"ok":true}` after deployment.

Production endpoints are:

- `POST /community/posts` — validate and create a post.
- `PATCH /community/posts/:postId` — validate and edit an owner post.

Both require `Authorization: Bearer <Supabase access token>`. There is intentionally no public validation-preview endpoint. Create and edit fail closed when validation or tag configuration is unavailable.

## 3. Configure Flutter

Flutter receives public configuration only:

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR_PUBLISHABLE_KEY",
  "COMMUNITY_API_URL": "https://YOUR_COMMUNITY_API"
}
```

The existing recommendation backend already defaults to port `3000`. When both
services run locally, set the Community validator to `PORT=3001` and use
`http://10.0.2.2:3001` in Flutter. A physical phone needs the computer's
reachable LAN address. Use HTTPS after deployment.

Create the module objects after the host app has initialized Supabase and restored its authenticated session:

```dart
final communityRepository = SupabaseCommunityRepository(
  Supabase.instance.client,
  communityApiUrl: communityApiUrl,
);
final communityController = CommunityController(communityRepository);
```

The host owns the controller lifecycle and must call `dispose()` when its feature scope ends. `CommunityApp` remains available as a standalone shell, while an integrated app can render `CommunityFeedScreen` with the shared controller and callbacks.

## 4. Trip History create/edit

Only render a Community action for a completed trip. On tap call:

```dart
await openTripHistoryPostAction(
  context,
  controller: communityController,
  tripSessionId: trip.id,
);
```

The entrypoint calls `community_post_id_for_trip_v4`: no post opens Create; an existing owner post opens Edit. Create Post locks its destination and attraction to the supplied completed-trip ID and does not allow choosing another trip. The server rechecks eligibility, so the hidden/visible button is not the security boundary.

Publishing requires 1–6 JPG/JPEG/PNG images, at most 10 MB each. Node validates title and description for length, meaningfulness, repetition, abusive/obfuscated language, links, and relevance to the locked trip location. Any link is rejected. Tags are assigned separately from destination, attraction, database aliases/rules, and optional Google Places types; post text never selects tags.

## 5. Profile bookmarks

For a full saved-post page:

```dart
await openCommunityBookmarks(
  context,
  controller: communityController,
  integrationCallbacks: callbacks,
);
```

To embed bookmarks inside Profile, render `SavedPostsSection`. Selecting a bookmark opens its original post.

## 6. Start Journey callback

Pass the host route through `CommunityIntegrationCallbacks`:

```dart
final callbacks = CommunityIntegrationCallbacks(
  onStartJourney: (request) {
    // Open the host Start Journey module using:
    // request.postId
    // request.attractionName
    // request.destinationName
  },
);
```

The tappable location on Post Details invokes this callback. The host should prefill the destination/attraction but retain its own journey validation.

## 7. Authentication and ownership

The host must sign the user in through its existing authentication flow before Community operations that mutate user data. This module deliberately has no credential fields. Likes, bookmarks, comments, create, and edit use the current Supabase session. Comments are limited to 500 characters and author identity comes from the authenticated server/database context rather than Flutter input.

## 8. Operational configuration

Manage blocked terms, allow-list entries, location aliases, tag rules, and fallback tag through the community-owned Supabase configuration tables. Do not modify the shared `tags` table from this module. Google Places failure falls back to database mappings.

Image-location moderation is not implemented. A future system may combine EXIF GPS, Places metadata, optional server-side vision, and manual review for uncertain images.

## 9. Handoff checklist

- Apply migrations in order and confirm all expected functions exist.
- Deploy Node and verify `/health` without logging secrets.
- Confirm Flutter contains only URL, publishable key, and API URL.
- Wire the host's existing authenticated Supabase client.
- Add Community to the host navigation.
- Wire Trip History with `openTripHistoryPostAction`.
- Wire Profile with `openCommunityBookmarks` or `SavedPostsSection`.
- Wire `onStartJourney` to the host journey route.
- Enable Realtime for posts, likes, bookmarks, and comments.
- Run `npm test`, `npm run build`, `flutter analyze`, `flutter test`, and `flutter build apk --debug`.
- Test two signed-in sessions for comment/like synchronization and duplicate-submission protection.
- Test completed/unposted → Create, completed/posted → Edit, and incomplete → no action.
- Test portrait/landscape galleries, full-screen paging, pinch/double-tap zoom, pan, and X dismissal.
- When sharing the folder directly instead of through Git, exclude `backend/community_validation/.env`, `flutter_app/config/community.env.json`, and `flutter_app/android/local.properties`; each is machine-specific and ignored by Git.

Detailed publishing cases remain in `CREATE_POST_TEST_CASES.md`.
