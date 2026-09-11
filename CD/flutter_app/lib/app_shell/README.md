# Shared application shell

`ohmy_app.dart` is the single owner of application-level navigation.

## Navigation destinations

| Tab | Module root |
| --- | --- |
| Home | Shared project landing page |
| AI Chat | `ai_chatbot/ChatScreen` |
| Start Trip | Solo-or-Group selection |
| Community | `community_discovery/CommunityFeedScreen` |
| Profile | `user_management/ProfileScreen` |

The Start Trip choices are:

- **Solo trip** opens `preference_recommender/PlaceMapPage`. Weather, traffic,
  recommendations, routing, and navigation remain part of that flow.
- **Group trip** opens `travel_group/TravelGroupDiscoveryScreen` with its
  shared group controller.

Each tab has a nested `Navigator`. Module screens can continue using
`Navigator.of(context).push(...)`; the shared bottom navigation remains outside
that nested route stack.

## Module integration rule

Feature modules should expose ordinary Flutter screens, not another
`MaterialApp` or application-level navigation bar. Standalone `MaterialApp`
files may remain for isolated module testing, but the integrated application
must import the module screen into `OhMyShell`.

When adding a new tab destination:

1. Add its root `WidgetBuilder` to `_rootBuilders`.
2. Add the corresponding navigator key.
3. Add exactly one `NavigationDestination`.
4. Update the navigation integration test.

## Supabase startup

The root `main.dart` initializes Supabase only when both `SUPABASE_URL` and
`SUPABASE_ANON_KEY` are supplied. With configuration present, `AuthGate`
protects the integrated shell. Without it, development modules still open with
demo data and the Profile tab displays setup guidance instead of crashing.
