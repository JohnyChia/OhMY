# ohMY Preference Recommender

The Preference Recommender module for **ohMY**, a Malaysian cultural and heritage leisure-travel application. It discovers attractions around the user's current location, assigns general and cultural-value tags from Google reviews, ranks suitable places, displays them on a Flutter map, and supports route planning plus prototype GPS guidance.

## Current capabilities

- Google Places search and built-in Android map POI selection.
- Rule-based NLP tag assignment from up to five relevant reviews.
- General tags and cultural-value tags.
- Nearby candidate discovery from dynamic tag-to-Google-type planning.
- Preference-based and destination-tag-based similarity ranking.
- Ranked recommendation markers and carousel.
- Place details, photos, tags, ETA, distance and address.
- Current conditions and hourly forecasts through Google Weather API.
- Google Maps live traffic overlay.
- Origin and destination search with alternative Google driving routes.
- High-quality 2D route polylines, ETA, distance and traffic labels.
- Prototype active journey with live GPS following and Google maneuver instructions.
- Navigation-time recommendations based on destination tags or personal preferences.

Bookmarks, user-profile preferences, expandable journey details, voice guidance, arrival handling and automatic off-route rerouting are later integrations.

## Technology

- Flutter and Dart
- Node.js and Express
- Google Maps SDK for Android
- Google Places API (New)
- Google Routes API
- Google Weather API
- Google Geocoding API
- Supabase

## Repository structure

```text
.
├── backend/
│   ├── public/                         Existing HTML/CSS/JavaScript prototype
│   ├── scripts/                        Tagging and recommendation checks
│   ├── server.js                       Express entry point and API routes
│   ├── tagging-service.js              Rule-based review tagging
│   ├── ranking-service.js              Similarity and cultural ranking
│   ├── candidate-query-planner.js      Tags to Google place-type search plan
│   ├── googlePlacesService.js          Google Places requests
│   ├── routing-service.js              Google Routes integration
│   ├── weather-service.js              Google Weather integration
│   ├── collectPlaces.js                Attraction data collection utility
│   ├── attractions.json                Development tagging dataset
│   ├── .env.example                    Safe backend configuration template
│   ├── package.json
│   └── package-lock.json
├── flutter_app/
│   ├── lib/
│   │   ├── main.dart                   Application entry and Android map setup
│   │   ├── pages/place_map_page.dart   Search, map, recommendations and details
│   │   ├── route_feature.dart          Route setup, selection and navigation
│   │   └── weather_feature.dart        Weather model, service and UI
│   ├── android/                         Android configuration
│   ├── plugins/google_maps_flutter_android/
│   │                                    Local POI-tap plugin override
│   ├── web/                             Flutter web platform files
│   ├── pubspec.yaml
│   ├── pubspec.lock
│   └── analysis_options.yaml
├── .gitignore
└── README.md
```

## Important local Maps plugin

Do not remove `flutter_app/plugins/google_maps_flutter_android` or the `dependency_overrides` entry in `flutter_app/pubspec.yaml`.

The local Android plugin adds a native `OnPoiClickListener`. It sends the Place ID of a built-in Google Maps POI to Flutter through `ohmy/google_map_poi/<mapId>`, allowing the backend to fetch reviews, assign tags and display the custom place panel.

The app also enables Android hybrid composition to keep multiple map screens stable.

## Prerequisites

- Node.js 20 or newer
- npm
- Flutter 3.41.5 or a compatible stable version
- Dart 3.11 or compatible
- Android Studio and Android SDK
- Android emulator with a Google APIs system image, or a USB-debuggable device
- Windows Developer Mode when developing on Windows
- A Google Cloud project with billing enabled
- A Supabase project

Enable the required Google APIs for the project:

- Maps SDK for Android
- Places API (New)
- Routes API
- Weather API
- Geocoding API
- Maps JavaScript API only if testing the legacy HTML map

## 1. Clone and install

```powershell
git clone https://github.com/YOUR_ORGANIZATION/YOUR_REPOSITORY.git
cd YOUR_REPOSITORY
```

Install backend dependencies:

```powershell
cd backend
npm install
cd ..
```

Install Flutter dependencies:

```powershell
cd flutter_app
flutter pub get
cd ..
```

## 2. Configure the backend

Create a local environment file:

```powershell
Copy-Item backend\.env.example backend\.env
```

Edit `backend/.env`:

```dotenv
PORT=3000
GOOGLE_PLACES_API_KEY=YOUR_SERVER_SIDE_GOOGLE_KEY
GOOGLE_MAPS_BROWSER_API_KEY=YOUR_BROWSER_RESTRICTED_KEY
GOOGLE_MAPS_MAP_ID=YOUR_MAP_ID
GOOGLE_WEATHER_API_KEY=YOUR_OPTIONAL_WEATHER_KEY
GOOGLE_ROUTES_API_KEY=YOUR_OPTIONAL_ROUTES_KEY
SUPABASE_URL=YOUR_SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVER_ONLY_SERVICE_ROLE_KEY
```

`GOOGLE_WEATHER_API_KEY` and `GOOGLE_ROUTES_API_KEY` are optional. If omitted, the backend uses `GOOGLE_PLACES_API_KEY`; the key must then be permitted to call all required APIs.

Never expose the Supabase service-role key or server-side Google keys in Flutter.

## 3. Configure Android

Create the local Android configuration:

```powershell
Copy-Item flutter_app\android\local.properties.example flutter_app\android\local.properties
```

Edit `flutter_app/android/local.properties`:

```properties
sdk.dir=C:\\Users\\YOUR_NAME\\AppData\\Local\\Android\\Sdk
flutter.sdk=C:\\path\\to\\flutter
MAPS_API_KEY=YOUR_ANDROID_RESTRICTED_GOOGLE_MAPS_KEY
```

Restrict the Android key by package name and SHA certificate where practical. Neither `backend/.env` nor `android/local.properties` should be committed.

## 4. Supabase data model

The planned shared schema is:

```text
places
  id, name, description, latitude, longitude,
  google_place_id, created_at

tags
  id, name, tag_type

place_tags
  place_id, tag_id, confidence
```

The current live prototype can assign and rank tags in memory. Supabase persistence can be added for reuse between modules while avoiding storage of full Google review text.

## 5. Run the backend

```powershell
cd backend
npm start
```

Verify the health endpoint:

```text
http://127.0.0.1:3000/
```

Expected response:

```json
{
  "status": "ok",
  "service": "Recommendation API"
}
```

The legacy HTML test interface is served by the same backend.

## 6. Run on an Android emulator

Start the emulator in Android Studio. Forward the local backend port:

```powershell
adb reverse tcp:3000 tcp:3000
```

Repeat this command after restarting the emulator.

If the emulator location starts outside Malaysia, set a Kuala Lumpur test location. The emulator command expects longitude first:

```powershell
adb emu geo fix 101.6869 3.1390
```

Run Flutter:

```powershell
cd flutter_app
flutter run
```

Use a full restart after changes to the local Android Maps plugin; hot reload cannot rebuild native code.

## Physical Android device

For a USB-debuggable device:

```powershell
adb devices
adb reverse tcp:3000 tcp:3000
cd flutter_app
flutter run -d DEVICE_ID
```

Alternatively, expose the backend on the computer's LAN address:

```powershell
flutter run --dart-define=BACKEND_URL=http://YOUR_COMPUTER_LAN_IP:3000
```

Allow Node.js through the host firewall when using the LAN option.

## Main flows

### Place tagging

```text
Search or tap a Google POI
→ fetch place details and reviews
→ process up to five usable reviews
→ assign general and cultural tags
→ display the custom place panel
→ open place details
```

### Nearby recommendation

```text
Get current location
→ build Google place-type searches from reference tags
→ discover and deduplicate nearby candidates
→ fetch reviews and assign tags
→ calculate similarity and cultural relevance
→ rank matched places
→ show markers and carousel
```

### Route and journey

```text
Directions
→ choose current/searched origin and destination
→ request alternative driving routes
→ select route
→ Start Journey
→ live GPS and maneuver guidance
```

During navigation, the lightbulb asks whether recommendations should use destination tags or personal preferences. Matching and ranking run from the user's current GPS location, and results appear in a carousel without recommendation markers.

## Useful backend endpoints

```text
POST /api/places/search
POST /api/places/analyze
GET  /api/places/photo
POST /api/recommendations/nearby-tagged
GET  /api/weather/overview
GET  /api/routes
GET  /api/config/maps
GET  /
```

## Verification

Backend syntax and regression checks:

```powershell
cd backend
node --check server.js
node --check tagging-service.js
node --check routing-service.js
npm run test:tagging
npm run test:recommendation
```

Flutter analysis and debug build:

```powershell
cd flutter_app
flutter analyze
flutter build apk --debug
```

The debug APK is generated at:

```text
flutter_app/build/app/outputs/flutter-apk/app-debug.apk
```

## Troubleshooting

### `ClientException with SocketConnection`

Ensure the backend is running and repeat:

```powershell
adb reverse tcp:3000 tcp:3000
```

### Emulator uses an overseas location

Set the emulator location in Extended Controls or run:

```powershell
adb emu geo fix 101.6869 3.1390
```

### Built-in POI taps do not open the custom panel

- Confirm the local Android Maps plugin override is present.
- Run `flutter clean` and `flutter pub get`.
- Fully stop and rebuild the app.
- Do not rely on hot reload after native plugin changes.

### Map rendering instability

- Cold boot the emulator.
- Give the emulator at least 4 GB RAM when available.
- Close unnecessary emulator/system applications.
- Fully rebuild after changing Android map composition.

## Git and security

Commit source files, configuration templates and lock files. Do not commit:

- `backend/.env`
- `backend/node_modules/`
- `flutter_app/android/local.properties`
- `flutter_app/.dart_tool/`
- `flutter_app/build/`
- `flutter_app/.gradle/`
- `.idea/`, `.vscode/` or `*.iml`
- API keys, service-role keys, keystores or generated APKs

Review `git status` before every commit. If a secret is committed, remove it from Git history and rotate the credential immediately.

## Team workflow

Create a feature branch rather than committing directly to `main`:

```powershell
git switch -c feature/short-description
```

After making changes:

```powershell
git status
git add backend flutter_app README.md .gitignore
git commit -m "Describe the completed change"
git push -u origin feature/short-description
```

Open a pull request, document setup changes, and avoid mixing unrelated module changes in one commit.

