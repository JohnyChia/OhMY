import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'weather_feature.dart';

const _routeBlue = Color(0xff3266cc);
const _routeInk = Color(0xff14213d);
const _routeMuted = Color(0xff68748b);

class RouteLocation {
  const RouteLocation({
    this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
  final String? id;
  final String name, address;
  final double latitude, longitude;

  factory RouteLocation.fromPlace(Map<String, dynamic> place) {
    final location = Map<String, dynamic>.from(
      place['location'] as Map? ?? const {},
    );
    return RouteLocation(
      id: place['id']?.toString(),
      name: place['displayName']?['text']?.toString() ?? 'Selected place',
      address: place['formattedAddress']?.toString() ?? '',
      latitude: (location['latitude'] as num).toDouble(),
      longitude: (location['longitude'] as num).toDouble(),
    );
  }
}

class DrivingRoute {
  const DrivingRoute({
    required this.index,
    required this.minutes,
    required this.distanceKm,
    required this.traffic,
    required this.points,
    required this.steps,
  });
  final int index, minutes;
  final double distanceKm;
  final String traffic;
  final List<LatLng> points;
  final List<NavigationStep> steps;

  factory DrivingRoute.fromJson(Map<String, dynamic> json) => DrivingRoute(
    index: (json['routeIndex'] as num?)?.round() ?? 0,
    minutes: (json['durationMinutes'] as num?)?.round() ?? 0,
    distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
    traffic: json['traffic']?.toString() ?? 'Traffic unavailable',
    points: decodePolyline(json['geometry']?.toString() ?? ''),
    steps: List<Map<String, dynamic>>.from(
      json['steps'] ?? [],
    ).map(NavigationStep.fromJson).toList(),
  );
}

class NavigationStep {
  const NavigationStep({
    required this.instruction,
    required this.maneuver,
    required this.distanceMeters,
    required this.start,
    required this.end,
  });
  final String instruction, maneuver;
  final int distanceMeters;
  final LatLng start, end;

  factory NavigationStep.fromJson(Map<String, dynamic> json) {
    final start = Map<String, dynamic>.from(json['start'] as Map? ?? const {});
    final end = Map<String, dynamic>.from(json['end'] as Map? ?? const {});
    return NavigationStep(
      instruction: json['instruction']?.toString() ?? 'Continue on the route',
      maneuver: json['maneuver']?.toString() ?? 'STRAIGHT',
      distanceMeters: (json['distanceMeters'] as num?)?.round() ?? 0,
      start: LatLng(
        (start['lat'] as num).toDouble(),
        (start['lon'] as num).toDouble(),
      ),
      end: LatLng(
        (end['lat'] as num).toDouble(),
        (end['lon'] as num).toDouble(),
      ),
    );
  }
}

List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, latitude = 0, longitude = 0;
  while (index < encoded.length) {
    var result = 0, shift = 0, byte = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    latitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    result = 0;
    shift = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    longitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    points.add(LatLng(latitude / 1e5, longitude / 1e5));
  }
  return points;
}

class DirectionsSetupPage extends StatefulWidget {
  const DirectionsSetupPage({
    super.key,
    required this.backend,
    required this.destination,
  });
  final String backend;
  final RouteLocation destination;

  @override
  State<DirectionsSetupPage> createState() => _DirectionsSetupPageState();
}

class _DirectionsSetupPageState extends State<DirectionsSetupPage> {
  final startController = TextEditingController();
  final destinationController = TextEditingController();
  RouteLocation? start;
  late RouteLocation destination;
  List<Map<String, dynamic>> results = [];
  bool searching = false;
  int activeField = 0, tab = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    destination = widget.destination;
    destinationController.text = destination.name;
  }

  Future<Position?> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> useCurrentLocation() async {
    setState(() => searching = true);
    final position = await currentPosition();
    if (!mounted) return;
    if (position == null) {
      setState(() {
        searching = false;
        error = 'Location permission is required.';
      });
      return;
    }
    start = RouteLocation(
      name: 'Your location',
      address: 'Current location',
      latitude: position.latitude,
      longitude: position.longitude,
    );
    startController.text = start!.name;
    setState(() {
      searching = false;
      results = [];
      error = null;
    });
    openRoutesIfReady();
  }

  Future<void> searchPlaces(String query) async {
    if (query.trim().isEmpty) {
      setState(() => results = []);
      return;
    }
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final response = await http.post(
        Uri.parse('${widget.backend}/api/places/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query.trim()}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['error'] ?? 'Search failed.');
      }
      if (mounted) {
        setState(
          () => results = List<Map<String, dynamic>>.from(data['places'] ?? [])
              .where(
                (place) => place['location'] != null && place['isArea'] != true,
              )
              .toList(),
        );
      }
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  void selectPlace(Map<String, dynamic> place) {
    final selected = RouteLocation.fromPlace(place);
    setState(() {
      if (activeField == 0) {
        start = selected;
        startController.text = selected.name;
      } else {
        destination = selected;
        destinationController.text = selected.name;
      }
      results = [];
    });
    openRoutesIfReady();
  }

  void selectDestination(RouteLocation selected) {
    setState(() {
      destination = selected;
      destinationController.text = selected.name;
      results = [];
    });
    openRoutesIfReady();
  }

  void openRoutesIfReady() {
    if (start == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutePreviewPage(
          backend: widget.backend,
          start: start!,
          destination: destination,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff5f8fe),
    appBar: AppBar(
      title: const Text('Choose route'),
      backgroundColor: Colors.white,
    ),
    body: Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            children: [
              locationField(
                controller: startController,
                hint: 'Choose starting point',
                icon: Icons.my_location,
                field: 0,
              ),
              const SizedBox(height: 9),
              locationField(
                controller: destinationController,
                hint: 'Choose destination',
                icon: Icons.place,
                field: 1,
              ),
            ],
          ),
        ),
        if (activeField == 1 && results.isEmpty) categoryTabs(),
        if (searching) const LinearProgressIndicator(color: _routeBlue),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(child: resultContent()),
      ],
    ),
  );

  Widget locationField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required int field,
  }) => TextField(
    controller: controller,
    onTap: () => setState(() => activeField = field),
    onChanged: (value) {
      setState(() => activeField = field);
      searchPlaces(value);
    },
    onSubmitted: searchPlaces,
    decoration: InputDecoration(
      prefixIcon: Icon(icon, color: field == 0 ? _routeBlue : Colors.orange),
      hintText: hint,
      suffixIcon: IconButton(
        onPressed: () => searchPlaces(controller.text),
        icon: const Icon(Icons.search),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  Widget categoryTabs() => Padding(
    padding: const EdgeInsets.all(14),
    child: SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('Recent')),
        ButtonSegment(value: 1, label: Text('Suggested')),
        ButtonSegment(value: 2, label: Text('Saved')),
      ],
      selected: {tab},
      onSelectionChanged: (value) => setState(() => tab = value.first),
      showSelectedIcon: false,
    ),
  );

  Widget resultContent() {
    if (results.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: results.length,
        itemBuilder: (_, index) {
          final place = results[index];
          return ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.location_on_outlined),
            ),
            title: Text(place['displayName']?['text'] ?? 'Place'),
            subtitle: Text(place['formattedAddress'] ?? '', maxLines: 2),
            onTap: () => selectPlace(place),
          );
        },
      );
    }
    if (activeField == 0) {
      return ListView(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(18),
            leading: const CircleAvatar(
              backgroundColor: Color(0xffdff7fb),
              child: Icon(Icons.my_location, color: _routeBlue),
            ),
            title: const Text(
              'Your location',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Use current device location'),
            onTap: useCurrentLocation,
          ),
        ],
      );
    }
    final items = tab == 2 ? <RouteLocation>[] : [widget.destination];
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No saved places yet.',
          style: TextStyle(color: _routeMuted),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (_, index) => Card(
        child: ListTile(
          leading: const Icon(Icons.history, color: _routeBlue),
          title: Text(items[index].name),
          subtitle: Text(items[index].address, maxLines: 2),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => selectDestination(items[index]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    startController.dispose();
    destinationController.dispose();
    super.dispose();
  }
}

class RoutePreviewPage extends StatefulWidget {
  const RoutePreviewPage({
    super.key,
    required this.backend,
    required this.start,
    required this.destination,
  });
  final String backend;
  final RouteLocation start, destination;

  @override
  State<RoutePreviewPage> createState() => _RoutePreviewPageState();
}

class _RoutePreviewPageState extends State<RoutePreviewPage> {
  GoogleMapController? controller;
  List<DrivingRoute> routes = [];
  int selected = 0;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadRoutes();
  }

  Future<void> loadRoutes() async {
    final uri = Uri.parse('${widget.backend}/api/routes').replace(
      queryParameters: {
        'startLat': '${widget.start.latitude}',
        'startLon': '${widget.start.longitude}',
        'endLat': '${widget.destination.latitude}',
        'endLon': '${widget.destination.longitude}',
      },
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          data['details'] ?? data['error'] ?? 'Routes unavailable.',
        );
      }
      if (mounted) {
        setState(() {
          routes = List<Map<String, dynamic>>.from(
            data['routes'] ?? [],
          ).map(DrivingRoute.fromJson).toList();
          loading = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => fitRoute());
    } catch (exception) {
      if (mounted) {
        setState(() {
          loading = false;
          error = exception.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Set<Polyline> get polylines => routes
      .map(
        (route) => Polyline(
          polylineId: PolylineId('route-${route.index}'),
          points: route.points,
          color: route.index == routes[selected].index
              ? _routeBlue
              : Colors.blueGrey.withValues(alpha: .5),
          width: route.index == routes[selected].index ? 7 : 5,
          zIndex: route.index == routes[selected].index ? 2 : 1,
          onTap: () {
            setState(() => selected = routes.indexOf(route));
            fitRoute();
          },
        ),
      )
      .toSet();

  Future<void> fitRoute() async {
    if (controller == null ||
        routes.isEmpty ||
        routes[selected].points.isEmpty) {
      return;
    }
    final points = routes[selected].points;
    var south = points.first.latitude,
        north = points.first.latitude,
        west = points.first.longitude,
        east = points.first.longitude;
    for (final point in points.skip(1)) {
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
    }
    await controller!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        70,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(widget.start.latitude, widget.start.longitude),
            zoom: 13,
          ),
          onMapCreated: (value) {
            controller = value;
            fitRoute();
          },
          markers: {
            Marker(
              markerId: const MarkerId('start'),
              position: LatLng(widget.start.latitude, widget.start.longitude),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
            ),
            Marker(
              markerId: const MarkerId('destination'),
              position: LatLng(
                widget.destination.latitude,
                widget.destination.longitude,
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueOrange,
              ),
            ),
          },
          polylines: routes.isEmpty ? {} : polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          buildingsEnabled: false,
          indoorViewEnabled: false,
          tiltGesturesEnabled: false,
          zoomControlsEnabled: false,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_back_ios_new, color: _routeBlue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.start.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _routeMuted,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${widget.start.name}  →  ${widget.destination.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _routeInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (loading)
          const Center(child: CircularProgressIndicator(color: _routeBlue)),
        if (error != null)
          Center(
            child: Card(
              margin: const EdgeInsets.all(30),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(error!, textAlign: TextAlign.center),
              ),
            ),
          ),
        if (routes.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 58,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: routes.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final route = routes[index];
                          return ChoiceChip(
                            selected: selected == index,
                            onSelected: (_) {
                              setState(() => selected = index);
                              fitRoute();
                            },
                            label: Text(
                              'Route ${index + 1}  •  ${route.minutes} min',
                            ),
                          );
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${routes[selected].minutes} min',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${routes[selected].distanceKm.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        routes[selected].traffic,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _routeMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ActiveNavigationPage(
                              backend: widget.backend,
                              destination: widget.destination,
                              routes: routes,
                              initialRoute: selected,
                            ),
                          ),
                        ),
                        child: const Text('Start Journey'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}

class ActiveNavigationPage extends StatefulWidget {
  const ActiveNavigationPage({
    super.key,
    required this.backend,
    required this.destination,
    required this.routes,
    required this.initialRoute,
  });
  final String backend;
  final RouteLocation destination;
  final List<DrivingRoute> routes;
  final int initialRoute;

  @override
  State<ActiveNavigationPage> createState() => _ActiveNavigationPageState();
}

class _ActiveNavigationPageState extends State<ActiveNavigationPage> {
  static const navigationPreferences = [
    'Museum',
    'Heritage',
    'Cultural Learning',
    'Nature',
    'Religious Heritage',
  ];
  GoogleMapController? controller;
  StreamSubscription<Position>? positionSubscription;
  late int selectedRoute;
  int stepIndex = 0;
  Position? position;
  bool trafficEnabled = false, followUser = true;
  bool recommendationLoading = false, showRecommendationCarousel = false;
  List<Map<String, dynamic>> recommendations = [];
  String recommendationTitle = 'Recommended stops';
  String? locationError;

  DrivingRoute get route => widget.routes[selectedRoute];
  NavigationStep? get step => route.steps.isEmpty
      ? null
      : route.steps[math.min(stepIndex, route.steps.length - 1)];

  @override
  void initState() {
    super.initState();
    selectedRoute = widget.initialRoute;
    startTracking();
  }

  Future<void> startTracking() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => locationError = 'Turn on location services to navigate.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(
        () => locationError = 'Location permission is required to navigate.',
      );
      return;
    }
    positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 5,
          ),
        ).listen(
          updatePosition,
          onError: (Object error) {
            if (mounted) setState(() => locationError = error.toString());
          },
        );
    updatePosition(
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      ),
    );
  }

  void updatePosition(Position value) {
    if (!mounted) return;
    final currentStep = step;
    if (currentStep != null &&
        distance(
              value.latitude,
              value.longitude,
              currentStep.end.latitude,
              currentStep.end.longitude,
            ) <
            35 &&
        stepIndex < route.steps.length - 1) {
      stepIndex++;
    }
    setState(() {
      position = value;
      locationError = null;
    });
    if (followUser) moveCamera(value);
  }

  Future<void> moveCamera(Position value) async {
    await controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(value.latitude, value.longitude),
          zoom: 17.5,
          bearing: value.heading.isFinite && value.heading >= 0
              ? value.heading
              : 0,
          tilt: 0,
        ),
      ),
    );
  }

  double distance(double lat1, double lon1, double lat2, double lon2) {
    double radians(double value) => value * math.pi / 180;
    const earth = 6371000.0;
    final dLat = radians(lat2 - lat1), dLon = radians(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(radians(lat1)) *
            math.cos(radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String instructionDistance() {
    if (position == null || step == null) return 'Locating…';
    final metres = distance(
      position!.latitude,
      position!.longitude,
      step!.end.latitude,
      step!.end.longitude,
    );
    return metres >= 1000
        ? '${(metres / 1000).toStringAsFixed(1)} km'
        : '${math.max(10, (metres / 10).round() * 10)} m';
  }

  IconData maneuverIcon(String maneuver) {
    if (maneuver.contains('LEFT')) return Icons.turn_left_rounded;
    if (maneuver.contains('RIGHT')) return Icons.turn_right_rounded;
    if (maneuver.contains('UTURN')) return Icons.u_turn_left_rounded;
    if (maneuver.contains('ROUNDABOUT')) return Icons.roundabout_left_rounded;
    if (maneuver.contains('MERGE')) return Icons.merge_rounded;
    return Icons.straight_rounded;
  }

  void chooseRoute() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        itemCount: widget.routes.length,
        separatorBuilder: (_, index) => const Divider(),
        itemBuilder: (_, index) {
          final item = widget.routes[index];
          return ListTile(
            leading: Icon(
              index == selectedRoute ? Icons.check_circle : Icons.alt_route,
              color: _routeBlue,
            ),
            title: Text('Route ${index + 1}  •  ${item.minutes} min'),
            subtitle: Text(
              '${item.distanceKm.toStringAsFixed(1)} km  •  ${item.traffic}',
            ),
            onTap: () {
              setState(() {
                selectedRoute = index;
                stepIndex = 0;
              });
              Navigator.pop(sheetContext);
            },
          );
        },
      ),
    ),
  );

  Future<void> showWeather() async {
    final current = position;
    if (current == null) return;
    try {
      final weather = await WeatherService(
        backend: widget.backend,
      ).getOverview(current.latitude, current.longitude);
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => SafeArea(
          child: WeatherBottomPanel(
            weather: weather,
            onTap: () {},
            onClose: () => Navigator.pop(context),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  void showRecommendationMode() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recommend a stop based on',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _routeInk,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose how suggestions should be matched.',
              style: TextStyle(color: _routeMuted),
            ),
            const SizedBox(height: 14),
            recommendationModeCard(
              title: 'Destination tags',
              subtitle: 'Find similar places like ${widget.destination.name}',
              selected: false,
              onTap: () {
                Navigator.pop(sheetContext);
                loadRecommendations('destination');
              },
            ),
            const SizedBox(height: 10),
            recommendationModeCard(
              title: 'My personal preferences',
              subtitle: navigationPreferences.join(', '),
              selected: true,
              onTap: () {
                Navigator.pop(sheetContext);
                loadRecommendations('preferences');
              },
            ),
          ],
        ),
      ),
    ),
  );

  Widget recommendationModeCard({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) => Material(
    color: selected ? _routeBlue : const Color(0xfff1f6ff),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? _routeBlue : const Color(0xffb9cff7),
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : _routeInk,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: selected ? Colors.white70 : _routeMuted),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> loadRecommendations(String mode) async {
    final current = position;
    if (current == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for your current GPS location.')),
      );
      return;
    }
    if (mode == 'destination' && widget.destination.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Destination tags are unavailable for this location.'),
        ),
      );
      return;
    }
    setState(() {
      recommendationLoading = true;
      showRecommendationCarousel = false;
    });
    try {
      final body = <String, dynamic>{
        'latitude': current.latitude,
        'longitude': current.longitude,
        'mode': mode,
        if (mode == 'destination') 'destinationPlaceId': widget.destination.id,
        if (mode == 'preferences') 'preferences': navigationPreferences,
      };
      final response = await http
          .post(
            Uri.parse('${widget.backend}/api/recommendations/nearby-tagged'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          data['details'] ?? data['error'] ?? 'Recommendations unavailable.',
        );
      }
      if (!mounted) return;
      setState(() {
        recommendations = List<Map<String, dynamic>>.from(
          data['matchedPlaces'] ?? [],
        );
        recommendationTitle = mode == 'destination'
            ? 'Similar to ${widget.destination.name}'
            : 'Based on your preferences';
        showRecommendationCarousel = recommendations.isNotEmpty;
      });
      if (recommendations.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No matching stops found nearby.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => recommendationLoading = false);
    }
  }

  void cancelJourney() =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final currentStep = step;
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: route.points.isEmpty
                  ? LatLng(
                      widget.destination.latitude,
                      widget.destination.longitude,
                    )
                  : route.points.first,
              zoom: 16,
            ),
            onMapCreated: (value) {
              controller = value;
              if (position != null) moveCamera(position!);
            },
            onCameraMoveStarted: () => followUser = false,
            polylines: {
              Polyline(
                polylineId: const PolylineId('active-route'),
                points: route.points,
                color: _routeBlue,
                width: 7,
              ),
            },
            markers: {
              Marker(
                markerId: const MarkerId('destination'),
                position: LatLng(
                  widget.destination.latitude,
                  widget.destination.longitude,
                ),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                ),
              ),
            },
            trafficEnabled: trafficEnabled,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            buildingsEnabled: false,
            indoorViewEnabled: false,
            tiltGesturesEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: _routeBlue,
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Row(
                    children: [
                      Icon(
                        maneuverIcon(currentStep?.maneuver ?? 'STRAIGHT'),
                        color: Colors.white,
                        size: 38,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentStep?.instruction ??
                                  'Continue toward ${widget.destination.name}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              instructionDistance(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!showRecommendationCarousel)
            Positioned(
              left: 14,
              bottom: 132,
              child: Column(
                children: [
                  navigationButton(Icons.cloud_outlined, showWeather),
                  const SizedBox(height: 9),
                  navigationButton(
                    Icons.traffic,
                    () => setState(() => trafficEnabled = !trafficEnabled),
                    active: trafficEnabled,
                  ),
                ],
              ),
            ),
          if (!showRecommendationCarousel)
            Positioned(
              right: 14,
              bottom: 132,
              child: Column(
                children: [
                  navigationButton(
                    Icons.lightbulb_outline_rounded,
                    showRecommendationMode,
                  ),
                  const SizedBox(height: 9),
                  navigationButton(Icons.my_location_rounded, () {
                    followUser = true;
                    if (position != null) moveCamera(position!);
                  }),
                ],
              ),
            ),
          if (locationError != null)
            Positioned(
              top: 130,
              left: 24,
              right: 24,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    locationError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ),
          if (recommendationLoading)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 170,
              child: Center(
                child: CircularProgressIndicator(color: _routeBlue),
              ),
            ),
          if (showRecommendationCarousel) navigationRecommendationCarousel(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              elevation: 14,
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '⌃  Swipe up for journey details',
                        style: TextStyle(fontSize: 10, color: _routeMuted),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          navigationButton(
                            Icons.close,
                            cancelJourney,
                            danger: true,
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '${route.minutes} min',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${route.distanceKm.toStringAsFixed(1)} km remaining',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _routeMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          navigationButton(
                            Icons.alt_route_rounded,
                            chooseRoute,
                            label: 'Routes',
                          ),
                        ],
                      ),
                      const Text(
                        'Powered by Google',
                        style: TextStyle(fontSize: 8, color: _routeMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget navigationButton(
    IconData icon,
    VoidCallback onPressed, {
    bool active = false,
    bool danger = false,
    String? label,
  }) => Material(
    elevation: 4,
    color: danger
        ? const Color(0xfffff0f3)
        : active
        ? _routeBlue
        : const Color(0xffedf4ff),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onPressed,
      child: SizedBox(
        width: 54,
        height: 54,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: danger
                  ? Colors.red
                  : active
                  ? Colors.white
                  : _routeBlue,
              size: label == null ? 25 : 21,
            ),
            if (label != null)
              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  color: active ? Colors.white : _routeBlue,
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget navigationRecommendationCarousel() => Positioned(
    left: 0,
    right: 0,
    bottom: 112,
    height: 220,
    child: Material(
      elevation: 14,
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 0, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    recommendationTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Text(
                  'Swipe for more →',
                  style: TextStyle(fontSize: 9, color: _routeMuted),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => showRecommendationCarousel = false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recommendations.length,
                separatorBuilder: (_, index) => const SizedBox(width: 10),
                itemBuilder: (_, index) =>
                    navigationRecommendationCard(recommendations[index]),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget navigationRecommendationCard(Map<String, dynamic> item) {
    final place = Map<String, dynamic>.from(item['place'] as Map? ?? const {});
    final analysis = Map<String, dynamic>.from(
      item['analysis'] as Map? ?? const {},
    );
    final ranking = Map<String, dynamic>.from(
      item['ranking'] as Map? ?? const {},
    );
    final tags = <String>[
      ...List<String>.from(analysis['generalTags'] ?? []),
      ...List<String>.from(analysis['culturalTags'] ?? []),
    ].take(3).toList();
    final photoName = place['photo']?['name']?.toString();
    final title =
        place['displayName']?['text']?.toString() ?? 'Recommended stop';
    final eta = (place['etaMinutes'] as num?)?.round();
    final distanceKm =
        (place['routeDistanceKm'] ?? place['distanceKm']) as num?;
    return Container(
      width: 330,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xfff7faff),
        border: Border.all(color: const Color(0xffc9daf8)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 92,
              height: 92,
              child: photoName == null
                  ? const ColoredBox(
                      color: Color(0xffffc35d),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.white,
                      ),
                    )
                  : Image.network(
                      '${widget.backend}/api/places/photo?name=${Uri.encodeQueryComponent(photoName)}',
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, stack) => const ColoredBox(
                        color: Color(0xffffc35d),
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '#${item['rank'] ?? 1}  $title',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${ranking['similarityPercentage'] ?? 0}% match',
                      style: const TextStyle(
                        fontSize: 10,
                        color: _routeBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  place['description']?.toString() ??
                      place['formattedAddress']?.toString() ??
                      'Description unavailable.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _routeMuted),
                ),
                const SizedBox(height: 6),
                Text(
                  '${eta == null ? 'ETA unavailable' : '$eta min'}  •  ${distanceKm == null ? 'Distance unavailable' : '${distanceKm.toStringAsFixed(1)} km'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _routeBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  tags.isEmpty ? 'Tags unavailable' : tags.join('  •  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: _routeMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    positionSubscription?.cancel();
    controller?.dispose();
    super.dispose();
  }
}
