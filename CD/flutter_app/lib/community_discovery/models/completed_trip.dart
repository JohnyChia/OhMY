class CompletedTrip {
  const CompletedTrip({
    required this.id,
    required this.title,
    required this.locationName,
    required this.attractionName,
    required this.completedAt,
  });

  final String id;
  final String title;
  final String locationName;
  final String attractionName;
  final DateTime completedAt;

  factory CompletedTrip.fromMap(Map<String, dynamic> map) => CompletedTrip(
    id: map['id'] as String,
    title: map['title'] as String,
    locationName: map['location_name'] as String,
    attractionName: map['attraction_name'] as String,
    completedAt: DateTime.parse(map['ended_at'] as String),
  );
}
