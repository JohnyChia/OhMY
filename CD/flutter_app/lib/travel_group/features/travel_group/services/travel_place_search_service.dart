import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:flutter_app/user_management/config/travel_preference_options.dart';

import '../models/travel_group_models.dart';

TravelGroupPlace? recommendationAnchorFor(
  TravelGroup group,
  List<ItineraryStop> itinerary,
) {
  final visited = itinerary
      .where((stop) => stop.status != StopStatus.upcoming)
      .toList(growable: false);
  if (visited.isNotEmpty) {
    final stop = visited.last;
    if (stop.latitude != null && stop.longitude != null) {
      return TravelGroupPlace(
        id: stop.placeId ?? stop.id,
        name: stop.placeName,
        address: '',
        latitude: stop.latitude!,
        longitude: stop.longitude!,
      );
    }
  }
  final latitude = group.destinationLatitude;
  final longitude = group.destinationLongitude;
  if (latitude == null || longitude == null) return null;
  return TravelGroupPlace(
    id: group.destinationPlaceId ?? group.id,
    name: group.destination,
    address: group.destinationAddress,
    latitude: latitude,
    longitude: longitude,
    photoName: group.destinationPhotoName,
  );
}

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
    bool areasOnly = false,
  }) async {
    final restrictToPlaces = placesOnly && !areasOnly;
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final response = await _client.post(
      Uri.parse('$backendUrl/api/places/search'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'query': normalized,
        'placesOnly': restrictToPlaces,
        'areasOnly': areasOnly,
      }),
    );
    final body = _decode(response);
    return List<Map<String, dynamic>>.from(body['places'] ?? const [])
        .where((place) => !areasOnly || place['isArea'] == true)
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
    final supportedPreferences = preferences
        .where(culturalTravelPreferenceOptions.contains)
        .toList(growable: false);
    final hasPreferences = supportedPreferences.isNotEmpty;
    final response = await _client.post(
      Uri.parse('$backendUrl/api/recommendations/nearby-tagged'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'mode': hasPreferences ? 'preferences' : 'destination',
        if (hasPreferences) 'preferences': supportedPreferences,
        if (!hasPreferences && hasDestination)
          'destinationPlaceId': destinationPlaceId,
        if (hasDestination) 'excludePlaceId': destinationPlaceId,
      }),
    );
    final body = _decode(response);
    return List<Map<String, dynamic>>.from(body['matchedPlaces'] ?? const [])
        .map(_fromRecommendation)
        .whereType<NearbyPlace>()
        .take(12)
        .toList(growable: false);
  }

  Future<List<NearbyPlace>> searchNearbyByText({
    required String query,
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final response = await _client.post(
      Uri.parse('$backendUrl/api/places/search'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'query': normalized,
        'placesOnly': true,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': (radiusKm * 1000).round(),
      }),
    );
    final body = _decode(response);
    return List<Map<String, dynamic>>.from(body['places'] ?? const [])
        .map(
          (place) => _fromNearbySearchResult(
            place,
            latitude: latitude,
            longitude: longitude,
          ),
        )
        .whereType<NearbyPlace>()
        .where((place) => place.distanceKm <= radiusKm)
        .take(12)
        .toList(growable: false);
  }

  NearbyPlace? _fromRecommendation(Map<String, dynamic> item) {
    final place = Map<String, dynamic>.from(item['place'] as Map? ?? const {});
    final name = place['displayName']?['text']?.toString();
    if (name == null || name.trim().isEmpty) return null;
    final distanceKm = (place['distanceKm'] as num?)?.toDouble();
    final tags = List<String>.from(
      (item['matchedPreferences'] as List? ?? const []).map(
        (tag) => tag.toString(),
      ),
    );
    final location = Map<String, dynamic>.from(
      place['location'] as Map? ?? const {},
    );
    final category = tags.isNotEmpty
        ? tags.first
        : _readablePlaceType(
            place['primaryTypeDisplayName']?.toString() ??
                place['primaryType']?.toString(),
          );
    final photo = Map<String, dynamic>.from(place['photo'] as Map? ?? const {});
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
      photoName: photo['name']?.toString(),
    );
  }

  NearbyPlace? _fromNearbySearchResult(
    Map<String, dynamic> place, {
    required double latitude,
    required double longitude,
  }) {
    final location = Map<String, dynamic>.from(
      place['location'] as Map? ?? const {},
    );
    final placeLatitude = (location['latitude'] as num?)?.toDouble();
    final placeLongitude = (location['longitude'] as num?)?.toDouble();
    final name = place['displayName']?['text']?.toString().trim();
    if (name == null ||
        name.isEmpty ||
        placeLatitude == null ||
        placeLongitude == null) {
      return null;
    }
    final displayType = place['primaryTypeDisplayName'];
    final rawType = displayType is Map
        ? displayType['text']?.toString()
        : displayType?.toString() ?? place['primaryType']?.toString();
    final category = _readablePlaceType(rawType);
    final photos = List<Map<String, dynamic>>.from(
      place['photos'] as List? ?? const [],
    );
    return NearbyPlace(
      name: name,
      source: 'Google Places search',
      category: category,
      distanceKm: _distanceKm(
        latitude,
        longitude,
        placeLatitude,
        placeLongitude,
      ),
      crowdLevel: 'Unknown',
      durationMinutes: 60,
      tags: [category],
      placeId: place['id']?.toString(),
      latitude: placeLatitude,
      longitude: placeLongitude,
      photoName: photos.firstOrNull?['name']?.toString(),
    );
  }

  double _distanceKm(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    double radians(double degrees) => degrees * math.pi / 180;
    const earthRadiusKm = 6371.0;
    final latitudeDelta = radians(endLatitude - startLatitude);
    final longitudeDelta = radians(endLongitude - startLongitude);
    final value =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(radians(startLatitude)) *
            math.cos(radians(endLatitude)) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusKm *
        2 *
        math.atan2(math.sqrt(value), math.sqrt(1 - value));
  }

  String _readablePlaceType(String? value) {
    final words = (value ?? '')
        .trim()
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (words.isEmpty) return 'Place';
    return '${words[0].toUpperCase()}${words.substring(1).toLowerCase()}';
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
