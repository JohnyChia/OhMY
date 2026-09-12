import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../features/routes/route_feature.dart';
import '../features/routes/navigation_sensor.dart';
import '../features/weather/weather_feature.dart';
import '../widgets/wau_loading_indicator.dart';
import '../../user_management/services/traveler_profile_service.dart';
import '../../user_management/services/saved_location_service.dart';
import 'package:community_discovery/community_discovery.dart'
    show SupabaseConfig;
import '../../shared/services/recommendation_sound.dart';
import '../../shared/utils/place_description.dart';

const blue = Color(0xff3266cc),
    ink = Color(0xff14213d),
    muted = Color(0xff68748b),
    soft = Color(0xffedf4ff);

class PlaceMapPage extends StatefulWidget {
  const PlaceMapPage({
    super.key,
    this.autofocusSearch = false,
    this.initialRecommendation,
    this.initialSearchQuery,
  });
  final bool autofocusSearch;
  final Map<String, dynamic>? initialRecommendation;
  final String? initialSearchQuery;
  @override
  State<PlaceMapPage> createState() => _PlaceMapPageState();
}

class _PlaceMapPageState extends State<PlaceMapPage> {
  static const double recommendationPanelHeight = 258;
  static const backend = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final Object searchTapGroup = Object();
  final recommendationPage = PageController(viewportFraction: .9);
  Timer? searchDebounce;
  Timer? messageTimer;
  int searchRequest = 0;
  Future<BitmapDescriptor>? recommendationMarkerFuture;
  GoogleMapController? controller;
  MethodChannel? poiChannel;
  List<Map<String, dynamic>> results = [], recommendations = [];
  Map<String, dynamic>? selected;
  Set<Marker> markers = {};
  bool loading = false, showCarousel = false, bookmarked = false;
  bool trafficEnabled = false;
  bool showWeatherPill = false, weatherLoading = false;
  WeatherOverview? weather;
  Position? currentPosition;
  bool locationPermissionGranted = false;
  String? message;
  String recommendationTitle = 'Based on your preferences';
  String? highlightedRecommendationId;
  final Set<String> bookmarkedRecommendations = {};
  bool initialRecommendationApplied = false;

  @override
  void initState() {
    super.initState();
    completedJourneyLocation.addListener(_resumeAtCompletedJourneyLocation);
    currentTravelerPreferences.addListener(_onPreferencesChanged);
    savedLocationService.changes.addListener(_onSavedLocationsChanged);
    unawaited(_loadSavedLocations());
    unawaited(initializeCurrentLocation());
    if (widget.autofocusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) searchFocus.requestFocus();
      });
    }
    final initialQuery = widget.initialSearchQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) {
      search.text = initialQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        searchFocus.requestFocus();
        unawaited(runSearch(query: initialQuery));
      });
    }
  }

  Future<void> _loadSavedLocations() async {
    try {
      await savedLocationService.fetch(force: true);
      _onSavedLocationsChanged();
    } on SavedLocationFailure {
      // Saving will surface a useful message if the user taps the button.
    }
  }

  void _onSavedLocationsChanged() {
    if (!mounted) return;
    final selectedItem = selected;
    setState(() {
      bookmarkedRecommendations
        ..clear()
        ..addAll(
          savedLocationService.cached
              .map((location) => location.googlePlaceId)
              .whereType<String>(),
        );
      bookmarked =
          selectedItem != null && savedLocationService.isSaved(selectedItem);
    });
  }

  Future<void> _toggleBookmark(Map<String, dynamic> item) async {
    try {
      final isSaved = await savedLocationService.toggle(item);
      if (!mounted) return;
      setState(() {
        bookmarked = selected == item ? isSaved : bookmarked;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSaved
                ? 'Location saved to bookmarks.'
                : 'Location removed from bookmarks.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } on SavedLocationFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    }
  }

  void _onPreferencesChanged() {
    if (!mounted) return;
    setState(() {
      if (recommendationTitle == 'Based on your preferences') {
        recommendations = [];
        markers = {};
        showCarousel = false;
        highlightedRecommendationId = null;
      }
    });
  }

  void _resumeAtCompletedJourneyLocation() {
    final location = completedJourneyLocation.value;
    if (!mounted || location == null) return;
    completedJourneyLocation.value = null;
    final latest = Position(
      longitude: location.longitude,
      latitude: location.latitude,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    setState(() => currentPosition = latest);
    unawaited(moveMapTo(latest, zoom: 16));
  }

  Future<void> initializeCurrentLocation() async {
    final value = await position();
    if (!mounted || value == null) return;
    setState(() => currentPosition = value);
    await moveMapTo(value, zoom: 16);
    unawaited(_loadWeather(value, showErrors: false));
  }

  Future<void> _applyInitialRecommendation() async {
    final item = widget.initialRecommendation;
    if (initialRecommendationApplied || item == null || controller == null) {
      return;
    }
    initialRecommendationApplied = true;
    final selectedItem = Map<String, dynamic>.from(item);
    final place = Map<String, dynamic>.from(
      selectedItem['place'] as Map? ?? const {},
    );
    selectedItem['place'] = place;
    final origin = currentPosition ?? await position();
    if (origin != null) await _applyDrivingMetrics(place, origin);
    await choose(selectedItem, true);
  }

  String name(Map p) =>
      p['displayName']?['text']?.toString() ?? 'Selected place';
  String? description(Map p) {
    final value = usablePlaceDescription(p['description']);
    if (value != null) return value;
    final type = p['primaryTypeDisplayName']?.toString().trim() ?? '';
    final address = p['formattedAddress']?.toString().trim() ?? '';
    if (type.isNotEmpty && address.isNotEmpty) return '$type at $address.';
    return null;
  }

  List<String> tags(Map item) => [
    ...List<String>.from(item['analysis']?['generalTags'] ?? []),
    ...List<String>.from(item['analysis']?['culturalTags'] ?? []),
  ];
  String distance(Map p) {
    final v = p['routeDistanceKm'] ?? p['distanceKm'];
    return v is num ? '${v.toStringAsFixed(1)} km' : 'Distance unavailable';
  }

  String eta(Map p) {
    final v = p['etaMinutes'];
    return v is num
        ? '${p['etaEstimated'] == true ? '~' : ''}${v.round()} min'
        : 'ETA unavailable';
  }

  String? photo(Map p) {
    final n = p['photo']?['name']?.toString();
    return n == null
        ? null
        : '$backend/api/places/photo?name=${Uri.encodeQueryComponent(n)}';
  }

  Future<BitmapDescriptor> recommendationMarkerIcon() {
    recommendationMarkerFuture ??= _buildHibiscusMarker();
    return recommendationMarkerFuture!;
  }

  Future<BitmapDescriptor> _buildHibiscusMarker() async {
    const scale = 3.0;
    const width = 46.0;
    const height = 56.0;
    final flowerData = await rootBundle.load(
      'assets/images/preference_recommender/location_mark.png',
    );
    final flowerCodec = await ui.instantiateImageCodec(
      flowerData.buffer.asUint8List(),
      targetWidth: (42 * scale).round(),
      targetHeight: (42 * scale).round(),
    );
    final flowerFrame = await flowerCodec.getNextFrame();
    final flowerImage = flowerFrame.image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    final pointer = Path()
      ..moveTo(15.5, 33)
      ..quadraticBezierTo(18, 45, width / 2, height)
      ..quadraticBezierTo(28, 45, 30.5, 33)
      ..close();
    canvas.drawPath(
      pointer,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 3.2,
    );
    canvas.drawPath(pointer, Paint()..color = const Color(0xFFFF5A7D));
    canvas.drawImageRect(
      flowerImage,
      Rect.fromLTWH(
        0,
        0,
        flowerImage.width.toDouble(),
        flowerImage.height.toDouble(),
      ),
      const Rect.fromLTWH(2, 0, 42, 42),
      Paint()..filterQuality = FilterQuality.high,
    );

    final image = await recorder.endRecording().toImage(
      (width * scale).round(),
      (height * scale).round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    flowerImage.dispose();
    flowerCodec.dispose();
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: scale * 1.5,
    );
  }

  Future<Map<String, dynamic>> post(String path, Map body) async {
    final r = await http.post(
      Uri.parse('$backend$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Request failed');
    }
    return data;
  }

  Future<Position?> position() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      return null;
    }
    if (mounted && !locationPermissionGranted) {
      setState(() => locationPermissionGranted = true);
    }
    final value = await Geolocator.getCurrentPosition(
      locationSettings: navigationLocationSettings,
    );
    if (mounted) currentPosition = value;
    return value;
  }

  Future<void> moveMapTo(Position value, {double zoom = 15}) async {
    await controller?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(value.latitude, value.longitude), zoom),
    );
  }

  double km(Position a, Map b) {
    double rad(double n) => n * math.pi / 180;
    const r = 6371.0;
    final p1 = rad(a.latitude), p2 = rad((b['latitude'] as num).toDouble());
    final dp = p2 - p1,
        dl = rad((b['longitude'] as num).toDouble() - a.longitude);
    final x =
        math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return r * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  void searchChanged(String value) {
    searchDebounce?.cancel();
    final query = value.trim();
    final request = ++searchRequest;
    if (query.isEmpty) {
      setState(() {
        results = [];
        loading = false;
        message = null;
      });
      return;
    }
    searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(runSearch(query: query, request: request)),
    );
  }

  void dismissSearchResults() {
    searchFocus.unfocus();
    if (results.isNotEmpty) setState(() => results = []);
  }

  Future<void> runSearch({String? query, int? request}) async {
    final requestedQuery = (query ?? search.text).trim();
    if (requestedQuery.isEmpty) {
      if (mounted) setState(() => results = []);
      return;
    }
    searchDebounce?.cancel();
    final requestedId = request ?? ++searchRequest;
    setState(() {
      loading = true;
      results = [];
      showCarousel = false;
      showWeatherPill = false;
      message = 'Searching places…';
    });
    try {
      final d = await post('/api/places/search', {'query': requestedQuery});
      if (mounted &&
          requestedId == searchRequest &&
          search.text.trim() == requestedQuery) {
        setState(() {
          results = List<Map<String, dynamic>>.from(d['places'] ?? []);
          message = results.isEmpty ? 'No places found.' : null;
        });
        _scheduleMessageDismissal();
      }
    } catch (e) {
      if (requestedId == searchRequest) fail(e);
    } finally {
      if (mounted && requestedId == searchRequest) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> selectPlace(String id) async {
    setState(() {
      loading = true;
      results = [];
      showCarousel = false;
      showWeatherPill = false;
      message = 'Fetching reviews and assigning tags…';
    });
    try {
      final positionFuture = position();
      Map<String, dynamic> item;
      try {
        item = await post('/api/places/analyze', {'placeId': id});
      } catch (_) {
        item = await post('/api/places/details', {'placeId': id});
        item['analysis'] = const <String, dynamic>{
          'generalTags': <String>[],
          'culturalTags': <String>[],
        };
      }
      final pos = await positionFuture;
      final p = item['place'] as Map<String, dynamic>;
      if (pos != null && p['location'] != null) {
        await _applyDrivingMetrics(p, pos);
      }
      await choose(item, true);
    } catch (e) {
      fail(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<List<String>> _travelerPreferences() async {
    if (!SupabaseConfig.isConfigured) {
      throw Exception(
        'Sign-in services are not configured. Start the app with run-ohmy.ps1.',
      );
    }
    return TravelerProfileService().requireCurrentPreferences();
  }

  Future<void> _applyDrivingMetrics(
    Map<String, dynamic> place,
    Position origin,
  ) async {
    final location = place['location'];
    if (location is! Map ||
        location['latitude'] is! num ||
        location['longitude'] is! num) {
      return;
    }
    final uri = Uri.parse('$backend/api/routes').replace(
      queryParameters: {
        'startLat': '${origin.latitude}',
        'startLon': '${origin.longitude}',
        'endLat': '${location['latitude']}',
        'endLon': '${location['longitude']}',
      },
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = List<Map<String, dynamic>>.from(data['routes'] ?? []);
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          routes.isNotEmpty) {
        final route = routes.first;
        place['routeDistanceKm'] = route['distanceKm'];
        place['etaMinutes'] = route['durationMinutes'];
        place['etaEstimated'] = false;
        return;
      }
    } catch (_) {
      // Retain an explicitly marked estimate if live routing is unavailable.
    }
    final directDistance = km(origin, location);
    place['distanceKm'] = directDistance;
    place['etaMinutes'] = math.max(2, (directDistance * 2).ceil());
    place['etaEstimated'] = true;
  }

  Future<void> choose(Map<String, dynamic> item, bool create) async {
    final p = item['place'] as Map<String, dynamic>,
        l = p['location'] as Map<String, dynamic>;
    final target = LatLng(
      (l['latitude'] as num).toDouble(),
      (l['longitude'] as num).toDouble(),
    );
    final markerIcon = create ? await recommendationMarkerIcon() : null;
    if (!mounted) return;
    setState(() {
      selected = item;
      highlightedRecommendationId = null;
      bookmarked = savedLocationService.isSaved(item);
      message = null;
      if (create) {
        markers = {
          Marker(
            markerId: MarkerId(p['id'].toString()),
            position: target,
            icon: markerIcon!,
            onTap: () => setState(() => selected = item),
          ),
        };
      }
    });
    await controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
  }

  Future<void> nearby() async {
    setState(() {
      loading = true;
      selected = null;
      showWeatherPill = false;
      message = 'Discovering and tagging nearby places…';
    });
    try {
      final pos = await position();
      if (pos == null) throw Exception('Location permission is required.');
      final preferences = await _travelerPreferences();
      final d = await post('/api/recommendations/nearby-tagged', {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'mode': 'preferences',
        'preferences': preferences,
      });
      final recommendationIcon = await recommendationMarkerIcon();
      final matched = List<Map<String, dynamic>>.from(d['matchedPlaces'] ?? []),
          m = <Marker>{};
      final visiblePoints = <LatLng>[LatLng(pos.latitude, pos.longitude)];
      for (final item in matched) {
        final p = item['place'] as Map<String, dynamic>,
            l = p['location'] as Map<String, dynamic>;
        final markerPosition = LatLng(
          (l['latitude'] as num).toDouble(),
          (l['longitude'] as num).toDouble(),
        );
        visiblePoints.add(markerPosition);
        m.add(
          Marker(
            markerId: MarkerId(p['id'].toString()),
            position: markerPosition,
            icon: recommendationIcon,
            anchor: const Offset(.5, 1),
            onTap: () => _selectTaggedMarker(item),
          ),
        );
      }
      if (mounted) {
        setState(() {
          recommendations = matched;
          markers = m;
          recommendationTitle = 'Based on your preferences';
          showCarousel = recommendations.isNotEmpty;
          message = recommendations.isEmpty ? 'No matches found.' : null;
        });
        _scheduleMessageDismissal();
      }
      if (matched.isNotEmpty) unawaited(RecommendationSound.play());
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await _showNearbyArea(visiblePoints);
    } catch (e) {
      fail(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> recommendFromSelectedPlace() async {
    final sourceItem = selected;
    final sourcePlace = sourceItem?['place'];
    final sourceLocation = sourcePlace?['location'];
    final sourceId = sourcePlace?['id']?.toString();
    if (sourceItem == null ||
        sourcePlace is! Map ||
        sourceLocation is! Map ||
        sourceId == null ||
        sourceId.isEmpty) {
      fail(Exception('This place cannot be used for recommendations.'));
      return;
    }

    setState(() {
      loading = true;
      showWeatherPill = false;
      message = 'Finding similar places within 10 kmâ€¦';
    });
    try {
      final data = await post('/api/recommendations/nearby-tagged', {
        'latitude': sourceLocation['latitude'],
        'longitude': sourceLocation['longitude'],
        'mode': 'destination',
        'destinationPlaceId': sourceId,
      });
      final recommendationIcon = await recommendationMarkerIcon();
      final matched = List<Map<String, dynamic>>.from(
        data['matchedPlaces'] ?? [],
      );
      final visiblePoints = <LatLng>[
        LatLng(
          (sourceLocation['latitude'] as num).toDouble(),
          (sourceLocation['longitude'] as num).toDouble(),
        ),
      ];
      final recommendationMarkers = <Marker>{};
      for (final item in matched) {
        final place = item['place'];
        final location = place?['location'];
        if (place is! Map || location is! Map) continue;
        final markerPosition = LatLng(
          (location['latitude'] as num).toDouble(),
          (location['longitude'] as num).toDouble(),
        );
        visiblePoints.add(markerPosition);
        recommendationMarkers.add(
          Marker(
            markerId: MarkerId(place['id'].toString()),
            position: markerPosition,
            icon: recommendationIcon,
            anchor: const Offset(.5, 1),
            onTap: () => _selectTaggedMarker(item),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        recommendations = matched;
        markers = recommendationMarkers;
        recommendationTitle = 'Similar to ${name(sourcePlace)}';
        highlightedRecommendationId = null;
        showCarousel = matched.isNotEmpty;
        message = matched.isEmpty
            ? 'No similar places found within 10 km.'
            : null;
      });
      _scheduleMessageDismissal();
      if (matched.isNotEmpty) unawaited(RecommendationSound.play());
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await _showNearbyArea(visiblePoints);
    } catch (error) {
      fail(error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _showNearbyArea(List<LatLng> points) async {
    if (points.isEmpty || controller == null) return;
    if (points.length == 1) {
      await controller!.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 12),
      );
      return;
    }

    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;
    for (final point in points.skip(1)) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    await controller!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        72,
      ),
    );
  }

  void _selectTaggedMarker(Map<String, dynamic> item) {
    final placeId = item['place']?['id'];
    final index = recommendations.indexWhere(
      (candidate) => candidate['place']?['id'] == placeId,
    );
    setState(() {
      highlightedRecommendationId = placeId?.toString();
      showCarousel = true;
    });
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!recommendationPage.hasClients) return;
      recommendationPage.animateToPage(
        index,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _selectCarouselPlace(int index) {
    if (index < 0 || index >= recommendations.length) return;
    final item = recommendations[index];
    final place = item['place'];
    final location = place is Map ? place['location'] : null;
    final placeId = place is Map ? place['id']?.toString() : null;
    if (mounted) {
      setState(() => highlightedRecommendationId = placeId);
    }
    if (location is! Map ||
        location['latitude'] is! num ||
        location['longitude'] is! num) {
      return;
    }
    unawaited(
      controller?.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(
                (location['latitude'] as num).toDouble(),
                (location['longitude'] as num).toDouble(),
              ),
              15,
            ),
          ) ??
          Future<void>.value(),
    );
  }

  void fail(Object e) {
    if (mounted) {
      setState(() => message = e.toString().replaceFirst('Exception: ', ''));
      _scheduleMessageDismissal();
    }
  }

  void _scheduleMessageDismissal() {
    messageTimer?.cancel();
    final currentMessage = message;
    if (currentMessage == null) return;
    messageTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || message != currentMessage) return;
      setState(() => message = null);
    });
  }

  void toggleTraffic() => setState(() => trafficEnabled = !trafficEnabled);

  Future<void> moveToCurrentLocation() async {
    final currentPosition = await position();
    if (currentPosition == null) {
      fail(Exception('Location permission is required.'));
      return;
    }
    await moveMapTo(currentPosition);
  }

  Future<void> toggleWeather() async {
    if (showWeatherPill) {
      setState(() => showWeatherPill = false);
      return;
    }
    setState(() => showWeatherPill = true);
    if (weather != null || weatherLoading) return;
    try {
      final currentPosition = await position();
      if (currentPosition == null) {
        throw Exception('Location permission is required for weather.');
      }
      await _loadWeather(currentPosition, showErrors: true);
    } catch (error) {
      if (mounted) {
        setState(() {
          showWeatherPill = false;
          message = error.toString().replaceFirst('Exception: ', '');
        });
        _scheduleMessageDismissal();
      }
    }
  }

  Future<void> openWeatherPage() async {
    final overview = weather;
    if (overview == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WeatherDetailPage(weather: overview),
      ),
    );
  }

  Future<void> _loadWeather(
    Position location, {
    required bool showErrors,
  }) async {
    if (weatherLoading) return;
    if (mounted) setState(() => weatherLoading = true);
    try {
      final value = await WeatherService(
        backend: backend,
      ).getOverview(location.latitude, location.longitude);
      if (mounted) setState(() => weather = value);
    } catch (error) {
      if (mounted && showErrors) {
        setState(() {
          showWeatherPill = false;
          message = error.toString().replaceFirst('Exception: ', '');
        });
        _scheduleMessageDismissal();
      }
    } finally {
      if (mounted) setState(() => weatherLoading = false);
    }
  }

  void directions(Map p) {
    if (p['location'] is! Map) {
      fail(Exception('Location coordinates are unavailable.'));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DirectionsSetupPage(
          backend: backend,
          destination: RouteLocation.fromPlace(Map<String, dynamic>.from(p)),
        ),
      ),
    );
  }

  void details(Map<String, dynamic> item) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlaceDetailPage(item: item, backend: backend),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: currentPosition == null
                ? const LatLng(0, 0)
                : LatLng(currentPosition!.latitude, currentPosition!.longitude),
            zoom: currentPosition == null ? 2 : 16,
          ),
          onMapCreated: (c) {
            controller = c;
            if (currentPosition != null) {
              unawaited(moveMapTo(currentPosition!, zoom: 16));
            }
            poiChannel = MethodChannel('ohmy/google_map_poi/${c.mapId}');
            poiChannel!.setMethodCallHandler((call) async {
              if (call.method != 'onPoiTap') return;
              final poi = Map<String, dynamic>.from(call.arguments as Map);
              final placeId = poi['placeId']?.toString();
              if (placeId != null && placeId.isNotEmpty) {
                await selectPlace(placeId);
              }
            });
            unawaited(_applyInitialRecommendation());
          },
          onTap: (_) => dismissSearchResults(),
          markers: markers,
          trafficEnabled: trafficEnabled,
          myLocationEnabled: locationPermissionGranted,
          myLocationButtonEnabled: false,
          compassEnabled: false,
          buildingsEnabled: false,
          indoorViewEnabled: false,
          tiltGesturesEnabled: false,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TapRegion(
                    groupId: searchTapGroup,
                    onTapOutside: (_) => dismissSearchResults(),
                    child: Material(
                      elevation: 5,
                      borderRadius: BorderRadius.circular(18),
                      child: TextField(
                        controller: search,
                        focusNode: searchFocus,
                        onChanged: searchChanged,
                        onSubmitted: (_) => unawaited(runSearch()),
                        decoration: InputDecoration(
                          hintText: 'Search attractions…',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 17,
                            vertical: 14,
                          ),
                          suffixIcon: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: search,
                            builder: (_, value, child) => value.text.isEmpty
                                ? const Icon(Icons.search)
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      search.clear();
                                      searchChanged('');
                                      searchFocus.requestFocus();
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (results.isNotEmpty) resultList(),
        controls(),
        nearbyButton(),
        currentLocationButton(),
        if (selected != null && !showCarousel) selectionPanel(),
        if (showCarousel) carousel(),
        if (loading)
          const Center(
            child: WauLoadingIndicator(size: 68, label: 'Loading...'),
          ),
        if (message != null && !loading)
          Positioned(
            left: 70,
            right: 70,
            bottom: showCarousel ? recommendationPanelHeight + 15 : 22,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget resultList() => Positioned(
    top: MediaQuery.paddingOf(context).top + 72,
    left: 16,
    right: 16,
    child: TapRegion(
      groupId: searchTapGroup,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 330),
          child: ListView.builder(
            padding: const EdgeInsets.all(7),
            shrinkWrap: true,
            itemCount: results.length,
            itemBuilder: (_, i) {
              final p = results[i];
              return ListTile(
                dense: true,
                leading: Icon(
                  p['isArea'] == true ? Icons.map_outlined : Icons.place,
                  color: blue,
                ),
                title: Text(name(p), maxLines: 1),
                subtitle: Text(p['formattedAddress'] ?? '', maxLines: 2),
                onTap: p['isArea'] == true ? null : () => selectPlace(p['id']),
              );
            },
          ),
        ),
      ),
    ),
  );
  Widget controls() => Positioned(
    left: 16,
    bottom: showCarousel ? recommendationPanelHeight + 12 : 20,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mapButton(Icons.traffic, toggleTraffic, active: trafficEnabled),
        const SizedBox(height: 10),
        weatherButton(),
      ],
    ),
  );

  Widget weatherButton() => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    width: showWeatherPill ? 184 : 52,
    height: 52,
    child: Material(
      elevation: 5,
      color: showWeatherPill ? soft : Colors.white,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          InkWell(
            onTap: toggleWeather,
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(
              width: 52,
              height: 52,
              child: weatherLoading
                  ? const Padding(
                      padding: EdgeInsets.all(15),
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          weatherIcon(weather?.current.condition ?? ''),
                          color: blue,
                          size: 22,
                        ),
                        Text(
                          '${weather?.current.temperatureC?.round() ?? '--'}°',
                          style: const TextStyle(
                            color: ink,
                            fontSize: 12,
                            height: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (showWeatherPill) ...[
            Container(width: 1, height: 30, color: const Color(0xffdde4ef)),
            Expanded(
              child: InkWell(
                onTap: weather == null ? null : openWeatherPage,
                child: SizedBox.expand(
                  child: Row(
                    children: [
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              weatherDescription(
                                weather?.current.description ?? '',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ink,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Rain ${weather?.current.rainProbability ?? 0}%',
                              maxLines: 1,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: ink),
                      const SizedBox(width: 7),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
  Widget mapButton(IconData i, VoidCallback onPressed, {bool active = false}) =>
      Material(
        elevation: 5,
        color: active ? blue : Colors.white,
        shape: const CircleBorder(),
        child: IconButton(
          color: active ? Colors.white : blue,
          icon: Icon(i),
          onPressed: onPressed,
        ),
      );
  Widget nearbyButton() => Positioned(
    right: 16,
    bottom: showCarousel ? recommendationPanelHeight + 12 : 20,
    child: FloatingActionButton.extended(
      heroTag: 'nearby',
      backgroundColor: blue,
      foregroundColor: Colors.white,
      onPressed: nearby,
      icon: const Icon(Icons.lightbulb_outline_rounded),
      label: const Text('Nearby For You'),
    ),
  );

  Widget currentLocationButton() => Positioned(
    right: 16,
    bottom: showCarousel ? recommendationPanelHeight + 76 : 84,
    child: FloatingActionButton.small(
      heroTag: 'current-location',
      backgroundColor: Colors.white,
      foregroundColor: blue,
      onPressed: moveToCurrentLocation,
      child: const Icon(Icons.my_location_rounded),
    ),
  );

  Widget selectionPanel() {
    final item = selected!, p = item['place'] as Map<String, dynamic>;
    final img = photo(p);
    final placeDescription = description(p);
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Material(
        elevation: 12,
        color: const Color(0xff252a34),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => details(item),
          child: SizedBox(
            height: 232,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (img != null)
                  Image.network(
                    img,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) =>
                        const ColoredBox(color: Color(0xff252a34)),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xe6000000),
                        Color(0x8a000000),
                        Color(0x1a000000),
                      ],
                      stops: [0, .6, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _overlayPill('Selected place'),
                          const Spacer(),
                          IconButton.filledTonal(
                            onPressed: () => setState(() => selected = null),
                            icon: const Icon(Icons.close),
                            color: Colors.white,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black38,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        name(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (placeDescription != null)
                        Text(
                          placeDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      const SizedBox(height: 5),
                      Text(
                        '${eta(p)}  ·  ${distance(p)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _overlayTags(tags(item)),
                      const Spacer(),
                      Row(
                        children: [
                          _overlayAction(
                            Icons.directions,
                            'Directions',
                            () => directions(p),
                          ),
                          _overlayAction(
                            bookmarked ? Icons.bookmark : Icons.bookmark_border,
                            'Bookmark',
                            () => unawaited(_toggleBookmark(item)),
                          ),
                          _overlayAction(
                            Icons.lightbulb_outline_rounded,
                            'Similar',
                            recommendFromSelectedPlace,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget carousel() => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    height: recommendationPanelHeight,
    child: Material(
      elevation: 14,
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 0, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    recommendationTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (recommendations.length > 1)
                  const Text(
                    'Swipe for more →',
                    style: TextStyle(fontSize: 9, color: muted),
                  ),
                IconButton(
                  onPressed: () => setState(() => showCarousel = false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: PageView.builder(
                controller: recommendationPage,
                itemCount: recommendations.length,
                onPageChanged: _selectCarouselPlace,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: recommendationCard(recommendations[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget recommendationCard(Map<String, dynamic> item) {
    final p = item['place'] as Map<String, dynamic>;
    final img = photo(p);
    final isSelected = highlightedRecommendationId == p['id']?.toString();
    final ranking = Map<String, dynamic>.from(
      item['ranking'] as Map? ?? const {},
    );
    final placeId = p['id']?.toString() ?? '';
    final isBookmarked = bookmarkedRecommendations.contains(placeId);
    final placeDescription = description(p);
    return Material(
      color: const Color(0xff252a34),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected ? Colors.white : Colors.white24,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => details(item),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (img != null)
              Image.network(
                img,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) =>
                    const ColoredBox(color: Color(0xff252a34)),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xe6000000),
                    Color(0x80000000),
                    Color(0x1a000000),
                  ],
                  stops: [0, .56, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _overlayPill('#${item['rank'] ?? 1}'),
                      const Spacer(),
                      _overlayPill(
                        '${ranking['similarityPercentage'] ?? 0}% match',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name(p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (placeDescription != null)
                    Text(
                      placeDescription,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    '${eta(p)}  ·  ${distance(p)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _overlayTags(tags(item)),
                  const Spacer(),
                  Row(
                    children: [
                      _overlayAction(
                        Icons.directions,
                        'Directions',
                        () => directions(p),
                      ),
                      _overlayAction(
                        isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                        'Bookmark',
                        () => unawaited(_toggleBookmark(item)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overlayPill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .38),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white38),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _overlayTags(List<String> values) => SizedBox(
    height: 24,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: math.min(5, values.length),
      separatorBuilder: (_, index) => const SizedBox(width: 5),
      itemBuilder: (_, index) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white38),
        ),
        child: Text(
          values[index],
          style: const TextStyle(color: Colors.white, fontSize: 9),
        ),
      ),
    ),
  );

  Widget _overlayAction(IconData icon, String label, VoidCallback onPressed) =>
      Padding(
        padding: const EdgeInsets.only(right: 7),
        child: SizedBox(
          height: 30,
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 14),
            label: Text(label, style: const TextStyle(fontSize: 9)),
            style: FilledButton.styleFrom(
              foregroundColor: blue,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      );

  Widget tiny(IconData i, String s, VoidCallback f) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: SizedBox(
      height: 28,
      child: OutlinedButton.icon(
        onPressed: f,
        icon: Icon(i, size: 14),
        label: Text(s, style: const TextStyle(fontSize: 9)),
        style: OutlinedButton.styleFrom(
          foregroundColor: blue,
          side: const BorderSide(color: Color(0xff9bb9ec)),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          visualDensity: VisualDensity.compact,
        ),
      ),
    ),
  );
  Widget tagRow(List<String> t) => SizedBox(
    height: 24,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final x in t.take(5))
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: soft,
                border: Border.all(color: const Color(0xffc9dcfb)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                x,
                maxLines: 1,
                style: const TextStyle(fontSize: 9, color: blue),
              ),
            ),
          ),
        if (t.length > 5) const Text('…'),
      ],
    ),
  );
  @override
  void dispose() {
    completedJourneyLocation.removeListener(_resumeAtCompletedJourneyLocation);
    currentTravelerPreferences.removeListener(_onPreferencesChanged);
    savedLocationService.changes.removeListener(_onSavedLocationsChanged);
    searchDebounce?.cancel();
    messageTimer?.cancel();
    search.dispose();
    searchFocus.dispose();
    recommendationPage.dispose();
    poiChannel?.setMethodCallHandler(null);
    controller?.dispose();
    super.dispose();
  }
}

class PlaceDetailPage extends StatefulWidget {
  const PlaceDetailPage({super.key, required this.item, required this.backend});
  final Map<String, dynamic> item;
  final String backend;
  @override
  State<PlaceDetailPage> createState() => _PlaceDetailPageState();
}

class _PlaceDetailPageState extends State<PlaceDetailPage> {
  bool saved = false;
  int page = 0;

  @override
  void initState() {
    super.initState();
    saved = savedLocationService.isSaved(widget.item);
    savedLocationService.changes.addListener(_savedChanged);
    unawaited(_refreshSavedState());
  }

  Future<void> _refreshSavedState() async {
    try {
      await savedLocationService.fetch();
      _savedChanged();
    } on SavedLocationFailure {
      // The bookmark action reports errors when the user requests it.
    }
  }

  void _savedChanged() {
    if (mounted) {
      setState(() => saved = savedLocationService.isSaved(widget.item));
    }
  }

  Future<void> _toggleSaved() async {
    try {
      await savedLocationService.toggle(widget.item);
    } on SavedLocationFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    savedLocationService.changes.removeListener(_savedChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.item['place'] as Map<String, dynamic>,
        a =
            widget.item['analysis'] as Map<String, dynamic>? ??
            <String, dynamic>{},
        t = [
          ...List<String>.from(a['generalTags'] ?? []),
          ...List<String>.from(a['culturalTags'] ?? []),
        ],
        photos = List<Map<String, dynamic>>.from(p['photos'] ?? []),
        n = p['displayName']?['text'] ?? 'Place details';
    final placeDescription =
        usablePlaceDescription(p['description']) ??
        usablePlaceDescription(p['primaryTypeDisplayName']);
    return Scaffold(
      appBar: AppBar(
        title: Text(n, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: () => unawaited(_toggleSaved()),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: () {
            final place = widget.item['place'] as Map<String, dynamic>;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DirectionsSetupPage(
                  backend: widget.backend,
                  destination: RouteLocation.fromPlace(place),
                ),
              ),
            );
          },
          icon: const Icon(Icons.directions),
          label: const Text('Directions'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          if (photos.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 250,
                child: PageView.builder(
                  itemCount: math.min(9, photos.length),
                  onPageChanged: (v) => setState(() => page = v),
                  itemBuilder: (_, i) => Image.network(
                    '${widget.backend}/api/places/photo?name=${Uri.encodeQueryComponent(photos[i]['name'])}',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const _PhotoUnavailable(),
                  ),
                ),
              ),
            ),
            if (photos.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${page + 1} of ${math.min(9, photos.length)}',
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                    const Text(
                      'Swipe for more →',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
          ] else
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(20)),
              child: SizedBox(height: 250, child: _PhotoUnavailable()),
            ),
          const SizedBox(height: 18),
          const Text(
            'ABOUT THIS PLACE',
            style: TextStyle(
              color: blue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            n,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          if (placeDescription != null) ...[
            const SizedBox(height: 10),
            Text(
              placeDescription,
              style: const TextStyle(color: muted, height: 1.5),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            p['formattedAddress'] ?? 'Address unavailable',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: metric(
                  'Estimated arrival',
                  p['etaMinutes'] is num
                      ? '${p['etaEstimated'] == true ? '~' : ''}${(p['etaMinutes'] as num).round()} min'
                      : 'Unavailable',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: metric(
                  'Distance',
                  (p['routeDistanceKm'] ?? p['distanceKm']) is num
                      ? '${((p['routeDistanceKm'] ?? p['distanceKm']) as num).toStringAsFixed(1)} km'
                      : 'Unavailable',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text('Tags', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: t
                .map(
                  (x) => Chip(
                    label: Text(x, style: const TextStyle(fontSize: 11)),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget metric(String l, String v) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: soft,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l, style: const TextStyle(fontSize: 10, color: muted)),
        const SizedBox(height: 5),
        Text(
          v,
          style: const TextStyle(
            color: blue,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _PhotoUnavailable extends StatelessWidget {
  const _PhotoUnavailable();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: const Color(0xfff4bc60),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.image_not_supported_outlined,
          size: 42,
          color: Color(0xff765521),
        ),
        SizedBox(height: 10),
        Text(
          'Picture unavailable',
          style: TextStyle(
            color: Color(0xff765521),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
