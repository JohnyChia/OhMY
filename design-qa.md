# Travel Group workspace redesign — design QA

## Evidence

- Source visual truth: the two Travel Group reference images attached to the current user request.
- Implementation: Flutter Android seeded QA target rendered on Pixel 9 API 34.
- Viewport: 1080 × 2424 physical pixels, approximately 360 × 808 logical pixels at device density 3.
- Source density: supplied composite reference; visually normalized by comparing each phone panel as an individual mobile viewport rather than the full three-panel canvas.
- Final implementation captures:
  - `qa-details-revised.png`
  - `qa-lobby-revised.png`
  - `qa-suggestions-revised.png`
  - `qa-itinerary-two-stops.png`
- State: creator-owned recruiting group with three members; unconfirmed meetup; confirmed and unconfirmed suggestions; two-stop editable itinerary.

## Full-view comparison

The final screens preserve the reference hierarchy: compact group header and phase badge, three-tab workspace, prominent map previews, confirmation callout, locked meetup state, member management, vote-led suggestions, creator-only Add action, destination-first itinerary, route recalculation notice, and whole-card reordering. Group Details uses a destination image surface rather than a map and gives destination, host, capacity, join mode, and privacy information clear priority.

## Focused comparison

| Fidelity surface | Result | Evidence |
| --- | --- | --- |
| Typography | Passed | Titles use the app’s strong display hierarchy; status, metadata, and labels remain legible at phone density without clipped text. |
| Spacing and layout | Passed | `qa-lobby-revised.png` and `qa-suggestions-revised.png` show consistent 16 dp margins, compact tabs, balanced cards, and no overflow. |
| Colors and tokens | Passed | Existing OhMY primary blue, pale-blue surfaces, green success, amber confirmation, and lavender/warm cards map consistently to the reference states. |
| Image quality | Passed with live-data fallback | Group Details requests the persisted Google Places photo name and falls back only when the recommendation backend has no photo. No hardcoded place images were added. |
| Copy and content | Passed | Confirmation, meetup privacy, member roles, ranking, route recalculation, and first-destination copy state the actual behavior. |
| Interaction states | Passed | Tabs, destination search, voting, creator Add, removal, drag reorder, group confirmation, member profiles, and navigation CTA are wired to controller actions. |
| Privacy | Passed | Outsiders receive sanitized group discovery data. Meetup name, note, and coordinates are available only from the member-protected group row; the lobby also hides an existing meetup until group confirmation. |
| Responsiveness | Passed | Widget suite includes a 375 × 812 viewport overflow check; final Pixel 9 captures show no overlap or hidden persistent controls. |

Focused regions were necessary for the confirmation/meetup section, suggestion voting row, and itinerary ordering controls; their final states are visible in the lobby, suggestions, and two-stop itinerary captures above.

## Comparison history

### Pass 1 — blocked

- P1: all three new map previews were blank. Emulator logs showed `Lite mode does not apply to the Navigation SDK` and an unhandled `PlatformException`.
- P1: the unconfirmed member lobby displayed a previously stored meetup name and note.
- P2: interest pills expanded to full-width rows in Group Details.

Fixes applied:

- Removed `liteModeEnabled` from maps backed by the project’s Navigation SDK.
- Made pre-confirmation meetup content a locked generic state and hid the note.
- Changed `AppPill` sizing so chips hug their content.

### Pass 2 — passed

- `qa-lobby-revised.png` and `qa-suggestions-revised.png` show rendered Google maps with no platform exception in the post-fix log.
- `qa-details-revised.png` shows compact tags and destination-image hierarchy.
- `qa-itinerary-two-stops.png` shows the first destination fixed at position one, calculated next-leg metadata, and a draggable future stop.
- No actionable P0, P1, or P2 visual defects remain in the checked states.

## Automated and device checks

- Dart analyzer: no issues in `lib/travel_group` and `test/travel_group`.
- Travel Group tests: 50 passed.
- Android debug APK: built successfully.
- Pixel 9 map log after fix: no `PlatformException` or lite-mode errors.
- Supabase validation: solo-confirm guard installed; discovery result excludes meetup fields; anonymous execution of the discovery RPC is denied.

## Follow-up polish

- P3: replace the photo fallback with a neutral destination-category illustration if the recommendation backend is offline for an extended period.
- P3: add an optional departure time and accessibility/mobility note to Group Details when those become real group fields.

final result: passed
