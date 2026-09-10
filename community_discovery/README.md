# UC600 Community Discovery

Android-ready Flutter community module backed by Supabase and a secured TypeScript/Express validation service. It intentionally excludes unrelated application modules.

## Included

- Supabase feed, search, loading/error/empty states, and OR-based multi-tag filtering from every row in the existing shared `tags` table. No separate Community tag table is created.
- One to six JPG/JPEG/PNG images per post, maximum 10 MB each.
- Consistent cropped feed previews, uncropped portrait display in details, and a dark full-screen pager with pinch/double-tap zoom, pan, and X dismissal.
- Post details ordered image → title → actionable location → description → reactions → comments.
- Synced likes, comments, and bookmarks; saved posts open the original post.
- Create/Edit only from completed Trip History, one post per trip, and author-only editing.
- Server NLP for title/description length, quality, spam, obfuscated profanity, and completed-trip location relevance. No score is returned or shown.
- Automatic one-to-three tag assignment based only on the locked destination/attraction, database aliases/rules, and optional Google Places types. Post text never determines tags.
- Seven Kuala Lumpur seed posts and location-specific sample photos.

## Run

Open this folder in Android Studio, choose an Android emulator or device, and run `lib/main.dart`. Windows desktop is not configured because this module targets Android.

The module includes safe public Supabase client defaults, so Android Studio can
run `lib/main.dart` directly. The private service-role and server API keys are
never bundled. To target another environment, the local
`config/flutter.env.json` contains only public Flutter values and is ignored by
Git. Add this to the Flutter run configuration's additional arguments:

```text
--dart-define-from-file=config/flutter.env.json
```

The equivalent terminal command is:

```text
flutter run -d <android-device> --dart-define-from-file=config/flutter.env.json
```

For local Android Emulator development, `COMMUNITY_API_URL` is
`http://10.0.2.2:3000`. A physical phone needs the development computer's LAN
URL; deployed builds must use HTTPS.

Build and test the backend from `server/` with `npm test` and `npm run build`.
`server/.env.example` documents the private values consumed by Community
Discovery.
Never place the Supabase service-role key, unrestricted Google server keys, or
Groq keys in Flutter. Rotate any key previously exposed in chat.

See [INTEGRATION.md](INTEGRATION.md) for migration order, deployment, Profile bookmarks, Trip History Create/Edit, Start Journey callback wiring, realtime setup, security boundaries, and acceptance tests.

## Validation test examples

- Pass: title `Morning at Kwai Chai Hong`; description clearly mentions Kwai Chai Hong or Kuala Lumpur with useful trip details.
- Block: title shorter than three characters or description shorter than ten.
- Block: repeated/gibberish text, any link in the title or description, abusive words, leetspeak, or deliberately separated profanity.
- Block: a Langkawi-only story for a locked Kuala Lumpur/Kwai Chai Hong trip.
- False-positive check: an allow-listed location such as `Scunthorpe` is not rejected by substring matching.
- Tag independence: identical post text on Kwai Chai Hong and Jalan Alor trips produces different location-derived tags.

Image-location moderation is not implemented. The documented future design combines EXIF GPS, Places metadata, optional server-side recognition, and manual review for uncertain results.

## Add a test picture to the Android Emulator

Use a JPG, JPEG, or PNG no larger than 10 MB. Drag it from Windows File
Explorer onto the running emulator; Android normally places it in Downloads.
In Create Post, tap the picture area and select it from Files/Photos >
Downloads. Alternatively, open Android Studio's **View > Tool Windows > Device
Explorer**, upload the file to `/storage/emulated/0/Download`, then reopen the
picker. A real post requires 1–6 pictures.
