import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../../ai_chatbot/services/nova_voice_choice_controller.dart';
import '../../../ai_chatbot/services/nova_voice_controller.dart';
import '../../../ai_chatbot/services/nova_barge_in_service.dart';
import '../../../ai_chatbot/services/nova_bounded_voice_listener.dart';
import '../../../ai_chatbot/services/api_service.dart';
import '../weather/weather_feature.dart';
import 'navigation_sensor.dart';

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
    this.autoStart = false,
    this.isAiJourney = false,
  });
  final String backend;
  final RouteLocation destination;
  final bool autoStart;
  final bool isAiJourney;

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
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(useCurrentLocation());
      });
    }
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
          isAiJourney: widget.isAiJourney,
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

class AiPlaceRouteCandidate {
  const AiPlaceRouteCandidate({
    required this.place,
    required this.destination,
    required this.previewRoute,
  });

  final Map<String, dynamic> place;
  final RouteLocation destination;
  final DrivingRoute previewRoute;
}

/// AI-only verified place selection. Google Places supplies the destinations
/// and Google Routes supplies each ETA/distance before Nova describes them.
class AiPlaceChoicePage extends StatefulWidget {
  const AiPlaceChoicePage({
    super.key,
    required this.backend,
    required this.start,
    required this.places,
  });

  final String backend;
  final RouteLocation start;
  final List<Map<String, dynamic>> places;

  @override
  State<AiPlaceChoicePage> createState() => _AiPlaceChoicePageState();
}

class _AiPlaceChoicePageState extends State<AiPlaceChoicePage> {
  late final FlutterTts tts;
  late final NovaBoundedVoiceListener choiceListener;
  NovaVoiceChoiceRegistration? voiceRegistration;
  GoogleMapController? mapController;
  List<AiPlaceRouteCandidate> candidates = [];
  int selected = 0;
  int speechGeneration = 0;
  bool loading = true;
  bool speaking = false;
  String? error;

  String get _language {
    final code = NovaVoiceController.state.value.languageCode.toLowerCase();
    if (code.startsWith('zh')) return 'zh-CN';
    if (code.startsWith('ms')) return 'ms-MY';
    return 'en-US';
  }

  @override
  void initState() {
    super.initState();
    tts = FlutterTts();
    choiceListener = NovaBoundedVoiceListener();
    voiceRegistration = NovaVoiceChoiceController.register(_handleVoiceChoice);
    unawaited(_loadCandidates());
  }

  Future<AiPlaceRouteCandidate?> _loadCandidate(
    Map<String, dynamic> place,
  ) async {
    try {
      final destination = RouteLocation.fromPlace(place);
      final uri = Uri.parse('${widget.backend}/api/routes').replace(
        queryParameters: {
          'startLat': '${widget.start.latitude}',
          'startLon': '${widget.start.longitude}',
          'endLat': '${destination.latitude}',
          'endLon': '${destination.longitude}',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final routes = List<Map<String, dynamic>>.from(
        data['routes'] ?? [],
      ).map(DrivingRoute.fromJson).toList();
      if (routes.isEmpty) return null;
      routes.sort((a, b) => a.minutes.compareTo(b.minutes));
      return AiPlaceRouteCandidate(
        place: place,
        destination: destination,
        previewRoute: routes.first,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCandidates() async {
    final places = widget.places
        .where((place) => place['location'] is Map)
        .take(4)
        .toList(growable: false);
    final loaded = await Future.wait(places.map(_loadCandidate));
    if (!mounted) return;
    setState(() {
      candidates = loaded.whereType<AiPlaceRouteCandidate>().toList();
      loading = false;
      if (candidates.isEmpty) {
        error = 'No verified driving routes are available for these places.';
      }
    });
    if (candidates.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitSelected());
      unawaited(_narrateCandidates());
    }
  }

  String _candidateNarration() {
    final summaries = candidates
        .asMap()
        .entries
        .map((entry) {
          final ordinal = entry.key + 1;
          final candidate = entry.value;
          final route = candidate.previewRoute;
          final distance = route.distanceKm.toStringAsFixed(1);
          if (_language.startsWith('zh')) {
            return '第$ordinal个，${candidate.destination.name}，约${route.minutes}分钟，距离$distance公里。';
          }
          if (_language.startsWith('ms')) {
            return 'Pilihan $ordinal, ${candidate.destination.name}, kira-kira ${route.minutes} minit dan $distance kilometer.';
          }
          return 'Option $ordinal, ${candidate.destination.name}, about ${route.minutes} minutes and $distance kilometres.';
        })
        .join(' ');
    if (_language.startsWith('zh')) {
      return '$summaries 您想选择哪个地点？请说地点编号或名称。';
    }
    if (_language.startsWith('ms')) {
      return '$summaries Tempat mana pilihan anda? Sebut nombor atau nama tempat.';
    }
    return '$summaries Which place would you like? Say its number or name.';
  }

  Future<void> _narrateCandidates() async {
    final generation = ++speechGeneration;
    final narration = _candidateNarration();
    var userStartedSpeaking = false;
    setState(() => speaking = true);
    NovaVoiceController.update(
      phase: NovaVoicePhase.speaking,
      response: narration,
      clearMessage: true,
    );
    try {
      await NovaBargeInService.start(
        languageCode: _language,
        onSpeechStarted: () async {
          if (!mounted || generation != speechGeneration) return;
          userStartedSpeaking = true;
          NovaVoiceController.update(
            phase: NovaVoicePhase.listening,
            clearResponse: true,
          );
          await tts.stop();
          await NovaBargeInService.stop();
          if (!mounted || generation != speechGeneration) return;
          await _startCandidateChoiceListening();
        },
        onTranscript: _handleBargeIn,
      );
      await tts.setLanguage(_language);
      await tts.setSpeechRate(0.48);
      await tts.awaitSpeakCompletion(true);
      await tts.speak(narration);
    } catch (_) {
      // The visible Google data remains usable when device TTS is unavailable.
    }
    if (userStartedSpeaking) return;
    await NovaBargeInService.stop();
    if (!mounted || generation != speechGeneration) return;
    setState(() => speaking = false);
    await _startCandidateChoiceListening();
  }

  Future<void> _startCandidateChoiceListening() async {
    if (!mounted || candidates.isEmpty) return;
    speechGeneration++;
    await NovaBargeInService.stop();
    await tts.stop();
    if (!mounted) return;
    setState(() => speaking = false);
    await choiceListener.start(
      context: candidates
          .asMap()
          .entries
          .map((entry) => '${entry.key + 1}: ${entry.value.destination.name}')
          .join(' | '),
      onTranscript: (transcript) async {
        if (!mounted) return;
        NovaVoiceController.update(message: transcript);
        await _handleVoiceChoice(transcript);
      },
      onSilence: () {
        NovaVoiceController.update(phase: NovaVoicePhase.completed);
      },
    );
  }

  void _selectCandidateManually(int index) {
    NovaVoiceController.reset();
    speechGeneration++;
    unawaited(NovaBargeInService.stop());
    unawaited(choiceListener.stop(discard: true));
    unawaited(tts.stop());
    setState(() {
      speaking = false;
      selected = index;
    });
    unawaited(_fitSelected());
  }

  void _openCandidateManually() {
    NovaVoiceController.reset();
    speechGeneration++;
    unawaited(NovaBargeInService.stop());
    unawaited(choiceListener.stop(discard: true));
    unawaited(tts.stop());
    if (mounted) setState(() => speaking = false);
    _openSelected();
  }

  Future<void> _handleBargeIn(String transcript, bool isFinal) async {
    if (!mounted || !speaking) return;
    NovaVoiceController.update(message: transcript);
    if (!isFinal) return;
    final consumed = await _handleVoiceChoice(transcript);
    if (!consumed) return;
    speechGeneration++;
    await NovaBargeInService.stop();
    await tts.stop();
    if (mounted) setState(() => speaking = false);
  }

  Future<bool> _handleVoiceChoice(String transcript) async {
    if (!mounted || candidates.isEmpty) return false;
    final resolution = await ApiService.resolveVoiceChoice(
      transcript: transcript,
      mode: 'place_selection',
      selectedIndex: selected,
      choices: candidates
          .asMap()
          .entries
          .map(
            (entry) => <String, dynamic>{
              'index': entry.key,
              'label': entry.value.destination.name,
            },
          )
          .toList(growable: false),
    );
    if (!mounted) return false;
    if (resolution['action'] == 'reject') {
      Navigator.pop(context);
      return true;
    }
    final index = resolution['index'];
    if (resolution['action'] == 'select' && index is int) {
      setState(() => selected = index);
      await _fitSelected();
      _openSelected();
      return true;
    }
    if (resolution['action'] == 'confirm') {
      _openSelected();
      return true;
    }
    return false;
  }

  void _openSelected() {
    if (!mounted || candidates.isEmpty) return;
    speechGeneration++;
    unawaited(NovaBargeInService.stop());
    unawaited(choiceListener.stop(discard: true));
    unawaited(tts.stop());
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutePreviewPage(
          backend: widget.backend,
          start: widget.start,
          destination: candidates[selected].destination,
          isAiJourney: true,
        ),
      ),
    );
  }

  Future<void> _fitSelected() async {
    if (mapController == null || candidates.isEmpty) return;
    final points = candidates[selected].previewRoute.points;
    if (points.isEmpty) return;
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
    await mapController!.animateCamera(
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
            zoom: 11,
          ),
          onMapCreated: (controller) {
            mapController = controller;
            unawaited(_fitSelected());
          },
          markers: candidates.asMap().entries.map((entry) {
            final destination = entry.value.destination;
            return Marker(
              markerId: MarkerId(destination.id ?? 'candidate-${entry.key}'),
              position: LatLng(destination.latitude, destination.longitude),
              infoWindow: InfoWindow(title: destination.name),
              onTap: () => _selectCandidateManually(entry.key),
            );
          }).toSet(),
          polylines: candidates.isEmpty
              ? const <Polyline>{}
              : {
                  Polyline(
                    polylineId: const PolylineId('candidate-preview'),
                    points: candidates[selected].previewRoute.points,
                    color: _routeBlue,
                    width: 7,
                  ),
                },
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FloatingActionButton.small(
                heroTag: 'ai-place-back',
                onPressed: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back),
              ),
            ),
          ),
        ),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null)
          Center(
            child: Card(
              margin: const EdgeInsets.all(28),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(error!, textAlign: TextAlign.center),
              ),
            ),
          ),
        if (candidates.isNotEmpty)
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
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: candidates.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final candidate = candidates[index];
                          final route = candidate.previewRoute;
                          return ChoiceChip(
                            selected: selected == index,
                            onSelected: (_) => _selectCandidateManually(index),
                            label: SizedBox(
                              width: 150,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${index + 1}. ${candidate.destination.name}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${route.minutes} min · ${route.distanceKm.toStringAsFixed(1)} km',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: _startCandidateChoiceListening,
                          icon: const Icon(Icons.mic_rounded),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: _openCandidateManually,
                            child: const Text('Choose this place'),
                          ),
                        ),
                      ],
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
    speechGeneration++;
    NovaBargeInService.stop();
    choiceListener.dispose();
    voiceRegistration?.dispose();
    tts.stop();
    mapController?.dispose();
    super.dispose();
  }
}

class RoutePreviewPage extends StatefulWidget {
  const RoutePreviewPage({
    super.key,
    required this.backend,
    required this.start,
    required this.destination,
    this.isAiJourney = false,
  });
  final String backend;
  final RouteLocation start, destination;
  final bool isAiJourney;

  @override
  State<RoutePreviewPage> createState() => _RoutePreviewPageState();
}

class _RoutePreviewPageState extends State<RoutePreviewPage> {
  GoogleMapController? controller;
  late final FlutterTts routeTts;
  late final NovaBoundedVoiceListener routeChoiceListener;
  List<DrivingRoute> routes = [];
  int selected = 0;
  bool loading = true;
  String? error;
  Timer? aiConfirmationTimer;
  NovaVoiceChoiceRegistration? voiceChoiceRegistration;
  int aiSecondsLeft = 20;
  int narrationGeneration = 0;
  bool aiNarrating = false;
  bool navigationStarting = false;

  @override
  void initState() {
    super.initState();
    routeTts = FlutterTts();
    routeChoiceListener = NovaBoundedVoiceListener();
    if (widget.isAiJourney) {
      voiceChoiceRegistration = NovaVoiceChoiceController.register(
        _handleVoiceChoice,
      );
      NovaVoiceController.startRequests.addListener(_interruptNarration);
    }
    loadRoutes();
  }

  Future<bool> _handleVoiceChoice(String transcript) async {
    if (!mounted || routes.isEmpty) return false;
    final resolution = await ApiService.resolveVoiceChoice(
      transcript: transcript,
      mode: 'route_selection',
      selectedIndex: selected,
      choices: routes
          .asMap()
          .entries
          .map(
            (entry) => <String, dynamic>{
              'index': entry.key,
              'label':
                  '${entry.value.minutes} min, '
                  '${entry.value.distanceKm.toStringAsFixed(1)} km, '
                  '${entry.value.traffic}',
            },
          )
          .toList(growable: false),
    );
    if (!mounted) return false;
    final requested = resolution['index'];
    if (resolution['action'] == 'select' && requested is int) {
      setState(() => selected = requested);
      await fitRoute();
      if (!mounted) return true;
      _beginNavigation();
      return true;
    }
    if (resolution['action'] == 'confirm') {
      _beginNavigation();
      return true;
    }
    if (resolution['action'] == 'reject') {
      Navigator.pop(context);
      return true;
    }
    return false;
  }

  void _interruptNarration() {
    if (!aiNarrating) return;
    NovaVoiceController.reset();
    narrationGeneration++;
    unawaited(NovaBargeInService.stop());
    unawaited(routeTts.stop());
    if (mounted) setState(() => aiNarrating = false);
  }

  Future<void> _handleBargeInTranscript(String transcript, bool isFinal) async {
    if (!mounted || !aiNarrating) return;
    NovaVoiceController.update(message: transcript);
    if (!isFinal) return;
    final consumed = await _handleVoiceChoice(transcript);
    if (!consumed) return;
    narrationGeneration++;
    await NovaBargeInService.stop();
    await routeTts.stop();
    if (!mounted) return;
    setState(() => aiNarrating = false);
  }

  String get _voiceLanguage {
    final code = NovaVoiceController.state.value.languageCode.toLowerCase();
    if (code.startsWith('ms')) return 'ms-MY';
    if (code.startsWith('zh')) return 'zh-CN';
    return 'en-US';
  }

  String _routeNarration() {
    final summaries = routes
        .asMap()
        .entries
        .map((entry) {
          final number = entry.key + 1;
          final route = entry.value;
          final distance = route.distanceKm.toStringAsFixed(1);
          if (_voiceLanguage.startsWith('ms')) {
            return 'Laluan $number mengambil masa ${route.minutes} minit, '
                'sejauh $distance kilometer, dengan ${route.traffic}.';
          }
          if (_voiceLanguage.startsWith('zh')) {
            return '路线$number需要${route.minutes}分钟，全程$distance公里，'
                '交通状况为${route.traffic}。';
          }
          return 'Route $number takes ${route.minutes} minutes, covers '
              '$distance kilometres, with ${route.traffic}.';
        })
        .join(' ');
    if (_voiceLanguage.startsWith('ms')) {
      return '$summaries Laluan mana pilihan anda? Sila jawab sekarang.';
    }
    if (_voiceLanguage.startsWith('zh')) {
      return '$summaries 您要选择哪条路线？请现在回答。';
    }
    return '$summaries Which route would you like? You may answer now.';
  }

  Future<void> _narrateRoutes() async {
    if (!mounted || !widget.isAiJourney || routes.isEmpty) return;
    final generation = ++narrationGeneration;
    final narration = _routeNarration();
    var userStartedSpeaking = false;
    setState(() => aiNarrating = true);
    NovaVoiceController.update(
      phase: NovaVoicePhase.speaking,
      response: narration,
      amplitude: 0.45,
      clearMessage: true,
    );
    try {
      await NovaBargeInService.start(
        languageCode: _voiceLanguage,
        onSpeechStarted: () async {
          if (!mounted || generation != narrationGeneration) return;
          userStartedSpeaking = true;
          NovaVoiceController.update(
            phase: NovaVoicePhase.listening,
            clearResponse: true,
          );
          await routeTts.stop();
          await NovaBargeInService.stop();
          if (!mounted || generation != narrationGeneration) return;
          setState(() => aiNarrating = false);
          _startAiCountdown();
          await _startRouteChoiceListening();
        },
        onTranscript: _handleBargeInTranscript,
      );
      await routeTts.setLanguage(_voiceLanguage);
      await routeTts.setSpeechRate(0.48);
      await routeTts.setVolume(1);
      await routeTts.awaitSpeakCompletion(true);
      await routeTts.speak(narration);
    } catch (_) {
      // The visible route data remains authoritative when device TTS is
      // unavailable; continue into the hands-free confirmation session.
    }
    if (userStartedSpeaking) return;
    await NovaBargeInService.stop();
    if (!mounted || generation != narrationGeneration) return;
    setState(() => aiNarrating = false);
    _startAiCountdown();
    await _startRouteChoiceListening();
  }

  Future<void> _startRouteChoiceListening() async {
    if (!mounted || routes.isEmpty || navigationStarting) return;
    await routeChoiceListener.start(
      context: routes
          .asMap()
          .entries
          .map(
            (entry) =>
                '${entry.key + 1}: ${entry.value.minutes} min, '
                '${entry.value.distanceKm.toStringAsFixed(1)} km',
          )
          .join(' | '),
      onTranscript: (transcript) async {
        if (!mounted) return;
        NovaVoiceController.update(message: transcript);
        await _handleVoiceChoice(transcript);
      },
      onSilence: () {
        NovaVoiceController.update(phase: NovaVoicePhase.completed);
      },
    );
  }

  void _selectRouteManually(int index) {
    NovaVoiceController.reset();
    narrationGeneration++;
    unawaited(NovaBargeInService.stop());
    unawaited(routeChoiceListener.stop(discard: true));
    unawaited(routeTts.stop());
    setState(() {
      aiNarrating = false;
      selected = index;
    });
    if (aiSecondsLeft <= 0) _startAiCountdown();
    unawaited(fitRoute());
  }

  void _beginNavigation() {
    if (!mounted || routes.isEmpty || navigationStarting) return;
    NovaVoiceController.reset();
    navigationStarting = true;
    narrationGeneration++;
    unawaited(NovaBargeInService.stop());
    unawaited(routeChoiceListener.stop(discard: true));
    unawaited(routeTts.stop());
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ActiveNavigationPage(
          backend: widget.backend,
          destination: widget.destination,
          routes: routes,
          initialRoute: selected,
        ),
      ),
    );
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
        if (widget.isAiJourney && routes.isNotEmpty) {
          unawaited(_narrateRoutes());
        }
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

  void _startAiCountdown() {
    aiConfirmationTimer?.cancel();
    aiSecondsLeft = 20;
    aiConfirmationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || aiSecondsLeft <= 1) {
        timer.cancel();
        if (mounted) setState(() => aiSecondsLeft = 0);
        return;
      }
      setState(() => aiSecondsLeft--);
    });
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
                            onSelected: (_) => _selectRouteManually(index),
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
                    Row(
                      children: [
                        if (widget.isAiJourney) ...[
                          IconButton.filledTonal(
                            onPressed: _startRouteChoiceListening,
                            icon: const Icon(Icons.mic_rounded),
                            tooltip: 'Start or cancel by voice',
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: FilledButton(
                            onPressed: widget.isAiJourney && aiSecondsLeft <= 0
                                ? null
                                : _beginNavigation,
                            child: Text(
                              widget.isAiJourney
                                  ? aiSecondsLeft > 0
                                        ? 'Start Journey · ${aiSecondsLeft}s'
                                        : 'Journey confirmation expired'
                                  : 'Start Journey',
                            ),
                          ),
                        ),
                      ],
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
    narrationGeneration++;
    NovaBargeInService.stop();
    routeChoiceListener.dispose();
    aiConfirmationTimer?.cancel();
    voiceChoiceRegistration?.dispose();
    NovaVoiceController.startRequests.removeListener(_interruptNarration);
    routeTts.stop();
    controller?.dispose();
    super.dispose();
  }
}

class _DrivingAlert {
  const _DrivingAlert({required this.message, required this.routes});

  final String message;
  final List<DrivingRoute> routes;
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
  late final FlutterTts alertTts;
  late final NovaBoundedVoiceListener alertVoiceListener;
  StreamSubscription<Position>? positionSubscription;
  late int selectedRoute;
  late RouteLocation activeDestination;
  late List<DrivingRoute> activeRoutes;
  int stepIndex = 0;
  Position? position;
  bool movingCameraProgrammatically = false;
  bool reducedLocationAccuracy = false;
  bool trafficEnabled = true, followUser = true;
  bool recommendationLoading = false, showRecommendationCarousel = false;
  List<Map<String, dynamic>> recommendations = [];
  String recommendationTitle = 'Recommended stops';
  String? locationError;
  final Set<String> bookmarkedRecommendations = {};
  Timer? disruptionTimer;
  NovaVoiceChoiceRegistration? voiceChoiceRegistration;
  _DrivingAlert? drivingAlert;
  bool disruptionCheckRunning = false;
  String? lastAlertSignature;
  bool initialDisruptionCheckStarted = false;
  int alertSpeechGeneration = 0;

  DrivingRoute get route => activeRoutes[selectedRoute];
  NavigationStep? get step => route.steps.isEmpty
      ? null
      : route.steps[math.min(stepIndex, route.steps.length - 1)];

  @override
  void initState() {
    super.initState();
    alertTts = FlutterTts();
    alertVoiceListener = NovaBoundedVoiceListener();
    activeDestination = widget.destination;
    activeRoutes = List<DrivingRoute>.from(widget.routes);
    selectedRoute = widget.initialRoute;
    voiceChoiceRegistration = NovaVoiceChoiceController.register(
      _handleVoiceChoice,
    );
    startTracking();
    disruptionTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(_checkDrivingConditions()),
    );
  }

  Future<bool> _handleVoiceChoice(String transcript) async {
    if (!mounted || drivingAlert == null) return false;
    final resolution = await ApiService.resolveVoiceChoice(
      transcript: transcript,
      mode: 'reroute_confirmation',
      selectedIndex: selectedRoute,
      choices: activeRoutes
          .asMap()
          .entries
          .map(
            (entry) => <String, dynamic>{
              'index': entry.key,
              'label':
                  '${entry.value.minutes} min, '
                  '${entry.value.distanceKm.toStringAsFixed(1)} km, '
                  '${entry.value.traffic}',
            },
          )
          .toList(growable: false),
    );
    if (!mounted || drivingAlert == null) return false;
    if (resolution['action'] == 'confirm' || resolution['action'] == 'select') {
      _acceptReroute();
      return true;
    }
    if (resolution['action'] == 'reject') {
      _keepCurrentRoute();
      return true;
    }
    return false;
  }

  String get _alertVoiceLanguage {
    final code = NovaVoiceController.state.value.languageCode.toLowerCase();
    if (code.startsWith('ms')) return 'ms-MY';
    if (code.startsWith('zh')) return 'zh-CN';
    return 'en-US';
  }

  String _spokenReroutePrompt(String reason) {
    if (_alertVoiceLanguage.startsWith('ms')) {
      return '$reason dikesan. Adakah anda mahu tukar laluan sekarang?';
    }
    if (_alertVoiceLanguage.startsWith('zh')) {
      return '检测到$reason。您现在需要重新规划路线吗？';
    }
    return '$reason detected. Would you like to reroute now?';
  }

  Future<void> _announceDrivingAlert(String reason, String alertMessage) async {
    final generation = ++alertSpeechGeneration;
    final prompt = _spokenReroutePrompt(reason);
    var interrupted = false;
    NovaVoiceController.update(
      phase: NovaVoicePhase.speaking,
      response: prompt,
      amplitude: 0.45,
      clearMessage: true,
    );
    try {
      await NovaBargeInService.start(
        languageCode: _alertVoiceLanguage,
        onSpeechStarted: () async {
          if (!mounted || generation != alertSpeechGeneration) return;
          interrupted = true;
          NovaVoiceController.update(
            phase: NovaVoicePhase.listening,
            clearResponse: true,
          );
          await alertTts.stop();
          await NovaBargeInService.stop();
          if (!mounted || generation != alertSpeechGeneration) return;
          await _listenForDrivingAnswer();
        },
        onTranscript: (transcript, isFinal) async {
          if (!mounted || generation != alertSpeechGeneration) return;
          NovaVoiceController.update(
            phase: NovaVoicePhase.listening,
            message: transcript,
          );
          if (!isFinal) return;
          interrupted = true;
          await alertTts.stop();
          final consumed = await _handleVoiceChoice(transcript);
          if (consumed) await NovaBargeInService.stop();
        },
      );
      await alertTts.setLanguage(_alertVoiceLanguage);
      await alertTts.setSpeechRate(0.48);
      await alertTts.setVolume(1);
      await alertTts.awaitSpeakCompletion(true);
      await alertTts.speak(prompt);
    } catch (_) {
      // The alert remains visible and actionable if TTS is unavailable.
    }
    if (!interrupted) await NovaBargeInService.stop();
    if (!mounted ||
        interrupted ||
        generation != alertSpeechGeneration ||
        drivingAlert?.message != alertMessage) {
      return;
    }
    await _listenForDrivingAnswer();
  }

  Future<void> _listenForDrivingAnswer() async {
    if (!mounted || drivingAlert == null) return;
    await alertVoiceListener.start(
      context: drivingAlert!.message,
      onTranscript: (transcript) async {
        if (!mounted) return;
        NovaVoiceController.update(message: transcript);
        await _handleVoiceChoice(transcript);
      },
      onSilence: () {
        if (mounted) {
          NovaVoiceController.update(phase: NovaVoicePhase.completed);
        }
      },
    );
  }

  Future<void> _checkDrivingConditions() async {
    final current = position;
    if (!mounted || current == null || disruptionCheckRunning) return;
    disruptionCheckRunning = true;
    try {
      final routeUri = Uri.parse('${widget.backend}/api/routes').replace(
        queryParameters: {
          'startLat': '${current.latitude}',
          'startLon': '${current.longitude}',
          'endLat': '${activeDestination.latitude}',
          'endLon': '${activeDestination.longitude}',
        },
      );
      final routeResponse = await http
          .get(routeUri)
          .timeout(const Duration(seconds: 25));
      WeatherOverview? weather;
      try {
        weather = await WeatherService(
          backend: widget.backend,
        ).getOverview(current.latitude, current.longitude);
      } catch (_) {
        // Traffic monitoring remains available if weather is unavailable.
      }
      final routeJson = jsonDecode(routeResponse.body) as Map<String, dynamic>;
      if (routeResponse.statusCode < 200 || routeResponse.statusCode >= 300) {
        return;
      }
      final refreshedRoutes = List<Map<String, dynamic>>.from(
        routeJson['routes'] ?? [],
      ).map(DrivingRoute.fromJson).toList();
      if (refreshedRoutes.isEmpty || !mounted) return;
      var fastest = 0;
      for (var index = 1; index < refreshedRoutes.length; index++) {
        if (refreshedRoutes[index].minutes < refreshedRoutes[fastest].minutes) {
          fastest = index;
        }
      }
      final activeIndex = math.max(
        0,
        math.min(selectedRoute, refreshedRoutes.length - 1),
      );
      final trafficText = refreshedRoutes[activeIndex].traffic.toLowerCase();
      final trafficRisk = RegExp(
        r'heavy|severe|congestion|congested|delay|jam|slow',
      ).hasMatch(trafficText);
      final currentWeather = weather?.current;
      final weatherText = currentWeather == null
          ? ''
          : '${currentWeather.condition} ${currentWeather.description}'
                .toLowerCase();
      final weatherRisk =
          currentWeather != null &&
          (currentWeather.rainProbability >= 70 ||
              RegExp(
                r'thunder|storm|heavy rain|downpour',
              ).hasMatch(weatherText));
      if (!trafficRisk && !weatherRisk) return;
      final reason = [
        if (trafficRisk) refreshedRoutes[activeIndex].traffic,
        if (weatherRisk)
          '${weatherDescription(currentWeather.description)}, rain ${currentWeather.rainProbability}%',
      ].join(' • ');
      final signature = '$reason:${refreshedRoutes[fastest].minutes}';
      if (signature == lastAlertSignature) return;
      lastAlertSignature = signature;
      final message =
          '$reason detected. Reroute now? / Perlu tukar laluan? / 需要重新规划路线吗？';
      setState(() {
        drivingAlert = _DrivingAlert(message: message, routes: refreshedRoutes);
      });
      NovaVoiceController.update(
        phase: NovaVoicePhase.awaitingConfirmation,
        message: message,
      );
      unawaited(_announceDrivingAlert(reason, message));
    } catch (_) {
      // A monitor outage must never interrupt active turn-by-turn navigation.
    } finally {
      disruptionCheckRunning = false;
    }
  }

  void _acceptReroute() {
    final alert = drivingAlert;
    if (alert == null || alert.routes.isEmpty) return;
    NovaVoiceController.reset();
    alertSpeechGeneration++;
    unawaited(alertTts.stop());
    unawaited(alertVoiceListener.stop(discard: true));
    var fastest = 0;
    for (var index = 1; index < alert.routes.length; index++) {
      if (alert.routes[index].minutes < alert.routes[fastest].minutes) {
        fastest = index;
      }
    }
    setState(() {
      activeRoutes = alert.routes;
      selectedRoute = fastest;
      stepIndex = 0;
      drivingAlert = null;
    });
    NovaVoiceController.update(
      phase: NovaVoicePhase.completed,
      message: 'Route updated.',
    );
  }

  void _keepCurrentRoute() {
    if (!mounted) return;
    NovaVoiceController.reset();
    alertSpeechGeneration++;
    unawaited(alertTts.stop());
    unawaited(alertVoiceListener.stop(discard: true));
    setState(() => drivingAlert = null);
    NovaVoiceController.update(
      phase: NovaVoicePhase.completed,
      message: 'Keeping the current route.',
    );
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
    reducedLocationAccuracy =
        await Geolocator.getLocationAccuracy() ==
        LocationAccuracyStatus.reduced;
    positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: navigationLocationSettings,
        ).listen(
          updatePosition,
          onError: (Object error) {
            if (mounted) setState(() => locationError = error.toString());
          },
        );
    updatePosition(
      await Geolocator.getCurrentPosition(
        locationSettings: navigationLocationSettings,
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
      locationError = reducedLocationAccuracy
          ? 'Precise location is off. Tap here to enable it in app settings.'
          : null;
    });
    if (followUser) moveCamera(value);
    if (!initialDisruptionCheckStarted) {
      initialDisruptionCheckStarted = true;
      unawaited(_checkDrivingConditions());
    }
  }

  Future<void> moveCamera(Position value) async {
    final mapController = controller;
    if (mapController == null || movingCameraProgrammatically) return;
    movingCameraProgrammatically = true;
    try {
      await mapController.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(value.latitude, value.longitude),
            zoom: 17.5,
            bearing: 0,
            tilt: 0,
          ),
        ),
      );
    } finally {
      movingCameraProgrammatically = false;
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
        const SnackBar(content: Text('Waiting for your current GPS location.')),
      );
      return;
    }
    if (mode == 'destination' && activeDestination.id == null) {
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
        if (mode == 'destination') 'destinationPlaceId': activeDestination.id,
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
            ? 'Similar to ${activeDestination.name}'
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
        const SnackBar(
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
      final newRoutes = List<Map<String, dynamic>>.from(
        data['routes'] ?? [],
      ).map(DrivingRoute.fromJson).toList();
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
        showRecommendationCarousel = false;
        recommendations = [];
        followUser = true;
      });
      await moveCamera(current);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fastest route changed to ${newDestination.name}.'),
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
    } finally {
      if (mounted) setState(() => recommendationLoading = false);
    }
  }

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
                      activeDestination.latitude,
                      activeDestination.longitude,
                    )
                  : route.points.first,
              zoom: 16,
            ),
            onMapCreated: (value) {
              controller = value;
              if (position != null) moveCamera(position!);
            },
            onCameraMoveStarted: () {
              if (!movingCameraProgrammatically) followUser = false;
            },
            polylines: {
              Polyline(
                polylineId: const PolylineId('active-route'),
                points: route.points,
                color: _routeBlue.withValues(alpha: 0.68),
                width: 5,
              ),
            },
            markers: {
              Marker(
                markerId: const MarkerId('destination'),
                position: LatLng(
                  activeDestination.latitude,
                  activeDestination.longitude,
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
                                  'Continue toward ${activeDestination.name}',
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
          if (drivingAlert != null)
            Positioned(
              top: 118,
              left: 16,
              right: 16,
              child: Material(
                elevation: 10,
                color: const Color(0xFFFDF7E7),
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFF9A6700),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              drivingAlert!.message,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _routeInk,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _listenForDrivingAnswer,
                            icon: const Icon(Icons.mic_rounded),
                            tooltip: 'Answer by voice',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _keepCurrentRoute,
                              child: const Text('Keep route'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _acceptReroute,
                              child: const Text('Reroute'),
                            ),
                          ),
                        ],
                      ),
                    ],
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

  @override
  void dispose() {
    alertSpeechGeneration++;
    disruptionTimer?.cancel();
    alertVoiceListener.dispose();
    voiceChoiceRegistration?.dispose();
    alertTts.stop();
    positionSubscription?.cancel();
    controller?.dispose();
    super.dispose();
  }
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
                      itemCount: math.min(5, photos.length),
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
                    '${photoPage + 1} of ${math.min(5, photos.length)}',
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
