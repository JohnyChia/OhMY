enum JoinMode { open, request }

enum GroupStatus { waiting, active, completed }

enum JoinRequestStatus { pending, accepted, declined }

enum StopStatus { upcoming, current, completed }

class PrototypeUser {
  PrototypeUser(
      {required this.id, required this.name, required this.isVerified});

  final String id;
  final String name;
  bool isVerified;
}

class TravelGroup {
  TravelGroup({
    required this.id,
    required this.creatorId,
    required this.creatorName,
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
    this.meetupNote = '',
  });

  final String id;
  final String creatorId;
  final String creatorName;
  String name;
  String destination;
  String description;
  String meetupPoint;
  String meetupNote;
  List<String> tags;
  int maxMembers;
  double distanceKm;
  JoinMode joinMode;
  GroupStatus status;
  List<String> memberIds;

  bool get isFull => memberIds.length >= maxMembers;
}

class JoinRequest {
  JoinRequest({
    required this.id,
    required this.groupId,
    required this.travellerId,
    required this.travellerName,
    this.status = JoinRequestStatus.pending,
  });

  final String id;
  final String groupId;
  final String travellerId;
  final String travellerName;
  JoinRequestStatus status;
}

class GroupSuggestion {
  GroupSuggestion({
    required this.id,
    required this.groupId,
    required this.suggestedByUserId,
    required this.placeName,
    required this.source,
    required this.category,
    required this.distanceKm,
    required this.crowdLevel,
    required this.durationMinutes,
    required this.tags,
    Set<String>? upvoterIds,
    Set<String>? downvoterIds,
    this.isConfirmed = false,
  })  : upvoterIds = upvoterIds ?? <String>{},
        downvoterIds = downvoterIds ?? <String>{};

  final String id;
  final String groupId;
  final String suggestedByUserId;
  final String placeName;
  final String source;
  final String category;
  final double distanceKm;
  final String crowdLevel;
  final int durationMinutes;
  final List<String> tags;
  final Set<String> upvoterIds;
  final Set<String> downvoterIds;
  bool isConfirmed;

  int get score => upvoterIds.length - downvoterIds.length;
}

class ItineraryStop {
  ItineraryStop({
    required this.id,
    required this.groupId,
    required this.suggestionId,
    required this.placeName,
    required this.position,
    required this.estimatedDurationMinutes,
    required this.travelTimeFromPreviousMinutes,
    this.status = StopStatus.upcoming,
  });

  final String id;
  final String groupId;
  final String suggestionId;
  final String placeName;
  int position;
  int estimatedDurationMinutes;
  int travelTimeFromPreviousMinutes;
  StopStatus status;
}

class NearbyPlace {
  const NearbyPlace({
    required this.name,
    required this.source,
    required this.category,
    required this.distanceKm,
    required this.crowdLevel,
    required this.durationMinutes,
    required this.tags,
  });

  final String name;
  final String source;
  final String category;
  final double distanceKm;
  final String crowdLevel;
  final int durationMinutes;
  final List<String> tags;
}

class TravelGroupException implements Exception {
  const TravelGroupException(this.message, [this.code = 'travel_group_error']);

  final String message;
  final String code;

  @override
  String toString() => message;
}
