# Create Post test cases

Run these cases through the main application's authenticated Profile Travel History integration. Use a real persisted Supabase solo or group history row and press its Create Post or Edit Post action. Itinerary stops are not separate Community post sources. This module contains no standalone login, sample-history screen, or review-only endpoint.

## Success cases

| ID | Trip location | Input/action | Expected result |
|---|---|---|---|
| S1 | Kuala Lumpur | Title: `Morning in Kuala Lumpur`; Description: `Kuala Lumpur has colourful heritage lanes to explore before breakfast.`; add one valid JPG | Approved and created once; displayed history destination remains locked; tags are assigned from location rules. |
| S2 | TAR UMT, Kuala Lumpur | Title: `TARUMT`; Description: `I love TARUMT`; add one valid JPG | Approved: joined and spaced forms of the same complete place name are equivalent. |
| S3 | KLCC Park, Kuala Lumpur | Meaningful title/description mentioning KLCC Park; add six JPG/PNG files, each at most 10 MB | Approved with all six images; gallery can page horizontally. |
| S4 | Jalan Alor, Kuala Lumpur | Use the same neutral text style as S1 but mention Jalan Alor; add a portrait PNG | Approved; Restaurant/Local Cuisine tags come from Google Places/location rules, not from post wording; previews have no grey letterboxing and the complete image remains available in the full-screen viewer. |
| S5 | Persisted history row with an existing owner post | Open the Travel History action, edit title/description, keep existing images | Edit form opens; the same post is updated and no second post is created. |
| S6 | Kuala Lumpur | Include an allow-listed word such as `Scunthorpe` while still clearly describing Kuala Lumpur | Approved; substring matching does not create a false profanity result. |

## Failure cases

| ID | Input/action | Expected result/code |
|---|---|---|
| F1 | Title has fewer than 3 characters | Rejected: `INVALID_LENGTH`; title field error. |
| F2 | Description has fewer than 10 characters | Rejected: `INVALID_LENGTH`; description field error. |
| F3 | Description includes a configured dirty word | Rejected: `INAPPROPRIATE_LANGUAGE`; nothing is inserted. |
| F4 | Use disguised profanity such as separated letters or leetspeak | Rejected: `INAPPROPRIATE_LANGUAGE`. |
| F5 | Repeat one word many times or use unreadable repeated characters | Rejected: `LOW_QUALITY_TEXT`. |
| F6 | Include any URL in the title or description (`https://`, `www.`, or a plain domain) | Rejected: `LINK_NOT_ALLOWED`; no post is inserted. |
| F7 | Submit Langkawi-only text for a locked Kuala Lumpur trip | Rejected: `LOCATION_MISMATCH`. |
| F7a | Mention the locked location in only the title or only the description | Rejected: `LOCATION_MISMATCH` on the field that does not relate to the trip. |
| F8 | Submit without an image, with seven images, WebP, or an image over 10 MB | Rejected before publishing with the relevant image message. |
| F9 | Use a local demo/fallback history card | No Create Post action is shown because the entry does not exist in Supabase. |
| F9a | Use a persisted group-history row | Create/Edit Post is available with the same validation as a solo-history row. |
| F10 | Try to create a second post for the same history row | Travel History opens Edit; a direct duplicate create is rejected by the private RPC/unique constraint. |
| F11 | Try to edit another user's post | Edit is hidden; direct API attempt is rejected as author-only. |
| F12 | Stop the Node validator and press Publish | Publishing is blocked; Retry/unavailable message appears; temporary uploaded images are cleaned up. |
| F13 | Remove the configured fallback/location mappings | Publishing is blocked: `TAG_CONFIGURATION_MISSING`; Flutter never guesses a tag. |
| F14 | Send no JWT or an expired JWT | Rejected: `UNAUTHENTICATED`; no write RPC is called. |

## Synchronization checks after a successful post

1. Open the post in two authenticated sessions.
2. Like and comment from session A; confirm session B refreshes through Supabase Realtime.
3. Bookmark from session A; confirm it appears under Profile saved posts and opens the same post.
4. Tap the location; confirm `onStartJourney` receives the post ID, attraction, and destination.
5. Open each image full screen; verify swipe, pinch/double-tap zoom, pan, and X dismissal.
6. Confirm authors cannot bookmark their own posts.
7. Confirm a comment author can delete their comment, a post author can delete comments on their post, and only a post author can delete that post.

## Automated coverage

Run `npm test` inside `server/`. It covers successful create, missing images, dirty/disguised language, ineligible history rows, authentication, short text, links, spam, unrelated locations, allow-list behavior, Google Places/location-only tag assignment, and rejection of unmapped types. Run `flutter test` for the production-facing Community feed and integration surface.
