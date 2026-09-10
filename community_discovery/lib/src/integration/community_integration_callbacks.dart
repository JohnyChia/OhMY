import 'dart:async';

class StartJourneyRequest {
  const StartJourneyRequest({
    required this.postId,
    required this.attractionName,
    required this.destinationName,
  });
  final String postId;
  final String attractionName;
  final String destinationName;
}

typedef StartJourneyCallback =
    FutureOr<void> Function(StartJourneyRequest request);

class CommunityIntegrationCallbacks {
  const CommunityIntegrationCallbacks({this.onStartJourney});
  final StartJourneyCallback? onStartJourney;
}
