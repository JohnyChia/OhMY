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
import '../../community_discovery/config/supabase_config.dart';
import '../../shared/services/recommendation_sound.dart';

const blue = Color(0xff3266cc),
    ink = Color(0xff14213d),
    muted = Color(0xff68748b),
    soft = Color(0xffedf4ff);

class PlaceMapPage extends StatefulWidget {
  const PlaceMapPage({
    super.key,
    this.autofocusSearch = false,
    this.initialRecommendation,
  });
  final bool autofocusSearch;
  final Map<String, dynamic>? initialRecommendation;
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
  bool trafficEnabled = false, showWeatherPanel = false, weatherLoading = false;
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
    unawaited(initializeCurrentLocation());
    if (widget.autofocusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) searchFocus.requestFocus();
      });
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
  }

  Future<void> _applyInitialRecommendation() async {
    final item = widget.initialRecommendation;
    if (initialRecommendationApplied || item == null || controller == null) {
      return;
    }
    initialRecommendationApplied = true;
    await choose(Map<String, dynamic>.from(item), true);
  }

  String name(Map p) =>
      p['displayName']?['text']?.toString() ?? 'Selected place';
  String description(Map p) =>
      p['description']?.toString().trim().isNotEmpty == true
      ? p['description'].toString()
      : p['primaryTypeDisplayName'] != null
      ? '${p['primaryTypeDisplayName']} at ${p['formattedAddress'] ?? 'this location'}.'
      : 'Description unavailable.';
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
      showWeatherPanel = false;
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
      showWeatherPanel = false;
      message = 'Fetching reviews and assigning tags…';
    });
    try {
      final all = await Future.wait([
        post('/api/places/analyze', {'placeId': id}),
        position(),
      ]);
      final item = all[0] as Map<String, dynamic>, pos = all[1] as Position?;
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
    final profile = await TravelerProfileService().fetchCurrentProfile();
    final values = profile?.favoriteCategories ?? const [];
    if (values.isEmpty) {
      throw Exception(
        'Your travel preferences are unavailable. Complete your profile first.',
      );
    }
    return values;
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
    setState(() {
      selected = item;
      highlightedRecommendationId = null;
      bookmarked = false;
      message = null;
      if (create) {
        markers = {
          Marker(
            markerId: MarkerId(p['id'].toString()),
            position: target,
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
      showWeatherPanel = false;
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
      showWeatherPanel = false;
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
    if (showWeatherPanel) {
      setState(() => showWeatherPanel = false);
      return;
    }
    setState(() {
      showWeatherPanel = true;
      showCarousel = false;
      selected = null;
      weatherLoading = true;
      message = null;
    });
    try {
      final currentPosition = await position();
      if (currentPosition == null) {
        throw Exception('Location permission is required for weather.');
      }
      final value = await WeatherService(
        backend: backend,
      ).getOverview(currentPosition.latitude, currentPosition.longitude);
      if (mounted) setState(() => weather = value);
    } catch (error) {
      if (mounted) {
        setState(() {
          showWeatherPanel = false;
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
        if (showWeatherPanel)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: weatherLoading
                ? const Material(
                    elevation: 14,
                    child: SizedBox(
                      height: 140,
                      child: Center(child: WauLoadingIndicator(size: 46)),
                    ),
                  )
                : weather == null
                ? const SizedBox.shrink()
                : WeatherBottomPanel(
                    weather: weather!,
                    onClose: () => setState(() => showWeatherPanel = false),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WeatherDetailPage(weather: weather!),
                      ),
                    ),
                  ),
          ),
        if (loading)
          const Center(
            child: WauLoadingIndicator(size: 68, label: 'Finding places…'),
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
    bottom: showCarousel
        ? recommendationPanelHeight + 12
        : showWeatherPanel
        ? 202
        : 20,
    child: Column(
      children: [
        mapButton(Icons.traffic, toggleTraffic, active: trafficEnabled),
        const SizedBox(height: 9),
        mapButton(Icons.cloud, toggleWeather, active: showWeatherPanel),
      ],
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
    child: showWeatherPanel
        ? const SizedBox.shrink()
        : FloatingActionButton.extended(
            heroTag: 'nearby',
            backgroundColor: blue,
            foregroundColor: Colors.white,
            onPressed: nearby,
            icon: const Icon(Icons.lightbulb_outline_rounded),
            label: const Text('Nearby matches'),
          ),
  );

  Widget currentLocationButton() => Positioned(
    right: 16,
    bottom: showCarousel ? recommendationPanelHeight + 76 : 84,
    child: showWeatherPanel
        ? const SizedBox.shrink()
        : FloatingActionButton.small(
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
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Material(
        elevation: 12,
        color: blue,
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
                        const ColoredBox(color: blue),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xf014213d),
                        Color(0xa33266cc),
                        Color(0x300b1730),
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
                      Text(
                        description(p),
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
                            () => setState(() => bookmarked = !bookmarked),
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
                onPageChanged: (index) => setState(
                  () => highlightedRecommendationId =
                      recommendations[index]['place']?['id']?.toString(),
                ),
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
    return Material(
      color: blue,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected ? Colors.white : const Color(0xff9bb9ec),
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
                    const ColoredBox(color: blue),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xe614213d),
                    Color(0x993266cc),
                    Color(0x330b1730),
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
                  Text(
                    description(p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
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
                        () => setState(() {
                          if (isBookmarked) {
                            bookmarkedRecommendations.remove(placeId);
                          } else {
                            bookmarkedRecommendations.add(placeId);
                          }
                        }),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(n, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: () => setState(() => saved = !saved),
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
          const SizedBox(height: 10),
          Text(
            p['description'] ??
                p['primaryTypeDisplayName'] ??
                'Description unavailable.',
            style: const TextStyle(color: muted, height: 1.5),
          ),
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
