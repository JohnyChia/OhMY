# Home Page Design QA

**Source visual truth**

- User-provided OhMY mobile homepage reference in the 2026-09-12 conversation.
- Source image dimensions visible in the prompt: 720 × 1280 pixels.

**Implementation evidence**

- Implementation: `lib/app_shell/personalized_home_page.dart`
- Android debug APK: `build/app/outputs/flutter-apk/app-debug.apk`
- Intended logical viewport: responsive Android phone width, verified structurally by widget tests.
- Implementation screenshot: unavailable.

**State**

- Personalised featured attraction, ranked nearby carousel, and Community post preview.
- Live content requires an authenticated user, current location, the recommendation backend, and Community repository data.

**Full-view comparison evidence**

- Blocked. No Android device was connected (`adb devices` returned no devices), and the conversation image was not exposed as a local image file that could be combined with an implementation capture.

**Focused-region comparison evidence**

- Blocked for the same reason. The hero, nearby carousel, Community cards, and persistent bottom navigation could not be captured from a running device.

**Automated checks completed**

- Flutter analyzer: no issues.
- Flutter test suite: 53 tests passed.
- Android debug APK build: passed.
- App-shell tests cover bottom-navigation hiding/restoration and top-level Back routing.

**Findings**

- [P1] Runtime visual comparison is unavailable.
  - Location: redesigned Home page.
  - Evidence: no connected emulator/device was available for a screenshot.
  - Impact: exact image crop, real-data text wrapping, and device-specific spacing cannot be visually certified.
  - Fix: run `run-ohmy.ps1 -Emulator Pixel_8`, sign in, wait for live recommendations, and capture the Home screen at the same state as the reference.

**Implementation Checklist**

- Connect or boot an Android device.
- Start the backend and authenticated Flutter application.
- Capture the populated Home screen at 720 × 1280-equivalent density.
- Compare it beside the source reference and resolve any P1/P2 visual differences.

**Follow-up Polish**

- Confirm long Malaysian attraction names remain balanced with real API data.
- Confirm two nearby cards plus a visible portion of the third at the target device width.

final result: blocked
