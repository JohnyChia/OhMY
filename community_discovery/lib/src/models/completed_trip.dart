class CompletedTrip {
  const CompletedTrip({
    required this.id,
    required this.title,
    required this.locationName,
    required this.attractionName,
    required this.completedAt,
    this.communityPostId,
  });

  final String id;
  final String title;
  final String locationName;
  final String attractionName;
  final DateTime completedAt;
  final String? communityPostId;

  bool get hasCommunityPost => communityPostId != null;

  factory CompletedTrip.fromMap(Map<String, dynamic> map) => CompletedTrip(
    id: map['id'].toString(),
    title: map['title'] as String? ?? 'Completed trip',
    locationName: map['location_name'] as String? ?? '',
    attractionName:
        map['attraction_name'] as String? ??
        map['location_name'] as String? ??
        '',
    completedAt: DateTime.parse(map['ended_at'] as String),
    communityPostId: map['community_post_id'] as String?,
  );
}
