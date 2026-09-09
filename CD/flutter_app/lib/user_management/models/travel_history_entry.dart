class TravelHistoryEntry {
  const TravelHistoryEntry({
    required this.id,
    required this.title,
    required this.destination,
    required this.startedAt,
    required this.completedAt,
  });

  final String id;
  final String title;
  final String destination;
  final DateTime startedAt;
  final DateTime completedAt;

  factory TravelHistoryEntry.fromSupabase(Map<String, dynamic> row) {
    final group = row['travel_groups'];
    final groupData = group is Map
        ? Map<String, dynamic>.from(group)
        : const <String, dynamic>{};
    return TravelHistoryEntry(
      id: row['id'] as String,
      title: groupData['name'] as String? ?? 'Completed trip',
      destination: groupData['destination'] as String? ?? 'Unknown destination',
      startedAt: DateTime.parse(row['started_at'] as String),
      completedAt: DateTime.parse(row['ended_at'] as String),
    );
  }
}
