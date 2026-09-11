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
