enum JoinMode { open, request }

enum GroupStatus { waiting, active, completed, cancelled }

enum GroupTripPhase {
  recruiting,
  gathering,
  navigating,
  choosingNext,
  completed,
  cancelled,
}

enum JoinRequestStatus { pending, accepted, declined }

enum StopStatus { upcoming, current, completed }

class PrototypeUser {
  PrototypeUser({
    required this.id,
    required this.name,
    required this.isVerified,
  });

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
    this.destinationPlaceId,
    this.destinationAddress = '',
    this.destinationLatitude,
    this.destinationLongitude,
    this.destinationPhotoName,
    this.meetupLatitude,
    this.meetupLongitude,
    this.confirmedAt,
    this.tripPhase = GroupTripPhase.recruiting,
    int? memberCount,
  }) : memberCount = memberCount ?? memberIds.length;

  final String id;
  final String creatorId;
  final String creatorName;
  String name;
  String destination;
  String description;
  String meetupPoint;
  String meetupNote;
  String? destinationPlaceId;
  String destinationAddress;
  double? destinationLatitude;
  double? destinationLongitude;
  String? destinationPhotoName;
  double? meetupLatitude;
  double? meetupLongitude;
  DateTime? confirmedAt;
  GroupTripPhase tripPhase;
  int memberCount;
  List<String> tags;
  int maxMembers;
  double distanceKm;
  JoinMode joinMode;
  GroupStatus status;
  List<String> memberIds;

  bool get isFull => memberCount >= maxMembers;
  bool get isConfirmed => confirmedAt != null;
}

class TravelGroupTripSession {
  const TravelGroupTripSession({
    required this.id,
    required this.groupId,
    required this.phase,
    this.currentStopId,
    this.currentStopIndex = 0,
  });

  final String id;
  final String groupId;
  final GroupTripPhase phase;
  final String? currentStopId;
  final int currentStopIndex;
}

class TravelGroupPlace {
  const TravelGroupPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.photoName,
  });

  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String? photoName;

  TravelGroupPlace copyWith({String? photoName}) => TravelGroupPlace(
    id: id,
    name: name,
    address: address,
    latitude: latitude,
    longitude: longitude,
    photoName: photoName ?? this.photoName,
  );
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
    this.placeId,
    this.latitude,
    this.longitude,
    this.isConfirmed = false,
  }) : upvoterIds = upvoterIds ?? <String>{},
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
  final String? placeId;
  final double? latitude;
  final double? longitude;
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
    this.travelDistanceFromPreviousKm = 0,
    this.placeId,
    this.latitude,
    this.longitude,
    this.status = StopStatus.upcoming,
  });

  final String id;
  final String groupId;
  final String suggestionId;
  final String placeName;
  final String? placeId;
  final double? latitude;
  final double? longitude;
  int position;
  int estimatedDurationMinutes;
  int travelTimeFromPreviousMinutes;
  double travelDistanceFromPreviousKm;
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
    this.placeId,
    this.latitude,
    this.longitude,
  });

  final String name;
  final String source;
  final String category;
  final double distanceKm;
  final String crowdLevel;
  final int durationMinutes;
  final List<String> tags;
  final String? placeId;
  final double? latitude;
  final double? longitude;
}

class TravelGroupException implements Exception {
  const TravelGroupException(this.message, [this.code = 'travel_group_error']);

  final String message;
  final String code;

  @override
  String toString() => message;
}
