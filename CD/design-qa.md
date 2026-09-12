# Shared Navigation and Map UI Design QA

- Source visual truth: the three user-provided bottom-navigation references showing flat inactive items and an active icon that rises above the bar inside a coloured circle.
- Test device: Android Pixel emulator at 1080 x 2400 physical pixels.
- Implementation evidence:
  - `flutter_app/docs/design-qa/ohmy_nav_preview.png`
  - `flutter_app/docs/design-qa/ohmy_nav_ai_preview.png`
  - `flutter_app/docs/design-qa/ohmy_trip_hub.png`
  - `flutter_app/docs/design-qa/ohmy_wau_loading.png`
  - `flutter_app/docs/design-qa/ohmy_marker_final.png`
  - `flutter_app/docs/design-qa/ohmy_nav_spacing_final.png`

## Visual comparison

The shared navigation matches the reference interaction model while retaining the existing ohMY blue theme. Inactive destinations use the supplied off-state artwork, grey labels, no outline, and no vertical emphasis. The active destination switches to its on-state artwork, rises 18 logical pixels, and gains a high-resolution blue circular border and shadow. Home, AI Chat, and Start Trip states were selected and inspected independently.

The navigation remains above the Android gesture area and does not cover module content. Five labels remain legible at the Pixel viewport, and the animated selected state does not clip at the top of the bar.

The follow-up spacing capture confirms that the container divider no longer crosses behind the selected icon. Moving labels upward by 12 logical pixels produces a compact icon-to-label relationship without overlap.

## Supporting states

- The Wau artwork was captured during a live Nearby Matches request. It is centred, clearly visible against the map, appropriately sized, and accompanied by the existing loading label.
- The final recommendation map capture shows the supplied pink `locationMark.png` flower with its matching pointed tail. The first pass was too large in dense results; the logical size was reduced while retaining the high-resolution bitmap, producing the final readable map state.
- Application snackbars and the Solo Trip status banner now dismiss after no more than three seconds.

## Findings

- No P0, P1, or P2 layout, clipping, readability, state, or interaction issues remain in the tested states.
- P3: Very dense city-centre recommendation results can still overlap. Marker clustering can be considered in a later mapping phase, but the reduced markers remain individually recognizable.

## Verification

- Flutter/Dart analyzer: passed with no issues.
- Full Flutter test suite: 29 tests passed.
- Final focused app-shell and navigation tests: passed.
- Android debug APK: built and installed successfully.

## Final result

final result: passed

---

# Homepage and Active Navigation Refinement QA

- Source visual truth: user-provided UNIQLO mobile homepage reference and written ohMY requirements.
- Implementation screenshot path: `flutter_app/docs/design-qa/ohmy_home_refined.png`.
- Intended viewport/state: Android phone, authenticated homepage with location and recommendation data; active Navigation SDK journey.
- Source dimensions: 423 x 843 pixels for the supplied mock. Implementation dimensions: 1080 x 2340 physical pixels on the connected Android phone; density was reviewed proportionally because the source mock was not supplied at the same device density.

## Evidence and findings

- Automated code validation covers widget compilation, navigation-shell behavior, and existing module flows.
- The installed on-device loading state now follows the supplied composition: icon/search header, warm featured-place region, “Places You May Like” horizontal cards, traveller-post section, and persistent bottom navigation.
- Typography, blue/cream tokens, spacing rhythm, rounded cards, and copy hierarchy were checked in the full-phone capture. No overflow is visible on the homepage.
- The interaction implementation keeps the bottom bar visible during navigation, uses traffic-coloured ETA, uses image-backed POI cards, and sources route metrics through the Directions service.
- Live place-photo content and the revised selected-POI card could not be captured because this QA APK was launched without the runtime backend/Supabase defines used by `run-ohmy.ps1`.

## Comparison history

- First capture exposed a large blank loading region. The loading/empty state was rebuilt with the same featured-region and horizontal-card structure as the mock; the post-fix on-device capture confirms the corrected hierarchy and no homepage overflow.

## Implementation checklist

- Capture the homepage after live nearby recommendations load through `run-ohmy.ps1`.
- Capture an individual POI card over the map.
- Capture active navigation in light, medium, and heavy traffic states.
- Confirm the selected-POI card has no overflow with live tags and all three buttons.

## Final result

final result: blocked
