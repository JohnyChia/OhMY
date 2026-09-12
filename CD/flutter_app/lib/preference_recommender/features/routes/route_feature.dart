import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/ohmy_snack_bar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    as navigation;
import 'package:http/http.dart' as http;

import '../weather/weather_feature.dart';
import 'navigation_sensor.dart';
import 'native_navigation_map.dart';
import '../../../user_management/services/traveler_profile_service.dart';
import 'package:community_discovery/community_discovery.dart'
    show SupabaseConfig;
import '../../../shared/services/recommendation_sound.dart';
import '../../widgets/wau_loading_indicator.dart';
import '../../../user_management/models/travel_history_entry.dart';
import '../../../user_management/services/travel_history_service.dart';

const _routeBlue = Color(0xff3266cc);
const _routeInk = Color(0xff14213d);
const _routeMuted = Color(0xff68748b);

/// Publishes the final road-snapped position when a journey completes so the
/// existing Solo Trip map can resume at the place where navigation ended.
final ValueNotifier<LatLng?> completedJourneyLocation = ValueNotifier(null);

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
    required this.routeToken,
    required this.minutes,
    required this.staticMinutes,
    required this.distanceKm,
    required this.traffic,
    required this.tollPrices,
    required this.points,
    required this.steps,
  });
  final int index, minutes, staticMinutes;
  final String routeToken;
  final double distanceKm;
  final String traffic;
  final List<Map<String, dynamic>> tollPrices;
  final List<LatLng> points;
  final List<NavigationStep> steps;

  factory DrivingRoute.fromJson(Map<String, dynamic> json) => DrivingRoute(
    index: (json['routeIndex'] as num?)?.round() ?? 0,
    routeToken: json['routeToken']?.toString() ?? '',
    minutes: (json['durationMinutes'] as num?)?.round() ?? 0,
    staticMinutes:
        (json['staticDurationMinutes'] as num?)?.round() ??
        (json['durationMinutes'] as num?)?.round() ??
        0,
    distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
    traffic: json['traffic']?.toString() ?? 'Traffic unavailable',
    tollPrices: List<Map<String, dynamic>>.from(json['tollPrices'] ?? []),
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
    return Geolocator.getCurrentPosition(
      locationSettings: navigationLocationSettings,
    );
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
        body: jsonEncode({'query': query.trim(), 'placesOnly': true}),
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
        if (searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: WauLoadingIndicator(size: 28),
          ),
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
  Map<int, BitmapDescriptor> routeIndicatorIcons = {};

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
      final navigationRoutes =
          List<Map<String, dynamic>>.from(data['routes'] ?? [])
              .map(DrivingRoute.fromJson)
              .where((route) => route.routeToken.isNotEmpty)
              .toList();
      if (navigationRoutes.isEmpty) {
        throw Exception(
          'The Routes API did not return a navigation-compatible route.',
        );
      }
      if (mounted) {
        setState(() {
          routes = navigationRoutes;
          loading = false;
        });
        await buildRouteIndicatorIcons();
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
          consumeTapEvents: true,
          onTap: () {
            selectRoute(routes.indexOf(route));
          },
        ),
      )
      .toSet();

  String routeCaption(int index) {
    final fastest = routes.map((route) => route.minutes).reduce(math.min);
    final shortest = routes.map((route) => route.distanceKm).reduce(math.min);
    if (routes[index].minutes == fastest) return 'Best';
    if (routes[index].distanceKm == shortest) return 'Shortest distance';
    return 'Alternative route';
  }

  String tollDescription(DrivingRoute route) {
    if (route.tollPrices.isEmpty) return 'No toll estimate';
    final price = route.tollPrices.first;
    final amount =
        (price['units'] as num? ?? 0).toDouble() +
        (price['nanos'] as num? ?? 0).toDouble() / 1000000000;
    final currency = price['currencyCode']?.toString() ?? '';
    return 'Tolls $currency ${amount.toStringAsFixed(2)}'.trim();
  }

  Future<BitmapDescriptor> routeIndicatorIcon(int index) async {
    const scale = 3.0;
    const width = 142.0;
    const bodyHeight = 50.0;
    const height = 58.0;
    final selectedRoute = selected == index;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final background = Paint()
      ..color = selectedRoute ? _routeBlue : const Color(0xfff7f9ff);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, width * scale, bodyHeight * scale),
        const Radius.circular(14 * scale),
      ),
      background,
    );
    final pointer = Path()
      ..moveTo((width / 2 - 7) * scale, (bodyHeight - 1) * scale)
      ..lineTo((width / 2) * scale, height * scale)
      ..lineTo((width / 2 + 7) * scale, (bodyHeight - 1) * scale)
      ..close();
    canvas.drawPath(pointer, background);
    if (!selectedRoute) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(1, 1, width * scale - 2, bodyHeight * scale - 2),
          const Radius.circular(14 * scale),
        ),
        Paint()
          ..color = const Color(0xff9bb8ee)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    void paintText(String text, double top, double size, FontWeight weight) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: selectedRoute ? Colors.white : _routeInk,
            fontSize: size * scale,
            fontWeight: weight,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: (width - 18) * scale);
      painter.paint(canvas, Offset(9 * scale, top * scale));
    }

    final route = routes[index];
    paintText(
      '${route.minutes} min · ${route.distanceKm.toStringAsFixed(1)} km',
      6,
      11,
      FontWeight.w700,
    );
    paintText(routeCaption(index), 27, 9, FontWeight.w500);
    final image = await recorder.endRecording().toImage(
      (width * scale).round(),
      (height * scale).round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: scale,
    );
  }

  Future<void> buildRouteIndicatorIcons() async {
    final icons = <int, BitmapDescriptor>{};
    for (var index = 0; index < routes.length; index++) {
      icons[index] = await routeIndicatorIcon(index);
    }
    if (mounted) setState(() => routeIndicatorIcons = icons);
  }

  void selectRoute(int index) {
    if (index == selected) return;
    setState(() => selected = index);
    unawaited(buildRouteIndicatorIcons());
  }

  Set<Marker> get routeMarkers {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('start'),
        position: LatLng(widget.start.latitude, widget.start.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(
          widget.destination.latitude,
          widget.destination.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
    };
    for (var index = 0; index < routes.length; index++) {
      final route = routes[index];
      final icon = routeIndicatorIcons[index];
      if (route.points.isEmpty || icon == null) continue;
      final fraction = (index + 1) / (routes.length + 1);
      final indicatorIndex = math.min(
        route.points.length - 1,
        ((route.points.length - 1) * fraction).round(),
      );
      markers.add(
        Marker(
          markerId: MarkerId('route-indicator-$index'),
          position: route.points[indicatorIndex],
          icon: icon,
          anchor: const Offset(.5, 1),
          zIndexInt: selected == index ? 4 : 3,
          onTap: () => selectRoute(index),
        ),
      );
    }
    return markers;
  }

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
          markers: routeMarkers,
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
        if (loading) const Center(child: WauLoadingIndicator(size: 64)),
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
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 3,
                        children: [
                          Text(
                            routeCaption(selected),
                            style: const TextStyle(
                              fontSize: 12,
                              color: _routeBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            routes[selected].traffic,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _routeMuted,
                            ),
                          ),
                          Text(
                            tollDescription(routes[selected]),
                            style: const TextStyle(
                              fontSize: 12,
                              color: _routeMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pushReplacement(
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
  final navigationMapKey = GlobalKey<NativeNavigationMapState>();
  final TravelHistoryService travelHistoryService = TravelHistoryService();
  late int selectedRoute;
  late RouteLocation activeDestination;
  late List<DrivingRoute> activeRoutes;
  late final DateTime journeyStartedAt;
  int stepIndex = 0;
  Position? position;
  bool reducedLocationAccuracy = false;
  bool trafficEnabled = true, followUser = true;
  navigation.TrafficDelaySeverity trafficSeverity =
      navigation.TrafficDelaySeverity.noData;
  bool recommendationLoading = false, showRecommendationCarousel = false;
  List<Map<String, dynamic>> recommendations = [];
  String recommendationTitle = 'Recommended stops';
  String? locationError;
  double? sdkRemainingDistanceMeters;
  double? sdkRemainingTimeSeconds;
  bool arrivalHandled = false;
  final bool useNativeNavigationFooter = false;
  bool navigationPanelExpanded = false;
  bool voiceGuidanceEnabled = true;
  bool vibrationEnabled = true;
  final Set<String> bookmarkedRecommendations = {};
  DateTime? _heavyTrafficSince;
  DateTime? _normalTrafficSince;
  DateTime? _lastTrafficCheckAt;
  DateTime? _lastTrafficPromptAt;
  bool _trafficPromptedForEpisode = false;
  bool _trafficEvaluationInProgress = false;

  static const _trafficConfirmationPeriod = Duration(seconds: 20);
  static const _trafficEpisodeResetPeriod = Duration(minutes: 5);
  static const _trafficCheckInterval = Duration(minutes: 2);
  static const _trafficPromptCooldown = Duration(minutes: 15);
  static const _minimumTrafficDelayMinutes = 5;

  List<String> get navigationPreferences => currentTravelerPreferences.value;

  DrivingRoute get route => activeRoutes[selectedRoute];
  NavigationStep? get step => route.steps.isEmpty
      ? null
      : route.steps[math.min(stepIndex, route.steps.length - 1)];

  @override
  void initState() {
    super.initState();
    activeDestination = widget.destination;
    activeRoutes = List<DrivingRoute>.from(widget.routes);
    selectedRoute = widget.initialRoute;
    journeyStartedAt = DateTime.now();
  }

  Color get etaColor => switch (trafficSeverity) {
    navigation.TrafficDelaySeverity.heavy => const Color(0xffd93025),
    navigation.TrafficDelaySeverity.medium => const Color(0xffed8b00),
    navigation.TrafficDelaySeverity.light => const Color(0xff188038),
    navigation.TrafficDelaySeverity.noData => _routeBlue,
  };

  void _handleTrafficProgress(
    double remainingDistanceMeters,
    double remainingTimeSeconds,
    navigation.TrafficDelaySeverity severity,
  ) {
    final now = DateTime.now();
    if (severity != navigation.TrafficDelaySeverity.heavy) {
      _heavyTrafficSince = null;
      _normalTrafficSince ??= now;
      if (now.difference(_normalTrafficSince!) >= _trafficEpisodeResetPeriod) {
        _trafficPromptedForEpisode = false;
      }
      return;
    }

    _normalTrafficSince = null;
    _heavyTrafficSince ??= now;
    if (now.difference(_heavyTrafficSince!) < _trafficConfirmationPeriod ||
        remainingTimeSeconds < 15 * 60 ||
        remainingDistanceMeters < 5000 ||
        arrivalHandled ||
        recommendationLoading ||
        showRecommendationCarousel ||
        _trafficPromptedForEpisode ||
        _trafficEvaluationInProgress ||
        (_lastTrafficCheckAt != null &&
            now.difference(_lastTrafficCheckAt!) < _trafficCheckInterval) ||
        (_lastTrafficPromptAt != null &&
            now.difference(_lastTrafficPromptAt!) < _trafficPromptCooldown)) {
      return;
    }
    unawaited(_evaluateTrafficRecommendation());
  }

  Future<void> _evaluateTrafficRecommendation() async {
    final current = position;
    if (current == null || _trafficEvaluationInProgress) return;
    _trafficEvaluationInProgress = true;
    _lastTrafficCheckAt = DateTime.now();
    try {
      final segment =
          await navigation.GoogleMapsNavigator.getCurrentRouteSegment();
      final hasTrafficJam =
          segment?.trafficData?.roadStretchRenderingDataList.any(
            (stretch) =>
                stretch?.style ==
                navigation
                    .RouteSegmentTrafficDataRoadStretchRenderingDataStyle
                    .trafficJam,
          ) ??
          false;
      if (!hasTrafficJam) return;

      final uri = Uri.parse('${widget.backend}/api/routes').replace(
        queryParameters: {
          'startLat': '${current.latitude}',
          'startLon': '${current.longitude}',
          'endLat': '${activeDestination.latitude}',
          'endLon': '${activeDestination.longitude}',
        },
      );
      final routeResponse = await http
          .get(uri)
          .timeout(const Duration(seconds: 25));
      final routeData = jsonDecode(routeResponse.body) as Map<String, dynamic>;
      if (routeResponse.statusCode < 200 || routeResponse.statusCode >= 300) {
        return;
      }
      final routeResults = List<Map<String, dynamic>>.from(
        routeData['routes'] ?? const [],
      );
      if (routeResults.isEmpty) return;
      final bestRoute = routeResults.reduce((a, b) {
        final aDuration = (a['durationMinutes'] as num?)?.toInt() ?? 1 << 30;
        final bDuration = (b['durationMinutes'] as num?)?.toInt() ?? 1 << 30;
        return aDuration <= bDuration ? a : b;
      });
      final delayMinutes =
          (bestRoute['trafficDelayMinutes'] as num?)?.round() ??
          math.max(
            0,
            ((bestRoute['durationMinutes'] as num?)?.round() ?? 0) -
                ((bestRoute['staticDurationMinutes'] as num?)?.round() ?? 0),
          );
      if (delayMinutes < _minimumTrafficDelayMinutes || !mounted) return;
      await _loadTrafficRecommendations(delayMinutes);
    } catch (_) {
      // Traffic suggestions are optional and must never interrupt guidance.
    } finally {
      _trafficEvaluationInProgress = false;
    }
  }

  Future<void> _loadTrafficRecommendations(int delayMinutes) async {
    final current = position;
    if (current == null || !mounted) return;
    setState(() => recommendationLoading = true);
    try {
      var preferences = navigationPreferences;
      if (SupabaseConfig.isConfigured) {
        preferences =
            (await TravelerProfileService().fetchCurrentProfile())
                ?.favoriteCategories ??
            preferences;
      }
      if (preferences.isEmpty) return;
      final response = await http
          .post(
            Uri.parse('${widget.backend}/api/recommendations/nearby-tagged'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'latitude': current.latitude,
              'longitude': current.longitude,
              'mode': 'preferences',
              'preferences': preferences,
            }),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300 || !mounted) {
        return;
      }
      final matches = List<Map<String, dynamic>>.from(
        data['matchedPlaces'] ?? const [],
      );
      if (matches.isEmpty) return;
      setState(() {
        recommendations = matches;
        recommendationTitle =
            'Traffic adds ~$delayMinutes min — explore nearby';
        showRecommendationCarousel = true;
        _trafficPromptedForEpisode = true;
        _lastTrafficPromptAt = DateTime.now();
      });
      unawaited(RecommendationSound.play());
    } finally {
      if (mounted) setState(() => recommendationLoading = false);
    }
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
        itemCount: activeRoutes.length,
        separatorBuilder: (_, index) => const Divider(),
        itemBuilder: (_, index) {
          final item = activeRoutes[index];
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
                sdkRemainingDistanceMeters = null;
                sdkRemainingTimeSeconds = null;
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
          OhMySnackBar(
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
              subtitle: 'Find similar places like ${activeDestination.name}',
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
              selected: false,
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
    color: selected ? _routeBlue : Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.pressed)
            ? _routeBlue.withValues(alpha: 0.9)
            : null,
      ),
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
        const OhMySnackBar(
          content: Text('Waiting for your current GPS location.'),
        ),
      );
      return;
    }
    if (mode == 'destination' && activeDestination.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const OhMySnackBar(
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
      var preferences = navigationPreferences;
      if (mode == 'preferences') {
        if (!SupabaseConfig.isConfigured) {
          throw Exception(
            'Sign-in services are not configured. Start the app with run-ohmy.ps1.',
          );
        }
        preferences = await TravelerProfileService()
            .requireCurrentPreferences();
      }
      final body = <String, dynamic>{
        'latitude': current.latitude,
        'longitude': current.longitude,
        'mode': mode,
        if (mode == 'destination') 'destinationPlaceId': activeDestination.id,
        if (mode == 'preferences') 'preferences': preferences,
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
            ? 'Similar to ${activeDestination.name}'
            : 'Based on your preferences';
        showRecommendationCarousel = recommendations.isNotEmpty;
      });
      if (recommendations.isNotEmpty) {
        unawaited(RecommendationSound.play());
      }
      if (recommendations.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const OhMySnackBar(content: Text('No matching stops found nearby.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          OhMySnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => recommendationLoading = false);
    }
  }

  void cancelJourney() {
    // The active navigation page lives in the Start Trip tab's navigator.
    // Return to that tab's first page immediately while native cleanup runs
    // asynchronously from NativeNavigationMap.dispose().
    final latest = position;
    if (latest != null) {
      completedJourneyLocation.value = LatLng(
        latest.latitude,
        latest.longitude,
      );
    }
    Navigator.of(context).popUntil(
      (route) => route.settings.name == '/start-trip/solo-map' || route.isFirst,
    );
  }

  Future<void> finishJourney() async {
    if (!mounted || arrivalHandled) return;
    arrivalHandled = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (dialogContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(dialogContext),
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: IgnorePointer(
              child: Dialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: const BoxDecoration(
                          color: Color(0xffe9f1ff),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: _routeBlue,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'You have arrived!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _routeInk,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        activeDestination.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _routeBlue,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Enjoy your time exploring this place.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _routeMuted, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap anywhere to continue',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _routeMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    completedJourneyLocation.value = LatLng(
      position?.latitude ?? activeDestination.latitude,
      position?.longitude ?? activeDestination.longitude,
    );
    final completedAt = DateTime.now();
    try {
      await travelHistoryService.recordCompletedTrip(
        CompletedTravelDraft(
          type: TravelHistoryType.solo,
          sourceReference: 'solo-${journeyStartedAt.microsecondsSinceEpoch}',
          title: '${activeDestination.name} Solo Trip',
          destination: activeDestination.name,
          startedAt: journeyStartedAt,
          completedAt: completedAt,
          stops: [
            TravelHistoryStop(
              name: activeDestination.name,
              visitedAt: completedAt,
            ),
          ],
          distanceKm: route.distanceKm,
          durationMinutes: completedAt.difference(journeyStartedAt).inMinutes,
          tags: const [],
          travelMode: 'Driving',
        ),
      );
    } on TravelHistoryFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
    if (!mounted) return;
    Navigator.of(context).popUntil(
      (route) => route.settings.name == '/start-trip/solo-map' || route.isFirst,
    );
  }

  void openRecommendationDetails(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _NavigationPlaceDetailPage(
          item: item,
          backend: widget.backend,
          onNavigate: () async {
            Navigator.pop(context);
            await navigateToRecommendation(item);
          },
        ),
      ),
    );
  }

  Future<void> navigateToRecommendation(Map<String, dynamic> item) async {
    final current = position;
    final place = Map<String, dynamic>.from(item['place'] as Map? ?? const {});
    final location = Map<String, dynamic>.from(
      place['location'] as Map? ?? const {},
    );
    if (current == null ||
        location['latitude'] is! num ||
        location['longitude'] is! num) {
      ScaffoldMessenger.of(context).showSnackBar(
        const OhMySnackBar(
          content: Text('Current or destination location is unavailable.'),
        ),
      );
      return;
    }

    setState(() => recommendationLoading = true);
    try {
      final newDestination = RouteLocation.fromPlace(place);
      final uri = Uri.parse('${widget.backend}/api/routes').replace(
        queryParameters: {
          'startLat': '${current.latitude}',
          'startLon': '${current.longitude}',
          'endLat': '${newDestination.latitude}',
          'endLon': '${newDestination.longitude}',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          data['details'] ?? data['error'] ?? 'Routes unavailable.',
        );
      }
      final newRoutes = List<Map<String, dynamic>>.from(data['routes'] ?? [])
          .map(DrivingRoute.fromJson)
          .where((route) => route.routeToken.isNotEmpty)
          .toList();
      if (newRoutes.isEmpty) throw Exception('No driving route was returned.');
      var fastestIndex = 0;
      for (var index = 1; index < newRoutes.length; index++) {
        if (newRoutes[index].minutes < newRoutes[fastestIndex].minutes) {
          fastestIndex = index;
        }
      }
      if (!mounted) return;
      setState(() {
        activeDestination = newDestination;
        activeRoutes = newRoutes;
        selectedRoute = fastestIndex;
        stepIndex = 0;
        sdkRemainingDistanceMeters = null;
        sdkRemainingTimeSeconds = null;
        showRecommendationCarousel = false;
        recommendations = [];
        followUser = true;
      });
      await navigationMapKey.currentState?.recenter();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        OhMySnackBar(
          content: Text('Fastest route changed to ${newDestination.name}.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          OhMySnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => recommendationLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const OhMySnackBar(
              content: Text('Use the close button to cancel navigation.'),
            ),
          );
      },
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: NativeNavigationMap(
                key: navigationMapKey,
                destinationName: activeDestination.name,
                destinationLatitude: activeDestination.latitude,
                destinationLongitude: activeDestination.longitude,
                routeToken: route.routeToken,
                trafficEnabled: trafficEnabled,
                voiceGuidanceEnabled: voiceGuidanceEnabled,
                vibrationEnabled: vibrationEnabled,
                onArrived: finishJourney,
                onLocation: (latitude, longitude) {
                  if (!mounted) return;
                  setState(() {
                    position = Position(
                      longitude: longitude,
                      latitude: latitude,
                      timestamp: DateTime.now(),
                      accuracy: 0,
                      altitude: 0,
                      altitudeAccuracy: 0,
                      heading: 0,
                      headingAccuracy: 0,
                      speed: 0,
                      speedAccuracy: 0,
                    );
                  });
                },
                onProgress: (distanceMeters, timeSeconds, traffic) {
                  if (!mounted) return;
                  setState(() {
                    sdkRemainingDistanceMeters = distanceMeters;
                    sdkRemainingTimeSeconds = timeSeconds;
                    trafficSeverity = traffic;
                  });
                  _handleTrafficProgress(distanceMeters, timeSeconds, traffic);
                },
                onStatus: (message) {
                  if (mounted) setState(() => locationError = message);
                },
              ),
            ),
            if (!showRecommendationCarousel)
              Positioned(
                left: 14,
                bottom: 132,
                child: Column(
                  children: [
                    navigationButton(Icons.cloud_outlined, showWeather),
                  ],
                ),
              ),
            if (!showRecommendationCarousel)
              Positioned(
                right: 14,
                bottom: navigationPanelExpanded ? 264 : 132,
                child: Column(
                  children: [
                    navigationButton(Icons.explore_outlined, () {
                      followUser = false;
                      navigationMapKey.currentState?.showNorthUp();
                    }),
                    const SizedBox(height: 9),
                    navigationButton(
                      Icons.lightbulb_outline_rounded,
                      showRecommendationMode,
                    ),
                    const SizedBox(height: 9),
                    navigationButton(Icons.my_location_rounded, () {
                      followUser = true;
                      navigationMapKey.currentState?.recenter();
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
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: reducedLocationAccuracy
                        ? Geolocator.openAppSettings
                        : null,
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
              ),
            if (navigationSimulationEnabled && locationError == null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 132,
                left: 18,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xff14213d).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Text(
                        'TEST SIMULATION  -  5x',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (recommendationLoading)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 170,
                child: Center(child: WauLoadingIndicator(size: 58)),
              ),
            if (showRecommendationCarousel) navigationRecommendationCarousel(),
            if (!useNativeNavigationFooter)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity < -120 && !navigationPanelExpanded) {
                      _setNavigationPanelExpanded(true);
                    } else if (velocity > 120 && navigationPanelExpanded) {
                      _setNavigationPanelExpanded(false);
                    }
                  },
                  child: Material(
                    elevation: 14,
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    child: SafeArea(
                      top: false,
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Semantics(
                                button: true,
                                label: navigationPanelExpanded
                                    ? 'Collapse navigation settings'
                                    : 'Expand navigation settings',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _setNavigationPanelExpanded(
                                    !navigationPanelExpanded,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      32,
                                      2,
                                      32,
                                      8,
                                    ),
                                    child: Container(
                                      width: 42,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: const Color(0xffaeb7c6),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
                                          '${sdkRemainingTimeSeconds == null ? route.minutes : math.max(1, (sdkRemainingTimeSeconds! / 60).ceil())} min',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            color: etaColor,
                                          ),
                                        ),
                                        Text(
                                          '${(sdkRemainingDistanceMeters == null ? route.distanceKm : sdkRemainingDistanceMeters! / 1000).toStringAsFixed(1)} km remaining',
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
                              if (navigationPanelExpanded) ...[
                                const Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: Divider(height: 1),
                                ),
                                SwitchListTile.adaptive(
                                  contentPadding: const EdgeInsets.only(
                                    left: 4,
                                  ),
                                  secondary: const Icon(
                                    Icons.volume_up_outlined,
                                    color: _routeBlue,
                                  ),
                                  title: const Text('Voice Guidance'),
                                  subtitle: const Text(
                                    'Spoken turn-by-turn directions',
                                  ),
                                  value: voiceGuidanceEnabled,
                                  onChanged: (value) => setState(
                                    () => voiceGuidanceEnabled = value,
                                  ),
                                ),
                                SwitchListTile.adaptive(
                                  contentPadding: const EdgeInsets.only(
                                    left: 4,
                                  ),
                                  secondary: const Icon(
                                    Icons.vibration_rounded,
                                    color: _routeBlue,
                                  ),
                                  title: const Text('Vibration'),
                                  subtitle: const Text(
                                    'Navigation haptic feedback',
                                  ),
                                  value: vibrationEnabled,
                                  onChanged: (value) =>
                                      setState(() => vibrationEnabled = value),
                                ),
                              ],
                            ],
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
    );
  }

  void _setNavigationPanelExpanded(bool expanded) {
    if (navigationPanelExpanded == expanded) return;
    setState(() => navigationPanelExpanded = expanded);
    unawaited(
      navigationMapKey.currentState?.setBottomPanelExpanded(expanded) ??
          Future<void>.value(),
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
    height: 260,
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
                if (recommendations.length > 1)
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
                    navigationPhotoRecommendationCard(recommendations[index]),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget navigationPhotoRecommendationCard(Map<String, dynamic> item) {
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
    ].take(5).toList();
    final photoName = place['photo']?['name']?.toString();
    final title =
        place['displayName']?['text']?.toString() ?? 'Recommended stop';
    final description =
        place['description']?.toString() ??
        place['formattedAddress']?.toString() ??
        'Description unavailable.';
    final eta = (place['etaMinutes'] as num?)?.round();
    final distanceKm =
        (place['routeDistanceKm'] ?? place['distanceKm']) as num?;
    final placeId = place['id']?.toString() ?? '';
    final bookmarked = bookmarkedRecommendations.contains(placeId);

    return SizedBox(
      width: 350,
      child: Material(
        color: const Color(0xff252a34),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openRecommendationDetails(item),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photoName != null)
                Image.network(
                  '${widget.backend}/api/places/photo?name=${Uri.encodeQueryComponent(photoName)}',
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
                        navigationOverlayPill('#${item['rank'] ?? 1}'),
                        const Spacer(),
                        navigationOverlayPill(
                          '${ranking['similarityPercentage'] ?? 0}% match',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${eta == null ? 'ETA unavailable' : '$eta min'}  ·  ${distanceKm == null ? 'Distance unavailable' : '${distanceKm.toStringAsFixed(1)} km'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    navigationOverlayTags(tags),
                    const Spacer(),
                    Row(
                      children: [
                        navigationOverlayAction(
                          Icons.navigation_rounded,
                          'Navigate',
                          () => navigateToRecommendation(item),
                        ),
                        navigationOverlayAction(
                          bookmarked ? Icons.bookmark : Icons.bookmark_border,
                          'Bookmark',
                          () => setState(
                            () => bookmarked
                                ? bookmarkedRecommendations.remove(placeId)
                                : bookmarkedRecommendations.add(placeId),
                          ),
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
    );
  }

  Widget navigationOverlayPill(String text) => Container(
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

  Widget navigationOverlayTags(List<String> tags) => SizedBox(
    height: 24,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: tags.length,
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
          tags[index],
          style: const TextStyle(color: Colors.white, fontSize: 9),
        ),
      ),
    ),
  );

  Widget navigationOverlayAction(
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: SizedBox(
      height: 30,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 9)),
        style: FilledButton.styleFrom(
          foregroundColor: _routeBlue,
          backgroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          visualDensity: VisualDensity.compact,
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
    ].take(5).toList();
    final photoName = place['photo']?['name']?.toString();
    final title =
        place['displayName']?['text']?.toString() ?? 'Recommended stop';
    final eta = (place['etaMinutes'] as num?)?.round();
    final distanceKm =
        (place['routeDistanceKm'] ?? place['distanceKm']) as num?;
    final placeId = place['id']?.toString() ?? '';
    final bookmarked = bookmarkedRecommendations.contains(placeId);
    return SizedBox(
      width: 350,
      child: Material(
        color: const Color(0xfff7faff),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xffc9daf8)),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openRecommendationDetails(item),
          child: Padding(
            padding: const EdgeInsets.all(10),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
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
                        style: const TextStyle(
                          fontSize: 11,
                          color: _routeMuted,
                        ),
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
                        style: const TextStyle(fontSize: 0, height: 0),
                      ),
                      navigationTagRow(tags),
                      const Spacer(),
                      Row(
                        children: [
                          navigationCardAction(
                            Icons.navigation_rounded,
                            'Navigate',
                            () => navigateToRecommendation(item),
                          ),
                          navigationCardAction(
                            bookmarked ? Icons.bookmark : Icons.bookmark_border,
                            'Bookmark',
                            () => setState(() {
                              if (bookmarked) {
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
        ),
      ),
    );
  }

  Widget navigationTagRow(List<String> tags) => SizedBox(
    height: 24,
    child: tags.isEmpty
        ? const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tags unavailable',
              style: TextStyle(fontSize: 9, color: _routeMuted),
            ),
          )
        : ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tags.length,
            separatorBuilder: (_, index) => const SizedBox(width: 5),
            itemBuilder: (_, index) => Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: const Color(0xffedf4ff),
                border: Border.all(color: const Color(0xffc9dcfb)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                tags[index],
                maxLines: 1,
                style: const TextStyle(fontSize: 9, color: _routeBlue),
              ),
            ),
          ),
  );

  Widget navigationCardAction(
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: SizedBox(
      height: 28,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 9)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _routeBlue,
          side: const BorderSide(color: Color(0xff9bb9ec)),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          visualDensity: VisualDensity.compact,
        ),
      ),
    ),
  );
}

class _NavigationPlaceDetailPage extends StatefulWidget {
  const _NavigationPlaceDetailPage({
    required this.item,
    required this.backend,
    required this.onNavigate,
  });

  final Map<String, dynamic> item;
  final String backend;
  final Future<void> Function() onNavigate;

  @override
  State<_NavigationPlaceDetailPage> createState() =>
      _NavigationPlaceDetailPageState();
}

class _NavigationPlaceDetailPageState
    extends State<_NavigationPlaceDetailPage> {
  bool bookmarked = false;
  int photoPage = 0;

  @override
  Widget build(BuildContext context) {
    final place = Map<String, dynamic>.from(
      widget.item['place'] as Map? ?? const {},
    );
    final analysis = Map<String, dynamic>.from(
      widget.item['analysis'] as Map? ?? const {},
    );
    final photos = List<Map<String, dynamic>>.from(place['photos'] ?? []);
    final tags = <String>[
      ...List<String>.from(analysis['generalTags'] ?? []),
      ...List<String>.from(analysis['culturalTags'] ?? []),
    ];
    final title = place['displayName']?['text']?.toString() ?? 'Place details';
    final eta = (place['etaMinutes'] as num?)?.round();
    final distanceKm =
        (place['routeDistanceKm'] ?? place['distanceKm']) as num?;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: () => setState(() => bookmarked = !bookmarked),
            icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: widget.onNavigate,
          icon: const Icon(Icons.navigation_rounded),
          label: const Text('Navigate'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 250,
              child: photos.isEmpty
                  ? const _NavigationPhotoUnavailable()
                  : PageView.builder(
                      itemCount: math.min(9, photos.length),
                      onPageChanged: (value) =>
                          setState(() => photoPage = value),
                      itemBuilder: (_, index) => Image.network(
                        '${widget.backend}/api/places/photo?name=${Uri.encodeQueryComponent(photos[index]['name'])}',
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) =>
                            const _NavigationPhotoUnavailable(),
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
                    '${photoPage + 1} of ${math.min(9, photos.length)}',
                    style: const TextStyle(fontSize: 11, color: _routeMuted),
                  ),
                  const Text(
                    'Swipe for more →',
                    style: TextStyle(fontSize: 11, color: _routeMuted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          const Text(
            'ABOUT THIS PLACE',
            style: TextStyle(
              color: _routeBlue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: _routeInk,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            place['description']?.toString() ??
                place['primaryTypeDisplayName']?.toString() ??
                'Description unavailable.',
            style: const TextStyle(color: _routeMuted, height: 1.5),
          ),
          const SizedBox(height: 12),
          Text(
            place['formattedAddress']?.toString() ?? 'Address unavailable',
            style: const TextStyle(color: _routeMuted),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: detailMetric(
                  'Estimated arrival',
                  eta == null ? 'Unavailable' : '$eta min',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: detailMetric(
                  'Distance',
                  distanceKm == null
                      ? 'Unavailable'
                      : '${distanceKm.toStringAsFixed(1)} km',
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
            children: tags
                .map(
                  (tag) => Chip(
                    label: Text(tag, style: const TextStyle(fontSize: 11)),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget detailMetric(String label, String value) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xffedf4ff),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: _routeMuted)),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: _routeBlue,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _NavigationPhotoUnavailable extends StatelessWidget {
  const _NavigationPhotoUnavailable();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xfff4bc60),
    child: Column(
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
