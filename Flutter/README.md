# ohMY Flutter Map Module

Mobile frontend for the ohMY Malaysian cultural-attraction recommender. It uses the existing Node/Express backend for Google Places search, review tagging, nearby discovery, ranking, and photo proxying.

## Important project structure

```text
flutter_app/
├─ lib/
│  ├─ main.dart                         App entry point and Material theme
│  └─ pages/place_map_page.dart         Map, search, tagging panel, carousel and details UI
├─ android/
│  ├─ app/src/main/AndroidManifest.xml  Internet, location and Maps-key configuration
│  ├─ app/build.gradle.kts              Reads MAPS_API_KEY from local.properties
│  └─ local.properties.example          Safe configuration template
├─ plugins/
│  └─ google_maps_flutter_android/      Local plugin override for built-in POI taps
├─ pubspec.yaml                         Flutter packages and plugin override
├─ pubspec.lock                         Resolved dependency versions
├─ analysis_options.yaml                Dart analysis configuration
└─ README.md                            This guide
```

The local plugin directory is required. Its native `OnPoiClickListener` sends a built-in Google Maps POI Place ID to Flutter through `ohmy/google_map_poi/<mapId>`. Do not remove the `dependency_overrides` entry in `pubspec.yaml` unless this feature is replaced upstream.

## Requirements

- Flutter 3.41.5 or a compatible stable release
- Dart 3.11 or compatible
- Android Studio and Android SDK
- Pixel 8 emulator with a Google APIs system image
- Windows Developer Mode when running on Windows (required for plugin symlinks)
- Google Cloud project with Maps SDK for Android enabled
- The repository's Node backend running on port 3000

## Local configuration

Copy the template:

```powershell
Copy-Item android\local.properties.example android\local.properties
```

Edit `android/local.properties`:

```properties
sdk.dir=C:\\Users\\YOUR_NAME\\AppData\\Local\\Android\\Sdk
flutter.sdk=C:\\path\\to\\flutter
MAPS_API_KEY=YOUR_ANDROID_GOOGLE_MAPS_API_KEY
```

`android/local.properties` is ignored by Git. Never share or commit the real API key.

## Start the backend

From the repository root:

```powershell
cd backend
npm install
npm start
```

Confirm `http://127.0.0.1:3000` returns HTTP 200.

## Prepare the Android emulator

Start a Pixel 8 emulator in Android Studio, then forward the backend port:

```powershell
adb reverse tcp:3000 tcp:3000
```

The Flutter debug default is `http://127.0.0.1:3000`, which relies on this forwarding. Repeat the command after restarting the emulator.

Set a Kuala Lumpur test location if the emulator starts overseas:

```powershell
adb emu geo fix 101.6869 3.1390
```

The emulator command expects longitude first, then latitude.

## Install and run

```powershell
flutter clean
flutter pub get
flutter run
```

Native POI support is Android code, so use a full stop/rebuild after changing the local Maps plugin; hot reload is insufficient.

## Physical Android device

ADB reverse also works for a USB-debugging device:

```powershell
adb reverse tcp:3000 tcp:3000
flutter run -d DEVICE_ID
```

Alternatively, run with a reachable computer LAN address:

```powershell
flutter run --dart-define=BACKEND_URL=http://YOUR_COMPUTER_LAN_IP:3000
```

Allow Node.js through Windows Firewall when using the LAN option.

## Main user flows

- Search result → fetch five reviews → assign tags → custom place panel → details page
- Built-in Android Google POI → native Place ID bridge → tagging → custom panel
- Nearby matches → browser/device location → tagged/ranked places → map markers and carousel
- Tagged marker → open and scroll carousel to matching card
- Carousel card → full place details
- Directions → external Google Maps
- Bookmark, weather and traffic controls are local placeholders for team integrations

## Verification

```powershell
flutter analyze
flutter build apk --debug
```

The APK is generated at:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Files not to send or commit

- `android/local.properties`
- Real API keys or backend `.env`
- `.dart_tool/`
- `build/`
- `.gradle/`
- IDE metadata such as `.idea/` and `*.iml`

For teammate handoff, send the complete `flutter_app` folder after removing generated files, while keeping `plugins/google_maps_flutter_android`.
