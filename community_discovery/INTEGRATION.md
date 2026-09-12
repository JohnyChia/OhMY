# Community Discovery integration

This package contains the Flutter Community Discovery feature, its private Node.js validation service, and additive Supabase migrations. It contains no login UI, sample Trip History, review-only screen, or standalone test navigation. The host application owns authentication, Profile, Trip History, Start Journey, and bottom navigation.

## 1. Apply Supabase migrations

Apply `CD/supabase/migrations/20260911_travel_history.sql` first, then every file in this package's `supabase/migrations/` in filename order. The Community migrations change only Community-owned structures. They read `travel_history_entries` and `tags` but never update either shared table. `202609100004_filter_tags_rpc.sql` exposes shared tags through `get_filter_tags_v1()` without changing their RLS.

`202609100005_remove_legacy_review_rpcs.sql` removes the obsolete SQL review-preview and v2/v3 client write functions. `202609110002_travel_history_integration_v5.sql` installs the Travel History link and private Node/v5 path. `202609120001_all_history_post_eligibility.sql` then enables both solo and group history rows and updates the legacy post trigger. `202609120002_community_ownership_controls.sql` fixes Auth usernames, prevents self-bookmarks, and adds owner deletion RPCs. `202609120003_comment_spam_controls.sql` adds a server-enforced five-minute cooldown for each user/post combination and duplicate protection. `202609120004_google_place_tag_mappings.sql` maps current Google Places types to existing tags and corrects legacy TAR UMT posts. Apply all six even when earlier migrations were already run.

The final write path is service-only:

- Flutter cannot execute `community_create_post_v5` or `community_update_post_v5`.
- Node verifies the user's bearer JWT and calls the private v5 RPCs with the server secret.
- Supabase verifies ownership of the Profile Travel History row for both solo and group history, enforces one post per history entry, and permits author-only editing.

Enable Supabase Realtime for `community_posts`, `community_post_likes`, `community_post_bookmarks`, and `community_post_comments`.

## 2. Deploy the Node service

From `server/` run:

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

## 3. Configure and embed Flutter

Flutter receives public configuration only:

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR_PUBLISHABLE_KEY",
  "COMMUNITY_API_URL": "https://YOUR_COMMUNITY_API"
}
```

For local Android Emulator testing use `http://10.0.2.2:3000`. A physical phone needs the computer's reachable LAN address. Use HTTPS after deployment.

Create the module objects after the host app has initialized Supabase and restored its authenticated session:

```dart
final communityRepository = SupabaseCommunityRepository(
  Supabase.instance.client,
  communityApiUrl: communityApiUrl,
);
final communityController = CommunityController(communityRepository);
```

The integrated OhMY application uses the package through this path dependency:

```yaml
community_discovery:
  path: ../../community_discovery
```

Import only `package:community_discovery/community_discovery.dart`. The host owns one controller shared by the Community tab, Profile bookmarks, and Travel History, and calls `dispose()` when the shell ends.

## 4. Trip History create/edit

Render a Community action for every persisted Supabase `travel_history_entries` row, including both `solo` and `group` history. Itinerary stops and local fallback/demo cards must not expose the action. Convert the host history model into the public Community model and call:

```dart
await openTripHistoryPostAction(
  context,
  controller: communityController,
  historyEntry: CompletedTrip(
    id: trip.id,
    title: trip.title,
    locationName: trip.destination,
    attractionName: trip.destination,
    completedAt: trip.completedAt,
  ),
);
```

The entrypoint calls `community_post_id_for_history_v5`: no post opens Create; an existing owner post opens Edit. Create Post locks the location to the history row's displayed `destination`. The presence of the owned database history row is sufficient eligibility; Community does not inspect a separate status table or its itinerary stops. The server rechecks ownership, so button visibility is not the security boundary.

Publishing requires 1–6 JPG/JPEG/PNG images, at most 10 MB each. Node validates title and description separately for length, meaningfulness, repetition, abusive/obfuscated language, links, and relevance to the locked trip location. Both fields must relate to that location. Spaced and joined forms of the same complete location name (for example, `TAR UMT` and `TARUMT`) are equivalent. Any link is rejected. Tags are assigned separately from the Google Places types for the locked destination/attraction and explicit database location rules; post text never selects tags.

## 5. Profile bookmarks

For a full saved-post page:

```dart
await openCommunityBookmarks(
  context,
  controller: communityController,
  integrationCallbacks: callbacks,
);
```

To embed bookmarks inside Profile, render `SavedPostsSection`. Selecting a bookmark opens its original post. Authors cannot bookmark their own posts; the Flutter control is hidden and Supabase rejects direct self-bookmark inserts.

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

The host must sign the user in through its existing authentication flow before Community operations that mutate user data. This module deliberately has no credential fields. Likes, bookmarks, comments, create, edit, and delete use the current Supabase session. Comments are limited to 500 characters and author identity comes from the authenticated server/database context rather than Flutter input. Comment authors can delete their own comments; a post author can moderate comments on their post and permanently delete the post.

## 8. Operational configuration

Manage blocked terms, allow-list entries, location aliases, and tag rules through the community-owned Supabase configuration tables. Do not modify the shared `tags` table from this module. Google Places failure can use an explicit location rule; otherwise publishing fails closed instead of assigning a generic category.

Image-location moderation is not implemented. A future system may combine EXIF GPS, Places metadata, optional server-side vision, and manual review for uncertain images.

## 9. Handoff checklist

- Apply migrations in order and confirm all expected functions exist.
- Deploy Node and verify `/health` without logging secrets.
- Confirm Flutter contains only URL, publishable key, and API URL.
- Wire the host's existing authenticated Supabase client.
- Add Community to the host navigation.
- Wire every persisted solo or group Profile Travel History row with `openTripHistoryPostAction`.
- Wire Profile with `openCommunityBookmarks` or `SavedPostsSection`.
- Wire `onStartJourney` to the host journey route.
- Enable Realtime for posts, likes, bookmarks, and comments.
- Run `npm test`, `npm run build`, `flutter analyze`, `flutter test`, and `flutter build apk --debug`.
- Test two signed-in sessions for comment/like synchronization and duplicate-submission protection.
- Test persisted solo/group unposted → Create, persisted solo/group posted → Edit, and demo/fallback → no action.
- Test portrait/landscape galleries, full-screen paging, pinch/double-tap zoom, pan, and X dismissal.
- When sharing the folder directly instead of through Git, exclude `server/.env`, `config/flutter.env.json`, and `android/local.properties`; each is machine-specific and ignored by Git.

Detailed publishing cases remain in `CREATE_POST_TEST_CASES.md`.
