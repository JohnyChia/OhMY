class SavedLocation {
  const SavedLocation({
    required this.id,
    required this.contentHash,
    required this.googlePlaceId,
    required this.title,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.tags,
    required this.summary,
    required this.metadata,
  });

  final String id;
  final String contentHash;
  final String? googlePlaceId;
  final String title;
  final String address;
  final double latitude;
  final double longitude;
  final List<String> tags;
  final String summary;
  final Map<String, dynamic> metadata;

  factory SavedLocation.fromRow(Map<String, dynamic> row) {
    final metadata = Map<String, dynamic>.from(
      row['metadata'] as Map? ?? const {},
    );
    return SavedLocation(
      id: row['id']?.toString() ?? '',
      contentHash: row['content_hash']?.toString() ?? '',
      googlePlaceId: row['google_place_id']?.toString(),
      title: row['title']?.toString() ?? 'Saved place',
      address: row['location_hint']?.toString() ?? '',
      latitude: (row['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (row['longitude'] as num?)?.toDouble() ?? 0,
      tags: List<String>.from(row['travel_tags'] as List? ?? const []),
      summary: row['summary']?.toString() ?? '',
      metadata: metadata,
    );
  }

  Map<String, dynamic> get place => Map<String, dynamic>.from(
    metadata['place'] as Map? ??
        {
          'id': googlePlaceId,
          'displayName': {'text': title},
          'formattedAddress': address,
          'location': {'latitude': latitude, 'longitude': longitude},
        },
  );

  Map<String, dynamic> toRecommendationItem() => {
    'place': place,
    'analysis': Map<String, dynamic>.from(
      metadata['analysis'] as Map? ?? const {},
    ),
    if (metadata['ranking'] is Map)
      'ranking': Map<String, dynamic>.from(metadata['ranking'] as Map),
    if (metadata['matchedPreferences'] is List)
      'matchedPreferences': List<dynamic>.from(
        metadata['matchedPreferences'] as List,
      ),
  };

  String? get photoName {
    final direct = (place['photo'] as Map?)?['name']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final photos = place['photos'];
    if (photos is List && photos.isNotEmpty && photos.first is Map) {
      final first = (photos.first as Map)['name']?.toString().trim();
      if (first != null && first.isNotEmpty) return first;
    }
    return null;
  }

  String get locationLabel {
    final components = address
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (components.length >= 2) return components[components.length - 2];
    return components.isEmpty ? 'Malaysia' : components.first;
  }
}
