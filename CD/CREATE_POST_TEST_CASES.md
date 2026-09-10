# Create Post test cases

Run these cases through the main application's authenticated Trip History integration. Use a completed Trip History row and press its Create Post or Edit Post action; this module no longer contains a standalone login, sample-history screen, or review-only endpoint.

## Success cases

| ID | Trip location | Input/action | Expected result |
|---|---|---|---|
| S1 | Kwai Chai Hong, Kuala Lumpur | Title: `Morning at Kwai Chai Hong`; Description: `Kwai Chai Hong in Kuala Lumpur has colourful heritage lanes before breakfast.`; add one valid JPG | Approved and created once; location remains locked; Heritage-related tags are assigned from location rules. |
| S2 | KLCC Park, Kuala Lumpur | Meaningful title/description mentioning KLCC Park; add six JPG/PNG files, each at most 10 MB | Approved with all six images; gallery can page horizontally. |
| S3 | Jalan Alor, Kuala Lumpur | Use the same neutral text style as S1 but mention Jalan Alor; add a portrait PNG | Approved; Restaurant/Local Cuisine tags come from Jalan Alor, not from post wording; portrait is cropped in feed and complete in details. |
| S4 | Completed trip with an existing owner post | Open the Trip History action, edit title/description, keep existing images | Edit form opens; the same post is updated and no second post is created. |
| S5 | Kuala Lumpur | Include an allow-listed word such as `Scunthorpe` while still clearly describing Kuala Lumpur | Approved; substring matching does not create a false profanity result. |

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
| F8 | Submit without an image, with seven images, WebP, or an image over 10 MB | Rejected before publishing with the relevant image message. |
| F9 | Use an unfinished trip | No Create Post action in production; direct API attempt is rejected: `TRIP_NOT_ELIGIBLE`. |
| F10 | Try to create a second post for the same completed trip | Trip History opens Edit; a direct duplicate create is rejected by the private RPC/unique constraint. |
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

## Automated coverage

Run `npm test` inside `server/`. It covers successful create, missing images, dirty/disguised language, invalid trip status, authentication, short text, links, spam, unrelated locations, allow-list behavior, location-only tag assignment, and fallback tags. Run `flutter test` for the production-facing Community feed and integration surface.
