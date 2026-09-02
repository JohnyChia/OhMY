# Travel Group Flutter Prototype

A standalone Flutter implementation of the Travel Group flow from the
`CD COPY` Figma file. It uses a local in-memory repository and does not require
authentication, Supabase, Google Maps, or your groupmates' modules.

## Implemented flow

- Nearby lobby discovery, keyword/radius/open filtering
- Verified-traveller gate and demo-profile switch
- Open joining, request joining, capacity and duplicate protection
- Group creation
- Joined lobby, members, meetup details and creator join requests
- Suggestion board, exclusive voting and creator confirmation
- Reorderable itinerary, recalculated prototype travel times
- Starting the itinerary and completing stops one-by-one
- Full-screen simulated navigation using the exact Figma route asset

## First-time setup

Flutter was not installed in the workspace where this source was generated, so
native runner folders are intentionally generated on your Flutter machine:

```powershell
cd travel_group_flutter
flutter create --platforms=android,ios .
flutter pub get
flutter test
flutter run
```

If you only need Android, use:

```powershell
flutter create --platforms=android .
```

The `flutter create` command preserves the existing `lib`, `test`, assets and
`pubspec.yaml` while adding the platform runner files.

## Prototype personas

Tap the avatar beside the top search bar:

- **Aina Sofea** — verified creator of Petaling Street Food Hunt
- **Unverified Guest** — exercises the verification gate

For the fastest active-map demo, use Aina, open Petaling Street Food Hunt,
confirm one or more suggestions, open Itinerary, and tap **Start group
itinerary**.

## Supabase later

The UI talks only to `TravelGroupRepository`. A future implementation should
extend the adapter in:

`lib/features/travel_group/repositories/supabase_travel_group_repository.dart`

Then change only the repository construction in `lib/main.dart`. Suggested
tables and row mappings are documented in `docs/SUPABASE_INTEGRATION.md`.

