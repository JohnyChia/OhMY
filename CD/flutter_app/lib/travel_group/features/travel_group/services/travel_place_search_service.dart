import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/travel_group_models.dart';

class TravelPlaceSearchService {
  TravelPlaceSearchService({http.Client? client, String? backendUrl})
    : _client = client ?? http.Client(),
      backendUrl =
          backendUrl ??
          const String.fromEnvironment(
            'BACKEND_URL',
            defaultValue: 'http://127.0.0.1:3000',
          );

  final http.Client _client;
  final String backendUrl;
  final Map<String, Future<String?>> _photoCache = {};

  Future<String> areaForCoordinates({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$backendUrl/api/location/area').replace(
      queryParameters: {
        'lat': latitude.toString(),
        'lon': longitude.toString(),
      },
    );
    final response = await _client.get(uri);
    final body = _decode(response);
    return body['area']?.toString().trim().isNotEmpty == true
        ? body['area'].toString()
        : 'Current area';
  }

  Future<List<TravelGroupPlace>> search(
    String query, {
    bool placesOnly = true,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final response = await _client.post(
      Uri.parse('$backendUrl/api/places/search'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'query': normalized, 'placesOnly': placesOnly}),
    );
    final body = _decode(response);
    return List<Map<String, dynamic>>.from(body['places'] ?? const [])
        .map(_fromSearchResult)
        .whereType<TravelGroupPlace>()
        .toList(growable: false);
  }

  Future<List<NearbyPlace>> nearbySuggestions({
    required double latitude,
    required double longitude,
    String? destinationPlaceId,
    List<String> preferences = const [],
  }) async {
    final hasDestination =
        destinationPlaceId != null && destinationPlaceId.trim().isNotEmpty;
    final response = await _client.post(
      Uri.parse('$backendUrl/api/recommendations/nearby-tagged'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        if (hasDestination) 'mode': 'destination',
        if (hasDestination) 'destinationPlaceId': destinationPlaceId,
        if (!hasDestination) 'mode': 'preferences',
        if (!hasDestination) 'preferences': preferences,
      }),
    );
    final body = _decode(response);
    return List<Map<String, dynamic>>.from(body['matchedPlaces'] ?? const [])
        .map(_fromRecommendation)
        .whereType<NearbyPlace>()
        .take(12)
        .toList(growable: false);
  }

  NearbyPlace? _fromRecommendation(Map<String, dynamic> item) {
    final place = Map<String, dynamic>.from(item['place'] as Map? ?? const {});
    final name = place['displayName']?['text']?.toString();
    if (name == null || name.trim().isEmpty) return null;
    final distanceKm = (place['distanceKm'] as num?)?.toDouble();
    final category =
        place['primaryTypeDisplayName']?.toString() ??
        place['primaryType']?.toString() ??
        'Place';
    final tags = List<String>.from(
      (item['matchedPreferences'] as List? ?? const []).map(
        (tag) => tag.toString(),
      ),
    );
    final location = Map<String, dynamic>.from(
      place['location'] as Map? ?? const {},
    );
    return NearbyPlace(
      name: name,
      source: 'Google Places',
      category: category,
      distanceKm: distanceKm ?? 0.0,
      crowdLevel: 'Unknown',
      durationMinutes: 60,
      tags: tags.isEmpty ? [category] : tags,
      placeId: place['id']?.toString(),
      latitude: (location['latitude'] as num?)?.toDouble(),
      longitude: (location['longitude'] as num?)?.toDouble(),
    );
  }

  Future<TravelGroupPlace> loadDetails(TravelGroupPlace place) async {
    final response = await _client.post(
      Uri.parse('$backendUrl/api/places/details'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'placeId': place.id}),
    );
    final body = _decode(response);
    final details = Map<String, dynamic>.from(
      body['place'] as Map? ?? const {},
    );
    final photo = Map<String, dynamic>.from(
      details['photo'] as Map? ?? const {},
    );
    return place.copyWith(photoName: photo['name']?.toString());
  }

  String photoUrl(String photoName) =>
      '$backendUrl/api/places/photo?name=${Uri.encodeQueryComponent(photoName)}';

  Future<String?> photoForDestination(
    String destination, {
    String? knownPhotoName,
  }) {
    if (knownPhotoName != null && knownPhotoName.isNotEmpty) {
      return Future.value(photoUrl(knownPhotoName));
    }
    return _photoCache.putIfAbsent(destination, () async {
      try {
        final matches = await search(destination);
        if (matches.isEmpty) return null;
        final match = matches.first;
        final details = match.photoName == null
            ? await loadDetails(match)
            : match;
        final photoName = details.photoName;
        return photoName == null ? null : photoUrl(photoName);
      } catch (_) {
        return null;
      }
    });
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TravelGroupException(
        body['error']?.toString() ?? 'Place search failed.',
        'place_search_failed',
      );
    }
    return body;
  }

  TravelGroupPlace? _fromSearchResult(Map<String, dynamic> place) {
    final location = Map<String, dynamic>.from(
      place['location'] as Map? ?? const {},
    );
    final latitude = (location['latitude'] as num?)?.toDouble();
    final longitude = (location['longitude'] as num?)?.toDouble();
    final id = place['id']?.toString();
    if (id == null || latitude == null || longitude == null) return null;
    return TravelGroupPlace(
      id: id,
      name: place['displayName']?['text']?.toString() ?? 'Selected place',
      address: place['formattedAddress']?.toString() ?? '',
      latitude: latitude,
      longitude: longitude,
      photoName: ((place['photos'] as List?)?.firstOrNull as Map?)?['name']
          ?.toString(),
    );
  }

  void dispose() => _client.close();
}
