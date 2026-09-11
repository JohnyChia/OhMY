# Travel Groups redesign — design QA

## Scope

- Source of truth: approved destination-led Travel Groups concept generated in this session.
- Implementation: Flutter Android app running on the Pixel 9 API 34 emulator.
- Logical viewport: approximately 393 × 852 dp; captured device frame: 1080 × 2424 px.
- Comparison image: `tmp/travel-group-qa/comparison.png`.

## Normalization

- The emulator capture was cropped to remove Android-only status/gesture chrome.
- Both views were scaled to the same 853 × 1844 comparison frame.
- App-owned bottom navigation was retained.
- Live Google Places imagery was intentionally allowed to differ from the concept's illustrative imagery.

## Full-view comparison

The implementation preserves the approved structure and hierarchy: title and supporting copy, area selector, large destination-first image cards, group title, creator, traveller count, status, primary card action, and a right-aligned create FAB. Three complete groups are visible at once, with the next group partially visible as a scroll cue.

## Focused checks

| Area | Result | Evidence |
| --- | --- | --- |
| Destination cards | Passed | `tmp/travel-group-qa/09-discovery-final.png` |
| Dynamic place photos | Passed | Distinct Places-backed photos rendered for Petaling Street, KLCC Park, Chow Kit, and Batu Caves. No concept images were added to app assets. |
| Area control | Passed | Area/city selector includes a working Change dropdown. |
| Create action | Passed | Create FAB is on the requested right side. |
| Creation form | Passed | `tmp/travel-group-qa/10-create-final.png`; shell navigation does not obscure the sheet and meetup is absent. |
| Destination search | Passed | `tmp/travel-group-qa/11-create-search.png`; “KLCC” returns live Places results. |
| Creator meetup flow | Passed | `tmp/travel-group-qa/14-group-lobby-final.png` and `15-meetup-picker.png`; only the creator receives the map action, member locations are streamed, and the 5 km rule gates saving. |
| Automated checks | Passed | Flutter analysis reports no issues; all 27 tests pass. |

## Defects found and resolved

- P1: the shared bottom navigation obscured the creation sheet. Resolved by presenting the sheet on the root navigator.
- P2: activity tags produced unnecessary vertical density. Resolved with compact wrapping filter chips.
- P2: non-creators saw a disabled meetup map action and the lobby showed a mock distance. Resolved by making the action creator-only and removing the misleading distance line.

## Remaining integration boundary

Google Places search and imagery are live. Group persistence and multi-device member location sharing still use the repository/service mock adapters; the domain API is ready for a Supabase Realtime implementation, but real cross-phone synchronization is not claimed by this QA pass.

final result: passed
