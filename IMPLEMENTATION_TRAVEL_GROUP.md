# Travel Group Module — Prototype Implementation Guide

## 1. Purpose

This document describes how to implement the **Travel Group** module as a standalone prototype first, so it can be tested independently before being integrated with the other modules in the group assignment.

The prototype should focus on the functional flow rather than production-level infrastructure. External modules such as authentication, eKYC verification, maps, community posts, and the final shared backend should be represented through simple interfaces or mock data where necessary.

---

## 2. Prototype Scope

The Travel Group prototype covers:

1. Travel Group discovery
2. Traveller verification gate
3. Nearby group filtering
4. Group details
5. Open-group joining
6. Request-based joining
7. Group creation
8. Travel Group lobby
9. Suggestion board
10. Voting on suggested locations
11. Creator confirmation of itinerary stops
12. Itinerary ordering
13. Starting the group itinerary
14. Marking itinerary stops as completed
15. Highlighting the next stop

The following are treated as integration dependencies and may initially be mocked:

- User login
- User profile
- eKYC / Verified Traveller status
- Current GPS location
- Google Maps / Places data
- Community Discovery posts
- Push notifications
- Groupmates' modules

---

## 3. Recommended Prototype Approach

For the first implementation, keep the Travel Group module independent from the final backend.

Use:

- **Flutter / Dart** for the mobile UI
- A `MockTravelGroupRepository` for prototype data
- Local in-memory state for groups, requests, suggestions, votes, and itinerary
- A repository interface so the mock implementation can later be replaced by your group's actual backend API without rewriting the UI

Recommended architecture:

```text
UI Screens
    ↓
Controller / ViewModel
    ↓
TravelGroupRepository
    ↓
MockTravelGroupRepository        ← prototype
RESTTravelGroupRepository        ← later integration
    ↓
Backend / Database
```

The UI should never directly depend on mock JSON or a specific database.

---

## 4. Main Actors

### Traveller

A traveller can:

- Browse nearby travel groups
- Filter groups
- View group details
- Create a group
- Join an open group
- Request to join a request-based group
- View their joined group lobby
- Suggest nearby places
- Vote on suggestions
- View the itinerary

### Group Creator

The creator has all normal traveller capabilities and can additionally:

- Accept or decline join requests
- Confirm suggestions as itinerary stops
- Reorder itinerary stops
- Start the itinerary
- Mark a stop as completed

---

## 5. Important Prototype Rules

The following rules should be enforced inside the prototype because they are part of the Travel Group functionality.

### Verification

A user must be a verified traveller before joining or creating a Travel Group.

Prototype implementation:

```dart
if (!currentUser.isVerified) {
  navigateToVerificationRequired();
  return;
}
```

The actual verification process belongs to the user/account module and can initially be represented by:

```dart
currentUser.isVerified = true;
```

or

```dart
currentUser.isVerified = false;
```

for testing.

### Nearby Group Rule

Only nearby groups should normally appear in discovery.

For the prototype, each group can contain:

```dart
double distanceKm;
```

Then filter locally:

```dart
groups.where((group) => group.distanceKm <= selectedRadiusKm);
```

Later, replace this with real geolocation calculations or backend queries.

### Group Capacity

A group cannot be joined if:

```text
currentMemberCount >= maximumMemberCount
```

Show:

> This travel group is currently full.

The Join button must be disabled.

### Duplicate Membership

A traveller must not:

- Join the same group twice
- Send multiple pending requests to the same group

### Join Type

Each group has one of two join modes:

```dart
enum JoinMode {
  open,
  request,
}
```

#### Open

Traveller selects **Join Now** and becomes a member immediately.

#### Request

Traveller selects **Request to Join**.

A pending join request is created.

The creator can:

- Accept
- Decline

---

## 6. Suggested Project Structure

```text
lib/
├── modules/
│   └── travel_group/
│       ├── models/
│       │   ├── travel_group.dart
│       │   ├── travel_group_member.dart
│       │   ├── join_request.dart
│       │   ├── group_suggestion.dart
│       │   ├── itinerary_stop.dart
│       │   └── prototype_user.dart
│       │
│       ├── repositories/
│       │   ├── travel_group_repository.dart
│       │   └── mock_travel_group_repository.dart
│       │
│       ├── controllers/
│       │   └── travel_group_controller.dart
│       │
│       ├── screens/
│       │   ├── travel_group_discovery_screen.dart
│       │   ├── travel_group_details_screen.dart
│       │   ├── create_travel_group_screen.dart
│       │   ├── join_requests_screen.dart
│       │   ├── verification_required_screen.dart
│       │   ├── group_lobby_screen.dart
│       │   ├── suggestion_board_screen.dart
│       │   └── itinerary_screen.dart
│       │
│       └── widgets/
│           ├── group_card.dart
│           ├── member_avatar.dart
│           ├── suggestion_card.dart
│           └── itinerary_stop_card.dart
│
└── main.dart
```

This structure keeps the module separate enough to be copied or merged into the group's final application.

---

## 7. Data Models

## 7.1 Prototype User

```dart
class PrototypeUser {
  final String id;
  final String name;
  final bool isVerified;

  const PrototypeUser({
    required this.id,
    required this.name,
    required this.isVerified,
  });
}
```

For creator testing:

```dart
const currentUser = PrototypeUser(
  id: 'USER_001',
  name: 'Test Traveller',
  isVerified: true,
);
```

---

## 7.2 Travel Group

```dart
enum JoinMode {
  open,
  request,
}

enum GroupStatus {
  waiting,
  active,
  completed,
}

class TravelGroup {
  final String id;
  final String creatorId;

  String name;
  String destination;
  String description;
  String meetupPoint;

  List<String> tags;

  int maxMembers;
  double distanceKm;

  JoinMode joinMode;
  GroupStatus status;

  List<String> memberIds;

  TravelGroup({
    required this.id,
    required this.creatorId,
    required this.name,
    required this.destination,
    required this.description,
    required this.meetupPoint,
    required this.tags,
    required this.maxMembers,
    required this.distanceKm,
    required this.joinMode,
    required this.status,
    required this.memberIds,
  });

  bool get isFull => memberIds.length >= maxMembers;
}
```

The Travel Group is intended to support nearby, relatively spontaneous group travel. Therefore, a scheduled trip date is not required for the basic prototype.

---

## 7.3 Join Request

```dart
enum JoinRequestStatus {
  pending,
  accepted,
  declined,
}

class JoinRequest {
  final String id;
  final String groupId;
  final String travellerId;

  JoinRequestStatus status;

  JoinRequest({
    required this.id,
    required this.groupId,
    required this.travellerId,
    this.status = JoinRequestStatus.pending,
  });
}
```

---

## 7.4 Group Suggestion

```dart
class GroupSuggestion {
  final String id;
  final String groupId;
  final String suggestedByUserId;

  final String placeName;
  final String category;

  final double distanceKm;
  final String crowdLevel;

  final double? latitude;
  final double? longitude;

  Set<String> upvoterIds;
  Set<String> downvoterIds;

  bool isConfirmed;

  GroupSuggestion({
    required this.id,
    required this.groupId,
    required this.suggestedByUserId,
    required this.placeName,
    required this.category,
    required this.distanceKm,
    required this.crowdLevel,
    this.latitude,
    this.longitude,
    Set<String>? upvoterIds,
    Set<String>? downvoterIds,
    this.isConfirmed = false,
  })  : upvoterIds = upvoterIds ?? {},
        downvoterIds = downvoterIds ?? {};

  int get score => upvoterIds.length - downvoterIds.length;
}
```

A single user must not be counted in both vote sets.

---

## 7.5 Itinerary Stop

```dart
enum StopStatus {
  upcoming,
  current,
  completed,
}

class ItineraryStop {
  final String id;
  final String groupId;

  String placeName;
  int position;

  int estimatedDurationMinutes;
  int travelTimeFromPreviousMinutes;

  StopStatus status;

  ItineraryStop({
    required this.id,
    required this.groupId,
    required this.placeName,
    required this.position,
    required this.estimatedDurationMinutes,
    required this.travelTimeFromPreviousMinutes,
    this.status = StopStatus.upcoming,
  });
}
```

---

# 8. Repository Interface

The Travel Group UI should communicate with a repository instead of directly accessing local data.

```dart
abstract class TravelGroupRepository {
  Future<List<TravelGroup>> getNearbyGroups({
    required double radiusKm,
    List<String>? tags,
  });

  Future<TravelGroup?> getGroup(String groupId);

  Future<TravelGroup> createGroup(TravelGroup group);

  Future<void> joinOpenGroup({
    required String groupId,
    required String travellerId,
  });

  Future<JoinRequest> requestToJoin({
    required String groupId,
    required String travellerId,
  });

  Future<List<JoinRequest>> getJoinRequests(String groupId);

  Future<void> respondToJoinRequest({
    required String requestId,
    required bool accept,
  });

  Future<List<GroupSuggestion>> getSuggestions(String groupId);

  Future<void> addSuggestion(GroupSuggestion suggestion);

  Future<void> voteSuggestion({
    required String suggestionId,
    required String userId,
    required bool isUpvote,
  });

  Future<void> confirmSuggestion(String suggestionId);

  Future<List<ItineraryStop>> getItinerary(String groupId);

  Future<void> reorderItinerary(
    String groupId,
    List<String> orderedStopIds,
  );

  Future<void> markStopCompleted({
    required String groupId,
    required String stopId,
  });
}
```

---

# 9. Mock Repository

Create a temporary implementation:

```dart
class MockTravelGroupRepository implements TravelGroupRepository {
  final List<TravelGroup> groups = [];
  final List<JoinRequest> requests = [];
  final List<GroupSuggestion> suggestions = [];
  final List<ItineraryStop> itineraryStops = [];

  // Implement repository methods using these lists.
}
```

Populate it with a few sample groups on startup.

Example:

```dart
TravelGroup(
  id: 'GROUP_001',
  creatorId: 'USER_100',
  name: 'KL Heritage Walk',
  destination: 'Central Market',
  description: 'Exploring heritage locations around central KL.',
  meetupPoint: 'Central Market Main Entrance',
  tags: ['Heritage', 'Culture', 'Food'],
  maxMembers: 6,
  distanceKm: 1.2,
  joinMode: JoinMode.open,
  status: GroupStatus.waiting,
  memberIds: ['USER_100', 'USER_101'],
);
```

Create at least:

- One open group
- One request-based group
- One full group
- One group outside the selected radius

This lets all alternate flows be tested.

---

# 10. Screen Flow

```text
Travel Group Discovery
        │
        ├── Create Group
        │       │
        │       └── New Group → Lobby
        │
        └── Select Group
                │
                ▼
         Group Details
                │
     ┌──────────┴────────────┐
     │                       │
 Open Group            Request Group
     │                       │
 Join Now              Request to Join
     │                       │
     ▼                       ▼
   Lobby               Pending Status
                             │
                    Creator Accepts
                             │
                             ▼
                           Lobby

Lobby
 ├── Lobby Tab
 ├── Suggestions Tab
 │       ├── Add Suggestion
 │       ├── Upvote / Downvote
 │       └── Creator Confirm
 │
 └── Itinerary Tab
         ├── Reorder Stops
         ├── Start Itinerary
         └── Complete Stop
```

---

# 11. Discovery Screen

## Required UI

Display:

- Header
- Current location indicator
- Search/filter controls
- Radius filter
- Activity preference tags
- Nearby Travel Group cards
- Create Group button

Each group card should display:

- Group name
- Destination
- Creator
- Distance
- Tags
- Member count
- Maximum group size
- Join type
- Full state if applicable

Example:

```text
KL Heritage Walk
Central Market
1.2 km away

Heritage • Culture • Food

3 / 6 travellers
OPEN GROUP

[View Group]
```

---

# 12. Filtering

Prototype filters can run locally.

Example controller method:

```dart
Future<void> loadGroups() async {
  visibleGroups = await repository.getNearbyGroups(
    radiusKm: selectedRadius,
    tags: selectedTags,
  );

  notifyListeners();
}
```

Filtering should support:

- Radius
- Destination keyword
- Activity tags

A group should match the selected tags if it contains at least one selected tag.

Example:

```dart
final tagMatches =
    selectedTags.isEmpty ||
    group.tags.any(selectedTags.contains);
```

---

# 13. Group Details Screen

Display:

- Group name
- Destination
- Description
- Meetup point
- Distance
- Creator
- Members
- Activity tags
- Current member count
- Group capacity
- Join mode

Button state:

### Open + Available

```text
[ Join Now ]
```

### Request + Available

```text
[ Request to Join ]
```

### Already Pending

```text
Request Pending
```

Button disabled.

### Already Member

```text
[ Enter Lobby ]
```

### Full

```text
Group Full
```

Button disabled.

---

# 14. Joining an Open Group

Flow:

```text
Traveller presses Join Now
        ↓
Check verified status
        ↓
Check group capacity
        ↓
Check existing membership
        ↓
Add traveller to memberIds
        ↓
Open Lobby
```

Pseudo-code:

```dart
Future<void> joinOpenGroup(TravelGroup group) async {
  if (!currentUser.isVerified) {
    openVerificationRequired();
    return;
  }

  if (group.isFull) {
    showMessage('This travel group is currently full.');
    return;
  }

  if (group.memberIds.contains(currentUser.id)) {
    openLobby(group.id);
    return;
  }

  await repository.joinOpenGroup(
    groupId: group.id,
    travellerId: currentUser.id,
  );

  openLobby(group.id);
}
```

---

# 15. Request-Based Joining

Traveller flow:

```text
Request to Join
      ↓
Pending request created
      ↓
"Join request sent"
      ↓
Button becomes Request Pending
```

Creator flow:

```text
Lobby
  ↓
Join Requests
  ↓
Traveller Request
  ├── Accept
  └── Decline
```

### Accept

- Change request status to `accepted`
- Add traveller to `memberIds`
- Prevent acceptance if group has become full

### Decline

- Change request status to `declined`

Prototype notification:

```text
Your request to join was declined.
```

The final system can later replace this with a notification module.

---

# 16. Create Travel Group

Required fields:

- Group name
- Destination
- Activity tags
- Maximum group size
- Description
- Meetup point
- Join preference

Join preference:

```text
○ Open Group
○ Request Approval
```

Validation:

- Group name required
- Destination required
- At least one tag
- Maximum group size >= 2
- Description required
- Meetup point required

Upon creation:

1. Generate group ID
2. Set creator as current user
3. Add creator to `memberIds`
4. Set status to `waiting`
5. Save through repository
6. Open the new group lobby

---

# 17. Travel Group Lobby

The top navigation for all Travel Group pages should remain consistent:

```text
Lobby | Suggestions | Itinerary
```

## Lobby Tab

Display:

- Group name
- Destination
- Meetup point
- Group tags
- Member list
- Member count
- Creator indicator
- Current group status

Creator-only section:

```text
Join Requests (2)
```

This button should only appear for request-based groups where the current user is the creator.

---

# 18. Suggestion Board

The Suggestions tab allows members to propose nearby locations.

For the prototype, the available location list can be hard-coded.

Example:

```dart
final nearbyPlaces = [
  {
    'name': 'Central Market',
    'distance': 0.8,
    'category': 'Heritage',
    'crowd': 'Moderate',
  },
  {
    'name': 'Petaling Street',
    'distance': 1.1,
    'category': 'Culture',
    'crowd': 'Busy',
  },
  {
    'name': 'Kwai Chai Hong',
    'distance': 1.3,
    'category': 'Heritage',
    'crowd': 'Moderate',
  },
];
```

Later this list can come from:

- Google Places API
- Your map/location module
- Community Discovery
- Your shared backend

---

# 19. Adding a Suggestion

The traveller selects a nearby place:

```text
Kwai Chai Hong
1.3 km
Heritage
Crowd: Moderate

[Add Suggestion]
```

After adding:

- A `GroupSuggestion` is created
- It appears on the shared suggestion board
- Other group members can vote

Prevent duplicate suggestions for the same place inside the same group unless your final group requirements allow duplicates.

---

# 20. Voting

Each suggestion displays:

```text
Kwai Chai Hong
Heritage • 1.3 km
Crowd: Moderate

▲ 4      ▼ 1

Score: 3
```

Voting rules:

- User can have only one vote per suggestion
- Pressing upvote after downvoting removes the downvote first
- Pressing the same vote again may toggle the vote off
- Score:

```text
upvotes - downvotes
```

Sort suggestions from highest score to lowest.

Example:

```dart
suggestions.sort(
  (a, b) => b.score.compareTo(a.score),
);
```

---

# 21. Creator Confirms Suggestion

Only the creator can see:

```text
[ Add to Itinerary ]
```

When selected:

1. Mark suggestion as confirmed
2. Create an `ItineraryStop`
3. Append it to the itinerary
4. Disable the confirm button

Example:

```dart
if (currentUser.id == group.creatorId) {
  // show Add to Itinerary
}
```

---

# 22. Itinerary

The Itinerary tab displays confirmed stops.

Example:

```text
1. Central Market
   Estimated visit: 45 min
   Travel: 0 min

2. Petaling Street
   Estimated visit: 60 min
   Travel: 8 min

3. Kwai Chai Hong
   Estimated visit: 30 min
   Travel: 5 min
```

The creator can reorder stops.

Flutter can use:

```dart
ReorderableListView
```

Example:

```dart
ReorderableListView.builder(
  itemCount: stops.length,
  onReorder: controller.reorderStops,
  itemBuilder: ...,
);
```

---

# 23. Recalculating Prototype Travel Information

For the prototype, real route calculation is optional.

After reordering, simulate recalculation:

```dart
void recalculatePrototypeTravelTimes() {
  for (int i = 0; i < stops.length; i++) {
    stops[i].position = i;

    if (i == 0) {
      stops[i].travelTimeFromPreviousMinutes = 0;
    } else {
      stops[i].travelTimeFromPreviousMinutes = 5 + (i * 2);
    }
  }
}
```

Later replace this with Google Routes / Directions data.

The important part for your prototype is demonstrating that:

```text
Reorder stop
    ↓
System updates stop order
    ↓
ETA / travel information is recalculated
```

---

# 24. Starting the Itinerary

Only the creator should start the itinerary.

Before starting:

```text
Status: Waiting
[Start Itinerary]
```

After starting:

```text
Status: Active
```

Set the first incomplete stop to:

```dart
StopStatus.current
```

All later stops remain:

```dart
StopStatus.upcoming
```

---

# 25. Completing a Stop

Creator presses:

```text
[Mark Completed]
```

System:

1. Marks current stop as completed
2. Finds next incomplete stop
3. Marks it as current
4. Highlights it

Pseudo-code:

```dart
Future<void> completeStop(String stopId) async {
  await repository.markStopCompleted(
    groupId: group.id,
    stopId: stopId,
  );

  await loadItinerary();
}
```

Visual states:

```text
✓ Central Market       COMPLETED

→ Petaling Street      CURRENT

  Kwai Chai Hong       UPCOMING
```

---

# 26. Controller Responsibilities

Create one controller for the prototype:

```dart
class TravelGroupController extends ChangeNotifier {
  final TravelGroupRepository repository;
  final PrototypeUser currentUser;

  List<TravelGroup> groups = [];
  List<GroupSuggestion> suggestions = [];
  List<ItineraryStop> itinerary = [];

  double selectedRadius = 5;
  List<String> selectedTags = [];

  TravelGroupController({
    required this.repository,
    required this.currentUser,
  });

  Future<void> loadGroups() async {}
  Future<void> createGroup(...) async {}
  Future<void> joinGroup(...) async {}
  Future<void> requestJoin(...) async {}
  Future<void> vote(...) async {}
  Future<void> confirmSuggestion(...) async {}
  Future<void> reorderStops(...) async {}
  Future<void> completeStop(...) async {}
}
```

For a small prototype, `ChangeNotifier` is sufficient.

If your group already uses another state-management package, the repository design can stay the same while the controller is changed later.

---

# 27. Prototype Navigation

Suggested Flutter routes:

```text
/travel-groups
/travel-groups/create
/travel-groups/:id
/travel-groups/:id/lobby
/travel-groups/:id/requests
/travel-groups/:id/suggestions
/travel-groups/:id/itinerary
/verification-required
```

Using named routes is optional. The key requirement is that the Travel Group module should be navigable independently.

---

# 28. Mock Integration Boundaries

Do not hard-code another groupmate's implementation into this prototype.

Instead create temporary adapters.

## Authentication

Prototype:

```dart
PrototypeUser currentUser;
```

Later:

```dart
AuthService.currentUser;
```

## Verification

Prototype:

```dart
currentUser.isVerified;
```

Later:

```dart
VerificationService.isVerified(userId);
```

## Location

Prototype:

```dart
double currentLatitude = 3.145;
double currentLongitude = 101.695;
```

Later:

```dart
LocationService.getCurrentPosition();
```

## Places

Prototype:

```dart
MockNearbyPlaceRepository
```

Later:

```dart
GooglePlacesRepository
```

## Notifications

Prototype:

```dart
showMessage('Your request to join was declined.');
```

Later:

```dart
NotificationService.send(...);
```

---

# 29. Suggested Future REST API Contract

When integrating with your final backend, the repository can map to endpoints similar to these.

```text
GET    /api/travel-groups
GET    /api/travel-groups/{groupId}
POST   /api/travel-groups

POST   /api/travel-groups/{groupId}/join
POST   /api/travel-groups/{groupId}/join-requests

GET    /api/travel-groups/{groupId}/join-requests
PATCH  /api/join-requests/{requestId}

GET    /api/travel-groups/{groupId}/suggestions
POST   /api/travel-groups/{groupId}/suggestions

PUT    /api/suggestions/{suggestionId}/vote
POST   /api/suggestions/{suggestionId}/confirm

GET    /api/travel-groups/{groupId}/itinerary
PUT    /api/travel-groups/{groupId}/itinerary/order

POST   /api/travel-groups/{groupId}/start
PATCH  /api/travel-groups/{groupId}/itinerary/{stopId}/complete
```

These endpoints are recommendations for integration and do not need to exist during the first prototype.

---

# 30. Suggested Database Design for Later Integration

A future backend could use tables similar to:

```text
users
-----
user_id
name
verified_status

travel_groups
-------------
group_id
creator_id
name
destination
description
meetup_point
max_members
join_mode
status
latitude
longitude

travel_group_tags
-----------------
group_id
tag

travel_group_members
--------------------
group_id
user_id
joined_at

join_requests
-------------
request_id
group_id
traveller_id
status
created_at

group_suggestions
-----------------
suggestion_id
group_id
suggested_by
place_name
category
distance_km
crowd_level
latitude
longitude
confirmed

suggestion_votes
----------------
suggestion_id
user_id
vote_type

itinerary_stops
---------------
stop_id
group_id
place_name
position
estimated_duration_minutes
travel_time_from_previous_minutes
status
```

Important unique constraints:

```text
UNIQUE(group_id, user_id)
```

for memberships.

```text
UNIQUE(group_id, traveller_id, active/pending request)
```

for join requests.

```text
UNIQUE(suggestion_id, user_id)
```

for votes.

---

# 31. Prototype Test Scenarios

## Test 1 — Unverified Traveller

1. Set `currentUser.isVerified = false`
2. Open a Travel Group
3. Press Join
4. Verification-required page should appear
5. Traveller should not be added

Expected:

```text
PASS: Verification gate prevents Travel Group access.
```

---

## Test 2 — Join Open Group

1. Use verified traveller
2. Select open group
3. Press Join Now

Expected:

- Member count increases
- Traveller appears in member list
- Lobby opens

---

## Test 3 — Request-Based Group

1. Select request-based group
2. Press Request to Join

Expected:

- Pending request created
- Request Pending state shown
- Duplicate request blocked

---

## Test 4 — Creator Accepts Request

1. Login/use creator test user
2. Open Join Requests
3. Accept request

Expected:

- Request becomes accepted
- Traveller becomes group member

---

## Test 5 — Creator Declines Request

Expected message:

```text
Your request to join was declined.
```

Traveller is not added.

---

## Test 6 — Group Full

1. Open group where:

```text
memberIds.length == maxMembers
```

Expected:

- Join button disabled
- Group Full displayed

---

## Test 7 — Suggest Location

1. Enter group as member
2. Open Suggestions
3. Add location

Expected:

- Location appears on suggestion board

---

## Test 8 — Voting

1. Upvote suggestion
2. Confirm score increases
3. Change to downvote

Expected:

- Previous upvote is removed
- Downvote is registered
- Ranking refreshes

---

## Test 9 — Confirm Suggestion

1. Use creator
2. Select Add to Itinerary

Expected:

- Suggestion becomes confirmed
- New itinerary stop is created

---

## Test 10 — Reorder Itinerary

1. Drag stop 3 above stop 2

Expected:

- Positions change
- Prototype travel times recalculate

---

## Test 11 — Complete Stop

1. Start itinerary
2. Complete first stop

Expected:

```text
Stop 1 = Completed
Stop 2 = Current
Stop 3 = Upcoming
```

---

# 32. Minimum Prototype Completion Criteria

The module can be considered ready for group integration when all of the following work:

- [ ] Nearby Travel Group list displays
- [ ] Radius/tag filtering works
- [ ] Group details display correctly
- [ ] Verification gate works
- [ ] Group-full state works
- [ ] Open-group joining works
- [ ] Request-to-join works
- [ ] Creator can accept requests
- [ ] Creator can decline requests
- [ ] Traveller cannot send duplicate requests
- [ ] Traveller can create a Travel Group
- [ ] Lobby displays members
- [ ] Lobby / Suggestions / Itinerary navigation works
- [ ] Members can add suggestions
- [ ] Members can vote
- [ ] Suggestions sort by score
- [ ] Creator can confirm suggestions
- [ ] Confirmed suggestions become itinerary stops
- [ ] Creator can reorder itinerary
- [ ] Creator can start itinerary
- [ ] Creator can complete a stop
- [ ] Next stop becomes current
- [ ] Module works without requiring groupmates' modules

---

# 33. Recommended Development Order

Build the prototype in this order:

```text
1. Models
     ↓
2. Repository Interface
     ↓
3. Mock Repository
     ↓
4. Discovery Screen
     ↓
5. Group Details
     ↓
6. Open / Request Joining
     ↓
7. Create Group
     ↓
8. Lobby
     ↓
9. Suggestions
     ↓
10. Voting
     ↓
11. Itinerary
     ↓
12. Reordering / Completion
     ↓
13. Integration Adapters
```

Do not begin with Google Maps, Firebase, Supabase, WebSockets, or the shared backend unless the group has already finalised those technologies.

First prove that the Travel Group state transitions and UI flow work.

---

# 34. Integration Strategy

When the standalone prototype works, integrate in layers.

### Step 1 — User Module

Replace:

```dart
PrototypeUser
```

with your team's actual authenticated user object.

### Step 2 — Verification Module

Replace:

```dart
currentUser.isVerified
```

with the verification status from the user/profile module.

### Step 3 — Location Module

Replace prototype distance values with the actual current location.

### Step 4 — Places / Maps

Replace hard-coded nearby locations with data from the map or location service.

### Step 5 — Backend

Implement:

```dart
RESTTravelGroupRepository
```

which implements the same `TravelGroupRepository` interface.

Then switch:

```dart
TravelGroupController(
  repository: MockTravelGroupRepository(),
)
```

to:

```dart
TravelGroupController(
  repository: RESTTravelGroupRepository(...),
)
```

The screens should require little or no modification.

---

# 35. Assumptions Used in This Document

The prototype currently assumes:

1. The client application is implemented in Flutter/Dart.
2. Travel Groups are nearby/impromptu groups rather than scheduled trip-planning groups.
3. A verified traveller is required to create or join a group.
4. The module will eventually receive authentication, verification, maps, places, notifications, and backend services from other parts of the project.
5. Real-time synchronization is not required for the first standalone prototype.
6. A page refresh/controller reload is acceptable for demonstrating another user's actions during prototype testing.
7. The creator controls final itinerary confirmation and stop completion.
8. Members can suggest and vote, but cannot directly modify the confirmed itinerary.

If your group's final requirements differ from any of these assumptions, change the relevant interface or business rule before integrating the module rather than rewriting the entire prototype.

---

# 36. Optional Upgrade After the Basic Prototype

After the minimum prototype works, the most useful upgrades are:

```text
Mock Repository
      ↓
Supabase / REST backend
      ↓
Real authenticated users
      ↓
Realtime lobby updates
      ↓
Real GPS distance
      ↓
Google Places
      ↓
Google Routes / Directions
      ↓
Push notifications
```

These are integration enhancements, not requirements for proving the standalone Travel Group functionality.

---

## Final Prototype Goal

The standalone prototype should demonstrate this complete scenario:

```text
Verified traveller
    ↓
Discovers nearby group
    ↓
Joins / requests access
    ↓
Enters Travel Group lobby
    ↓
Suggests nearby activity
    ↓
Members vote
    ↓
Creator confirms activity
    ↓
Activity enters itinerary
    ↓
Creator reorders route
    ↓
Group starts itinerary
    ↓
Stops are completed one-by-one
```

Once this flow works using the mock repository, the Travel Group module is ready to be connected to the group project's actual authentication, database, mapping, and notification implementations.
